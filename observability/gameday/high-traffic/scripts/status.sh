#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
gd::info "Estado de los servicios"
gd::compose ps --all
gd::info "Ejecución del escenario"
if [[ -s "$CURRENT_RUN_FILE" ]]; then
  printf 'run-id=%s\n' "$(<"$CURRENT_RUN_FILE")"
else
  printf 'No hay ejecución pendiente.\n'
fi
if [[ -s "$PROFILE_PID_FILE" ]]; then
  printf 'profile-pid=%s (si el proceso ya no existe, recover limpiará el marcador)\n' "$(<"$PROFILE_PID_FILE")"
fi
gd::info "Tráfico, errores y latencia (último minuto / ventana de 5 min)"
for query in \
  'sum(rate(zulip_http_requests_total[1m]))' \
  'sum(rate(zulip_http_requests_total{status_class="5xx"}[1m])) / sum(rate(zulip_http_requests_total[1m]))' \
  'histogram_quantile(0.95,sum by(le)(rate(zulip_http_request_duration_seconds_bucket[5m])))' \
  'sum by(name)(rate(container_cpu_usage_seconds_total{name=~".*zulip.*"}[1m]))' \
  'sum by(name)(container_memory_working_set_bytes{name=~".*zulip.*"})' \
  'zulip_dependency_up'; do
  printf '\nPromQL: %s\n' "$query"
  curl --silent --show-error --fail --get --data-urlencode "query=$query" \
    http://localhost:9090/api/v1/query || true
  printf '\n'
done
