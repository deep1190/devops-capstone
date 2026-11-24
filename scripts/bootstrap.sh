#!/usr/bin/env bash
# One-command platform bring-up: cluster + ingress + Argo + monitoring + logging + app.
# Prereqs: docker, terraform, kubectl (see ansible/bootstrap-host.yml).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GH_USER:?export GH_USER=<your github username>}"
export TF_VAR_grafana_admin_password="${TF_VAR_grafana_admin_password:-$(openssl rand -base64 18)}"

echo "==> Pointing manifests at your GitHub user ($GH_USER)"
grep -rl YOUR_GH_USER k8s argocd .github 2>/dev/null | xargs -r sed -i "s/YOUR_GH_USER/${GH_USER,,}/g" || true

echo "==> Terraform: cluster + platform components"
terraform -chdir=terraform init -input=false
terraform -chdir=terraform apply -auto-approve -input=false

export KUBECONFIG="$(terraform -chdir=terraform output -raw kubeconfig_path)"

echo "==> Alert receiver + GitOps application"
kubectl apply -f monitoring/alert-sink.yaml
kubectl apply -f argocd/application.yaml

echo "==> Waiting for the rollout to become healthy"
kubectl -n taskflow wait --for=condition=available rollout/taskflow --timeout=300s || \
  kubectl -n taskflow get rollout,pods

grep -q "taskflow.local" /etc/hosts || echo "Add to /etc/hosts:  127.0.0.1 taskflow.local"
echo "Grafana admin password: $TF_VAR_grafana_admin_password"
echo "Done. Try: ./scripts/smoke-test.sh http://taskflow.local"
