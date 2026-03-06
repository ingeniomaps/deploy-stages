#!/usr/bin/env bash
# Comprueba que .env tenga las variables obligatorias para deploy-simple.
# Uso: desde la raíz del repo; lee .env y sale con error si falta PROJECT_NAME, PROJECT_PORT o NETWORK.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly ROOT_ENV="${ENV_FILE:-${PROJECT_ROOT}/.env}"

PROJECT_NAME=""
PROJECT_PORT=""
NETWORK=""

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
            PROJECT_NAME) [[ -n "${value}" ]] && PROJECT_NAME="${value}" ;;
            PROJECT_PORT) [[ -n "${value}" ]] && PROJECT_PORT="${value}" ;;
            NETWORK)     [[ -n "${value}" ]] && NETWORK="${value}" ;;
        esac
    done < "${ROOT_ENV}"
fi

missing=()
[[ -z "${PROJECT_NAME}" ]] && missing+=("PROJECT_NAME")
[[ -z "${PROJECT_PORT}" ]] && missing+=("PROJECT_PORT")
[[ -z "${NETWORK}" ]]     && missing+=("NETWORK")

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: en .env faltan variables obligatorias para deploy-simple: ${missing[*]}" >&2
    echo "Añádelas en .env (ver deploy/.env.example)." >&2
    exit 1
fi
