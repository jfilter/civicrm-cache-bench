#!/usr/bin/env python3
"""Classifies the runs of one series as valid/invalid and writes summary.md next to them.

Usage: bench/summarize.py results/<series>
"""
import json
import statistics
import sys
from pathlib import Path

USER_HZ = 100
LIMITS = {'vm_cpu': 0.5, 'other_cpu': 1.0, 'load_cpu': 0.9 * 2}


def load(path):
    return json.loads(path.read_text())


def cpu_deltas(before, after, project):
    wall = after['time'] - before['time']
    jb, ja = before['host_cpu_jiffies'], after['host_cpu_jiffies']
    # user nice system idle iowait irq softirq steal: busy = all but idle and iowait
    busy = sum(ja[i] - jb[i] for i in (0, 1, 2, 5, 6, 7)) / USER_HZ / wall
    containers = {c: (after['container_cpu_usec'][c] - before['container_cpu_usec'][c]) / 1e6 / wall
                  for c in after['container_cpu_usec'] if before['container_cpu_usec'].get(c) is not None}
    vms = sum(after['vm_cpu_ns'][v] - before['vm_cpu_ns'].get(v, 0) for v in after['vm_cpu_ns']) / 1e9 / wall
    return {
        'vm_cpu': vms,
        'other_cpu': busy - sum(containers.values()) - vms,
        'load_cpu': containers.get(f'{project}-load', 0.0),
    }


def classify(run_dir, project):
    oha = load(run_dir / 'oha.json')
    reasons = []
    bad = {code: n for code, n in oha.get('statusCodeDistribution', {}).items() if not code.startswith(('2', '3'))}
    if bad:
        reasons.append(f'non-2xx/3xx responses {bad}')
    if oha.get('errorDistribution'):
        reasons.append(f"request errors {oha['errorDistribution']}")
    cpu = cpu_deltas(load(run_dir / 'before.json'), load(run_dir / 'after.json'), project)
    for key, limit in LIMITS.items():
        if cpu[key] > limit:
            reasons.append(f'{key} {cpu[key]:.2f} > {limit}')
    p = oha['latencyPercentiles']
    cold = load(run_dir / 'cold.json')['summary']['average']
    if cold is None:
        reasons.append('first request after flush failed')
    if p['p50'] is None:
        reasons.append('no successful request')
    if reasons:
        return {'invalid': reasons}
    return {
        'p50': p['p50'] * 1000, 'p95': p['p95'] * 1000, 'rps': oha['summary']['requestsPerSec'],
        'requests': sum(oha.get('statusCodeDistribution', {}).values()),
        'cold': cold * 1000,
        'cpu': cpu, 'invalid': reasons,
    }


def fmt_range(values, unit=''):
    if len(values) == 1:
        return f'{values[0]:.0f}{unit}'
    return f'{statistics.median(values):.0f}{unit} ({min(values):.0f}–{max(values):.0f})'


def main(series_dir):
    series = load(series_dir / 'series.json')
    project = 'cachebench'
    reps = len(series['order'])
    cells, exclusions = {}, []
    for oha_file in sorted(series_dir.glob('*/*/*/r*/oha.json')):
        run_dir = oha_file.parent
        variant, latency, scenario, rep = run_dir.relative_to(series_dir).parts
        result = classify(run_dir, project)
        if result['invalid']:
            exclusions.append(f'{variant}/{latency}/{scenario}/{rep}: ' + '; '.join(result['invalid']))
            continue
        cells.setdefault((scenario, latency), {}).setdefault(variant, []).append(result)
    for probe in sorted(series_dir.glob('*/*/probe-r*.json')):
        if not load(probe)['ok']:
            exclusions.append(f"{probe.parent.relative_to(series_dir)}: probe mismatch {load(probe)['mismatch']}, not measured")

    header = (f"CPU {series['cpu']}, governor `{series['governor']}`, CiviCRM {series['versions']['civicrm']}, "
              f"PHP {series['versions']['php']}, {series['clients']} clients, {series['measure']} per run, "
              f"{reps} repetition(s), revision `{series['revision']}`, core `{series.get('core', 'stable')}`.")
    legend = ('Latency in ms: median over repetitions, min–max in brackets. '
              '"Δ p50" is shown only when the min–max ranges of the variant and `default` do not overlap.')
    lines = [f"# Series {series['series']}", '', header, '', legend, '']
    for (scenario, latency), by_variant in sorted(cells.items()):
        lines += [f'## {scenario} · {latency}', '',
                  '| Variant | p50 | p95 | req/s | Δ p50 vs default | first request after flush | valid runs |',
                  '|---|---|---|---|---|---|---|']
        base = [r['p50'] for r in by_variant.get('default', [])]
        for variant, results in sorted(by_variant.items()):
            if len(results) < reps - 1 or not results:
                lines.append(f'| `{variant}` | no result | | | | | {len(results)}/{reps} |')
                continue
            p50 = [r['p50'] for r in results]
            delta = '—'
            if variant != 'default' and base and reps > 1 and (max(p50) < min(base) or min(p50) > max(base)):
                delta = f'{(statistics.median(p50) / statistics.median(base) - 1) * 100:+.0f} %'
            elif variant != 'default' and reps > 1:
                delta = 'no measurable difference'
            lines.append(f"| `{variant}` | {fmt_range(p50)} | {fmt_range([r['p95'] for r in results])} | "
                         f"{fmt_range([r['rps'] for r in results])} | {delta} | {fmt_range([r['cold'] for r in results])} | "
                         f'{len(results)}/{reps} |')
        lines.append('')
    lines += ['## Excluded runs', '']
    lines += [f'- {e}' for e in exclusions] or ['None.']
    apcu = series_dir / 'apcu-probe.json'
    if apcu.exists():
        lines += ['', '## APCu probe', '', f"`ok: {load(apcu)['ok']}`"]
    (series_dir / 'summary.md').write_text('\n'.join(lines) + '\n')
    print(series_dir / 'summary.md')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
