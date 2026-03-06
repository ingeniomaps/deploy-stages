#!/usr/bin/env bash
# Genera deploy/2.5-swarm/docker-stack.env-include.yml con las variables de entorno
# inyectadas como environment (valores leídos de los archivos), no como env_file.
# Así cada deploy/update usa siempre el contenido actual de .env y ENV_FILE.
# Rutas relativas a deploy/2.5-swarm/. Orden: .env raíz, luego ENV_FILE.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SWARM_DIR="${SCRIPT_DIR}/.."
readonly PROJECT_ROOT="$(cd "${SWARM_DIR}/../.." && pwd)"
readonly ROOT_ENV="${PROJECT_ROOT}/.env"
readonly OUT_FILE="${SWARM_DIR}/docker-stack.env-include.yml"

# Parsea una línea KEY=VALUE; escribe a la asociativa ENV_ARR (nombre pasado como string).
# Valor: permite comillas dobles/simples; quita saltos de línea.
parse_env_line() {
    local line="$1"
    local -n arr="$2"
    [[ "${line}" =~ ^[[:space:]]*# ]] && return 0
    [[ "${line}" =~ ^[[:space:]]*$ ]] && return 0
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        val="$(printf '%s' "${val}" | sed "s/^[\"']//;s/[\"']$//" | tr -d '\r\n')"
        arr["${key}"]="${val}"
    fi
}

# Escapa un valor para YAML (dobles comillas; dentro escapamos \ y ")
yaml_escape() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '%s' "${v}"
}

# Prioridad (último leído gana): 1) ENV_FILE (menor), 2) .env raíz (mayor).
declare -a FILES_TO_LOAD=()
if [[ -f "${ROOT_ENV}" ]]; then
    # 1) Cargar ENV_FILE extras primero (menor prioridad)
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" != ENV_FILE=* ]] && continue
        env_file_list="${line#ENV_FILE=}"
        env_file_list="$(printf '%s' "${env_file_list}" | sed "s/^['\"]//;s/['\"]$//" | tr -d '\r\n' | xargs)"
        [[ -z "${env_file_list}" ]] && break
        IFS=',' read -ra PARTS <<< "${env_file_list}"
        for part in "${PARTS[@]}"; do
            part="$(printf '%s' "${part}" | xargs)"
            [[ -z "${part}" ]] && continue
            if [[ "${part}" == /* ]]; then
                path="${part}"
            else
                path="${PROJECT_ROOT}/${part}"
            fi
            [[ -f "${path}" ]] && FILES_TO_LOAD+=("${path}")
        done
        break
    done < "${ROOT_ENV}"
    # 2) .env raíz último (mayor prioridad — sobrescribe ENV_FILE)
    FILES_TO_LOAD+=("${ROOT_ENV}")
fi

declare -A ENV_ARR=()
for f in "${FILES_TO_LOAD[@]}"; do
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_env_line "${line}" ENV_ARR
    done < "${f}"
done

mkdir -p "${SWARM_DIR}"
if [[ ${#ENV_ARR[@]} -eq 0 ]]; then
    printf '# Generado por scripts/generate-env-file-include.sh (no .env en raíz ni ENV_FILE)\nservices:\n  app: {}\n' > "${OUT_FILE}"
else
    {
        echo "# Generado por scripts/generate-env-file-include.sh — variables leídas de los archivos (no env_file)"
        echo "services:"
        echo "  app:"
        echo "    environment:"
        for k in $(echo "${!ENV_ARR[@]}" | tr ' ' '\n' | sort); do
            v="$(yaml_escape "${ENV_ARR[$k]}")"
            echo "      ${k}: \"${v}\""
        done
    } > "${OUT_FILE}"
fi
