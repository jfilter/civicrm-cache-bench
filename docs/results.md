# Results

Two comparisons from 2026-10-06, both with local database latency, 4 clients,
3 repetitions and production configuration (see [method.md](method.md)). All runs
were valid.

## Test machine

| | |
|---|---|
| CPU | AMD Ryzen 7 5700X, 8 cores / 16 threads, up to 4.67 GHz, 32 MiB L3; governor `performance` during the series |
| RAM | 64 GB DDR4 (4 modules, 2133 MT/s) |
| Storage | NVMe SSD (Viper VP4300L 1 TB) for the OS and Docker volumes |
| OS | Ubuntu 26.04.1 LTS, kernel 7.0, Docker 29.8 |
| Stack | civikitchen Standalone (Apache + mod_php), PHP 8.4.26 with OPcache, MariaDB 10.11.19, Redis 7.4.11, Memcached 1.6 |
| CPU split | limits app 4 CPUs, db 2, Redis 1, Memcached 1, load generator 2; each pinned to its own physical cores |
| Neighbours | two idle libvirt VMs share the host; their CPU use is checked per run (validity rules in method.md) |

Image digests are recorded in each series' `series.json`.

## 1. Cache backends on CiviCRM 6.18.2

Series `20261006T163228Z-full-stable`; full tables in
[its summary](../results/20261006T163228Z-full-stable/summary.md).

p50 in ms, median over 3 repetitions:

| Scenario | `default` | `redis` | `redis-sessions` | `redis-tiered` | `memcached` | `filecache` | `apcu-all` |
|---|---|---|---|---|---|---|---|
| admin-contact | 172 | 139 | 133 | 136 | 141 | 135 | 129 |
| admin-search | 163 | 171 | 169 | 169 | 165 | 300 | 143 |
| anon-contribute | 100 | 75 | 73 | 73 | 97 | 142 | 72 |
| anon-event | 63 | 60 | 58 | 58 | 62 | 60 | 58 |
| afform-contact | 311 | 286 | 285 | 282 | 289 | 288 | 278 |

- A memory backend instead of the database (`default`) is the main lever:
  −18 to −25 % on admin-contact, −25 to −28 % on anon-contribute (Redis,
  APCu), −7 to −11 % on afform-contact.
- Redis, Redis with sessions, tiered APCu → Redis and APCu alone lie within
  a few milliseconds of each other. APCu is fastest but single-server only;
  Redis is the general recommendation.
- Redis as session store saves a further 1–6 ms per request.
- Memcached gains almost nothing on anon-contribute (97 vs 100).
- FileCache is slow on admin-search (300) and anon-contribute (142), slower
  than `default`.
- No memory backend helps admin-search except APCu; Redis and Memcached are
  slightly slower than `default` there.

## 2. CiviCRM 6.18.2 vs 6.20.alpha1 (master)

Same dataset, upgraded with `cv upgrade:db`; the master build is the nightly
`civicrm-6.20.alpha1-standalone-202610061452`. Generated with
`bench/compare.py`: [core-6.18.2-vs-master.md](../results/core-6.18.2-vs-master.md).

- afform-contact is 27–31 % faster on master with every backend
  (e.g. Redis 286 → 201 ms). That gain is larger than any cache backend's.
- The server-rendered pages are 2–5 % slower on master; admin-search is
  unchanged (−3 to +3 %).
- Cause of the afform gain not established. Master includes
  [civicrm-core#37167](https://github.com/civicrm/civicrm-core/pull/37167),
  which stops the ClassScanner index from falling through to a per-request
  array cache; measuring 6.18.2 with only that patch would settle it.
