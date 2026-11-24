#!/usr/bin/env bash
# Runs the app locally, exercises it, and stores real outputs under docs/evidence/.
# Needs only python3 + flask + pytest (no Docker/cluster).
set -euo pipefail
cd "$(dirname "$0")/.."
EV=docs/evidence
mkdir -p "$EV"

echo "==> Unit tests"
(cd app && python3 -m pytest -v 2>&1) | tee "$EV/unit-tests.txt" >/dev/null
if python3 -c "import pytest_cov" 2>/dev/null; then
  (cd app && python3 -m pytest -q --cov=. --cov-report=term 2>&1 | tail -15) > "$EV/coverage.txt"
else
  rm -f "$EV/coverage.txt"; echo "pytest-cov not installed; coverage is enforced in CI"
fi

echo "==> Start app, run smoke test + traffic, capture logs and metrics"
(cd app && PORT=18080 APP_VERSION=evidence GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo local) \
  python3 -c "
import app
app.app.run(port=18080)
" > "../$EV/sample-app.log" 2>&1) &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -s localhost:18080/healthz >/dev/null && break; sleep 0.3; done

./scripts/smoke-test.sh http://localhost:18080 | tee "$EV/smoke-test.txt"
./scripts/load-test.sh http://localhost:18080 5 3 >/dev/null
curl -s localhost:18080/metrics > "$EV/sample-metrics.txt"
curl -s localhost:18080/api/version > "$EV/sample-version.json"
kill $PID 2>/dev/null || true
echo "Evidence written to $EV"
