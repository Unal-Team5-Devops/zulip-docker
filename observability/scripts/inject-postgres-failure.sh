#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
exec ./observability/gameday/postgres-failure/scripts/gameday.sh inject
