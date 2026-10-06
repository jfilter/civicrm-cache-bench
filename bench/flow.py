#!/usr/bin/env python3
"""Load generator for the afform-contact scenario: what a logged-in browser asks PHP for to show the form.

One iteration = GET the form page, then POST Afform.prefill for a random Individual, in sequence;
static assets and the year-cached navigation menu are left out. Writes oha-compatible JSON to stdout.
Usage: flow.py --base URL --cookie NAME=VALUE (-n COUNT | -z SECONDS) [-c CLIENTS] < individual-ids
"""
import argparse
import http.client
import json
import random
import sys
import threading
import time
import urllib.parse
from collections import Counter

FORM, ROUTE = 'afformBenchContact', '/civicrm/bench-contact'


def iteration(conn, cookie, cid):
    """Returns (status, error) of the first failing step, or (200, None)."""
    conn.request('GET', ROUTE, headers={'Cookie': cookie})
    res = conn.getresponse()
    body = res.read()
    if res.status != 200 or FORM.encode() not in body:
        return res.status, None if res.status != 200 else 'page without form'
    params = {'name': FORM, 'args': {'Individual1': [str(cid)]}, 'fillMode': 'form'}
    conn.request('POST', '/civicrm/ajax/api4/Afform/prefill',
                 body=urllib.parse.urlencode({'params': json.dumps(params)}),
                 headers={'Cookie': cookie, 'X-Requested-With': 'XMLHttpRequest',
                          'Content-Type': 'application/x-www-form-urlencoded'})
    res = conn.getresponse()
    body = res.read()
    if res.status != 200:
        return res.status, None
    try:
        filled = json.loads(body)['values'][0]['values'][0]['fields']['id']
    except (ValueError, LookupError, TypeError):
        return 200, 'prefill without record'
    return 200, None if filled == cid else f'prefill returned id {filled} for {cid}'


def client(args, ids, seed, deadline, results):
    rng = random.Random(seed)
    url = urllib.parse.urlsplit(args.base)
    conn = http.client.HTTPConnection(url.hostname, url.port or 80, timeout=60)
    count = 0
    # An iteration that starts before the deadline runs to completion, like oha -w.
    while (args.n is None or count < args.n) and (deadline is None or time.monotonic() < deadline):
        start = time.monotonic()
        try:
            status, error = iteration(conn, args.cookie, rng.choice(ids))
        except (OSError, http.client.HTTPException) as e:
            conn.close()
            status, error = None, type(e).__name__
        results.append((time.monotonic() - start, status, error))
        count += 1


def percentile(values, p):
    return values[min(len(values) - 1, int(p / 100 * len(values)))] if values else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', required=True)
    ap.add_argument('--cookie', required=True)
    ap.add_argument('-c', dest='clients', type=int, default=1)
    ap.add_argument('-n', type=int, help='iterations per client')
    ap.add_argument('-z', type=float, help='seconds')
    ap.add_argument('--seed', type=int, default=1)
    args = ap.parse_args()
    if (args.n is None) == (args.z is None):
        ap.error('exactly one of -n and -z is required')
    ids = [int(line) for line in sys.stdin if line.strip()]
    if not ids:
        ap.error('no Individual ids on stdin')

    results = []
    started = time.monotonic()
    deadline = started + args.z if args.z else None
    threads = [threading.Thread(target=client, args=(args, ids, args.seed * 1000 + i, deadline, results))
               for i in range(args.clients)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    elapsed = time.monotonic() - started

    ok = sorted(d for d, status, error in results if status == 200 and error is None)
    json.dump({
        'summary': {'requestsPerSec': len(results) / elapsed, 'average': sum(ok) / len(ok) if ok else None},
        'latencyPercentiles': {f'p{p}': percentile(ok, p) for p in (50, 90, 95, 99)},
        'statusCodeDistribution': dict(Counter(str(status) for _, status, _ in results if status is not None)),
        'errorDistribution': dict(Counter(error for _, _, error in results if error)),
    }, sys.stdout)


if __name__ == '__main__':
    main()
