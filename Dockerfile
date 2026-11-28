# ---- builder: install deps into an isolated venv ---------------------------
FROM python:3.12-slim AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY app/requirements.txt .
RUN pip install -r requirements.txt

# ---- runtime: minimal, non-root --------------------------------------------
FROM python:3.12-slim AS runtime
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="taskflow" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.version="${APP_VERSION}"
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    APP_VERSION=${APP_VERSION} GIT_SHA=${GIT_SHA} PORT=8080
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --no-create-home app
COPY --from=builder /opt/venv /opt/venv
WORKDIR /srv
COPY --chown=app:app app/app.py app/metrics.py ./
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"
# Single process keeps the in-memory demo store consistent; scale with replicas.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--worker-tmp-dir", "/dev/shm", "--workers", "1", "--threads", "8", "--access-logfile", "-", "app:app"]
