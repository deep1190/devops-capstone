#!/usr/bin/env python3
"""Offline simulation of the canary decision made by Argo Rollouts.

Uses the REAL TaskFlow application (two in-process instances: stable and canary),
splits traffic by the canary weight (20% -> 50% -> 100%), and evaluates the same rule as
k8s/base/analysistemplate.yaml:  success_rate = non-5xx requests / all requests  >= 0.95

Usage:  python3 scripts/simulate-canary.py            (runs both scenarios)
"""
import os
import random
import re
import sys

os.environ["LOG_LEVEL"] = "CRITICAL"  # keep the simulation output readable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
from app import create_app  # noqa: E402

THRESHOLD = 0.95
STEPS = [20, 50, 100]
REQUESTS_PER_STEP = 300


def success_rate(client):
    text = client.get("/metrics").get_data(as_text=True)
    total = ok = 0.0
    for line in text.splitlines():
        m = re.match(r'taskflow_http_requests_total\{.*status="(\d+)"\} ([\d.]+)', line)
        if m and "/api/" in line:
            n = float(m.group(2))
            total += n
            if not m.group(1).startswith("5"):
                ok += n
    return (ok / total) if total else None


def scenario(name, canary_fail_rate, seed):
    random.seed(seed)
    print(f"\n=== Scenario: {name} (canary FAIL_RATE={canary_fail_rate}) ===")
    stable = create_app({"TESTING": True, "FAIL_RATE": 0.0}).test_client()
    canary = create_app({"TESTING": True, "FAIL_RATE": canary_fail_rate}).test_client()
    for weight in STEPS:
        for _ in range(REQUESTS_PER_STEP):
            target = canary if random.random() * 100 < weight else stable
            target.post("/api/tasks", json={"title": "traffic"})
            target.get("/api/tasks")
        rate = success_rate(canary)
        verdict = "OK" if rate is None or rate >= THRESHOLD else "FAIL"
        shown = "no traffic" if rate is None else f"{rate * 100:.1f}%"
        print(f"setWeight {weight:>3}%  canary success rate = {shown:>10}  (threshold {THRESHOLD * 100:.0f}%)  -> {verdict}")
        if verdict == "FAIL":
            print("RESULT: AnalysisRun FAILED -> rollout ABORTED, 100% of traffic returned to the STABLE version")
            return False
    print("RESULT: all steps passed -> canary PROMOTED to 100% (new version is now stable)")
    return True


if __name__ == "__main__":
    good = scenario("healthy release", 0.0, seed=1)
    bad = scenario("faulty release", 0.6, seed=1)
    sys.exit(0 if (good and not bad) else 1)
