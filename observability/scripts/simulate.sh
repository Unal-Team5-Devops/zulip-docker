#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
compose=./observability/scripts/compose.sh
simulation_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
restored=false
restore() {
  if [[ "$restored" == false ]]; then
    "$compose" start database
  fi
}
trap restore EXIT INT TERM
python3 observability/scripts/snapshot.py pre-incident
"$compose" stop database
python3 observability/scripts/load.py --url https://zulip.localhost:8080/login/ --seconds 240 --rps 5 --output observability/evidence/incident-load.json
python3 observability/scripts/snapshot.py incident
"$compose" start database
restored=true
python3 observability/scripts/load.py --url https://zulip.localhost:8080/login/ --seconds 360 --rps 5 --output observability/evidence/recovery-load.json
python3 observability/scripts/snapshot.py recovery
"$compose" logs --since "$simulation_started" --no-color alert-receiver > observability/evidence/notifications.log
