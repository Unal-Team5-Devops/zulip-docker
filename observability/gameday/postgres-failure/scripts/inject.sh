#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
if [[ -s "$CURRENT_RUN_FILE" ]]; then
  gd::die "Ya existe una ejecución sin cerrar ($( <"$CURRENT_RUN_FILE" )). Revise el estado y ejecute recover antes de iniciar otra."
fi

"$GAMEDAY_SCRIPTS_DIR/health-check.sh"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$STATE_DIR"
CONTAINER_ID="$(gd::compose ps -q database)"
[[ -n "$CONTAINER_ID" ]] || gd::die "No se encontró el contenedor database antes de iniciar la inyección."

gd::info "Guardando línea base"
gd::capture pre-incident "$RUN_ID"

# Persistir el run-id antes de detener la base para no perder el vínculo de evidencia
# si la sesión de terminal se interrumpe después de la inyección.
printf '%s\n' "$RUN_ID" > "$CURRENT_RUN_FILE"

gd::info "Inyectando la falla: detener únicamente el servicio database"
gd::compose stop database
IS_RUNNING="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_ID")"
[[ "$IS_RUNNING" == "false" ]] || gd::die "El contenedor database continúa en ejecución. No se puede confirmar la inyección."

printf '\nPostgreSQL está detenido. No se realizará ninguna recuperación automática.\n'
printf 'Espere a que Prometheus observe la sonda fallida y capture el estado del incidente.\n'
if ! gd::wait_dependency_metric 0 45; then
  printf 'ADVERTENCIA: no se confirmó el valor 0 de la sonda en Prometheus dentro del tiempo esperado.\n' >&2
fi

gd::capture incident "$RUN_ID"

cat <<EOF

GameDay 1 está en fase de investigación.
Run ID: $RUN_ID
Dashboard:   http://localhost:3000/d/zulip-sre
Prometheus:  http://localhost:9090
Alertmanager: http://localhost:9093

No ejecute recover hasta que el equipo haya confirmado la causa y autorizado la mitigación.
Para revisar el estado: $GAMEDAY_SCRIPTS_DIR/gameday.sh status
Para recuperar manualmente: $GAMEDAY_SCRIPTS_DIR/gameday.sh recover
EOF
