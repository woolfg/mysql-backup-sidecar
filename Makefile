SHELL := /bin/bash

IMAGE_NAME := woolfg/mysql-backup-sidecar
PROJECT := mysql-backup-sidecar

DOCKER_COMPOSE_DEV := docker-compose -p $(PROJECT) -f examples/docker-compose.yml -f examples/docker-compose.dev.yml
 
VERSION_TAG := $(shell git describe HEAD)
VERSION_TAG_MYSQL := "$(VERSION_TAG)-mysql-8.0"
VERSION_TAG_MARIADB := "$(VERSION_TAG)-mariadb-10.4"

export

.PHONY: help
help: ## help message, list all command
	@echo -e "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)"

.PHONY: build
build: ## build docker image
	docker build -t $(IMAGE_NAME):$(VERSION_TAG_MARIADB) -f mariadb/10.4/Dockerfile .
	docker build -t $(IMAGE_NAME):$(VERSION_TAG_MYSQL) -f mysql/8.0/Dockerfile .

.PHONY: rebuild
rebuild: rebuild-mysql rebuild-mariadb ## build docker image without cache

.PHONY: rebuild-mysql
rebuild-mysql: ## build docker image without cache
	docker build --no-cache -t $(IMAGE_NAME):$(VERSION_TAG_MYSQL) -f mysql/8.0/Dockerfile .	

.PHONY: rebuild-mariadb
rebuild-mariadb: ## build docker image without cache
	docker build --no-cache -t $(IMAGE_NAME):$(VERSION_TAG_MARIADB) -f mariadb/10.4/Dockerfile .

.PHONY: runmysql
runmysql: ## run the example docker compose stack on MySQL
	VERSION_TAG=$(VERSION_TAG_MYSQL) \
	DB_IMAGE=mysql:8.0 \
	$(DOCKER_COMPOSE_DEV) up

.PHONY: runmariadb
runmariadb: ## run the example docker compose stack on MariaDB
	VERSION_TAG=$(VERSION_TAG_MARIADB) \
	DB_IMAGE=mariadb:10.4 \
	$(DOCKER_COMPOSE_DEV) up	

.PHONY: clean
clean: ## remove all containers and volumes
	docker container rm $(PROJECT)_backup_1 $(PROJECT)_db_1 \
	|| docker volume rm $(PROJECT)_backup $(PROJECT)_mysqldata

.PHONY: shell-% 
shell-%: ## run shell for given container e.g. shell-php
	$(DOCKER_COMPOSE_DEV) exec $* /bin/bash	