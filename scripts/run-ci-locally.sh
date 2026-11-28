#!/usr/bin/env bash
# Runs the same checks as the CI pipeline on your machine (skips tools that are not installed).
cd "$(dirname "$0")/.."
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
step "ruff lint";             command -v ruff >/dev/null && ruff check app || echo "(ruff not installed)"
step "unit tests";            (cd app && python3 -m pytest -v)
step "canary decision simulation"; python3 scripts/simulate-canary.py
step "hadolint";              command -v hadolint >/dev/null && hadolint --failure-threshold error Dockerfile && echo "Dockerfile OK" || echo "(hadolint not installed)"
step "kustomize overlays";    if command -v kustomize >/dev/null; then for o in dev prod ci; do kustomize build k8s/overlays/$o >/dev/null 2>&1 || kustomize build k8s/$o >/dev/null && echo "overlay $o renders"; done; else echo "(kustomize not installed)"; fi
step "prometheus rules";      command -v promtool >/dev/null && promtool check rules monitoring/alert-rules.yml || echo "(promtool not installed)"
