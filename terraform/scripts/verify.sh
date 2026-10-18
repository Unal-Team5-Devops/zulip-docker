#!/usr/bin/env bash
# Comprueba el despliegue hecho con terraform apply (versión Linux/macOS de verify.ps1).
# Uso: ./scripts/verify.sh [prefijo] [url]
set -uo pipefail
PREFIX="${1:-zulip-dev}"
URL="${2:-https://zulip.localhost/}"
APP="$PREFIX-zulip"
DATA=("$PREFIX-postgres" "$PREFIX-memcached" "$PREFIX-rabbitmq" "$PREFIX-redis")
fail=0

echo "== Estado de los contenedores =="
for name in "$APP" "${DATA[@]}"; do
  status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null) \
    || { echo "No existe $name; ejecute terraform apply primero." >&2; exit 1; }
  printf '%-22s %s\n' "$name" "$status"
  if [ "$name" != "$APP" ] && [ "$status" != "healthy" ]; then
    echo "  aviso: $name no está healthy; revise docker logs $name"; fail=1
  fi
done

echo; echo "== Solo Zulip publica puertos =="
for name in "${DATA[@]}"; do
  if [ -n "$(docker port "$name")" ]; then
    echo "ERROR: $name publica puertos en el host" >&2; fail=1
  else
    echo "$name: sin puertos publicados"
  fi
done
docker port "$APP"

echo; echo "== Respuesta HTTPS =="
code=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL") || code="sin respuesta"
echo "$URL -> $code"

echo; echo "== Redes y volúmenes =="
for net in "$PREFIX-frontend" "$PREFIX-backend"; do
  docker network inspect "$net" --format '{{.Name}} internal={{.Internal}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} contenedores={{len .Containers}}'
done
docker volume ls --filter "name=$PREFIX-"
exit "$fail"
