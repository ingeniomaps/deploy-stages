#!/usr/bin/env bash
# Despliega/actualiza el stack en Swarm.
# Uso: stack-deploy.sh <STACK_NAME> <REPLICAS>
set -euo pipefail

STACK_NAME="${1:?Falta STACK_NAME}"
REPLICAS="${2:?Falta REPLICAS}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Parseo seguro del .env (sin source/eval)
readonly ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"
# shellcheck source=../../scripts/lib/parse-env.sh
source "${PROJECT_ROOT}/deploy/scripts/lib/parse-env.sh"
load_env_export "${ENV_FILE}"

export REPLICAS
export SWARM_NETWORK_NAME="${NETWORK_SWARM:-${NETWORK}}"
SWARM_PORT="${PORTS:-}"
SWARM_PORT="${SWARM_PORT%%:*}"
export SWARM_PUBLISHED_PORT="${SWARM_PORT:-${PROJECT_PORT}}"
CONFIG_REV="$(date +%s)"
export CONFIG_REV
export UPDATE_DELAY="${UPDATE_DELAY:-60s}"

SWARM_DIR="${SCRIPT_DIR}/.."

# Stack base: si el proyecto tiene docker/docker-stack.yml, lo usa en vez del genérico.
# Esto evita problemas de merge de healthcheck/command en swarm.
env_dir="$(dirname "${ENV_FILE}")"
PROJECT_STACK=""
if [[ -n "${DOCKER_COMPOSE_APP:-}" ]]; then
    app_dir="$(dirname "${DOCKER_COMPOSE_APP}")"
    [[ "${app_dir}" != /* ]] && app_dir="${env_dir}/${app_dir}"
    [[ -f "${app_dir}/docker-stack.yml" ]] && PROJECT_STACK="${app_dir}/docker-stack.yml"
fi

STACK_FILES=()
if [[ -n "${PROJECT_STACK}" ]]; then
    STACK_FILES+=(-c "${PROJECT_STACK}")
else
    STACK_FILES+=(-c "${SWARM_DIR}/docker-stack.yml")
fi
STACK_FILES+=(-c "${SWARM_DIR}/docker-stack.env-include.yml")
if [ -n "${PORTS:-}" ]; then
    STACK_FILES+=(-c "${SWARM_DIR}/docker-stack.ports.yml")
fi

docker stack deploy "${STACK_FILES[@]}" "${STACK_NAME}"
