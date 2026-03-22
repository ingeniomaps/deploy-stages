#!/usr/bin/env bash
# Crea un cluster Kind con extraPortMappings para el NodePort del Service.
# Lee configuracion de .env.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly K8S_DIR="${SCRIPT_DIR}/.."
readonly PROJECT_ROOT="$(cd "${K8S_DIR}/../.." && pwd)"
readonly ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"
readonly KIND_CONFIG="${SCRIPT_DIR}/kind-config.yaml"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Lee un valor del .env
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

# Verificar que kind esta instalado
if ! command -v kind &>/dev/null; then
    echo -e "${RED}Error: kind no esta instalado.${NC}" >&2
    echo -e "${YELLOW}Instalar: https://kind.sigs.k8s.io/docs/user/quick-start/#installation${NC}" >&2
    exit 1
fi

PROJECT_NAME="$(get_env_value PROJECT_NAME "")"
if [[ -z "${PROJECT_NAME}" ]]; then
    echo -e "${RED}Error: PROJECT_NAME no definido en .env${NC}" >&2
    exit 1
fi
PROJECT_PREFIX="$(get_env_value PROJECT_PREFIX "")"
K8S_NODE_PORT="$(get_env_value K8S_NODE_PORT 30080)"

# Puerto del host: PORTS=host:container, tomamos host; fallback a PROJECT_PORT
PORTS="$(get_env_value PORTS "")"
PROJECT_PORT="$(get_env_value PROJECT_PORT 5050)"
if [[ -n "${PORTS}" ]]; then
    HOST_PORT="${PORTS%%:*}"
else
    HOST_PORT="${PROJECT_PORT}"
fi

cluster="${PROJECT_PREFIX:+${PROJECT_PREFIX}-}${PROJECT_NAME}-cluster"

# Si el cluster ya existe, preguntar
if kind get clusters 2>/dev/null | grep -q "^${cluster}$"; then
    echo -e "${YELLOW}El cluster '${cluster}' ya existe.${NC}"
    echo -e "${YELLOW}Usa 'kind delete cluster --name ${cluster}' para recrearlo.${NC}"
    exit 0
fi

# Generar kind-config.yaml
echo -e "${BLUE}Generando ${KIND_CONFIG}...${NC}"
cat > "${KIND_CONFIG}" << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: ${K8S_NODE_PORT}
        hostPort: ${HOST_PORT}
        protocol: TCP
EOF

echo -e "${YELLOW}Creando cluster Kind '${cluster}'...${NC}"
kind create cluster --name "${cluster}" --config "${KIND_CONFIG}"

echo -e "${YELLOW}Configurando kubectl context...${NC}"
kubectl cluster-info --context "kind-${cluster}"

# Cargar imagen si existe
echo -e "${YELLOW}Cargando imagen en el cluster...${NC}"
bash "${K8S_DIR}/scripts/load-image.sh" || echo -e "${YELLOW}Imagen no cargada (ejecuta 'make build' y 'make load-image-k8s').${NC}"

echo -e "${GREEN}✓ Cluster '${cluster}' creado y listo.${NC}"
