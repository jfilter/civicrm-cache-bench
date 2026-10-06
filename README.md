# civicrm-cache-bench

Measures how CiviCRM's response times change with the cache backend: the
default (MySQL), Redis, Redis with PHP sessions, Memcached, the file cache, and
two APCu layouts core cannot configure on its own (APCu in front of Redis, all
named caches in APCu).
Everything runs in Docker on one host with a synthetic dataset of 50 000
contacts.

The design — matrix, scenarios, validity rules — is in
[docs/method.md](docs/method.md).
Findings are in [docs/results.md](docs/results.md).

## Requirements

On the benchmark host: Docker with Compose, Python 3, `virsh` (libvirt; used to
record CPU time of VMs on the same host), cgroup v2 with the systemd driver.

## Usage

From the workstation, push the repo to the host (`BENCH_HOST`, its ssh name):

```bash
BENCH_HOST=<host> bench/sync.sh push
```

On the host, once:

```bash
cd civicrm-cache-bench
bench/prepare.sh        # install, seed (~20 min), golden snapshot
```

To measure another core, such as the nightly `master` build, once per tarball:

```bash
bench/fetch-core.sh master https://download.civicrm.org/latest/civicrm-NIGHTLY-standalone.tar.gz
BENCH_CORE=master bench/upgrade-golden.sh stable   # same dataset, upgraded
```

and prefix the `run.sh` calls below with `BENCH_CORE=master`. `BENCH_LATENCIES=local`
restricts a series to one database latency.

Then per series:

```bash
sudo cpupower frequency-set -g performance   # for full series
bench/run.sh quick      # ~25 min, setup check and first impression
bench/run.sh full       # ~150 min, numbers worth reporting
sudo cpupower frequency-set -g powersave
bench/summarize.py results/<series>
```

Back on the workstation:

```bash
BENCH_HOST=<host> bench/sync.sh pull
```

## Layout

| Path | Purpose |
|---|---|
| `compose.yaml` | app, MariaDB, Redis, Memcached; CPU sets per container |
| `variants/*.env` | cache settings per variant |
| `image/` | civikitchen Standalone image plus Redis/Memcached/APCu PHP extensions and the benchmark's afform; `load/` is the load generator image; `patches/` lets two variants put APCu into the cache chain |
| `bench/prepare.sh` | one-time install, seed and golden snapshot |
| `bench/fetch-core.sh`, `bench/upgrade-golden.sh` | alternative core (tarball) and its golden data |
| `bench/run.sh` | one series: restore, verify, measure per variant × latency × scenario |
| `bench/flow.py` | load generator for request sequences (`afform-contact`) |
| `bench/probe.php` | checks that the variant stores caches where expected |
| `bench/summarize.py` | marks invalid runs and writes `summary.md` |
| `bench/compare.py` | p50 of two series side by side, e.g. two cores |
| `results/` | raw results and summaries, one directory per series |

Image digests are pinned in `image/Dockerfile`, `compose.yaml` and
`bench/lib.sh`.
