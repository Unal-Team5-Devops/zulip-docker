#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
./observability/scripts/compose.sh config --quiet
docker run --rm --entrypoint promtool -v "$PWD/observability:/work:ro" -w /work/tests \
  prom/prometheus:v3.2.1 check rules /work/prometheus/rules.yml
docker run --rm --entrypoint promtool -v "$PWD/observability:/work:ro" -w /work/tests \
  prom/prometheus:v3.2.1 test rules rules.test.yml
docker run --rm --entrypoint amtool -v "$PWD/observability/alertmanager:/config:ro" \
  prom/alertmanager:v0.28.1 check-config /config/alertmanager.yml
python3 -m unittest discover -s observability/tests -p 'test_*.py'
