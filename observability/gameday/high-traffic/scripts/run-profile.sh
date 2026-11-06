#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

RUN_ID="${1:-}"
[[ "$RUN_ID" =~ ^[A-Za-z0-9TZ_-]+$ ]] || gd::die "run-id inválido."
OUTPUT_DIR="$EVIDENCE_DIR/incident/$RUN_ID"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$STATE_DIR"
printf '%s\n' "$$" > "$PROFILE_PID_FILE"

capture_on_exit() {
  local exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    printf '\nPerfil interrumpido o fallido (código %s); guardando evidencia parcial.\n' "$exit_code" >&2
  fi
  rm -f "$PROFILE_PID_FILE"
  gd::capture incident "$RUN_ID" || true
  exit "$exit_code"
}
trap capture_on_exit EXIT

# En este entorno, 100 RPS fue estable y 250 RPS produjo 5xx. La tercera
# etapa solo se ejecuta si la segunda no supera los umbrales.
stages=("20 100" "30 250" "15 350")
stage_number=0
profile_result="$OUTPUT_DIR/profile-result.txt"
printf 'stage target_rps client_rps gateway_rps gateway_5xx_ratio gateway_p95_seconds client_5xx_ratio client_transport_error_ratio generator_drop_ratio scheduler_shortfall_ratio result\n' > "$profile_result"
for stage in "${stages[@]}"; do
  read -r stage_seconds stage_rps <<< "$stage"
  stage_number=$((stage_number + 1))
  report="$OUTPUT_DIR/load-stage-$(printf '%02d' "$stage_number").json"
  gd::info "Etapa $stage_number/${#stages[@]}: $stage_rps solicitudes/s durante ${stage_seconds}s"
  python3 "$GAMEDAY_SCRIPTS_DIR/load-bounded.py" \
    --seconds "$stage_seconds" --rps "$stage_rps" --workers 256 --output "$report"
  gd::info "Reporte de la etapa guardado en $report"
  if python3 "$GAMEDAY_SCRIPTS_DIR/analyze-stage.py" \
    --stage "$stage_number" --report "$report" \
    --output "$OUTPUT_DIR/stage-$(printf '%02d' "$stage_number")-analysis.json" \
    --summary "$profile_result"
  then
    :
  else
    decision=$?
    if [[ "$decision" -eq 10 ]]; then
      printf '\nSe detectó degradación del servicio o un límite del generador; se detiene la rampa.\n'
      break
    fi
    exit "$decision"
  fi
done
printf '\nPerfil finalizado. Resultado por etapa: %s\n' "$profile_result"
printf 'La ejecución queda abierta para diagnóstico; no se modifica la infraestructura.\n'
printf 'Use status/evidence mientras revisa y recover cuando haya terminado.\n'
