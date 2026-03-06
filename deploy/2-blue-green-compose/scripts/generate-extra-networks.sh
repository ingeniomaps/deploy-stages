#!/usr/bin/env bash
# Genera docker-compose.extra-networks.yml con las redes adicionales de NETWORK_NAME para nginx.
# Las redes extras van solo en nginx (el punto de entrada); los app containers solo necesitan la red principal.
# Si NETWORK_NAME está vacío o no hay redes adicionales, elimina el archivo generado.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly DOCKER_DIR="${SCRIPT_DIR}/../docker"
readonly ROOT_ENV="${PROJECT_ROOT}/.env"
readonly OUT_FILE="${DOCKER_DIR}/docker-compose.extra-networks.yml"
# Limpiar archivos viejos (antes se generaban por color)
readonly OLD_BLUE="${DOCKER_DIR}/docker-compose.extra-networks-blue.yml"
readonly OLD_GREEN="${DOCKER_DIR}/docker-compose.extra-networks-green.yml"

NETWORK=""
NETWORK_DEFAULT=""
NETWORK_NAME=""

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
            NETWORK)         [[ -n "${value}" ]] && NETWORK="${value}" ;;
            NETWORK_DEFAULT) [[ -n "${value}" ]] && NETWORK_DEFAULT="${value}" ;;
            NETWORK_NAME)    [[ -n "${value}" ]] && NETWORK_NAME="${value}" ;;
        esac
    done < "${ROOT_ENV}"
fi

# Red principal (misma lógica que resolve-network.sh)
PRIMARY="${NETWORK:-${NETWORK_DEFAULT:-}}"
if [[ -z "${PRIMARY}" ]] && [[ -n "${NETWORK_NAME}" ]]; then
    PRIMARY="$(printf '%s' "${NETWORK_NAME%%,*}" | xargs)"
fi

# Recopilar redes adicionales (NETWORK_NAME menos la principal)
declare -a EXTRA_NETS=()
if [[ -n "${NETWORK_NAME}" ]]; then
    IFS=',' read -ra PARTS <<< "${NETWORK_NAME}"
    for part in "${PARTS[@]}"; do
        part="$(printf '%s' "${part}" | xargs)"
        [[ -z "${part}" ]] && continue
        [[ "${part}" == "${PRIMARY}" ]] && continue
        EXTRA_NETS+=("${part}")
    done
fi

# Limpiar archivos viejos por color
[[ -f "${OLD_BLUE}" ]] && rm -f "${OLD_BLUE}"
[[ -f "${OLD_GREEN}" ]] && rm -f "${OLD_GREEN}"

# Si no hay redes adicionales, limpiar y salir
if [[ ${#EXTRA_NETS[@]} -eq 0 ]]; then
    [[ -f "${OUT_FILE}" ]] && rm -f "${OUT_FILE}"
    exit 0
fi

mkdir -p "${DOCKER_DIR}"

{
    echo "# Generado por scripts/generate-extra-networks.sh (redes adicionales de NETWORK_NAME para nginx)"
    echo "services:"
    echo "  nginx:"
    echo "    networks:"
    echo "      default:"
    for net in "${EXTRA_NETS[@]}"; do
        echo "      ${net}:"
    done
    echo ""
    echo "networks:"
    for net in "${EXTRA_NETS[@]}"; do
        echo "  ${net}:"
        echo "    name: ${net}"
        echo "    external: true"
    done
} > "${OUT_FILE}"
