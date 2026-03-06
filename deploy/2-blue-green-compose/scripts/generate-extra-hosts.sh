#!/usr/bin/env bash
# Genera docker-compose.extra-hosts-blue.yml y -green.yml con extra_hosts
# a partir de variables HOST_* en .env (formato hostname:ip).
# Si no hay variables HOST_*, elimina los archivos generados.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly DOCKER_DIR="${SCRIPT_DIR}/../docker"
readonly ROOT_ENV="${PROJECT_ROOT}/.env"
readonly OUT_BLUE="${DOCKER_DIR}/docker-compose.extra-hosts-blue.yml"
readonly OUT_GREEN="${DOCKER_DIR}/docker-compose.extra-hosts-green.yml"

declare -a EXTRA_HOSTS=()

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

        if [[ "${key}" =~ ^HOST_[A-Za-z0-9_]+$ ]]; then
            [[ -z "${value}" ]] && continue
            if [[ "${value}" =~ ^[^:]+:[0-9.]+$ ]]; then
                EXTRA_HOSTS+=("${value}")
            fi
        fi
    done < "${ROOT_ENV}"
fi

# Si no hay hosts, limpiar archivos generados y salir
if [[ ${#EXTRA_HOSTS[@]} -eq 0 ]]; then
    [[ -f "${OUT_BLUE}" ]] && rm -f "${OUT_BLUE}"
    [[ -f "${OUT_GREEN}" ]] && rm -f "${OUT_GREEN}"
    exit 0
fi

mkdir -p "${DOCKER_DIR}"

# Genera overlay compose con extra_hosts para un servicio.
# $1 = archivo de salida, $2 = nombre del servicio
write_extra_hosts() {
    local out_file="${1:?}"
    local service_name="${2:?}"

    {
        echo "# Generado por scripts/generate-extra-hosts.sh (variables HOST_* en .env)"
        echo "services:"
        echo "  ${service_name}:"
        echo "    extra_hosts:"
        for host in "${EXTRA_HOSTS[@]}"; do
            echo "      - \"${host}\""
        done
    } > "${out_file}"
}

write_extra_hosts "${OUT_BLUE}" "app-blue"
write_extra_hosts "${OUT_GREEN}" "app-green"
