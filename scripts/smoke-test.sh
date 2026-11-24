#!/usr/bin/env bash
# Post-deploy smoke test. Usage: ./scripts/smoke-test.sh http://taskflow.local
set -euo pipefail
BASE="${1:-http://localhost:8080}"
fail() { echo "FAIL: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "$1 is required"; }
need curl; need python3

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

[ "$(code "$BASE/healthz")" = 200 ] || fail "/healthz"
[ "$(code "$BASE/readyz")" = 200 ]  || fail "/readyz"
echo "ok  health + readiness"

resp=$(curl -s -X POST "$BASE/api/tasks" -H 'Content-Type: application/json' -d '{"title":"smoke"}')
id=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["id"])' "$resp") || fail "create task: $resp"
echo "ok  created task $id"

[ "$(code "$BASE/api/tasks/$id")" = 200 ] || fail "get task"
[ "$(code -X PUT "$BASE/api/tasks/$id" -H 'Content-Type: application/json' -d '{"done":true}')" = 200 ] || fail "update task"
[ "$(code -X POST "$BASE/api/tasks" -H 'Content-Type: application/json' -d '{}')" = 400 ] || fail "validation"
[ "$(code -X DELETE "$BASE/api/tasks/$id")" = 204 ] || fail "delete task"
curl -s "$BASE/metrics" | grep -q '^taskflow_http_requests_total' || fail "/metrics"
echo "ok  CRUD, validation, metrics"
echo "SMOKE TEST PASSED ($BASE)"
