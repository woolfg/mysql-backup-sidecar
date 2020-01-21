SHELL := /bin/bash
VERSION_TAG := $(shell git describe HEAD)

IMAGE_NAME := woolfg/mysql-backup-sidecar
PROJECT := mysql-backup-sidecar

DOCKER_COMPOSE_DEV := docker-compose -p $(PROJECT) -f examples/docker-compose.dev.yml
 

export

.PHONY: help
help: ## help message, list all command
	@echo -e "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)"

.PHONY: build
build: ## build docker image
	docker build -t $(IMAGE_NAME):$(VERSION_TAG) .

.PHONY: cronrun
cronrun: ## run container starting the pattern every minute
	docker run -e CRON_PATTERN="* * * * *" $(IMAGE_NAME):$(VERSION_TAG)

.PHONY: run
run: ## run the example docker compose stack
	$(DOCKER_COMPOSE_DEV) up

.PHONY: shell-% 
shell-%: ## run shell for given container e.g. shell-php
	$(DOCKER_COMPOSE_DEV) exec $* /bin/sh	