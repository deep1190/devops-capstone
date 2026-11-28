#!/usr/bin/env bash
# One-command platform bring-up: cluster + ingress + Argo + monitoring + logging + app.
# Prereqs: docker, terraform, kubectl (see ansible/bootstrap-host.yml).
# The GitHub repo is detected from `git remote origin`; nothing needs editing.
set -euo pipefail
cd "$(dirname "$0")/.."

REMOTE="$(git remote get-url origin 2>/dev/null || true)"
SLUG="$(echo "$REMOTE" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
[ -n "$SLUG" ] || { echo "No git remote 'origin'. Push this repo to GitHub first."; exit 1; }
export TF_VAR_grafana_admin_password="${TF_VAR_grafana_admin_password:-$(openssl rand -base64 18)}"

echo "==> Terraform: cluster + platform components"
terraform -chdir=terraform init -input=false
terraform -chdir=terraform apply -auto-approve -input=false
export KUBECONFIG="$(terraform -chdir=terraform output -raw kubeconfig_path)"

echo "==> Alert receiver + GitOps application for $SLUG"
kubectl apply -f monitoring/alert-sink.yaml
sed "s#YOUR_GH_USER/devops-capstone#${SLUG}#" argocd/application.yaml | kubectl apply -f -

echo "==> Waiting for the rollout to become healthy"
kubectl -n taskflow wait --for=condition=available rollout/taskflow --timeout=300s || \
  kubectl -n taskflow get rollout,pods

grep -q "taskflow.local" /etc/hosts || echo "Add to /etc/hosts:  127.0.0.1 taskflow.local"
echo "Grafana admin password: $TF_VAR_grafana_admin_password"
echo "Done. Try: ./scripts/smoke-test.sh http://taskflow.local"
