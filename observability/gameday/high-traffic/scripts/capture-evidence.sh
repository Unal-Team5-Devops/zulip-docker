#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PHASE="${1:-}"
RUN_ID="${2:-}"
case "$PHASE" in
  pre-incident|incident|recovery) ;;
  *) gd::die "Uso: capture-evidence.sh <pre-incident|incident|recovery> [run-id]" ;;
esac
if [[ -z "$RUN_ID" ]]; then
  gd::require_active_run
fi
[[ "$RUN_ID" =~ ^[A-Za-z0-9TZ_-]+$ ]] || gd::die "run-id inválido."

cd "$REPO_ROOT"
OUTPUT_DIR="$EVIDENCE_DIR/$PHASE/$RUN_ID"
mkdir -p "$OUTPUT_DIR"

gd::info "Capturando evidencia: $PHASE / $RUN_ID"
gd::compose ps --all > "$OUTPUT_DIR/compose-ps.txt" 2>&1 || true
mapfile -t container_ids < <(gd::compose ps -q)
if (( ${#container_ids[@]} > 0 )); then
  docker stats --no-stream "${container_ids[@]}" > "$OUTPUT_DIR/compose-stats.txt" 2>&1 || true
else
  printf 'No se encontraron contenedores activos para capturar estadisticas.\n' > "$OUTPUT_DIR/compose-stats.txt"
fi
if gd::compose exec -T database pg_isready -U zulip -d zulip > "$OUTPUT_DIR/database-health.txt" 2>&1; then
  gd::compose exec -T database psql -U zulip -d zulip -c \
    'SELECT now() AS captured_at, pg_postmaster_start_time() AS postgres_started_at;' \
    >> "$OUTPUT_DIR/database-health.txt" 2>&1 || true
else
  printf '\nPostgreSQL no está disponible durante esta captura.\n' >> "$OUTPUT_DIR/database-health.txt"
fi
{
  curl --silent --show-error --insecure --max-time 10 --resolve zulip.localhost:8080:127.0.0.1 \
    --output /dev/null --write-out 'http_code=%{http_code}\ntime_total_seconds=%{time_total}\n' \
    https://zulip.localhost:8080/login/ || true
} > "$OUTPUT_DIR/gateway-check.txt" 2>&1
gd::compose exec -T gateway sh -c \
  'if [ -f /var/log/telemetry/access.json ]; then tail -n 200 /var/log/telemetry/access.json; else echo "El archivo JSON de access log aún no existe."; fi' \
  > "$OUTPUT_DIR/gateway-access.jsonl" 2>&1 || true
gd::compose logs --since 10m --no-color gateway zulip database redis memcached rabbitmq collector \
  > "$OUTPUT_DIR/service-logs.txt" 2>&1 || true
gd::compose exec -T zulip sh -c \
  'for file in /var/log/nginx/error.log /var/log/zulip/errors.log /var/log/zulip/django.log; do if [ -f "$file" ]; then printf "\n===== %s =====\n" "$file"; tail -n 200 "$file"; fi; done' \
  > "$OUTPUT_DIR/zulip-internal-errors.txt" 2>&1 || true
gd::compose logs --since 10m --no-color alert-receiver \
  > "$OUTPUT_DIR/alert-receiver-logs.txt" 2>&1 || true
python3 "$OBSERVABILITY_DIR/scripts/snapshot.py" "$PHASE-$RUN_ID" \
  --output "$OUTPUT_DIR/snapshot.json"
[[ -s "$OUTPUT_DIR/snapshot.json" ]] || gd::die "No se generó snapshot.json."
printf '\nEvidencia guardada en: %s\n' "$OUTPUT_DIR"
