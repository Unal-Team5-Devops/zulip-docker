#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ ! -f .env ]]; then
  ./scripts/generate-env.sh
  python3 - <<'PYENV'
from pathlib import Path
path = Path('.env')
path.write_text(path.read_text().replace('ZULIP_EXTERNAL_HOST=zulip.localhost', 'ZULIP_EXTERNAL_HOST=zulip.localhost:8080'))
PYENV
fi
if ! grep -q '^GRAFANA_ADMIN_PASSWORD=' .env; then
  printf '\nGRAFANA_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)" >> .env
  chmod 600 .env
fi
if ! grep -Eq '^GRAFANA_ADMIN_PASSWORD=.{16,}$' .env; then
  echo 'Defina GRAFANA_ADMIN_PASSWORD con al menos 16 caracteres en .env' >&2
  exit 1
fi
mkdir -p observability/.local/tls
if [[ ! -f observability/.local/tls/key.pem ]]; then
  umask 077
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout observability/.local/tls/key.pem \
    -out observability/.local/tls/cert.pem \
    -subj '/CN=zulip.localhost' -addext 'subjectAltName=DNS:zulip.localhost,DNS:localhost,IP:127.0.0.1'
fi
./observability/scripts/compose.sh up -d
