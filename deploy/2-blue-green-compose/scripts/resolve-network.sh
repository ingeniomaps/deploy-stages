#!/usr/bin/env bash
# Resuelve la red Docker PRINCIPAL para compose (la que recibe CONTAINER_IP).
# Prioridad: NETWORK > NETWORK_DEFAULT > primera de NETWORK_NAME.
# NETWORK_NAME aporta redes adicionales (ver generate-extra-networks.sh); solo se usa como
# fallback para la principal si NETWORK y NETWORK_DEFAULT están vacíos.
# Si la red no existe la crea (con NETWORK_SUBNET si está definido).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly PROJECT_ROOT
readonly ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"

# shellcheck source=../../scripts/lib/parse-env.sh
source "${PROJECT_ROOT}/deploy/scripts/lib/parse-env.sh"

# Devuelve el primer elemento (trimmeado) de una lista separada por comas.
first_from_list() {
    local list="${1:-}"
    [[ -z "${list}" ]] && return 1
    local first
    first="$(trim_string "${list%%,*}")"
    [[ -n "${first}" ]] && echo "${first}" && return 0
    return 1
}

load_env_export "${ENV_FILE}"

# Red principal: NETWORK > NETWORK_DEFAULT > primera de NETWORK_NAME
PRIMARY="${NETWORK:-${NETWORK_DEFAULT:-}}"
if [[ -z "${PRIMARY}" ]] && [[ -n "${NETWORK_NAME:-}" ]]; then
  PRIMARY="$(first_from_list "${NETWORK_NAME}")" || true
fi

if [[ -z "${PRIMARY}" ]]; then
  echo "ERROR: No se pudo determinar la red principal. Defina NETWORK, NETWORK_DEFAULT o NETWORK_NAME en .env" >&2
  exit 1
fi

# Crear si no existe
if ! docker network ls --format '{{.Name}}' | grep -Fxq "${PRIMARY}"; then
  if [[ -n "${NETWORK_SUBNET:-}" ]]; then
    docker network create --subnet="${NETWORK_SUBNET}" "${PRIMARY}" >&2
  else
    docker network create "${PRIMARY}" >&2
  fi
fi

echo "${PRIMARY}"
