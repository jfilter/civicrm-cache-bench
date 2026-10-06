#!/usr/bin/env bash
# Runs one benchmark series. Usage: [BENCH_CORE=<core>] [BENCH_LATENCIES="local remote"] bench/run.sh quick|full
set -euo pipefail
# shellcheck source=bench/lib.sh
. "$(dirname "$0")/lib.sh"

profile=${1:?usage: bench/run.sh quick|full}
case $profile in
  quick) reps=1 latencies=(local) ;;
  full) reps=3 latencies=(local remote) ;;
  *) echo "unknown profile: $profile" >&2; exit 2 ;;
esac
[[ -z ${BENCH_LATENCIES:-} ]] || read -r -a latencies <<<"$BENCH_LATENCIES"
for latency in "${latencies[@]}"; do
  [[ $latency == local || $latency == remote ]] || { echo "unknown latency: $latency" >&2; exit 2; }
done
variants=(default redis redis-sessions redis-tiered memcached filecache apcu-all)
APP_IMAGE=cachebench-app:$CORE
LOAD_IMAGE=cachebench-load
clients=4 warmup=10s measure=20s remote_delay=1ms shuffle_seed=${SHUFFLE_SEED:-1}
containers=("$PROJECT-app-1" "$PROJECT-db-1" "$PROJECT-redis-1" "$PROJECT-memcached-1" "$PROJECT-load")

golden_exists || { echo "no golden data for core $CORE: run bench/prepare.sh or bench/upgrade-golden.sh" >&2; exit 1; }
dc build -q app
docker build -q -t "$LOAD_IMAGE" image/load >/dev/null
series=$(date -u +%Y%m%dT%H%M%SZ)-$profile-$CORE
out=results/$series
mkdir -p "$out"

# Starts the stack for one variant on a fresh copy of the golden data.
start_variant() {
  dc stop app db >/dev/null 2>&1 || true
  restore_golden
  dc --env-file "variants/$1.env" up -d --force-recreate app db redis memcached >/dev/null 2>&1
  wait_healthy
}

oha() { docker exec "$PROJECT-load" oha --no-tui "$@"; }
# Request sequence of afform-contact; options as for oha (-n/-z, -c).
flow() { docker exec -i "$PROJECT-load" python3 /bench/flow.py --base http://app --cookie "$cookie" "$@" <<<"$IDS_INDIVIDUALS"; }
# Flushes inside Apache: cv runs in the CLI, whose APCu is separate from the web server's.
web_flush() {
  dc exec -T app curl -fsS -o /dev/null -X POST -H "Cookie: $1" -H 'X-Requested-With: XMLHttpRequest' \
    http://localhost/civicrm/ajax/api4/System/flush
}

start_variant default
if ! docker container inspect "$PROJECT-load" >/dev/null 2>&1; then
  docker run -d --name "$PROJECT-load" --network "${PROJECT}_default" --cpuset-cpus 7,15 --cpus 2 \
    -v "$PWD/bench:/bench:ro" "$LOAD_IMAGE" sleep infinity >/dev/null
fi

ids() { cv_app sql <<<"$1" | tail -n +2 | paste -sd'|' -; }
IDS_EVENTS=$(ids 'SELECT id FROM civicrm_event WHERE is_public = 1 AND is_active = 1')
IDS_PAGES=$(ids 'SELECT id FROM civicrm_contribution_page WHERE is_active = 1')
IDS_SMART_GROUPS=$(ids 'SELECT id FROM civicrm_group WHERE saved_search_id IS NOT NULL')
IDS_INDIVIDUALS=$(cv_app sql <<<"SELECT id FROM civicrm_contact WHERE contact_type = 'Individual' AND is_deleted = 0" | tail -n +2)
# Scenarios: auth mode and URL regex for oha; afform-contact is a request sequence (bench/flow.py).
declare -A SCENARIO_AUTH=(
  [anon-event]=anon [anon-contribute]=anon [admin-contact]=admin [admin-search]=admin [afform-contact]=admin
)
declare -A SCENARIO_URL=(
  [anon-event]="http://app/civicrm/event/info\\?reset=1&id=($IDS_EVENTS)"
  [anon-contribute]="http://app/civicrm/contribute/transact\\?reset=1&id=($IDS_PAGES)"
  [admin-contact]="http://app/civicrm/contact/view\\?reset=1&cid=[1-4][0-9]{4}"
  [admin-search]="http://app/civicrm/contact/search\\?reset=1&force=1&gid=($IDS_SMART_GROUPS)"
)
SCENARIOS=(anon-event anon-contribute admin-contact admin-search afform-contact)

order=$(python3 -c "import random,sys; r=random.Random($shuffle_seed); v=sys.argv[1:]
for _ in range($reps): r.shuffle(v); print(' '.join(v))" "${variants[@]}")
V_CIVICRM=$(cv_app ev 'echo CRM_Utils_System::version();')
V_PHP=$(dc exec -T app php -r 'echo PHP_VERSION;')
V_MARIADB=$(dc exec -T db mariadb --version)
V_REDIS=$(dc exec -T redis redis-server --version)
V_OHA=$(docker exec "$PROJECT-load" oha --version)
RUNTIME=$(dc exec -T app curl -fsS http://localhost/bench-runtime.php)
V_IMAGES=$(for s in app db redis memcached; do docker inspect -f "$s={{.Image}}" "$PROJECT-$s-1"; done | paste -sd' ' -)
SERIES=$series PROFILE=$profile SHUFFLE_SEED=$shuffle_seed ORDER=$order CLIENTS=$clients
WARMUP=$warmup MEASURE=$measure REMOTE_DELAY=$remote_delay
export SERIES PROFILE SHUFFLE_SEED ORDER CLIENTS WARMUP MEASURE REMOTE_DELAY CORE RUNTIME V_CIVICRM V_PHP V_MARIADB V_REDIS V_OHA V_IMAGES
python3 - "$out/series.json" <<'PY'
import json, os, sys
e = os.environ
runtime = json.loads(e['RUNTIME'])
production = {'display_errors': '', 'zend.assertions': '-1', 'opcache': True, 'debug_extensions': []}
if runtime != production:
    sys.exit(f'web PHP runtime is not a production configuration: {runtime}')
json.dump({
    'series': e['SERIES'], 'profile': e['PROFILE'],
    'cpu': next(line.split(':', 1)[1].strip() for line in open('/proc/cpuinfo') if line.startswith('model name')),
    'revision': open('REVISION').read().strip(), 'shuffle_seed': int(e['SHUFFLE_SEED']),
    'order': e['ORDER'].splitlines(), 'clients': int(e['CLIENTS']), 'warmup': e['WARMUP'], 'measure': e['MEASURE'],
    'remote_delay': e['REMOTE_DELAY'], 'core': e['CORE'],
    'core_source': open(f"image/core/{e['CORE']}.txt").read().split() if e['CORE'] != 'stable' else None,
    'php_runtime': runtime,
    'governor': open('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor').read().strip(),
    'versions': {'civicrm': e['V_CIVICRM'], 'php': e['V_PHP'], 'mariadb': e['V_MARIADB'], 'redis': e['V_REDIS'], 'oha': e['V_OHA'],
                 'images': dict(kv.split('=', 1) for kv in e['V_IMAGES'].split())},
}, open(sys.argv[1], 'w'), indent=2)
PY
log "series $series: $(wc -l <<<"$order") repetition(s), latencies ${latencies[*]}"

log "probe apcu (not load-tested)"
start_variant apcu
cv_app scr /bench/probe.php > "$out/apcu-probe.json" || log "apcu probe MISMATCH, see $out/apcu-probe.json"

# Read upfront: commands in the loop (docker compose exec) consume stdin.
mapfile -t rep_orders <<<"$order"
for i in "${!rep_orders[@]}"; do
  read -r -a rep_order <<<"${rep_orders[i]}"
  rep=$((i + 1))
  for variant in "${rep_order[@]}"; do
    for latency in "${latencies[@]}"; do
      base=$out/$variant/$latency
      mkdir -p "$base"
      log "rep $rep · $variant · $latency"
      start_variant "$variant"
      if [[ $latency == remote ]]; then
        docker run --rm --network "container:$PROJECT-db-1" --cap-add NET_ADMIN --entrypoint tc "$APP_IMAGE" \
          qdisc replace dev eth0 root netem delay "$remote_delay"
      fi
      if ! cv_app scr /bench/probe.php > "$base/probe-r$rep.json"; then
        log "probe MISMATCH — skipping $variant/$latency rep $rep"
        continue
      fi
      cookie=$(dc exec -T app bash -s admin admin < bench/login.sh)
      for scenario in "${SCENARIOS[@]}"; do
        dir=$base/$scenario/r$rep
        mkdir -p "$dir"
        auth=()
        [[ ${SCENARIO_AUTH[$scenario]} == admin ]] && auth=(-H "Cookie: $cookie")
        web_flush "$cookie"
        if [[ $scenario == afform-contact ]]; then
          flow -n 1 > "$dir/cold.json"
          flow -z "${warmup%s}" -c "$clients" >/dev/null
          bench/snapshot.py "${containers[@]}" > "$dir/before.json"
          flow -z "${measure%s}" -c "$clients" > "$dir/oha.json"
          bench/snapshot.py "${containers[@]}" > "$dir/after.json"
          continue
        fi
        url=${SCENARIO_URL[$scenario]}
        oha -n 1 -c 1 --rand-regex-url "${auth[@]}" --output-format json "$url" > "$dir/cold.json"
        oha -z "$warmup" -c "$clients" --rand-regex-url "${auth[@]}" --output-format quiet "$url"
        bench/snapshot.py "${containers[@]}" > "$dir/before.json"
        oha -z "$measure" -w -c "$clients" --rand-regex-url "${auth[@]}" --output-format json "$url" > "$dir/oha.json"
        bench/snapshot.py "${containers[@]}" > "$dir/after.json"
      done
    done
  done
done

docker rm -f "$PROJECT-load" >/dev/null
dc stop >/dev/null
log "done: $out"
