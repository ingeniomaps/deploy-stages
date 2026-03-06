#!/usr/bin/env bash
# Genera docker-compose.override.yml desde .env: extra_hosts (HOST_*), env_file, PORTS, CONTAINER_IP.
# Uso: desde la raíz del repo; lee .env y escribe deploy/1-simple-compose/docker-compose.override.yml

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT="$(cd "${COMPOSE_DIR}/../.." && pwd)"
readonly ROOT_ENV="${ENV_FILE:-${PROJECT_ROOT}/.env}"
readonly OVERRIDE_FILE="${COMPOSE_DIR}/docker-compose.override.yml"

EXTRA_HOSTS=()
CONTAINER_IP=""
PORTS_LIST=()
ENV_FILE_PATHS=()
PROJECT_SOURCE_VAL=""
DOCKERFILE_PATH_VAL=""

# Normaliza valor: quita comentarios inline, comillas y espacios.
normalize_value() {
    local v="$1"
    v="${v%%#*}"
    v="$(printf '%s' "${v}" | sed "s/^['\"]//;s/['\"]$//" | tr -d '\r\n' | xargs)"
    printf '%s' "${v}"
}

# Añade al archivo un bloque YAML de lista (clave + ítems).
append_yaml_list() {
    local key="$1"
    shift
    local items=("$@")
    if [ ${#items[@]} -eq 0 ]; then
        printf '    %s:\n      []\n' "${key}" >> "${OVERRIDE_FILE}"
        return
    fi
    printf '\n    %s:\n' "${key}" >> "${OVERRIDE_FILE}"
    for item in "${items[@]}"; do
        printf '      - "%s"\n' "${item}" >> "${OVERRIDE_FILE}"
    done
}

# ENV_FILE debe ser ruta a archivo; si parece host:ip se ignora.
is_likely_path() {
    [[ "$1" =~ ^[^:]+:[0-9.]+$ ]] && return 1
    return 0
}

# --- Recoger .env en raíz de 1-simple-compose
if [[ -f "${COMPOSE_DIR}/.env" ]]; then
    ENV_FILE_PATHS+=(".env")
fi

# --- Parsear .env de la raíz
if [[ -f "${ROOT_ENV}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" != *'='* ]] && continue
        key="${line%%=*}"
        key="$(printf '%s' "${key}" | xargs)"
        value="$(normalize_value "${line#*=}")"
        [[ -z "${key}" ]] && continue

        if [[ "${key}" =~ ^HOST_[A-Za-z0-9_]+$ ]]; then
            [[ -z "${value}" ]] && continue
            if [[ "${value}" =~ ^[^:]+:[0-9.]+$ ]]; then
                EXTRA_HOSTS+=("${value}")
            fi
        elif [[ "${key}" == "CONTAINER_IP" ]] && [[ -n "${value}" ]]; then
            CONTAINER_IP="${value}"
        elif [[ "${key}" == "PORTS" ]] && [[ -n "${value}" ]]; then
            IFS=',' read -ra PAIRS <<< "${value}"
            for pair in "${PAIRS[@]}"; do
                p="$(printf '%s' "${pair}" | xargs)"
                [[ -z "${p}" ]] && continue
                [[ "${p}" =~ ^[0-9]+:[0-9]+$ ]] && PORTS_LIST+=("${p}")
            done
        elif [[ "${key}" == "PROJECT_SOURCE" ]] && [[ -n "${value}" ]]; then
            PROJECT_SOURCE_VAL="${value}"
        elif [[ "${key}" == "DOCKERFILE_PATH" ]] && [[ -n "${value}" ]]; then
            DOCKERFILE_PATH_VAL="${value}"
        elif [[ "${key}" == "ENV_FILE" ]] && [[ -n "${value}" ]]; then
            IFS=',' read -ra PARTS <<< "${value}"
            for p in "${PARTS[@]}"; do
                p="$(printf '%s' "${p}" | xargs)"
                [[ -z "${p}" ]] && continue
                is_likely_path "${p}" || continue
                [[ "${p}" == ".env" ]] && [[ " ${ENV_FILE_PATHS[*]} " == *" .env "* ]] && continue
                ENV_FILE_PATHS+=("${p}")
            done
        fi
    done < "${ROOT_ENV}"
fi

# Resolver env_file a rutas absolutas y quitar duplicados (compose exige items únicos).
# Orden de prioridad (Docker Compose: la última definición gana):
#   1) Archivos de ENV_FILE en .env raíz     → en el orden declarado (menor prioridad).
#   2) .env raíz del repo                    → valores comunes de la etapa.
#   3) .env de PROJECT_SOURCE (ej. app/.env)  → más específico, mayor prioridad.
ENV_FILE_ABSOLUTE=()
PROJECT_SOURCE_ENV=""
if [[ -n "${PROJECT_SOURCE_VAL}" ]]; then
    if [[ "${PROJECT_SOURCE_VAL}" == /* ]]; then
        project_source_root="${PROJECT_SOURCE_VAL}"
    else
        project_source_root="${PROJECT_ROOT}/${PROJECT_SOURCE_VAL}"
    fi
    project_env="${project_source_root}/.env"
    if [[ -f "${project_env}" ]]; then
        PROJECT_SOURCE_ENV="${project_env}"
    fi
fi
if [[ -f "${ROOT_ENV}" ]]; then
    ENV_FILE_ABSOLUTE+=("${ROOT_ENV}")
fi
for p in "${ENV_FILE_PATHS[@]}"; do
    if [[ "${p}" == /* ]]; then
        path="${p}"
    else
        path="${PROJECT_ROOT}/${p}"
    fi
    [[ ! -f "${path}" ]] && continue
    # Evitar duplicados
    for existing in "${ENV_FILE_ABSOLUTE[@]}"; do
        [[ "${existing}" == "${path}" ]] && continue 2
    done
    ENV_FILE_ABSOLUTE+=("${path}")
done
# PROJECT_SOURCE .env al final (mayor prioridad en Docker Compose)
if [[ -n "${PROJECT_SOURCE_ENV}" ]]; then
    ENV_FILE_ABSOLUTE+=("${PROJECT_SOURCE_ENV}")
fi

# --- Escribir override: cabecera + extra_hosts
cat > "${OVERRIDE_FILE}" << 'HEAD'
# Generado por scripts/generate-extra-hosts.sh (HOST_*, ENV_FILE, PORTS, CONTAINER_IP en .env)

services:
  app:
    extra_hosts:
HEAD

# Completar lista extra_hosts
if [[ ${#EXTRA_HOSTS[@]} -eq 0 ]]; then
    echo "      []" >> "${OVERRIDE_FILE}"
else
    for entry in "${EXTRA_HOSTS[@]}"; do
        printf '      - "%s"\n' "${entry}" >> "${OVERRIDE_FILE}"
    done
fi

# Bloques opcionales solo si hay ítems (evitar env_file/ports vacíos)
if [[ ${#ENV_FILE_ABSOLUTE[@]} -gt 0 ]]; then
    append_yaml_list "env_file" "${ENV_FILE_ABSOLUTE[@]}"
fi
if [[ ${#PORTS_LIST[@]} -gt 0 ]]; then
    append_yaml_list "ports" "${PORTS_LIST[@]}"
fi

if [[ -n "${CONTAINER_IP}" ]]; then
    cat >> "${OVERRIDE_FILE}" << EOF

    networks:
      default:
        ipv4_address: "${CONTAINER_IP}"
EOF
fi

# Build context (si PROJECT_SOURCE o DOCKERFILE_PATH están definidos)
BUILD_CONTEXT=""
if [[ -n "${PROJECT_SOURCE_VAL}" ]]; then
    if [[ "${PROJECT_SOURCE_VAL}" == /* ]]; then
        BUILD_CONTEXT="${PROJECT_SOURCE_VAL}"
    else
        BUILD_CONTEXT="${PROJECT_ROOT}/${PROJECT_SOURCE_VAL}"
    fi
fi

if [[ -n "${BUILD_CONTEXT}" ]] || [[ -n "${DOCKERFILE_PATH_VAL}" ]]; then
    printf '\n    build:\n' >> "${OVERRIDE_FILE}"
    if [[ -n "${BUILD_CONTEXT}" ]]; then
        printf '      context: "%s"\n' "${BUILD_CONTEXT}" >> "${OVERRIDE_FILE}"
    fi
    if [[ -n "${DOCKERFILE_PATH_VAL}" ]]; then
        printf '      dockerfile: "%s"\n' "${DOCKERFILE_PATH_VAL}" >> "${OVERRIDE_FILE}"
    fi
fi
