# shellcheck shell=bash
# Shared helpers for prepare.sh and run.sh; sourced, not executed.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
PROJECT=cachebench
# Which CiviCRM the app image runs: "stable" (civikitchen) or a tarball name from image/core/.
CORE=${BENCH_CORE:-stable}
export BENCH_CORE=$CORE
DB_IMAGE=$(awk '/image: mariadb@/ {print $2}' compose.yaml)

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
dc() { docker compose "$@"; }
app() { dc exec -T -u www-data app "$@"; }
cv_app() { app bash -c 'cd /var/www/html && cv "$@"' cv "$@"; }

wait_healthy() {
  local s
  for _ in $(seq 1 180); do
    s=$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-app-1" 2>/dev/null || true)
    [[ $s == healthy ]] && return 0
    sleep 2
  done
  log "app did not become healthy"; return 1
}

# Copies one named volume onto another (contents replaced).
copy_volume() {
  docker run --rm -v "$1":/from:ro -v "$2":/to --entrypoint sh "$DB_IMAGE" \
    -c 'find /to -mindepth 1 -delete && cp -a /from/. /to/'
}

# Golden volumes: the data every run of a core starts from.
golden_exists() { docker volume inspect "${PROJECT}_golden_${1:-$CORE}_dbdata" >/dev/null 2>&1; }
restore_golden() {
  local v
  for v in dbdata private; do copy_volume "${PROJECT}_golden_${1:-$CORE}_$v" "${PROJECT}_$v"; done
}
snapshot_golden() {
  local v
  for v in dbdata private; do
    docker volume create "${PROJECT}_golden_${CORE}_$v" >/dev/null
    copy_volume "${PROJECT}_$v" "${PROJECT}_golden_${CORE}_$v"
  done
}
