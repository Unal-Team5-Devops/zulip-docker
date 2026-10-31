import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

parser = argparse.ArgumentParser()
parser.add_argument('name')
args = parser.parse_args()
queries = ['sum(rate(zulip_postgres_stat_total{operation=~"commit|rollback"}[5m]))', 'zulip_postgres_connections / zulip_postgres_max_connections', 'zulip_gateway_connections{state="active"} / 1024', 'zulip:telemetry_coverage:ratio', 'up', 'zulip_dependency_up', 'zulip:slo_compliance:30d', 'zulip:error_budget_remaining:ratio', 'zulip:slo_burn_rate:5m', 'zulip:slo_burn_rate:1h', 'ALERTS', 'sum by(status_class)(zulip_http_requests_total)', 'histogram_quantile(.95,sum by(le)(rate(zulip_http_request_duration_seconds_bucket[5m])))']
result = {'captured_at': datetime.now(timezone.utc).isoformat(), 'queries': {}}
for query in queries:
    with urlopen('http://localhost:9090/api/v1/query?' + urlencode({'query': query}), timeout=10) as response:
        result['queries'][query] = json.load(response)
for name, url in [('alertmanager', 'http://localhost:9093/api/v2/alerts'), ('targets', 'http://localhost:9090/api/v1/targets')]:
    with urlopen(url, timeout=10) as response:
        result[name] = json.load(response)
path = Path(__file__).resolve().parents[1] / 'evidence' / (args.name + '.json')
path.write_text(json.dumps(result, indent=2) + '\n')
print(path)
