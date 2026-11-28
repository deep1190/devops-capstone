#!/usr/bin/env bash
# Demonstrates automated rollback: deploys a "bad" release that returns 500s,
# generates traffic, and shows Argo Rollouts aborting the canary.
# Requires the platform from bootstrap.sh and the kubectl-argo-rollouts plugin.
set -euo pipefail
NS=taskflow
BASE="${1:-http://taskflow.local}"

echo "==> Simulating a bad release: 60% of API calls will fail"
kubectl -n $NS patch configmap taskflow-config --type merge -p '{"data":{"FAIL_RATE":"0.6"}}'
# Force a new ReplicaSet (config changes alone don't roll pods).
kubectl argo rollouts -n $NS restart taskflow

echo "==> Sending traffic for 3 minutes while the canary is analysed"
./scripts/load-test.sh "$BASE" 180 5 &
kubectl argo rollouts -n $NS get rollout taskflow --watch &
WATCH=$!
wait %1 || true
kill $WATCH 2>/dev/null || true

echo "==> Final status (expect: Degraded/Aborted, stable ReplicaSet still serving)"
kubectl argo rollouts -n $NS status taskflow --timeout 5s || true
kubectl -n $NS get analysisrun

echo "==> Restoring healthy config"
kubectl -n $NS patch configmap taskflow-config --type merge -p '{"data":{"FAIL_RATE":"0"}}'
kubectl argo rollouts -n $NS retry rollout taskflow || true
