import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from app import create_app  # noqa: E402


@pytest.fixture()
def client():
    return create_app({"TESTING": True, "FAIL_RATE": 0.0}).test_client()


def test_health_and_ready(client):
    assert client.get("/healthz").get_json() == {"status": "ok"}
    assert client.get("/readyz").get_json() == {"status": "ready"}


def test_not_ready_returns_503():
    app = create_app({"TESTING": True})
    app.extensions["taskflow_state"]["ready"] = False
    assert app.test_client().get("/readyz").status_code == 503


def test_create_and_get_task(client):
    r = client.post("/api/tasks", json={"title": "write report"})
    assert r.status_code == 201
    body = r.get_json()
    assert body["id"] == 1 and body["done"] is False
    assert client.get("/api/tasks/1").get_json()["title"] == "write report"
    assert len(client.get("/api/tasks").get_json()) == 1


@pytest.mark.parametrize(
    "payload",
    [{}, {"title": ""}, {"title": "   "}, {"title": 5}, {"title": "x" * 201}, {"title": "ok", "done": "yes"}],
)
def test_validation_rejects_bad_input(client, payload):
    assert client.post("/api/tasks", json=payload).status_code == 400


def test_non_json_body_rejected(client):
    assert client.post("/api/tasks", data="nope").status_code == 400


def test_update_and_delete(client):
    client.post("/api/tasks", json={"title": "a"})
    r = client.put("/api/tasks/1", json={"done": True})
    assert r.get_json()["done"] is True
    assert client.delete("/api/tasks/1").status_code == 204
    assert client.get("/api/tasks/1").status_code == 404
    assert client.delete("/api/tasks/1").status_code == 404
    assert client.put("/api/tasks/99", json={"done": True}).status_code == 404


def test_request_id_header_propagated(client):
    r = client.get("/", headers={"X-Request-ID": "abc123"})
    assert r.headers["X-Request-ID"] == "abc123"
    assert "X-Request-ID" in client.get("/").headers


def test_metrics_exposed(client):
    client.post("/api/tasks", json={"title": "m"})
    client.get("/api/tasks/404")
    text = client.get("/metrics").get_data(as_text=True)
    assert "# TYPE taskflow_http_requests_total counter" in text
    assert 'taskflow_http_requests_total{method="POST",path="/api/tasks",status="201"} 1.0' in text
    assert 'status="404"' in text
    assert "taskflow_http_request_duration_seconds_bucket" in text
    assert "taskflow_tasks_total 1.0" in text


def test_metrics_endpoint_not_self_counted(client):
    client.get("/metrics")
    assert 'path="/metrics"' not in client.get("/metrics").get_data(as_text=True)


def test_fail_rate_injects_500s_on_api_only():
    client = create_app({"TESTING": True, "FAIL_RATE": 1.0}).test_client()
    assert client.get("/api/tasks").status_code == 500
    assert client.get("/healthz").status_code == 200  # probes stay healthy


def test_version_endpoint(client):
    body = client.get("/api/version").get_json()
    assert set(body) == {"version", "git_sha"}
