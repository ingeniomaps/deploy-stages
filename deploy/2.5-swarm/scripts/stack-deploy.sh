#!/usr/bin/env bash
# Despliega/actualiza el stack en Swarm.
# Uso: stack-deploy.sh <STACK_NAME> <REPLICAS>
set -euo pipefail

STACK_NAME="${1:?Falta STACK_NAME}"
REPLICAS="${2:?Falta REPLICAS}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Parseo seguro del .env (sin source/eval)
# shellcheck source=../../scripts/lib/parse-env.sh
source "${PROJECT_ROOT}/deploy/scripts/lib/parse-env.sh"
load_env_export "${PROJECT_ROOT}/.env"

export REPLICAS
export SWARM_NETWORK_NAME="${NETWORK_SWARM:-${NETWORK}}"
SWARM_PORT="${PORTS%%:*}"
export SWARM_PUBLISHED_PORT="${SWARM_PORT:-${PROJECT_PORT}}"
CONFIG_REV="$(date +%s)"
export CONFIG_REV
export UPDATE_DELAY="${UPDATE_DELAY:-60s}"

SWARM_DIR="deploy/2.5-swarm"
STACK_FILES=(
    -c "${SWARM_DIR}/docker-stack.yml"
    -c "${SWARM_DIR}/docker-stack.env-include.yml"
)
if [ -n "${PORTS:-}" ]; then
    STACK_FILES+=(-c "${SWARM_DIR}/docker-stack.ports.yml")
fi

docker stack deploy "${STACK_FILES[@]}" "${STACK_NAME}"
