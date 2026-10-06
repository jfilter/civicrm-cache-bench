#!/usr/bin/env bash
# Derives the golden data for BENCH_CORE from another core's golden data via cv upgrade:db,
# so both cores are measured on the same dataset. Usage: BENCH_CORE=<core> bench/upgrade-golden.sh <from-core>
set -euo pipefail
# shellcheck source=bench/lib.sh
. "$(dirname "$0")/lib.sh"
from=${1:?usage: BENCH_CORE=<core> bench/upgrade-golden.sh <from-core>}
[[ $from != "$CORE" ]] || { echo "source and target core are both $CORE" >&2; exit 2; }

log "golden $CORE from golden $from"
dc down >/dev/null 2>&1 || true
dc build -q app
golden_exists "$from" || { echo "no golden data for core $from" >&2; exit 1; }
restore_golden "$from"
dc up -d app >/dev/null 2>&1
wait_healthy
cv_app upgrade:db
cv_app flush

log "snapshot golden volumes"
dc stop app db
snapshot_golden
dc down
log "upgraded"
