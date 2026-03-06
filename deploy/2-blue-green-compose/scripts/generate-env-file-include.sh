#!/usr/bin/env bash
# Genera docker-compose.env-include-blue.yml y docker-compose.env-include-green.yml (env_file con rutas absolutas, uno por stack).
# Lista: .env del proyecto (donde se llama) + archivos de ENV_FILE (comma-separated). No usa rutas relativas.
# Uso: desde la raíz del repo o desde donde exista .env; se invoca desde blue-green.sh.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly DOCKER_DIR="${SCRIPT_DIR}/../docker"
readonly ROOT_ENV="${PROJECT_ROOT}/.env"
readonly OUT_BLUE="${DOCKER_DIR}/docker-compose.env-include-blue.yml"
readonly OUT_GREEN="${DOCKER_DIR}/docker-compose.env-include-green.yml"

# Rutas absolutas para env_file
# Prioridad (último gana en Compose): 1) ENV_FILE (menor), 2) .env raíz (mayor).
declare -a FILES=()

# 1) Lista ENV_FILE del .env (comma-separated, menor prioridad — primero en la lista)
if [[ -f "${ROOT_ENV}" ]]; then
    env_file_list=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" != ENV_FILE=* ]] && continue
        env_file_list="${line#ENV_FILE=}"
        env_file_list="$(printf '%s' "${env_file_list}" | sed "s/^['\"]//;s/['\"]$//" | tr -d '\r\n' | xargs)"
        break
    done < "${ROOT_ENV}"

    if [[ -n "${env_file_list}" ]]; then
        IFS=',' read -ra PARTS <<< "${env_file_list}"
        for part in "${PARTS[@]}"; do
            part="$(printf '%s' "${part}" | xargs)"
            [[ -z "${part}" ]] && continue
            if [[ "${part}" == /* ]]; then
                path="${part}"
            else
                path="${PROJECT_ROOT}/${part}"
            fi
            if [[ -f "${path}" ]]; then
                FILES+=("$(cd "$(dirname "${path}")" && pwd)/$(basename "${path}")")
            fi
        done
    fi
fi

# 2) .env raíz (mayor prioridad — último en la lista)
if [[ -f "${ROOT_ENV}" ]]; then
    root_abs="$(cd "${PROJECT_ROOT}" && pwd)/.env"
    # Evitar duplicado si ya se incluyó vía ENV_FILE
    local_dup=false
    for existing in "${FILES[@]}"; do
        [[ "${existing}" == "${root_abs}" ]] && local_dup=true && break
    done
    [[ "${local_dup}" == false ]] && FILES+=("${root_abs}")
fi

# Escribir un YAML por stack para que al usar solo blue (o solo green) no se añada el otro servicio sin image.
write_env_include() {
    local out_file="${1:?}"
    local service_name="${2:?}"
    if [[ ${#FILES[@]} -eq 0 ]]; then
        cat > "${out_file}" << 'EOF'
# Generado por scripts/generate-env-file-include.sh (sin archivos .env para inyectar)
services: {}
EOF
    else
        {
            echo "# Generado por scripts/generate-env-file-include.sh (rutas absolutas)"
            echo "services:"
            echo "  ${service_name}:"
            echo "    env_file:"
            for f in "${FILES[@]}"; do
                echo "      - ${f}"
            done
        } > "${out_file}"
    fi
}

mkdir -p "${DOCKER_DIR}"
write_env_include "${OUT_BLUE}" "app-blue"
write_env_include "${OUT_GREEN}" "app-green"
