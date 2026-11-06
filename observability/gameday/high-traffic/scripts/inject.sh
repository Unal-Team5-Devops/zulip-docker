#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
if [[ -s "$CURRENT_RUN_FILE" ]]; then
  gd::die "Ya existe una ejecución pendiente ($( <"$CURRENT_RUN_FILE" )). Revise status y ejecute recover antes de iniciar otra."
fi
bash "$GAMEDAY_SCRIPTS_DIR/health-check.sh"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$STATE_DIR"
gd::capture pre-incident "$RUN_ID"
printf '%s\n' "$RUN_ID" > "$CURRENT_RUN_FILE"
printf '\nEjecución: %s\n' "$RUN_ID"
printf 'Observe Grafana/Prometheus desde otra terminal. Ctrl+C detiene la generación y conserva evidencia parcial.\n'
bash "$GAMEDAY_SCRIPTS_DIR/run-profile.sh" "$RUN_ID"
