SHELL := /bin/bash

IMAGE_NAME := woolfg/mysql-backup-sidecar
PROJECT := mysql-backup-sidecar

DOCKER_COMPOSE_DEV := docker compose -p $(PROJECT) -f examples/docker-compose.yml -f examples/docker-compose.dev.yml

VERSION_TAG := $(shell git describe HEAD)

export

.PHONY: help
help: ## help message, list all command
	@echo -e "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)"

.PHONY: build
build: build-mysql build-mariadb ## build docker image

.PHONY: rebuild
rebuild: rebuild-mysql rebuild-mariadb ## build docker image without cache

MYSQL_VERSIONS := 8.4 9.7
MARIADB_VERSIONS := 10.11 11.4 11.8 12.3
DB_FAMILY ?= mysql
DB_VERSION ?= 8.4

.PHONY: build-mysql rebuild-mysql build-mariadb rebuild-mariadb
build-mysql: ## build maintained MySQL LTS images
	@set -e; for version in $(MYSQL_VERSIONS); do \
		docker build -t "$(IMAGE_NAME):$(VERSION_TAG)-mysql-$$version" -f mysql/$$version/Dockerfile .; \
	done

rebuild-mysql: ## build maintained MySQL LTS images without cache
	@set -e; for version in $(MYSQL_VERSIONS); do \
		docker build --no-cache --pull -t "$(IMAGE_NAME):$(VERSION_TAG)-mysql-$$version" -f mysql/$$version/Dockerfile .; \
	done

build-mariadb: ## build maintained MariaDB LTS images
	@set -e; for version in $(MARIADB_VERSIONS); do \
		docker build -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-$$version" -f mariadb/$$version/Dockerfile .; \
	done

rebuild-mariadb: ## build maintained MariaDB LTS images without cache
	@set -e; for version in $(MARIADB_VERSIONS); do \
		docker build --no-cache --pull -t "$(IMAGE_NAME):$(VERSION_TAG)-mariadb-$$version" -f mariadb/$$version/Dockerfile .; \
	done

.PHONY: test-unit test-restore
test-unit: ## test backup/upload behavior without Docker (requires Python 3 and zip)
	python3 -m unittest discover -s tests -p 'test_*.py'

test-restore: ## build and verify full/incremental restores (DB_FAMILY=mysql DB_VERSION=8.4)
	bash tests/integration.sh $(DB_FAMILY) $(DB_VERSION)

.PHONY: runmysql
runmysql: ## run the example docker compose stack on MySQL
	DB_FAMILY=mysql DB_VERSION=8.4 \
	VERSION_TAG=$(VERSION_TAG)-mysql-8.4 \
	DB_IMAGE=mysql:8.4 \
	$(DOCKER_COMPOSE_DEV) up

.PHONY: runmariadb
runmariadb: ## run the example docker compose stack on MariaDB
	DB_FAMILY=mariadb DB_VERSION=11.8 \
	VERSION_TAG=$(VERSION_TAG)-mariadb-11.8 \
	DB_IMAGE=mariadb:11.8 \
	$(DOCKER_COMPOSE_DEV) up

.PHONY: clean
clean: ## remove all containers and volumes
	docker container rm $(PROJECT)_backup_1 $(PROJECT)_db_1 \
	|| docker volume rm $(PROJECT)_backup $(PROJECT)_mysqldata

.PHONY: shell-%
shell-%: ## run shell for given container e.g. shell-php
	$(DOCKER_COMPOSE_DEV) exec $* /bin/bash
