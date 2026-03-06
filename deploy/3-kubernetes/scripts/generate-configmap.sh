#!/usr/bin/env bash
# Genera service/configmap.yml a partir de .env raiz + archivos en ENV_FILE.
# Espejo de swarm/scripts/generate-env-file-include.sh adaptado a ConfigMap YAML.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly K8S_DIR="${SCRIPT_DIR}/.."
readonly PROJECT_ROOT="$(cd "${K8S_DIR}/../.." && pwd)"
readonly ROOT_ENV="${PROJECT_ROOT}/.env"
# Sin argumento: genera configmap-blue.yml y configmap-green.yml. Con "blue" o "green": solo ese.
readonly SUFFIX_ARG="${1:-}"

# Parsea una linea KEY=VALUE; escribe a la asociativa ENV_ARR.
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

# Escapa un valor para YAML double-quoted string
yaml_escape() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '%s' "${v}"
}

# Recopilar archivos a cargar
declare -a FILES_TO_LOAD=()
if [[ -f "${ROOT_ENV}" ]]; then
    FILES_TO_LOAD+=("${ROOT_ENV}")
    # Obtener lista ENV_FILE del .env raiz (comma-separated)
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
fi

# Parsear todas las variables
declare -A ENV_ARR=()
for f in "${FILES_TO_LOAD[@]}"; do
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_env_line "${line}" ENV_ARR
    done < "${f}"
done

# Asegurar que PROJECT_PORT existe (default 3000)
if [[ -z "${ENV_ARR[PROJECT_PORT]:-}" ]]; then
    ENV_ARR[PROJECT_PORT]="3000"
fi

# Nombre base sin prefijo: patch_k8s_names en blue-green.sh aplica PROJECT_PREFIX después
if [[ -z "${ENV_ARR[PROJECT_NAME]:-}" ]]; then
    echo "Error: PROJECT_NAME no definido en .env" >&2
    exit 1
fi
CONFIGMAP_BASE="${ENV_ARR[PROJECT_NAME]}-config"

write_one_configmap() {
    local name="${1:?}"
    local out_path="${K8S_DIR}/service/configmap-${name}.yml"
    mkdir -p "$(dirname "${out_path}")"
    {
        echo "# Generado por scripts/generate-configmap.sh — no editar manualmente"
        echo "apiVersion: v1"
        echo "kind: ConfigMap"
        echo "metadata:"
        echo "  name: ${CONFIGMAP_BASE}-${name}"
        echo "data:"
        for k in $(echo "${!ENV_ARR[@]}" | tr ' ' '\n' | sort); do
            v="$(yaml_escape "${ENV_ARR[$k]}")"
            echo "  ${k}: \"${v}\""
        done
    } > "${out_path}"
    echo "ConfigMap generado: ${out_path}"
}

if [[ "${SUFFIX_ARG}" == "blue" || "${SUFFIX_ARG}" == "green" ]]; then
    write_one_configmap "${SUFFIX_ARG}"
else
    write_one_configmap "blue"
    write_one_configmap "green"
fi
