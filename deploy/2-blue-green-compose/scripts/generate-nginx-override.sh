#!/usr/bin/env bash
# Genera docker-compose.override.yml solo con CONTAINER_IP para nginx.
# El env_file de app-blue y app-green está en los compose base (../../.env) para no
# definir servicios en el override que no existan al cargar solo blue o solo green.
# Uso: desde la raíz del repo; lee .env de la raíz.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly PROJECT_ROOT
readonly DOCKER_DIR="${SCRIPT_DIR}/../docker"
readonly ROOT_ENV="${ENV_FILE:-${PROJECT_ROOT}/.env}"
# Nota: ROOT_ENV usa ENV_FILE exportado por el Makefile del proyecto
readonly OVERRIDE_FILE="${DOCKER_DIR}/docker-compose.override.yml"

# shellcheck source=../../scripts/lib/parse-env.sh
source "${PROJECT_ROOT}/deploy/scripts/lib/parse-env.sh"

CONTAINER_IP="$(get_env_value "${ROOT_ENV}" "CONTAINER_IP")"

if [[ -z "${CONTAINER_IP}" ]]; then
    [[ -f "${OVERRIDE_FILE}" ]] && rm -f "${OVERRIDE_FILE}"
    exit 0
fi

mkdir -p "$(dirname "${OVERRIDE_FILE}")"
cat > "${OVERRIDE_FILE}" << EOF
# Generado por scripts/generate-nginx-override.sh (CONTAINER_IP en .env)

services:
  nginx:
    networks:
      default:
        ipv4_address: ${CONTAINER_IP}
EOF
