# Method

How the benchmark measures; usage is in the [README](../README.md), findings in
[results.md](results.md).

## Question

How much faster does CiviCRM get when its caches move out of MySQL, and which
backend is worth running? The answer should be a number per backend and page
type that a sysadmin can act on, with the measurement conditions stated next
to it.

The only published figure is a 2018 single-page measurement (CiviCRM 5.6,
Drupal 7, one laptop): the "Event Info" page went from ~460 ms to ~400 ms mean
with Redis (−13 %). It used one URL, one concurrency level and a MySQL on a RAM
disk.

## What the backends actually change

Verified on CiviCRM 6.18.2 / PHP 8.4 by writing a probe value into every named
cache and checking where it landed:

| `CIVICRM_DB_CACHE_CLASS` | 13 named caches (session, settings, metadata, navigation, …) | Search result paging (PrevNext) | Always in MySQL |
|---|---|---|---|
| `ArrayCache` (default) | MySQL (`civicrm_cache`) | MySQL | — |
| `Redis` | Redis | Redis | `prevNextCache`, `extension_browser` groups |
| `Memcached` / `Memcache` | Memcache | MySQL | same two groups |
| `FileCache` | files under `[civicrm.private]/filecache` | MySQL | same two groups |
| `APCucache` | MySQL — only the small default cache uses APCu | MySQL | — |

Smart group and ACL caches are SQL tables joined by search queries; no backend
moves them. On Standalone, PHP sessions are stored in `civicrm_session` unless
`php.ini` sets `session.save_handler = redis`.

Consequences for the design:

- `APCucache` behaves like the default for all named caches and is only
  probed, not load-tested.
- `Memcache` and `Memcached` share all code paths except the PHP client; only
  `Memcached` is measured.
- Redis sessions are a separate variant, not part of the plain `Redis` run.
- Core has no setting for an APCu tier in front of Redis (`CRM_Utils_Cache_Tiered`
  exists but is unused) or for named caches in APCu. A two-line patch to
  `CRM_Utils_Cache` (`image/patches/cache-tiers.patch`) builds both from
  `BENCH_TIERS`, to show what such a change in core would gain. It sits in
  `createStandard()`, so it also covers the caches core builds outside the
  container (settings, hooks, extension system, class scanner). The per-request
  array layer (`withArray`) is active in every variant.

## Matrix

| Variant | `CIVICRM_DB_CACHE_CLASS` | PHP sessions |
|---|---|---|
| `default` | `ArrayCache` | `civicrm_session` |
| `redis` | `Redis` | `civicrm_session` |
| `redis-sessions` | `Redis` | Redis |
| `memcached` | `Memcached` | `civicrm_session` |
| `filecache` | `FileCache` | `civicrm_session` |
| `redis-tiered` | `Redis`, named caches APCu → Redis (patch) | `civicrm_session` |
| `apcu-all` | `APCucache`, named caches in APCu (patch) | `civicrm_session` |

The APCu tier holds an entry for at most 300 s. Caches are flushed through the web
(APIv4 `System.flush`), not `cv flush`: the CLI has its own APCu and would leave
Apache's untouched. APCu is local to one web
server, so both patched variants only apply to single-server setups.

`APCucache` is not load-tested: the probe shows it stores every named cache in
MySQL like `default`. The probe runs for it in every series to keep that claim
checked; measurement noise is covered by the repetitions instead.

Each variant runs with two database latencies:

- **local** — MariaDB on the same Docker network (best case for MySQL caches).
- **remote** — 1 ms added round trip to MariaDB via `tc netem`, approximating a
  database on a separate host. Redis and Memcached stay local, as they usually
  run next to PHP.

Concurrency: 4 parallel clients, matching the 4 CPUs of the `app` container
(see [Time budget](#time-budget)).

## Workload

Scenarios are URL sets. Each request is a real HTTP request through Apache and
PHP.

| Scenario | Requests | Exercises |
|---|---|---|
| `anon-event` | `GET /civicrm/event/info?id=<n>` | the 2018 baseline page; metadata + settings caches |
| `anon-contribute` | `GET /civicrm/contribute/transact?reset=1&id=<n>` | QuickForm: session cache writes per request |
| `admin-contact` | `GET /civicrm/contact/view?reset=1&cid=<n>` (rotating ids) | custom data, contact fields, ACL |
| `admin-search` | `GET /civicrm/contact/search?reset=1&force=1&gid=<smart group>` | smart group cache, PrevNext (one row per result) |
| `afform-contact` | `GET /civicrm/bench-contact`, then `POST Afform.prefill` for an Individual (sequence) | Afform scanner, Angular module and metadata caches, prefill with joins and custom data |

`afform-contact` is a form shipped in the image (`image/afform/`): an
Individual with name, email, phone, address and the three custom groups,
prefilled from `#?Individual1=<id>`. Its latency is the whole sequence a
logged-in browser sends to PHP until the form is filled; static assets and
the navigation menu (browser-cached for a year) are not part of it. Each
iteration checks that the prefill returns the requested contact.

Each run also records the first request after a flush (cache rebuild cost).

Admin scenarios share one session of the `admin` user. It has all permissions, so ACL caches are not exercised.

### Data

A synthetic, deterministic dataset — no copies of real CRM data:

- 50 000 contacts (individuals, households, organisations), 20 groups including
  5 smart groups, 10 events, 5 contribution pages, 200 000 activities,
  50 000 contributions, 3 custom field groups.
- Generated once by a seeded APIv4 script (fixed RNG seed), then snapshotted
  into golden Docker volumes. Every run restores the same snapshot, so all
  variants see identical data.
- Activities and contributions are bulk-inserted with SQL (no financial
  records); the scenarios only read them.
- Golden volumes exist per core (see below). A newer core gets its golden data
  from the stable core's via `cv upgrade:db` (`bench/upgrade-golden.sh`), so
  both cores are measured on the same dataset.

## Core

By default the app runs the CiviCRM release that the pinned civikitchen image
ships (`stable`). `BENCH_CORE=<name>` swaps in a Standalone tarball stored by
`bench/fetch-core.sh` as `image/core/<name>.tar.gz`, for example the nightly
build of `master` to measure unreleased fixes. The image is tagged per core,
and `series.json` records the tarball URL and sha256.

## Environment

- Host: a dedicated Linux machine (AMD Ryzen 7 5700X, 8 cores / 16 threads, 64 GB RAM,
  NVMe). Docker runs directly on the host. Benchmarks run there, not on a laptop.
- The host also runs two libvirt VMs with 16 unpinned
  vCPUs each. They share every core with the benchmark, so their CPU use is
  recorded per run and counts towards the validity rules. Agents in those VMs
  should be idle during a `full` series.
- The CPU governor is `powersave`. `bench/run.sh` records it; switching to
  `performance` for a series needs root and is done by hand before and after.
- Stack per run (Docker Compose, one project per run):
  - `app` — civikitchen Standalone image, pinned by digest; Apache + mod_php;
    PHP extensions `redis`, `memcached`, `apcu` built into a thin derived
    image.
  - `db` — MariaDB 10.11.
  - `redis` — Redis 7, `requirepass` set.
  - `memcached` — Memcached 1.6.
  - `load` — load generator on the same Docker network.
- Resource limits: `app` 4 CPUs / 4 GB, `db` 2 CPUs / 4 GB, cache services
  1 CPU each, `load` 2 CPUs. Each container gets its own physical cores
  (both SMT siblings) via `cpuset`, so containers do not compete with each
  other.
- Production configuration: `php.ini-production`, OPcache with
  `validate_timestamps=0`, no debug extensions; CiviCRM `environment` is
  `Production` with debugging and backtraces off. `bench/run.sh` reads the web
  server's PHP runtime and aborts otherwise; the probe checks the CiviCRM
  settings per variant.

### Load generator

[`oha`](https://github.com/hatoo/oha): a single binary with JSON output that
includes latency percentiles and status-code counts. Request sequences
(`afform-contact`) run through `bench/flow.py`, standard-library Python with
oha-compatible JSON output. Both live in one load container
(`image/load/`), so nothing is installed on the host.

## Procedure

One **run** = one variant × latency × scenario.

1. Restore the golden snapshot; start the stack with the variant's settings.
2. **Verify the variant**: the probe script reports the storage class behind
   every named cache, the PrevNext driver and the PHP session handler. If the
   result does not match the matrix, the variant is skipped for that
   repetition — a misconfigured run must not produce numbers.
3. Flush (APIv4 `System.flush` over HTTP), then one request (first request after flush).
4. Warm-up: 10 s of the scenario, discarded.
5. Measurement: 20 s of the scenario.
6. Record environment data (see results).

The golden snapshot is restored once per variant and latency, not per run: the
scenarios only write sessions, cache entries and search paging.

Each run is repeated 3 times. The order of variants is shuffled per repetition
(fixed seed, recorded), so slow drift on the host spreads across variants
instead of favouring one.

## Time budget

| Profile | Matrix | Runs | Duration |
|---|---|---|---|
| `quick` | 7 variants × local × 5 scenarios × 1 repetition | 35 | ~25 min |
| `full` | 7 variants × 2 latencies × 5 scenarios × 3 repetitions | 210 | ~150 min |

`BENCH_LATENCIES=local` halves a `full` series to ~75 min.

Per run 30 s of load plus ~5 s overhead; per variant × latency ~40 s for
restore, start and probe. The dataset is generated once (~20 min) and
reused across series.

At ~200 ms per request and 4 clients, 20 s yields ~400 requests per run —
enough for a stable median and p95. Longer runs or more concurrency levels
multiply the duration; add them in a later series only if `full` shows
differences worth refining.

`quick` checks the setup and gives a first impression; only `full` results go
into the README.

## Results

Every run writes to `results/<series>/<variant>/<latency>/<scenario>/r<k>/`:

- `oha.json` — raw output of the load generator for the measurement.
- `cold.json` — the first request after a flush.
- `before.json`, `after.json` — host CPU counters, load average, VM CPU time,
  per-container CPU time and CPU governor around the measurement.

Per variant and latency, `probe-r<k>.json` holds the variant check. Per series,
`series.json` records host, revision of this repo, shuffle order, versions and
image digests; `summary.md` is the generated report. Results are committed:
they contain only synthetic data and timings.

## Validity rules

Before any aggregation, runs are classified. A run is **invalid** and excluded
when:

- the probe check failed;
- any response was not 2xx/3xx (an error page is fast and would flatter the
  variant);
- other workload on the host: the VMs used more than 0.5 CPU on average during
  the run (`virsh domstats --cpu-total` delta), or the host load outside the
  stack's containers exceeded 1 CPU;
- the load generator itself was CPU-bound (its container at > 90 % of its
  limit).

Every exclusion is listed with its reason in the summary; nothing is dropped
silently. If more than one of three repetitions of a run is invalid, that
cell is reported as "no result" instead of a number.

## Reporting

Per scenario × latency:

- median and p95 latency, throughput (requests/s), each as the median over the
  valid repetitions, with min–max across repetitions;
- difference to `default` in percent, shown only if the min–max ranges of the
  two variants do not overlap; otherwise "no measurable difference";
- `cold`: time of the first request after a flush, per variant.

`bench/summarize.py` writes these tables as `summary.md` per series;
`bench/compare.py` puts two series side by side. `docs/results.md` states the
conditions next to the headline numbers.

## Out of scope

- CMS flavours other than Standalone. WordPress and Drupal handle PHP sessions
  themselves; the cache backends behave the same.
- Multiple web servers. The question of cache coherence across servers is
  answered by the backend's design (APCu and FileCache are local), not by a
  benchmark.
- Tuning MariaDB itself.

