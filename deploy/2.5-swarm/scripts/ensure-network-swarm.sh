#!/usr/bin/env bash
# Asegura que exista la red overlay para Swarm con el nombre NETWORK (y opcionalmente NETWORK_SUBNET).
# Lee .env de la raíz: NETWORK, NETWORK_SUBNET. Si la red ya existe, no hace nada.
# Uso: desde la raíz del repo; se invoca antes de deploy-swarm.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly ROOT_ENV="${PROJECT_ROOT}/.env"

NETWORK_NAME=""
NETWORK_SWARM=""
NETWORK_SUBNET=""

if [[ -f "${ROOT_ENV}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" != *'='* ]] && continue
        key="${line%%=*}"
        key="$(printf '%s' "${key}" | xargs)"
        value="${line#*=}"
        value="${value%%#*}"
        value="$(printf '%s' "${value}" | sed "s/^['\"]//;s/['\"]$//" | tr -d '\r\n' | xargs)"
        [[ -z "${key}" ]] && continue
        case "${key}" in
            NETWORK)        [[ -n "${value}" ]] && NETWORK_NAME="${value}" ;;
            NETWORK_SWARM)  [[ -n "${value}" ]] && NETWORK_SWARM="${value}" ;;
            NETWORK_SUBNET) [[ -n "${value}" ]] && NETWORK_SUBNET="${value}" ;;
        esac
    done < "${ROOT_ENV}"
fi

# Para Swarm usar NETWORK_SWARM si está definido (p. ej. distinto de la bridge NETWORK); si no, NETWORK.
readonly NETWORK_NAME="${NETWORK_SWARM:-${NETWORK_NAME:-my-network}}"

# Solo reutilizar si existe una red overlay con ese nombre (scope Swarm). Si existe como bridge (local), no sirve para stack deploy.
existing_driver=""
while IFS= read -r line; do
    name="${line%% *}"
    driver="${line##* }"
    if [[ "${name}" == "${NETWORK_NAME}" ]]; then
        existing_driver="${driver}"
        break
    fi
done < <(docker network ls --format '{{.Name}} {{.Driver}}' 2>/dev/null || true)

if [[ "${existing_driver}" == "overlay" ]]; then
    echo "Red overlay existente: ${NETWORK_NAME}"
    exit 0
fi

if [[ -n "${existing_driver}" ]]; then
    echo "Error: la red '${NETWORK_NAME}' existe como ${existing_driver} (ámbito local). Para Swarm se necesita una red overlay. Usa otro nombre (p. ej. ${NETWORK_NAME}-swarm) o define NETWORK_SWARM en .env." >&2
    exit 1
fi

echo "Creando red overlay: ${NETWORK_NAME}"
# Si NETWORK_SWARM es un nombre distinto a NETWORK, no reusar NETWORK_SUBNET (evita solapamiento con la red bridge).
if [[ -n "${NETWORK_SUBNET}" ]] && [[ -z "${NETWORK_SWARM}" ]]; then
    docker network create --driver overlay --subnet "${NETWORK_SUBNET}" "${NETWORK_NAME}"
else
    docker network create --driver overlay "${NETWORK_NAME}"
fi
