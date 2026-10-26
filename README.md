# docker-stats-dump

Complete, sorted `docker stats` snapshots, even under high load.

Under high load, `docker stats` shows `--` for containers whose stats the
Docker daemon doesn't deliver within its 2 second timeout, so you only see
some of your services. `docker stats --no-stream` has the same limit.

`docker-stats-dump.sh` queries every running container on its own, retries
until real values come back, and writes one table with all containers into a
`.txt` file, then prints it.

## Installation

```bash
curl -fsSLO https://raw.githubusercontent.com/chahn/docker-stats-dump/main/docker-stats-dump.sh
chmod +x docker-stats-dump.sh
```

Requires Linux with bash, Docker CLI, GNU coreutils and `column`.

## Usage

```
Usage: docker-stats-dump.sh [-s mem|cpu|io] [-h] [outfile]

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
```

Examples:

```bash
./docker-stats-dump.sh                         # sorted by memory
./docker-stats-dump.sh -s cpu
./docker-stats-dump.sh -s io /tmp/stats.txt
PARALLEL=4 RETRIES=10 ./docker-stats-dump.sh   # gentler on a loaded host
```

## Output

```
# docker stats on myhost at 2026-01-01 12:00:00, sorted by cpu
CONTAINER ID  NAME     CPU %   MEM USAGE / LIMIT   MEM %  NET I/O        BLOCK I/O       PIDS
aaaaaaaaaaaa  db-1     42.10%  1.2GiB / 8GiB       15.00% 1.5GB / 900MB  20GB / 5GB      30
bbbbbbbbbbbb  app-1    12.50%  512MiB / 8GiB       6.25%  800MB / 1.1GB  2GB / 10MB      25
cccccccccccc  web-1    1.20%   64MiB / 8GiB        0.78%  2.1GB / 2.3GB  100MB / 0B      8
...

# took 4s, load average at start: 1.50 1.20 1.00 (4 CPUs)
# memory at start: 3.1Gi used of 8.0Gi, 4.6Gi available, swap 0B used of 2.0Gi
```

## Notes

- Memory is sorted by absolute usage, not by MEM %, because MEM % is relative
  to each container's own limit.
- BLOCK I/O is cumulative since container start, so `-s io` shows which
  containers did the most disk I/O overall, not which are busiest right now.
- Load average and system memory are read before the script starts its own
  `docker stats` calls, so they aren't affected by the script itself.
- Containers that still return `--` after all retries are listed at the bottom.

## License

MIT, see [LICENSE](LICENSE).
