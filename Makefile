SHELL := /bin/bash

IMAGE_NAME := woolfg/mysql-backup-sidecar
PROJECT := mysql-backup-sidecar

DOCKER_COMPOSE_DEV := docker-compose -p $(PROJECT) -f examples/docker-compose.yml -f examples/docker-compose.dev.yml

VERSION_TAG := $(shell git describe HEAD)

export

.PHONY: help
help: ## help message, list all command
	@echo -e "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)"

.PHONY: build
build: build-mysql build-mariadb ## build docker image

.PHONY: rebuild
rebuild: rebuild-mysql rebuild-mariadb ## build docker image without cache

.PHONY: build-mysql
build-mysql: ## build docker image
	docker build -t "$(IMAGE_NAME):$(VERSION_TAG)-mysql-8.0" -f mysql/8.0/Dockerfile .

.PHONY: build-mariadb
build-mariadb: ## build docker image
	docker build -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-10.4" -f mariadb/10.4/Dockerfile .
	docker build -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-10.5" -f mariadb/10.5/Dockerfile .
	docker build -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-10.8" -f mariadb/10.8/Dockerfile .
	docker build -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-10.9" -f mariadb/10.9/Dockerfile .

.PHONY: rebuild-mariadb
rebuild-mariadb: ## build docker image without cache
	docker build --no-cache -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-10.4" -f mariadb/10.4/Dockerfile .
	docker build --no-cache -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-10.5" -f mariadb/10.5/Dockerfile .
	docker build --no-cache -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-10.8" -f mariadb/10.8/Dockerfile .
	docker build --no-cache -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-10.9" -f mariadb/10.9/Dockerfile .

.PHONY: runmysql
runmysql: ## run the example docker compose stack on MySQL
	VERSION_TAG=$(VERSION_TAG)-mysql-8.0 \
	DB_IMAGE=mysql:8.0 \
	$(DOCKER_COMPOSE_DEV) up

.PHONY: runmariadb
runmariadb: ## run the example docker compose stack on MariaDB
	VERSION_TAG=$(VERSION_TAG)-mariadb-10.5 \
	DB_IMAGE=mariadb:10.5 \
	$(DOCKER_COMPOSE_DEV) up

.PHONY: clean
clean: ## remove all containers and volumes
	docker container rm $(PROJECT)_backup_1 $(PROJECT)_db_1 \
	|| docker volume rm $(PROJECT)_backup $(PROJECT)_mysqldata

.PHONY: shell-%
shell-%: ## run shell for given container e.g. shell-php
	$(DOCKER_COMPOSE_DEV) exec $* /bin/bash