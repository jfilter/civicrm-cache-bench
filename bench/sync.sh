#!/usr/bin/env bash
# Runs on the workstation: pushes the repo to the benchmark host (BENCH_HOST) and pulls results back.
# Usage: bench/sync.sh push|pull
set -euo pipefail
cd "$(dirname "$0")/.."
host=${BENCH_HOST:?set BENCH_HOST to the benchmark host (ssh name)} dir=civicrm-cache-bench
case ${1:?push|pull} in
  push) { git describe --always --dirty 2>/dev/null || echo uncommitted; } > REVISION
        rsync -a --delete --exclude .git --exclude results --exclude 'image/core/*.tar.gz' --exclude 'image/core/*.txt' ./ "$host:$dir/" ;;
  pull) rsync -a "$host:$dir/results/" results/ ;;
esac
