#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
if [[ -s "$CURRENT_RUN_FILE" ]]; then
  gd::die "Hay una ejecución pendiente ($( <"$CURRENT_RUN_FILE" )). Revise el estado y complete recover antes de validar una nueva línea base."
fi

gd::info "Estado actual de Compose"
gd::compose ps

gd::info "Comprobación de PostgreSQL"
gd::compose exec -T database pg_isready -U zulip -d zulip

gd::info "Comprobación del gateway HTTPS"
curl --silent --show-error --fail --insecure \
  --resolve zulip.localhost:8080:127.0.0.1 \
  --max-time 10 --output /dev/null \
  --write-out 'HTTP %{http_code} · %{time_total}s\n' \
  https://zulip.localhost:8080/login/

gd::info "Comprobación de Prometheus"
curl --silent --show-error --fail --max-time 5 \
  http://localhost:9090/-/ready --output /dev/null
printf 'Prometheus está listo.\n'

gd::info "Comprobación de Alertmanager"
curl --silent --show-error --fail --max-time 5 \
  http://localhost:9093/-/ready --output /dev/null
printf 'Alertmanager está listo.\n'

gd::info "Comprobación de Grafana"
curl --silent --show-error --fail --max-time 5 \
  http://localhost:3000/api/health --output /dev/null
printf 'Grafana responde.\n'

gd::info "Confirmación de sondas de dependencias en Prometheus"
gd::wait_all_dependencies_healthy 45

gd::info "Línea base validada"
printf 'El entorno está listo para inyectar GameDay 1.\n'
