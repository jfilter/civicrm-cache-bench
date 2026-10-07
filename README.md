# civicrm-cache-bench

CiviCRM keeps its internal caches — sessions, settings, metadata, navigation
and more — in MySQL by default; `CIVICRM_DB_CACHE_CLASS` moves them to Redis,
Memcached or files. This benchmark measures what that does to response times:
the default (MySQL), Redis, Redis with PHP sessions, Memcached, the file cache,
and two APCu layouts core cannot configure on its own (APCu in front of Redis,
all named caches in APCu).
Everything runs in Docker on one host with a synthetic dataset of 50 000
contacts, real HTTP requests through Apache and PHP, and production PHP
settings.

## Summary

Moving the caches out of MySQL into memory makes contact and contribution
pages about 20–25 % faster. Which memory backend matters little: Redis,
Memcached and APCu land within a few milliseconds of each other on most pages.
Redis is the sensible default; the file cache is slower than MySQL.

Median response time (p50, ms) on CiviCRM 6.18.2, local database, 4 parallel
clients, median of 3 repetitions (2026-10-06):

| Page | MySQL (default) | Redis | Redis + sessions | Memcached | File cache | APCu (patched) |
|---|---|---|---|---|---|---|
| Contact view (admin) | 172 | 139 | 133 | 141 | 135 | 129 |
| Smart-group search (admin) | 163 | 171 | 169 | 165 | 300 | 143 |
| Contribution page (anonymous) | 100 | 75 | 73 | 97 | 142 | 72 |
| Event info (anonymous) | 63 | 60 | 58 | 62 | 60 | 58 |
| FormBuilder form with prefill (admin) | 311 | 286 | 285 | 289 | 288 | 278 |

- **Redis** cuts contact view by 19 % and the contribution page by 25 %.
  Storing PHP sessions in Redis as well saves another 1–6 ms per request.
- **Memcached** matches Redis on contact view but gains almost nothing on the
  contribution page.
- **File cache** nearly doubles the smart-group search time.
- **APCu** is fastest or tied on every page, but core needs a patch to put the
  named caches there, and APCu is local to one web server.
- **Smart-group search** gets no faster with Redis or Memcached; its smart-group
  cache is an SQL table in every variant.
- **Upgrading core** can matter more than the backend: the nightly 6.20 build
  serves the FormBuilder form 27–31 % faster with every backend (Redis
  286 → 201 ms), while server-rendered pages are 2–5 % slower.

Test machine and the full core comparison are in
[docs/results.md](docs/results.md); matrix, scenarios and validity rules in
[docs/method.md](docs/method.md). Raw results are committed under `results/`.

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
