#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
files=(-f docker-compose.yml -f observability/compose.yml)
# Un entorno puede sumar archivos propios listándolos en .compose-extra (uno por
# línea; no se versiona). En AWS lo crea deploy/deploy.sh con deploy/compose.aws.yml.
if [[ -f .compose-extra ]]; then
  while IFS= read -r extra; do
    [[ -n "$extra" && "$extra" != \#* ]] && files+=(-f "$extra")
  done < .compose-extra
fi
exec docker compose "${files[@]}" "$@"
