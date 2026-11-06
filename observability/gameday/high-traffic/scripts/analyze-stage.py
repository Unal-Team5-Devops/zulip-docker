"""Compare measured gateway signals with the GameDay SLO thresholds."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import math
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen


parser = argparse.ArgumentParser()
parser.add_argument('--stage', type=int, required=True)
parser.add_argument('--report', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--summary', type=Path, required=True)
args = parser.parse_args()

queries = {
    'gateway_rps': 'sum(rate(zulip_http_requests_total[1m]))',
    'gateway_5xx_ratio': (
        'sum(rate(zulip_http_requests_total{status_class="5xx"}[1m]))'
        ' / sum(rate(zulip_http_requests_total[1m]))'
    ),
    'gateway_p95_seconds': (
        'histogram_quantile(0.95, sum by(le) '
        '(rate(zulip_http_request_duration_seconds_bucket[1m])))'
    ),
    'container_cpu_cores': (
        'sum by(name)(rate(container_cpu_usage_seconds_total'
        '{name=~".*zulip.*"}[1m]))'
    ),
    'container_memory_bytes': (
        'sum by(name)(container_memory_working_set_bytes'
        '{name=~".*zulip.*"})'
    ),
    'collector_up': 'up{job="zulip"}',
}

with args.report.open(encoding='utf-8') as stream:
    client = json.load(stream)

metrics = {}
errors = {}


def query_prometheus(name, query):
    try:
        url = 'http://localhost:9090/api/v1/query?' + urlencode({'query': query})
        with urlopen(url, timeout=5) as response:
            payload = json.load(response)
        if payload.get('status') != 'success':
            raise ValueError(payload.get('error', 'consulta Prometheus fallida'))
        return name, payload.get('data', {}).get('result', []), None
    except Exception as exc:
        return name, [], type(exc).__name__


with ThreadPoolExecutor(max_workers=len(queries)) as executor:
    futures = [executor.submit(query_prometheus, name, query)
               for name, query in queries.items()]
    for future in as_completed(futures):
        name, values, error = future.result()
        metrics[name] = values
        if error:
            errors[name] = error


def single_value(name):
    values = metrics[name]
    if not values:
        return None
    value = float(values[0]['value'][1])
    return value if math.isfinite(value) else None


gateway_rps = single_value('gateway_rps')
gateway_errors = single_value('gateway_5xx_ratio')
gateway_p95 = single_value('gateway_p95_seconds')
collector_up = single_value('collector_up')
offered = client['offered']
dropped = client['dropped_before_send']
drop_ratio = dropped / offered if offered else 0
expected = client['expected_requests']
scheduler_shortfall = max(0, expected - offered) / expected if expected else 0
requests = client['requests']
http_5xx = sum(int(count) for code, count in client['statuses'].items()
               if code.isdigit() and int(code) >= 500)
transport_errors = int(client['statuses'].get('0', 0))
client_http_5xx_ratio = http_5xx / requests if requests else 0
client_transport_error_ratio = transport_errors / requests if requests else 0

reasons = []
if gateway_errors is not None and gateway_errors > 0.01:
    reasons.append('gateway_5xx_above_1_percent')
if gateway_p95 is not None and gateway_p95 > 0.5:
    reasons.append('gateway_p95_above_500_ms')
service_breach = bool(reasons)
if (collector_up != 1 or gateway_rps is None or gateway_rps <= 0
        or gateway_errors is None or gateway_p95 is None):
    reasons.append('telemetry_missing')
if (drop_ratio > 0.05 or scheduler_shortfall > 0.05
        or client_transport_error_ratio > 0.05):
    reasons.append('generator_limit_or_network_error')

analysis = {
    'stage': args.stage,
    'configured_rps': client['configured_rps'],
    'client_actual_rps': client['actual_rps'],
    'client_completed_during_window_rps': client['completed_during_window_rps'],
    'client_p95_seconds': client['p95_seconds'],
    'client_p95_queue_seconds': client['p95_queue_seconds'],
    'client_http_5xx_ratio': client_http_5xx_ratio,
    'client_transport_error_ratio': client_transport_error_ratio,
    'generator_drop_ratio': drop_ratio,
    'scheduler_shortfall_ratio': scheduler_shortfall,
    'gateway_rps': gateway_rps,
    'gateway_5xx_ratio': gateway_errors,
    'gateway_p95_seconds': gateway_p95,
    'service_slo_breached': service_breach,
    'stop_reasons': reasons,
    'prometheus_queries': queries,
    'prometheus_results': metrics,
    'prometheus_errors': errors,
}
args.output.write_text(json.dumps(analysis, indent=2) + '\n', encoding='utf-8')


def display(value, digits=3):
    return 'n/a' if value is None else f'{value:.{digits}f}'


summary = (
    f'{args.stage} {client["configured_rps"]} {display(client["actual_rps"])} '
    f'{display(gateway_rps)} {display(gateway_errors, 4)} '
    f'{display(gateway_p95)} {display(client_http_5xx_ratio, 4)} '
    f'{display(client_transport_error_ratio, 4)} {display(drop_ratio, 4)} '
    f'{display(scheduler_shortfall, 4)} '
    f'{"|".join(reasons) if reasons else "within_slo"}\n'
)
with args.summary.open('a', encoding='utf-8') as stream:
    stream.write(summary)
print(summary.strip())
raise SystemExit(10 if reasons else 0)
