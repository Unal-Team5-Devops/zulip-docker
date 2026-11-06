#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$REPO_ROOT"
if [[ -s "$CURRENT_RUN_FILE" ]]; then
  gd::die "Hay una ejecución pendiente ($( <"$CURRENT_RUN_FILE" )). Revise status y complete recover antes de iniciar otra."
fi

gd::info "Contenedores del stack"
gd::compose ps --all
gd::info "Validando línea base de aplicación y observabilidad"
gd::check_ready
python3 - <<'PY'
import json
import math
from urllib.parse import urlencode
from urllib.request import urlopen

checks = {
    '5xx': ('(sum(rate(zulip_http_requests_total{status_class="5xx"}[1m])) / '
            'sum(rate(zulip_http_requests_total[1m]))) and '
            '(sum(rate(zulip_http_requests_total[1m])) > 0)', 0.01),
    'p95': ('histogram_quantile(0.95, sum by(le) '
            '(rate(zulip_http_request_duration_seconds_bucket[1m]))) and '
            '(sum(rate(zulip_http_requests_total[1m])) > 0)', 0.5),
}
for name, (query, limit) in checks.items():
    url = 'http://localhost:9090/api/v1/query?' + urlencode({'query': query})
    with urlopen(url, timeout=5) as response:
        payload = json.load(response)
    if payload.get('status') != 'success':
        raise SystemExit(f'No se pudo verificar la línea base de {name}.')
    values = payload.get('data', {}).get('result', [])
    if values:
        value = float(values[0]['value'][1])
        if not math.isfinite(value) or value > limit:
            raise SystemExit(
                f'Línea base degradada: {name}={value:.3f} (límite {limit}). '
                'Espere a que se vacíe la ventana de 1 minuto antes de inyectar.')
print('Línea base HTTP sana: 5xx <= 1% y p95 <= 500 ms en el último minuto.')
PY
gd::info "Línea base validada; cAdvisor y las cinco sondas están disponibles."
