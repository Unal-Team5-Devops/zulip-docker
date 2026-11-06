#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
gd::require_active_run
if [[ -s "$PROFILE_PID_FILE" ]]; then
  PROFILE_PID="$(<"$PROFILE_PID_FILE")"
  if [[ "$PROFILE_PID" =~ ^[0-9]+$ ]] && kill -0 "$PROFILE_PID" 2>/dev/null; then
    gd::die "El perfil de carga sigue ejecutándose (PID $PROFILE_PID). Espere a que termine o interrúmpalo con Ctrl+C antes de recover."
  fi
  rm -f "$PROFILE_PID_FILE"
fi
gd::info "Confirmando que la carga terminó y el sistema volvió a su línea base"
gd::check_ready
gd::capture recovery "$RUN_ID"
rm -f "$CURRENT_RUN_FILE"
printf '\nEscenario cerrado; no se reinició ni recreó ningún servicio.\n'
