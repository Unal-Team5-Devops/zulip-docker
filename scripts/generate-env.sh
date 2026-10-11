#!/usr/bin/env bash
# Genera .env con secretos aleatorios a partir de .env.example. No sobrescribe.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -e .env ]]; then
  echo ".env ya existe; no se sobrescribe." >&2
  exit 1
fi

rand() { openssl rand -hex 24; }

umask 077
while IFS= read -r line; do
  case "$line" in
    ZULIP__*=*) echo "${line%%=*}=$(rand)" ;;
    *) echo "$line" ;;
  esac
done < .env.example > .env
echo ".env creado (permisos 600). Edite ZULIP_EXTERNAL_HOST y ZULIP_ADMINISTRATOR."
