#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
gd::info "Contenedores"
gd::compose ps --all

gd::info "Estado de pg_isready"
if gd::compose exec -T database pg_isready -U zulip -d zulip; then
  printf 'PostgreSQL acepta conexiones.\n'
else
  printf 'PostgreSQL no está disponible. Continúe el diagnóstico; no se ejecuta recuperación.\n'
fi

gd::info "Sonda de dependencias en Prometheus"
if curl --silent --show-error --fail --get \
  --data-urlencode 'query=zulip_dependency_up' \
  http://localhost:9090/api/v1/query; then
  printf '\n'
else
  printf 'No se pudo consultar Prometheus.\n' >&2
fi

gd::info "Ejecución activa"
if [[ -s "$CURRENT_RUN_FILE" ]]; then
  printf 'run-id=%s\n' "$(<"$CURRENT_RUN_FILE")"
  printf 'La recuperación sigue siendo una acción manual.\n'
else
  printf 'No hay una ejecución pendiente de recuperación.\n'
fi
