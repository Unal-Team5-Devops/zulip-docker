#!/usr/bin/env bash
# Funciones compartidas por los comandos del GameDay 1.

GAMEDAY_SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GAMEDAY_DIR="$(cd -- "$GAMEDAY_SCRIPTS_DIR/.." && pwd)"
OBSERVABILITY_DIR="$(cd -- "$GAMEDAY_DIR/../.." && pwd)"
REPO_ROOT="$(cd -- "$OBSERVABILITY_DIR/.." && pwd)"
COMPOSE_SCRIPT="$OBSERVABILITY_DIR/scripts/compose.sh"
EVIDENCE_DIR="$GAMEDAY_DIR/evidence"
STATE_DIR="$GAMEDAY_DIR/.state"
CURRENT_RUN_FILE="$STATE_DIR/current-run"

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

gd::capture() {
  local phase="$1"
  local run_id="${2:-}"
  "$GAMEDAY_SCRIPTS_DIR/capture-evidence.sh" "$phase" "$run_id"
}

gd::wait_dependency_metric() {
  local expected="$1"
  local timeout_seconds="${2:-45}"

  python3 - "$expected" "$timeout_seconds" <<'PY'
import json
import sys
import time
from urllib.parse import urlencode
from urllib.request import urlopen

expected = float(sys.argv[1])
timeout = int(sys.argv[2])
query = 'zulip_dependency_up{dependency="postgres"}'
url = 'http://localhost:9090/api/v1/query?' + urlencode({'query': query})
deadline = time.monotonic() + timeout
last_value = None

while time.monotonic() < deadline:
    try:
        with urlopen(url, timeout=4) as response:
            payload = json.load(response)
        values = payload.get('data', {}).get('result', [])
        for item in values:
            sample_timestamp = float(item['value'][0])
            sample_age = time.time() - sample_timestamp
            if sample_age < 0 or sample_age > 35:
                continue
            value = float(item['value'][1])
            last_value = value
            if value == expected:
                print(f"Sonda PostgreSQL en Prometheus: {value:g} (muestra de hace {sample_age:.1f}s)")
                raise SystemExit(0)
    except Exception:
        pass
    time.sleep(3)

if last_value is None:
    print(f"No se obtuvo una muestra de la sonda PostgreSQL en {timeout}s.", file=sys.stderr)
else:
    print(f"La última muestra de la sonda fue {last_value:g}; se esperaba {expected:g}.", file=sys.stderr)
sys.exit(1)
PY
}

gd::wait_all_dependencies_healthy() {
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
        last = {
            item['metric'].get('dependency', 'unknown'): float(item['value'][1])
            for item in payload.get('data', {}).get('result', [])
        }
        if expected <= last.keys() and all(last[name] == 1 for name in expected):
            print('Dependencias observadas en Prometheus: ' + ', '.join(f'{name}=1' for name in sorted(expected)))
            raise SystemExit(0)
    except Exception:
        pass
    time.sleep(3)

print('No se confirmó que todas las dependencias estén saludables en Prometheus: ' + repr(last), file=sys.stderr)
sys.exit(1)
PY
}

gd::require_active_run() {
  [[ -s "$CURRENT_RUN_FILE" ]] || gd::die "No hay una ejecución activa. No se puede asociar la evidencia ni recuperar el escenario."
  RUN_ID="$(<"$CURRENT_RUN_FILE")"
  [[ "$RUN_ID" =~ ^[A-Za-z0-9TZ_-]+$ ]] || gd::die "El identificador local de ejecución no es válido."
}
