"""TaskFlow API - a small task-tracking REST service used as the capstone workload.

Production-readiness features:
  * /healthz (liveness) and /readyz (readiness) probes
  * /metrics in Prometheus format (request count, latency histogram, task gauge)
  * structured JSON logs with a per-request id (shipped to Loki by Promtail)
  * FAIL_RATE env var to inject errors, used to demo automated canary rollback
"""
import json
import logging
import os
import random
import threading
import time
import uuid
from datetime import datetime, timezone

from flask import Flask, Response, g, jsonify, request
from metrics import Counter, Gauge, Histogram, Registry

APP_VERSION = os.getenv("APP_VERSION", "dev")
GIT_SHA = os.getenv("GIT_SHA", "unknown")


class JsonFormatter(logging.Formatter):
    _SKIP = set(logging.LogRecord("", 0, "", 0, "", (), None).__dict__) | {"message", "asctime"}

    def format(self, record):
        payload = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
            "version": APP_VERSION,
        }
        payload.update({k: v for k, v in record.__dict__.items() if k not in self._SKIP})
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def _configure_logging():
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())
    logging.getLogger("werkzeug").setLevel(logging.WARNING)


def create_app(config=None):
    _configure_logging()
    app = Flask(__name__)
    app.config["FAIL_RATE"] = float(os.getenv("FAIL_RATE", "0"))
    app.config["MAX_TITLE_LEN"] = 200
    if config:
        app.config.update(config)

    log = logging.getLogger("taskflow")
    registry = Registry()
    req_total = Counter("taskflow_http_requests_total", "HTTP requests.", registry)
    req_latency = Histogram("taskflow_http_request_duration_seconds", "Request latency.", registry)
    tasks_gauge = Gauge("taskflow_tasks_total", "Tasks currently stored.", registry)
    build_info = Gauge("taskflow_build_info", "Build information.", registry)
    build_info.set(1, version=APP_VERSION, git_sha=GIT_SHA)
    tasks_gauge.set(0)

    store, lock, counter = {}, threading.Lock(), {"next": 1}
    state = {"ready": True}
    app.extensions["taskflow_state"] = state

    @app.before_request
    def _start():
        g.start = time.perf_counter()
        g.request_id = request.headers.get("X-Request-ID", uuid.uuid4().hex[:16])
        if request.path.startswith("/api/") and random.random() < app.config["FAIL_RATE"]:
            log.error("injected failure", extra={"request_id": g.request_id, "path": request.path})
            return jsonify(error="injected failure"), 500

    @app.after_request
    def _finish(resp):
        elapsed = time.perf_counter() - g.start
        route = request.url_rule.rule if request.url_rule else "unmatched"
        if route != "/metrics":
            req_total.inc(method=request.method, path=route, status=str(resp.status_code))
            req_latency.observe(elapsed, method=request.method, path=route)
        resp.headers["X-Request-ID"] = g.request_id
        if route not in ("/healthz", "/readyz", "/metrics"):
            log.info(
                "request",
                extra={
                    "request_id": g.request_id,
                    "method": request.method,
                    "path": request.path,
                    "status": resp.status_code,
                    "duration_ms": round(elapsed * 1000, 2),
                },
            )
        return resp

    # ---- operational endpoints -------------------------------------------
    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        if not state["ready"]:
            return jsonify(status="not ready"), 503
        return jsonify(status="ready")

    @app.get("/metrics")
    def metrics():
        return Response(registry.render(), mimetype="text/plain; version=0.0.4")

    @app.get("/api/version")
    def version():
        return jsonify(version=APP_VERSION, git_sha=GIT_SHA)

    @app.get("/")
    def index():
        return jsonify(service="taskflow", version=APP_VERSION, docs="GET/POST /api/tasks")

    # ---- business endpoints ----------------------------------------------
    def _validate(body, partial=False):
        if not isinstance(body, dict):
            return None, "JSON object body required"
        out = {}
        if "title" in body or not partial:
            title = body.get("title")
            if not isinstance(title, str) or not title.strip():
                return None, "title is required and must be a non-empty string"
            if len(title) > app.config["MAX_TITLE_LEN"]:
                return None, f"title must be at most {app.config['MAX_TITLE_LEN']} characters"
            out["title"] = title.strip()
        if "done" in body:
            if not isinstance(body["done"], bool):
                return None, "done must be a boolean"
            out["done"] = body["done"]
        return out, None

    @app.get("/api/tasks")
    def list_tasks():
        with lock:
            return jsonify(sorted(store.values(), key=lambda t: t["id"]))

    @app.post("/api/tasks")
    def create_task():
        data, err = _validate(request.get_json(silent=True))
        if err:
            return jsonify(error=err), 400
        with lock:
            tid = counter["next"]
            counter["next"] += 1
            task = {
                "id": tid,
                "title": data["title"],
                "done": data.get("done", False),
                "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            }
            store[tid] = task
            tasks_gauge.set(len(store))
        return jsonify(task), 201

    @app.get("/api/tasks/<int:tid>")
    def get_task(tid):
        with lock:
            task = store.get(tid)
        return (jsonify(task), 200) if task else (jsonify(error="not found"), 404)

    @app.put("/api/tasks/<int:tid>")
    def update_task(tid):
        data, err = _validate(request.get_json(silent=True), partial=True)
        if err:
            return jsonify(error=err), 400
        with lock:
            task = store.get(tid)
            if not task:
                return jsonify(error="not found"), 404
            task.update(data)
            return jsonify(task)

    @app.delete("/api/tasks/<int:tid>")
    def delete_task(tid):
        with lock:
            if store.pop(tid, None) is None:
                return jsonify(error="not found"), 404
            tasks_gauge.set(len(store))
        return "", 204

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
