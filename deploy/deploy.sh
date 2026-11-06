#!/usr/bin/env bash
# Despliega o actualiza la pila (Zulip + datos + observabilidad) en la instancia
# EC2. Lo ejecuta .github/workflows/deploy.yml en el runner self-hosted; también
# sirve a mano desde un checkout dentro de la instancia.
#
# Principio: la configuración se aplica sin reiniciar Zulip siempre que se pueda.
#   - Reglas/configuración de Prometheus y Alertmanager -> POST /-/reload.
#   - Configuración del gateway o certificado          -> nginx -s reload.
#   - Dashboards de Grafana                             -> Grafana los relee cada 10 s.
#   - Imagen o variables de un servicio                 -> Compose recrea solo ese servicio.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ZULIP_DEPLOY_DIR:-/opt/zulip}"
log() { printf '\n==> %s\n' "$*"; }
fail() { printf '::error::%s\n' "$*" >&2; exit 1; }

# --- 1. Nombre público --------------------------------------------------------
# <ip-con-guiones>.sslip.io resuelve a la IP elástica sin comprar un dominio.
public_host() {
  if [[ -n "${ZULIP_PUBLIC_HOST:-}" ]]; then
    echo "$ZULIP_PUBLIC_HOST"
    return
  fi
  local token ip
  token="$(curl -fsS -X PUT http://169.254.169.254/latest/api/token \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')"
  ip="$(curl -fsS -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/public-ipv4)"
  echo "${ip//./-}.sslip.io:8080"
}
HOST="$(public_host)"
HOST_NAME="${HOST%%:*}"
log "Destino $DEST, nombre público $HOST"

# --- 2. Sincronizar el código --------------------------------------------------
# Huella de la configuración antes del cambio, para decidir qué recargar.
fingerprint() {
  (cd "$DEST" 2>/dev/null && find "$@" -type f -print0 2>/dev/null | sort -z \
    | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1) || echo none
}
before_prometheus="$(fingerprint observability/prometheus)"
before_alertmanager="$(fingerprint observability/alertmanager)"

mkdir -p "$DEST"
# .env (secretos), certificados y evidencias del GameDay viven solo en la
# instancia: se excluyen o se protegen de --delete.
rsync -a --delete \
  --exclude '/.git/' --exclude '/.env' --exclude '/.compose-extra' \
  --exclude '/observability/.local/' --exclude '/terraform/' --exclude '/.venv*/' \
  --filter 'P /observability/evidence/***' \
  --filter 'P /observability/gameday/*/evidence/***' \
  --filter 'P /observability/gameday/*/.state/***' \
  "$SRC"/ "$DEST"/
cd "$DEST"

# --- 3. Configuración del entorno ----------------------------------------------
if [[ ! -f .env ]]; then
  log "Primer despliegue: generando .env con secretos aleatorios"
  ./scripts/generate-env.sh
fi
chmod 600 .env
set_env() {
  if grep -q "^$1=" .env; then
    sed -i "s|^$1=.*|$1=$2|" .env
  else
    printf '%s=%s\n' "$1" "$2" >> .env
  fi
}
set_env ZULIP_EXTERNAL_HOST "$HOST"
# La versión de Zulip se controla desde Git (.env.example), no a mano en la instancia.
set_env ZULIP_IMAGE "$(grep '^ZULIP_IMAGE=' .env.example | cut -d= -f2-)"
grep -Eq '^GRAFANA_ADMIN_PASSWORD=.{16,}$' .env || set_env GRAFANA_ADMIN_PASSWORD "$(openssl rand -hex 24)"

echo "deploy/compose.aws.yml" > .compose-extra

# Certificado autofirmado con el nombre público, sus subdominios (cada
# organización de Zulip usa uno) y zulip.localhost para los scripts del GameDay.
tls_dir=observability/.local/tls
install -d -m 700 "$tls_dir"
tls_changed=false
if [[ ! -f "$tls_dir/cert.pem" ]] || ! openssl x509 -in "$tls_dir/cert.pem" -noout -ext subjectAltName | grep -qF "*.$HOST_NAME"; then
  log "Generando certificado para $HOST_NAME"
  (umask 077 && openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout "$tls_dir/key.pem" -out "$tls_dir/cert.pem" -subj "/CN=$HOST_NAME" \
    -addext "subjectAltName=DNS:$HOST_NAME,DNS:*.$HOST_NAME,DNS:zulip.localhost,DNS:localhost,IP:127.0.0.1" 2>/dev/null)
  tls_changed=true
fi

# Gateway: igual a observability/nginx/nginx.conf, salvo el Host hacia Zulip.
# Los nombres locales que usan los scripts del GameDay dentro de la instancia
# (zulip.localhost, localhost, 127.0.0.1) se reescriben al nombre público; el
# resto pasa intacto, porque Zulip identifica cada organización por su
# subdominio (devops-team5.<ip>.sslip.io) y valida CSRF contra ese Host.
host_map="    map \$http_host \$zulip_host {
        default \$http_host;
        \"~^(zulip\\.localhost|localhost|127\\.0\\.0\\.1)(:[0-9]+)?\$\" \"$HOST\";
    }"
# ENVIRON en lugar de awk -v: -v interpretaría las barras invertidas del regex.
rendered="$(HOST_MAP="$host_map" awk '/map \$http_upgrade/ { print ENVIRON["HOST_MAP"] } { print }' observability/nginx/nginx.conf \
  | sed -e 's|proxy_set_header Host \$http_host;|proxy_set_header Host $zulip_host;|' \
        -e 's|proxy_set_header X-Forwarded-Host \$http_host;|proxy_set_header X-Forwarded-Host $zulip_host;|')"
grep -q 'proxy_set_header Host \$zulip_host;' <<<"$rendered" && grep -qF "\"$HOST\";" <<<"$rendered" \
  || fail "No se pudo generar la configuración del gateway"
nginx_changed=false
if [[ ! -f observability/.local/nginx.conf ]] || [[ "$(cat observability/.local/nginx.conf)" != "$rendered" ]]; then
  # Se escribe sobre el mismo archivo (mismo inode): el contenedor lo monta como
  # archivo suelto y no vería un reemplazo.
  printf '%s\n' "$rendered" > observability/.local/nginx.conf
  nginx_changed=true
fi

# --- 4. Levantar o actualizar ---------------------------------------------------
# Zulip se despliega con la imagen que publicó el CI en GHCR, nunca construida
# aquí: docker-compose.yml también declara "build" para uso local, y un
# "up --build" la reconstruiría en la instancia (25 min y una imagen distinta
# del artefacto probado). Solo se construyen el colector y el receptor de alertas.
log "Descargando imágenes (Zulip desde GHCR: $(grep '^ZULIP_IMAGE=' .env | cut -d= -f2-))"
./observability/scripts/compose.sh pull --quiet --ignore-buildable
./observability/scripts/compose.sh pull --quiet zulip
log "Construyendo colector y receptor de alertas"
./observability/scripts/compose.sh build --quiet collector alert-receiver
log "docker compose up (Compose recrea solo los servicios cuya definición o imagen cambió)"
./observability/scripts/compose.sh up -d --no-build --remove-orphans --wait --wait-timeout 1200

# --- 5. Recargas en caliente -----------------------------------------------------
reloaded=()
if [[ "$(fingerprint observability/prometheus)" != "$before_prometheus" ]]; then
  curl -fsS -X POST http://127.0.0.1:9090/-/reload && reloaded+=(prometheus)
fi
if [[ "$(fingerprint observability/alertmanager)" != "$before_alertmanager" ]]; then
  curl -fsS -X POST http://127.0.0.1:9093/-/reload && reloaded+=(alertmanager)
fi
if [[ "$nginx_changed" == true || "$tls_changed" == true ]]; then
  ./observability/scripts/compose.sh exec -T gateway nginx -t
  ./observability/scripts/compose.sh exec -T gateway nginx -s reload && reloaded+=(gateway)
fi
log "Recargados en caliente: ${reloaded[*]:-ninguno}"

# --- 6. Verificación ------------------------------------------------------------
query() {
  curl -fsS --get --data-urlencode "query=$1" http://127.0.0.1:9090/api/v1/query \
    | jq -r '.data.result[0].value[1] // "nan"'
}
log "Verificando Zulip a través del gateway"
for _ in $(seq 1 30); do
  if curl -kfsS --max-time 10 --resolve "$HOST_NAME:8080:127.0.0.1" \
      "https://$HOST/api/v1/server_settings" -o /dev/null; then
    zulip_ok=true
    break
  fi
  sleep 10
done
[[ "${zulip_ok:-false}" == true ]] || fail "Zulip no responde a través del gateway"

log "Verificando telemetría (targets, sondas y recarga de configuración)"
for _ in $(seq 1 18); do
  targets="$(query 'min(up)')"
  probes="$(query 'count(zulip_dependency_up == 1)')"
  prom_cfg="$(query 'prometheus_config_last_reload_successful')"
  [[ "$targets" == 1 && "$probes" == 5 && "$prom_cfg" == 1 ]] && break
  sleep 10
done
[[ "$targets" == 1 ]] || fail "Hay targets de Prometheus caídos (min(up)=$targets)"
[[ "$probes" == 5 ]] || fail "No todas las dependencias responden ($probes de 5)"
[[ "$prom_cfg" == 1 ]] || fail "Prometheus rechazó la configuración nueva"

log "Despliegue correcto: https://$HOST"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "url=https://$HOST" >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Despliegue en AWS"
    echo "| | |"
    echo "|---|---|"
    echo "| Zulip | https://$HOST |"
    echo "| Commit | \`${GITHUB_SHA:-local}\` |"
    echo "| Imagen | \`$(grep '^ZULIP_IMAGE=' .env | cut -d= -f2-)\` |"
    echo "| Recargado en caliente | ${reloaded[*]:-ninguno} |"
    echo "| Targets / sondas | up=$targets, dependencias=$probes/5 |"
    echo
    echo '```'
    ./observability/scripts/compose.sh ps --format 'table {{.Service}}\t{{.Status}}'
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
