#!/usr/bin/env python3
"""Compares p50 of two series (e.g. two cores) per scenario, variant and latency; prints Markdown.

Only valid runs count (rules from summarize.py). Usage: bench/compare.py results/<series-a> results/<series-b>
"""
import json
import statistics
import sys
from pathlib import Path

from summarize import classify


def medians(series_dir):
    cells = {}
    for oha_file in series_dir.glob('*/*/*/r*/oha.json'):
        variant, latency, scenario, _ = oha_file.parent.relative_to(series_dir).parts
        result = classify(oha_file.parent, 'cachebench')
        if not result['invalid']:
            cells.setdefault((latency, scenario, variant), []).append(result['p50'])
    return {key: statistics.median(values) for key, values in cells.items()}


def label(series_dir):
    series = json.loads((series_dir / 'series.json').read_text())
    return f"CiviCRM {series['versions']['civicrm']} (`{series['series']}`)"


def main(a_dir, b_dir):
    a, b = medians(a_dir), medians(b_dir)
    print(f'p50 in ms, median over valid repetitions. A = {label(a_dir)}, B = {label(b_dir)}.')
    for latency in sorted({k[0] for k in a} & {k[0] for k in b}):
        variants = sorted({k[2] for k in a if k[0] == latency})
        print(f'\n## {latency}\n')
        print('| Scenario | ' + ' | '.join(f'`{v}` A → B' for v in variants) + ' |')
        print('|---|' + '---|' * len(variants))
        for scenario in sorted({k[1] for k in a if k[0] == latency}):
            row = []
            for v in variants:
                x, y = a.get((latency, scenario, v)), b.get((latency, scenario, v))
                row.append(f'{x:.0f} → {y:.0f} ({(y / x - 1) * 100:+.0f} %)' if x and y else 'no result')
            print(f'| {scenario} | ' + ' | '.join(row) + ' |')


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]))
