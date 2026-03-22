#!/usr/bin/env bash
# Carga una imagen Docker local en el cluster Kind.
# Lee PROJECT_IMAGE, PROJECT_VERSION, PROJECT_NAME de .env.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Carga .env de forma segura
get_env_value() {
    local key="${1:?}"
    local default="${2:-}"
    if [[ -f "${ENV_FILE}" ]]; then
        local line
        line=$(grep "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1) || true
        if [[ -n "${line}" ]]; then
            echo "${line#*=}" | tr -d '\r\n' | sed "s/^['\"]//;s/['\"]$//"
            return
        fi
    fi
    echo "${default}"
}

PROJECT_NAME="$(get_env_value PROJECT_NAME "")"
if [[ -z "${PROJECT_NAME}" ]]; then
    echo -e "${RED}Error: PROJECT_NAME no definido en .env${NC}" >&2
    exit 1
fi
PROJECT_IMAGE="$(get_env_value PROJECT_IMAGE "${PROJECT_NAME}")"
PROJECT_VERSION="$(get_env_value PROJECT_VERSION latest)"
PROJECT_PREFIX="$(get_env_value PROJECT_PREFIX "")"

image="${PROJECT_IMAGE}:${PROJECT_VERSION}"
cluster="${PROJECT_PREFIX:+${PROJECT_PREFIX}-}${PROJECT_NAME}-cluster"

# Verificar que kind esta instalado
if ! command -v kind &>/dev/null; then
    echo -e "${RED}Error: kind no esta instalado.${NC}" >&2
    exit 1
fi

# Verificar que la imagen existe localmente
if ! docker image inspect "${image}" &>/dev/null; then
    echo -e "${RED}Error: La imagen '${image}' no existe localmente.${NC}" >&2
    echo -e "${YELLOW}Ejecuta 'make build' primero.${NC}" >&2
    exit 1
fi

# Verificar que el cluster Kind existe
if ! kind get clusters 2>/dev/null | grep -q "^${cluster}$"; then
    echo -e "${RED}Error: El cluster Kind '${cluster}' no existe.${NC}" >&2
    echo -e "${YELLOW}Ejecuta 'make setup-k8s' primero.${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}Cargando imagen '${image}' en cluster '${cluster}'...${NC}"
kind load docker-image "${image}" --name "${cluster}"
echo -e "${GREEN}Imagen '${image}' cargada en cluster '${cluster}'.${NC}"
