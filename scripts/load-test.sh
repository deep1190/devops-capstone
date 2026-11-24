#!/usr/bin/env bash
# Generates steady traffic so dashboards, HPA and canary analysis have data.
# Usage: ./scripts/load-test.sh http://taskflow.local [seconds] [concurrency]
set -euo pipefail
BASE="${1:-http://localhost:8080}"
DURATION="${2:-60}"
CONC="${3:-5}"
end=$((SECONDS + DURATION))

worker() {
  while [ $SECONDS -lt $end ]; do
    curl -s -o /dev/null -X POST "$BASE/api/tasks" -H 'Content-Type: application/json' -d '{"title":"load"}'
    curl -s -o /dev/null "$BASE/api/tasks"
    curl -s -o /dev/null "$BASE/api/tasks/1"
  done
}
for _ in $(seq "$CONC"); do worker & done
wait
echo "load test finished (${DURATION}s, ${CONC} workers)"
