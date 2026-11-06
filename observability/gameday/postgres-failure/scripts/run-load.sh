#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
gd::require_active_run

SECONDS_TO_RUN="${1:-180}"
REQUESTS_PER_SECOND="${2:-5}"
[[ "$SECONDS_TO_RUN" =~ ^[0-9]+$ ]] || gd::die "La duración debe ser un número entero de segundos."
python3 - "$SECONDS_TO_RUN" "$REQUESTS_PER_SECOND" <<'PY'
import sys

seconds = int(sys.argv[1])
try:
    rps = float(sys.argv[2])
except ValueError:
    raise SystemExit("La tasa debe ser un número.")
if not 15 <= seconds <= 300:
    raise SystemExit("La duración permitida es de 15 a 300 segundos.")
if not 0 < rps <= 10:
    raise SystemExit("La tasa permitida es mayor que 0 y hasta 10 solicitudes por segundo.")
PY

CONTAINER_ID="$(gd::compose ps --all -q database)"
[[ -n "$CONTAINER_ID" ]] || gd::die "No se encontró el contenedor database."
IS_RUNNING="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_ID")"
[[ "$IS_RUNNING" == "false" ]] || gd::die "PostgreSQL debe estar detenido por la inyección antes de iniciar la carga."

OUTPUT_DIR="$EVIDENCE_DIR/incident/$RUN_ID"
mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/load-report.json"

gd::info "Generando carga sintética sobre la página de login"
printf 'Duración: %ss · tasa objetivo: %s solicitudes/s · máximo: 10 solicitudes/s\n' \
  "$SECONDS_TO_RUN" "$REQUESTS_PER_SECOND"
python3 "$OBSERVABILITY_DIR/scripts/load.py" \
  --url 'https://zulip.localhost:8080/login/' \
  --seconds "$SECONDS_TO_RUN" \
  --rps "$REQUESTS_PER_SECOND" \
  --output "$REPORT_FILE"

gd::info "Actualizando captura de evidencia del incidente"
gd::capture incident "$RUN_ID"
printf '\nReporte de carga: %s\n' "$REPORT_FILE"
