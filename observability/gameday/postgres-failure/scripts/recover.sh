#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
gd::require_active_run

printf 'Se va a iniciar el contenedor PostgreSQL existente para la ejecución %s.\n' "$RUN_ID"
printf 'No se eliminará ni recreará el volumen de datos.\n'
gd::compose start database

gd::info "Esperando a que PostgreSQL acepte conexiones"
READY=false
for attempt in $(seq 1 60); do
  if gd::compose exec -T database pg_isready -U zulip -d zulip >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 2
done
[[ "$READY" == true ]] || gd::die "PostgreSQL no respondió en 120 segundos. El identificador de ejecución se conserva; continúe el diagnóstico."

gd::compose exec -T database psql -U zulip -d zulip -c \
  'SELECT now() AS recovered_at, pg_postmaster_start_time() AS postgres_started_at;'

gd::info "Esperando a que Prometheus confirme la recuperación de la dependencia"
if ! gd::wait_dependency_metric 1 45; then
  gd::die "PostgreSQL responde, pero Prometheus no ha confirmado la sonda en 45 segundos. El identificador de ejecución se conserva."
fi

gd::info "Comprobando la ruta pública de Zulip"
curl --silent --show-error --fail --insecure \
  --resolve zulip.localhost:8080:127.0.0.1 \
  --max-time 15 --output /dev/null \
  --write-out 'HTTP %{http_code} · %{time_total}s\n' \
  https://zulip.localhost:8080/login/

gd::info "Capturando evidencia de recuperación"
gd::capture recovery "$RUN_ID"

rm -f "$CURRENT_RUN_FILE"
printf '\nRecuperación completada y evidencia guardada.\n'
printf 'Revise Grafana y Alertmanager; las ventanas largas de SLO pueden seguir reflejando el incidente.\n'
