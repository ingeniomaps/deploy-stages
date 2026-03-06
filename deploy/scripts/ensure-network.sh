#!/usr/bin/env bash
# Asegura que la red Docker exista: si no existe la crea (con subnet si está en .env);
# si ya existe no hace nada (el compose la usará como externa).
# Lee .env en la raíz: NETWORK (prioridad) o NETWORK_DEFAULT, y opcionalmente NETWORK_SUBNET.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly ROOT_ENV="${ENV_FILE:-${PROJECT_ROOT}/.env}"

NETWORK_NAME=""
NETWORK_DEFAULT_TMP=""
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
            NETWORK)           [[ -n "${value}" ]] && NETWORK_NAME="${value}" ;;
            NETWORK_DEFAULT)   [[ -n "${value}" ]] && NETWORK_DEFAULT_TMP="${value}" ;;
            NETWORK_SUBNET)    [[ -n "${value}" ]] && NETWORK_SUBNET="${value}" ;;
        esac
    done < "${ROOT_ENV}"
fi

# Prioridad: NETWORK > NETWORK_DEFAULT > my-network
readonly NETWORK_NAME="${NETWORK_NAME:-${NETWORK_DEFAULT_TMP:-my-network}}"

if docker network ls --format '{{.Name}}' | grep -Fxq "${NETWORK_NAME}"; then
    echo "Red existente: ${NETWORK_NAME}"
    exit 0
fi

echo "Creando red: ${NETWORK_NAME}"
if [[ -n "${NETWORK_SUBNET}" ]]; then
    docker network create --driver bridge --subnet "${NETWORK_SUBNET}" "${NETWORK_NAME}"
else
    docker network create --driver bridge "${NETWORK_NAME}"
fi
