.PHONY: test lint run up down build scan cluster deploy smoke load

IMAGE ?= taskflow:local

test:
	cd app && python3 -m pytest -q --cov=. --cov-report=term-missing

lint:
	ruff check app

run:
	cd app && python3 app.py

build:
	docker build -t $(IMAGE) --build-arg APP_VERSION=local .

scan: build
	trivy image --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE)

up:
	docker compose up --build -d

down:
	docker compose down -v

cluster:
	./scripts/bootstrap.sh

smoke:
	./scripts/smoke-test.sh $(URL)

load:
	./scripts/load-test.sh $(URL)
