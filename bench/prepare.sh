#!/usr/bin/env bash
# One-time per core: fresh install, synthetic dataset, golden volumes that every run restores from.
set -euo pipefail
# shellcheck source=bench/lib.sh
. "$(dirname "$0")/lib.sh"

log "fresh stack"
dc down -v --remove-orphans >/dev/null 2>&1 || true
dc build -q app
dc up -d
wait_healthy

log "hook cache settings into civicrm.settings.php"
app bash -c "grep -q bench/cache-settings.php /var/www/html/private/civicrm.settings.php || sed -i '1a if (is_file(\"/usr/local/share/bench/cache-settings.php\")) { include \"/usr/local/share/bench/cache-settings.php\"; }' /var/www/html/private/civicrm.settings.php"

log "seed (takes ~20 min)"
cv_app scr /bench/seed.php
cv_app flush

log "snapshot golden volumes"
dc stop app db
snapshot_golden
dc down
log "prepared"
