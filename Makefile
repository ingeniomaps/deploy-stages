# ============================================================================
# Variables de Configuración
# ============================================================================
APP_VERSION := $(shell \
	git rev-parse --short HEAD 2>/dev/null \
	|| echo "latest")

# Detectar docker compose V2, fallback a V1
DOCKER_COMPOSE := $(shell \
	docker compose version >/dev/null 2>&1 \
	&& echo "docker compose" \
	|| echo "docker-compose")

# Helper para leer variables del .env raíz
_env = $(shell \
	grep '^$(1)=' .env 2>/dev/null \
	| cut -d= -f2- | tr -d "'\"\r\n" | xargs)

# Resolución de ruta del proyecto y Dockerfile
_PROJECT_SOURCE  := $(call _env,PROJECT_SOURCE)
_DOCKERFILE_PATH := $(call _env,DOCKERFILE_PATH)
_PROJECT_NAME    := $(call _env,PROJECT_NAME)
_PROJECT_PREFIX  := $(call _env,PROJECT_PREFIX)
COMPOSE_NAME     := $(strip $(if $(_PROJECT_PREFIX),$(_PROJECT_PREFIX)-,)$(_PROJECT_NAME))

BUILD_CONTEXT := $(strip $(if $(_PROJECT_SOURCE),$(if $(filter /%,$(_PROJECT_SOURCE)),$(_PROJECT_SOURCE),./$(_PROJECT_SOURCE)),.))
BUILD_DOCKERFILE := $(strip $(BUILD_CONTEXT)/$(if $(_DOCKERFILE_PATH),$(_DOCKERFILE_PATH),Dockerfile))
BUILD_IMAGE_NAME := $(strip $(_PROJECT_NAME))

# ============================================================================
# Tareas Comunes
# ============================================================================
.PHONY: help build

# Macro para formatear targets con ##
define _help_awk
	@awk 'BEGIN {FS = ":.*##"} \
		/^[a-zA-Z0-9_-]+:.*##/ { \
		printf "    make \033[36m%-20s\033[0m %s\n", $$1, $$2 \
	}' $(MAKEFILE_LIST)
endef

help: ## Muestra esta ayuda
	@echo "----------------------------------------------------"
	@echo " Manual de Despliegue Evolutivo"
	@echo "----------------------------------------------------"
	$(_help_awk) | grep "(Tareas Comunes)"
	@echo ""
	@echo " ETAPA 0: Manual en VM (sin Docker)"
	$(_help_awk) | grep "(ETAPA 0)"
	@echo ""
	@echo " ETAPA 1: Simple (un solo contenedor)"
	$(_help_awk) | grep "(ETAPA 1)"
	@echo ""
	@echo " ETAPA 2: Blue-Green (Compose)"
	$(_help_awk) | grep "(ETAPA 2)" | grep -v "(ETAPA 2.5)"
	@echo ""
	@echo " ETAPA 2.5: Docker Swarm (rolling update)"
	$(_help_awk) | grep "(ETAPA 2.5)"
	@echo ""
	@echo " ETAPA 3: Kubernetes"
	$(_help_awk) | grep "(ETAPA 3)"
	@echo ""

build: ## (Tareas Comunes) Construir imagen Docker
	@if [ -f "$(BUILD_DOCKERFILE)" ]; then \
		docker build \
			-f "$(BUILD_DOCKERFILE)" \
			-t "$(BUILD_IMAGE_NAME):$(APP_VERSION)" \
			"$(BUILD_CONTEXT)" && \
		docker tag \
			"$(BUILD_IMAGE_NAME):$(APP_VERSION)" \
			"$(BUILD_IMAGE_NAME):latest"; \
	else \
		echo "No se encontró Dockerfile en" \
			"$(BUILD_DOCKERFILE). Omitiendo build."; \
	fi

# ============================================================================
# ETAPA 0: Despliegue Manual en VM (sin Docker)
# ============================================================================
.PHONY: run-manual

run-manual: ## (ETAPA 0) Arrancar la app sin Docker
	@bash ./deploy/0-manual/run.sh

# ============================================================================
# ETAPA 1: Despliegue Simple (un solo contenedor)
# ============================================================================
.PHONY: deploy-simple down-simple

# DOCKER_COMPOSE_APP: compose extra opcional del proyecto
_COMPOSE_APP_RAW := $(call _env,DOCKER_COMPOSE_APP)
COMPOSE_APP := $(strip $(if $(_COMPOSE_APP_RAW),$(if $(filter /%,$(_COMPOSE_APP_RAW)),$(_COMPOSE_APP_RAW),$(BUILD_CONTEXT)/$(_COMPOSE_APP_RAW)),))

SIMPLE_DIR   := deploy/1-simple-compose
SIMPLE_FILES := -f $(SIMPLE_DIR)/docker-compose.yml \
	-f $(SIMPLE_DIR)/docker-compose.override.yml
SIMPLE_EXTRA  = $$(test -n "$(COMPOSE_APP)" \
	&& test -f "$(COMPOSE_APP)" \
	&& echo "-f $(COMPOSE_APP)")

deploy-simple: build ## (ETAPA 1) Desplegar un único contenedor
	@echo "Desplegando en modo simple..."
	@test -f .env || \
		(echo "Error: .env no existe."; exit 1)
	@bash $(SIMPLE_DIR)/scripts/validate-env.sh
	@bash deploy/scripts/ensure-network.sh
	@bash $(SIMPLE_DIR)/scripts/generate-extra-hosts.sh
	@$(DOCKER_COMPOSE) -p $(COMPOSE_NAME) $(SIMPLE_FILES) $(SIMPLE_EXTRA) \
		--env-file .env up -d
	@docker image prune -f

down-simple: ## (ETAPA 1) Detener el despliegue simple
	@test -f .env || \
		(echo "Error: .env no existe."; exit 1)
	@bash $(SIMPLE_DIR)/scripts/generate-extra-hosts.sh
	@$(DOCKER_COMPOSE) -p $(COMPOSE_NAME) $(SIMPLE_FILES) $(SIMPLE_EXTRA) \
		--env-file .env down --remove-orphans

# ============================================================================
# ETAPA 2: Blue-Green (Single-Host con Compose)
# ============================================================================
.PHONY: setup-bluegreen deploy-bluegreen
.PHONY: switch-bluegreen status-bluegreen down-bluegreen

BG_DIR := deploy/2-blue-green-compose
GREEN  ?= 1
BLUE   ?= 1

setup-bluegreen: ## (ETAPA 2) Configurar entorno Blue-Green
	@if [ ! -f .env ] && [ -f $(BG_DIR)/.env.example ]; then \
		cp $(BG_DIR)/.env.example .env \
			&& echo ".env creado desde $(BG_DIR)."; \
	fi
	@echo "Ejecutando setup interactivo..."
	@./$(BG_DIR)/scripts/setup.sh

deploy-bluegreen: build ## (ETAPA 2) Desplegar Blue-Green
	@echo "Blue-Green: Green=$(GREEN), Blue=$(BLUE)..."
	@test -f .env || \
		(echo "Error: .env no existe."; exit 1)
	@bash deploy/scripts/ensure-network.sh
	@bash $(BG_DIR)/scripts/generate-nginx-override.sh
	@./$(BG_DIR)/scripts/blue-green.sh deploy \
		$(GREEN) $(BLUE)

switch-bluegreen: ## (ETAPA 2) Cambiar tráfico
	@RECREATE=$(RECREATE) SCALE_DOWN=$(SCALE_DOWN) \
		./$(BG_DIR)/scripts/blue-green.sh \
		switch$(if $(STACK),:$(STACK)) \
		$(if $(filter environment command,\
		$(origin REPLICAS)),$(REPLICAS),)

status-bluegreen: ## (ETAPA 2) Ver estado Blue-Green
	@./$(BG_DIR)/scripts/blue-green.sh status

down-bluegreen: ## (ETAPA 2) Bajar Blue-Green
	@./$(BG_DIR)/scripts/blue-green.sh down $(STACK)

# ============================================================================
# ETAPA 2.5: Docker Swarm (rolling update)
# ============================================================================
.PHONY: setup-swarm deploy-swarm update-swarm
.PHONY: rollback-swarm scale-swarm status-swarm down-swarm

SWARM_DIR  := deploy/2.5-swarm
STACK_NAME ?= $(COMPOSE_NAME)
REPLICAS   ?= $(call _env,REPLICAS)

setup-swarm: ## (ETAPA 2.5) Inicializar Swarm
	@docker info 2>/dev/null \
		| grep -q "Swarm: active" || docker swarm init
	@docker network inspect ingress >/dev/null 2>&1 \
		|| docker network create --ingress --driver overlay ingress

deploy-swarm: build ## (ETAPA 2.5) Desplegar stack en Swarm
	@test -f .env || \
		(echo "Error: .env no existe."; exit 1)
	@bash $(SWARM_DIR)/scripts/ensure-network-swarm.sh
	@bash $(SWARM_DIR)/scripts/generate-env-file-include.sh
	@echo "Desplegando '$(STACK_NAME)' ($(REPLICAS) réplicas)..."
	@bash $(SWARM_DIR)/scripts/stack-deploy.sh \
		$(STACK_NAME) $(REPLICAS)
	@bash $(SWARM_DIR)/scripts/backup-env-swarm.sh
	@docker container prune -f \
		--filter "label=com.docker.stack.namespace=$(STACK_NAME)"

update-swarm: build ## (ETAPA 2.5) Rolling update (imagen + env)
	@test -f .env || \
		(echo "Error: .env no existe."; exit 1)
	@bash $(SWARM_DIR)/scripts/ensure-network-swarm.sh
	@bash $(SWARM_DIR)/scripts/generate-env-file-include.sh
	@echo "Actualizando '$(STACK_NAME)' (imagen + env)..."
	@bash $(SWARM_DIR)/scripts/stack-deploy.sh \
		$(STACK_NAME) $(REPLICAS)
	@docker service update $(STACK_NAME)_app
	@bash $(SWARM_DIR)/scripts/backup-env-swarm.sh
	@docker container prune -f \
		--filter "label=com.docker.stack.namespace=$(STACK_NAME)"

rollback-swarm: ## (ETAPA 2.5) Restaurar .env previo y redesplegar
	@bash $(SWARM_DIR)/scripts/restore-env-swarm.sh
	@bash $(SWARM_DIR)/scripts/generate-env-file-include.sh
	@bash $(SWARM_DIR)/scripts/stack-deploy.sh \
		$(STACK_NAME) $(REPLICAS)
	@docker container prune -f \
		--filter "label=com.docker.stack.namespace=$(STACK_NAME)"
	@echo "Rollback aplicado. Comprueba: make status-swarm"

scale-swarm: ## (ETAPA 2.5) Escalar réplicas (REPLICAS=N)
	@docker service scale $(STACK_NAME)_app=$(REPLICAS)
	@docker container prune -f \
		--filter "label=com.docker.stack.namespace=$(STACK_NAME)"
	@echo "Escalado a $(REPLICAS) réplica(s)."

status-swarm: ## (ETAPA 2.5) Estado del stack y servicio
	@echo "=== Stack $(STACK_NAME) ==="
	@docker stack services $(STACK_NAME) 2>/dev/null \
		|| echo "Stack no desplegado."
	@echo ""
	@docker service ps $(STACK_NAME)_app 2>/dev/null \
		|| true

down-swarm: ## (ETAPA 2.5) Eliminar el stack de Swarm
	@docker stack rm $(STACK_NAME)
	@echo "Stack $(STACK_NAME) eliminado."

# ============================================================================
# ETAPA 3: Kubernetes (Blue-Green con Kind)
# ============================================================================
.PHONY: setup-k8s load-image-k8s deploy-k8s
.PHONY: switch-k8s status-k8s down-k8s push-k8s

K8S_DIR := deploy/3-kubernetes

setup-k8s: ## (ETAPA 3) Crear cluster Kind local
	@bash $(K8S_DIR)/kind/setup.sh

load-image-k8s: build ## (ETAPA 3) Cargar imagen en Kind
	@test -f .env || \
		(echo "Error: .env no existe."; exit 1)
	@bash $(K8S_DIR)/scripts/load-image.sh

deploy-k8s: load-image-k8s ## (ETAPA 3) Desplegar en Kubernetes
	@test -f .env || \
		(echo "Error: .env no existe."; exit 1)
	@bash $(K8S_DIR)/scripts/blue-green.sh deploy \
		$(REPLICAS) $(REPLICAS)

switch-k8s: ## (ETAPA 3) Cambiar tráfico blue/green
	@if [ -n "$(STACK)" ]; then \
		RECREATE=$(RECREATE) \
			bash $(K8S_DIR)/scripts/blue-green.sh \
			switch:$(STACK) $(if $(filter \
			environment command,\
			$(origin REPLICAS)),$(REPLICAS),); \
	else \
		RECREATE=$(RECREATE) \
			bash $(K8S_DIR)/scripts/blue-green.sh switch; \
	fi

status-k8s: ## (ETAPA 3) Ver estado de pods y color activo
	@bash $(K8S_DIR)/scripts/blue-green.sh status

down-k8s: ## (ETAPA 3) Bajar recursos K8s
	@bash $(K8S_DIR)/scripts/blue-green.sh down $(STACK)

push-k8s: build ## (ETAPA 3) Subir imagen al registro
	@echo "Subiendo imagen al registro..."
	@docker tag \
		"$(BUILD_IMAGE_NAME):$(APP_VERSION)" \
		"$(REGISTRY_URL)/$(BUILD_IMAGE_NAME):$(APP_VERSION)"
	@docker push \
		"$(REGISTRY_URL)/$(BUILD_IMAGE_NAME):$(APP_VERSION)"
