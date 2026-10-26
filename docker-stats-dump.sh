#!/usr/bin/env bash
# Dump the stats of all running containers into one .txt file and print it.
#
# Under high load `docker stats` shows "--" for containers whose stats the
# daemon doesn't deliver within its 2s timeout. This script queries each
# container on its own and retries until real values come back.
#
# Run with -h for usage.
set -euo pipefail

usage() {
	cat <<EOF
Usage: $(basename "$0") [-s mem|cpu|io] [-h] [outfile]

Dump the stats of all running containers into one file and print it.
Highest values are on top.

Options:
  -s mem    sort by memory usage (default)
  -s cpu    sort by CPU %
  -s io     sort by block (disk) I/O, read + write since container start
  -h        show this help

Arguments:
  outfile   file to write to (default: docker-stats-YYYYMMDD-HHMMSS.txt
            in the current directory)

Environment:
  PARALLEL=8  number of containers queried at the same time
  RETRIES=5   attempts per container before giving up
EOF
}

SORT=mem
while getopts "s:h" opt; do
	case $opt in
		s) SORT=$OPTARG ;;
		h) usage; exit 0 ;;
		*) usage >&2; exit 1 ;;
	esac
done
shift $((OPTIND - 1))
case $SORT in
	mem | cpu | io) ;;
	*) echo "Invalid sort key: $SORT (use mem, cpu or io)" >&2; exit 1 ;;
esac

# Take time and load at start, before our own docker calls add load
START=$(date +%s)
LOAD="$(cut -d' ' -f1-3 /proc/loadavg) ($(nproc) CPUs)"
MEM=$(free -h | awk '
	/^Mem:/  { printf "%s used of %s, %s available", $3, $2, $7 }
	/^Swap:/ { printf ", swap %s used of %s", $3, $2 }')
OUT="${1:-docker-stats-$(date -d "@$START" +%Y%m%d-%H%M%S).txt}"
export PARALLEL="${PARALLEL:-8}"
export RETRIES="${RETRIES:-5}"
export FORMAT='{{.ID}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}'

tmp=$(mktemp -d)
export tmp
trap 'rm -rf "$tmp"' EXIT

query() {
	local idx=$1 id=$2 line=""
	for ((i = 1; i <= RETRIES; i++)); do
		line=$(docker stats --no-stream --format "$FORMAT" "$id" 2>/dev/null || true)
		# CPU column "--" means the daemon didn't answer in time
		[[ -n $line && $line != *$'\t--'* ]] && break
		sleep 1
	done
	printf '%s\n' "${line:-$id	?	(no stats)}" >"$tmp/$idx"
}
export -f query

# Prefix each line with a numeric key for $SORT, sort descending, drop the key
sort_lines() {
	awk -F'\t' -v key="$SORT" '
		function bytes(s,   u) {
			u = s; sub(/^[0-9.]+/, "", u)
			return (s + 0) * (u in unit ? unit[u] : 0)
		}
		BEGIN {
			unit["B"] = 1
			unit["kB"] = 1e3; unit["MB"] = 1e6; unit["GB"] = 1e9; unit["TB"] = 1e12
			unit["KiB"] = 1024; unit["MiB"] = 1024^2; unit["GiB"] = 1024^3; unit["TiB"] = 1024^4
		}
		{
			if (key == "cpu") k = $3 + 0
			else if (key == "mem") { split($4, m, " / "); k = bytes(m[1]) }
			else { split($7, b, " / "); k = bytes(b[1]) + bytes(b[2]) }
			printf "%.4f\t%s\n", k, $0
		}' | sort -t$'\t' -k1,1 -rn | cut -f2-
}

docker ps -q | awk '{printf "%04d %s\n", NR, $1}' |
	xargs -r -P "$PARALLEL" -n 2 bash -c 'query "$@"' _

{
	echo "# docker stats on $(hostname) at $(date -d "@$START" '+%Y-%m-%d %H:%M:%S'), sorted by $SORT"
	if compgen -G "$tmp/*" >/dev/null; then
		{
			printf 'CONTAINER ID\tNAME\tCPU %%\tMEM USAGE / LIMIT\tMEM %%\tNET I/O\tBLOCK I/O\tPIDS\n'
			cat "$tmp"/* | sort_lines
		} | column -t -s $'\t'
	else
		echo "No running containers."
	fi
	echo
	echo "# took $(($(date +%s) - START))s, load average at start: $LOAD"
	echo "# memory at start: $MEM"
} >"$OUT"

cat "$OUT"
echo
echo "Saved to $OUT"
