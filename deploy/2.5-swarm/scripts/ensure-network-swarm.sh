#!/usr/bin/env bash
# Asegura que exista la red overlay para Swarm con el nombre NETWORK (y opcionalmente NETWORK_SUBNET).
# Lee .env de la raíz: NETWORK, NETWORK_SUBNET. Si la red ya existe, no hace nada.
# Uso: desde la raíz del repo; se invoca antes de deploy-swarm.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly ROOT_ENV="${ENV_FILE:-${PROJECT_ROOT}/.env}"

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

# F2 fix: Si NETWORK_SWARM_ATTACHABLE=1|true, crear la overlay como --attachable.
# Esto permite que standalone containers (no-swarm services) se conecten a la overlay
# vía `docker network connect`. Útil cuando el stack Swarm necesita comunicarse con
# servicios externos al stack (p. ej. postgres/redis levantados con docker-compose).
# Default: false (overlay solo para Swarm services, comportamiento histórico preservado).
attachable_arg=""
case "$(printf '%s' "${NETWORK_SWARM_ATTACHABLE:-0}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes) attachable_arg="--attachable" ;;
esac

# Si NETWORK_SWARM es un nombre distinto a NETWORK, no reusar NETWORK_SUBNET (evita solapamiento con la red bridge).
if [[ -n "${NETWORK_SUBNET}" ]] && [[ -z "${NETWORK_SWARM}" ]]; then
    # shellcheck disable=SC2086
    docker network create --driver overlay ${attachable_arg} --subnet "${NETWORK_SUBNET}" "${NETWORK_NAME}"
else
    # shellcheck disable=SC2086
    docker network create --driver overlay ${attachable_arg} "${NETWORK_NAME}"
fi
