#!/usr/bin/env bash
# Funciones compartidas por los comandos del GameDay 2.

GAMEDAY_SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GAMEDAY_DIR="$(cd -- "$GAMEDAY_SCRIPTS_DIR/.." && pwd)"
OBSERVABILITY_DIR="$(cd -- "$GAMEDAY_DIR/../.." && pwd)"
REPO_ROOT="$(cd -- "$OBSERVABILITY_DIR/.." && pwd)"
COMPOSE_SCRIPT="$OBSERVABILITY_DIR/scripts/compose.sh"
EVIDENCE_DIR="$GAMEDAY_DIR/evidence"
STATE_DIR="$GAMEDAY_DIR/.state"
CURRENT_RUN_FILE="$STATE_DIR/current-run"
PROFILE_PID_FILE="$STATE_DIR/profile-pid"

gd::compose() {
  "$COMPOSE_SCRIPT" "$@"
}

gd::die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

gd::info() {
  printf '\n==> %s\n' "$*"
}

gd::require_active_run() {
  [[ -s "$CURRENT_RUN_FILE" ]] || gd::die "No hay una ejecución activa de high-traffic."
  RUN_ID="$(<"$CURRENT_RUN_FILE")"
  [[ "$RUN_ID" =~ ^[A-Za-z0-9TZ_-]+$ ]] || gd::die "El identificador local de ejecución no es válido."
}

gd::capture() {
  local phase="$1"
  local run_id="${2:-}"
  bash "$GAMEDAY_SCRIPTS_DIR/capture-evidence.sh" "$phase" "$run_id"
}

gd::wait_dependencies() {
  local timeout_seconds="${1:-45}"

  python3 - "$timeout_seconds" <<'PY'
import json
import sys
import time
from urllib.parse import urlencode
from urllib.request import urlopen

expected = {'postgres', 'redis', 'memcached', 'rabbitmq', 'gateway'}
timeout = int(sys.argv[1])
url = 'http://localhost:9090/api/v1/query?' + urlencode({'query': 'zulip_dependency_up'})
deadline = time.monotonic() + timeout
last = {}

while time.monotonic() < deadline:
    try:
        with urlopen(url, timeout=4) as response:
            payload = json.load(response)
        now = time.time()
        last = {}
        for item in payload.get('data', {}).get('result', []):
            dependency = item['metric'].get('dependency', 'unknown')
            timestamp, value = float(item['value'][0]), float(item['value'][1])
            if 0 <= now - timestamp <= 45:
                last[dependency] = value
        if expected <= last.keys() and all(last[name] == 1 for name in expected):
            print('Dependencias sanas: ' + ', '.join(f'{name}=1' for name in sorted(expected)))
            raise SystemExit(0)
    except Exception:
        pass
    time.sleep(3)

print('No se confirmó la salud de todas las dependencias: ' + repr(last), file=sys.stderr)
sys.exit(1)
PY
}

gd::check_ready() {
  gd::compose exec -T database pg_isready -U zulip -d zulip >/dev/null
  curl --silent --show-error --fail --insecure --resolve zulip.localhost:8080:127.0.0.1 \
    --max-time 10 --output /dev/null https://zulip.localhost:8080/login/
  curl --silent --show-error --fail --max-time 5 http://localhost:9090/-/ready --output /dev/null
  curl --silent --show-error --fail --max-time 5 http://localhost:9093/-/ready --output /dev/null
  curl --silent --show-error --fail --max-time 5 http://localhost:3000/api/health --output /dev/null
  gd::wait_dependencies 45
  python3 - <<'PY'
import json
from urllib.parse import urlencode
from urllib.request import urlopen

url = 'http://localhost:9090/api/v1/query?' + urlencode({'query': 'up{job="cadvisor"}'})
with urlopen(url, timeout=5) as response:
    values = json.load(response).get('data', {}).get('result', [])
if not values or not any(float(item['value'][1]) == 1 for item in values):
    raise SystemExit('cAdvisor no está siendo scrapeado; no se puede evaluar saturación de contenedores.')
print('cAdvisor está disponible para observar CPU y memoria.')
PY
}
