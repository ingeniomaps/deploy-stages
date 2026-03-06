#!/usr/bin/env bash
# Blue-Green Setup: crea/actualiza .env y opcionalmente docker-compose.override.yml.
# Uso: desde la raíz del repo; escribe en .env de la raíz y docker/.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"
readonly OVERRIDE_FILE="${SCRIPT_DIR}/../docker/docker-compose.override.yml"

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# --- Helpers ---

print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

# Lee una variable desde ENV_FILE (sin comentarios ni comillas).
get_env() {
    local key="${1}"
    if [[ ! -f "${ENV_FILE}" ]]; then
        return 0
    fi
    grep "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- \
        | sed -e 's/^["'\'']//' -e 's/["'\'']$//' -e 's/#.*//' | tr -d '\r\n' | xargs || true
}

# Pide un valor por teclado; mensajes a stderr para no mezclar con make.
prompt() {
    local prompt_text="${1}"
    local default="${2}"
    local value
    if [[ -n "${default}" ]]; then
        echo -e "${YELLOW}>>> ${prompt_text} (Enter = ${default})${NC}" >&2
        printf "    Respuesta: " >&2
    else
        echo -e "${YELLOW}>>> ${prompt_text}${NC}" >&2
        printf "    Respuesta: " >&2
    fi
    read -r value
    echo "${value:-${default}}"
}

# Escribe o actualiza KEY=VALUE en ENV_FILE (evita sed con valores arbitrarios).
update_env() {
    local key="${1}"
    local value="${2}"
    local tmp
    tmp=$(mktemp)
    (grep -v "^${key}=" "${ENV_FILE}" 2>/dev/null || true; printf '%s=%s\n' "${key}" "${value}") > "${tmp}"
    mv "${tmp}" "${ENV_FILE}"
}

# Aplica valores por defecto a las variables de proyecto.
apply_defaults() {
    PROJECT_NAME="${PROJECT_NAME:-my-app}"
    PROJECT_IMAGE="${PROJECT_IMAGE:-${PROJECT_NAME}}"
    PROJECT_PORT="${PROJECT_PORT:-3000}"
    PROJECT_VERSION="${PROJECT_VERSION:-latest}"
    HEALTH_PATH="${HEALTH_PATH:-/health}"
}

# ¿Modo no interactivo? ( .env con PROJECT_NAME, PROJECT_IMAGE, NETWORK o SETUP_NONINTERACTIVE=1 )
is_noninteractive() {
    [[ -n "${SETUP_NONINTERACTIVE:-}" ]] && return 0
    [[ ! -f "${ENV_FILE}" ]] && return 1
    local name img net
    name=$(get_env "PROJECT_NAME")
    img=$(get_env "PROJECT_IMAGE")
    net=$(get_env "NETWORK")
    [[ -n "${name}" && -n "${img}" && -n "${net}" ]]
}

# --- Main ---

print_message "${BLUE}" "Blue-Green Deployment Setup"
echo ""

# Step 1: Crear .env si no existe
if [[ -f "${ENV_FILE}" ]]; then
    print_message "${YELLOW}" ".env already exists, will update values in place"
else
    if [[ -f "${ENV_EXAMPLE}" ]]; then
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        print_message "${GREEN}" "Created .env from .env.example"
    else
        print_message "${YELLOW}" "No .env.example found, creating .env from scratch. A continuación se pedirán los valores."
        touch "${ENV_FILE}"
    fi
fi

# Step 2: Obtener configuración (desde .env en no interactivo o por prompts)
echo ""
print_message "${BLUE}" "Project Configuration"
echo "Las preguntas solo aparecen si este .env no tiene PROJECT_NAME, PROJECT_IMAGE y NETWORK."
echo ""

if is_noninteractive; then
    print_message "${YELLOW}" "Usando valores de .env (modo no interactivo)."
    PROJECT_NAME=$(get_env "PROJECT_NAME")
    PROJECT_IMAGE=$(get_env "PROJECT_IMAGE")
    PROJECT_PORT=$(get_env "PROJECT_PORT")
    PROJECT_VERSION=$(get_env "PROJECT_VERSION")
    PROJECT_PREFIX=$(get_env "PROJECT_PREFIX")
    NETWORK=$(get_env "NETWORK")
    HEALTH_PATH=$(get_env "HEALTH_PATH")
else
    echo -e "${BLUE}Introduce los valores (escribe y pulsa Enter; el valor por defecto está entre paréntesis).${NC}" >&2
    echo "" >&2
    PROJECT_NAME=$(prompt "Project name" "my-app")
    PROJECT_IMAGE=$(prompt "Docker image" "${PROJECT_NAME}")
    PROJECT_PORT=$(prompt "Application port" "3000")
    PROJECT_VERSION=$(prompt "Image version/tag" "latest")
    PROJECT_PREFIX=$(prompt "Container prefix (optional, leave empty for none)" "")
    NETWORK=$(prompt "Docker network name" "my-network")
    HEALTH_PATH=$(prompt "Health check path" "/health")
fi

apply_defaults

# Step 3: Persistir en .env
update_env "PROJECT_NAME" "${PROJECT_NAME}"
update_env "PROJECT_IMAGE" "${PROJECT_IMAGE}"
update_env "PROJECT_PORT" "${PROJECT_PORT}"
update_env "PROJECT_VERSION" "${PROJECT_VERSION}"
update_env "PROJECT_PREFIX" "${PROJECT_PREFIX}"
update_env "NETWORK" "${NETWORK}"
update_env "NETWORK_DEFAULT" "${NETWORK}"
update_env "HEALTH_PATH" "${HEALTH_PATH}"
print_message "${GREEN}" "Updated .env"

# Step 4: Override opcional (env_file relativo a docker/, volumen)
echo ""
print_message "${BLUE}" "Override Configuration"
echo ""

ENV_FILE_REL=""
VOLUME_MAP=""
if ! is_noninteractive; then
    echo -e "${YELLOW}>>> Path to your project's env file (relative to docker/, e.g. ../.env). Enter = omitir${NC}" >&2
    printf "    Respuesta: " >&2
    read -r ENV_FILE_REL
    echo -e "${YELLOW}>>> Volume mount (e.g. ../data:/app/data). Enter = omitir${NC}" >&2
    printf "    Respuesta: " >&2
    read -r VOLUME_MAP
fi

if [[ -n "${ENV_FILE_REL}" || -n "${VOLUME_MAP}" ]]; then
    {
        echo "# Generated by setup.sh — project-specific overrides"
        echo "services:"
        for color in blue green; do
            echo "  app-${color}:"
            if [[ -n "${ENV_FILE_REL}" ]]; then
                echo "    env_file:"
                echo "      - ${ENV_FILE_REL}"
            fi
            if [[ -n "${VOLUME_MAP}" ]]; then
                echo "    volumes:"
                echo "      - ${VOLUME_MAP}"
            fi
        done
    } > "${OVERRIDE_FILE}"
    print_message "${GREEN}" "Generated docker/docker-compose.override.yml"
else
    print_message "${YELLOW}" "No overrides needed, skipping docker-compose.override.yml"
fi

# Summary
echo ""
print_message "${BLUE}" "Setup Complete"
echo ""
echo "  Project:  ${PROJECT_NAME}"
echo "  Image:    ${PROJECT_IMAGE}:${PROJECT_VERSION}"
echo "  Port:     ${PROJECT_PORT}"
echo "  Network:  ${NETWORK}"
echo "  Health:   ${HEALTH_PATH}"
echo ""
print_message "${YELLOW}" "Next steps:"
echo "  1. Review .env and adjust as needed"
echo "  2. Run 'make deploy-bluegreen' for first deployment"
echo "  3. Run 'make status-bluegreen' to check state"
echo "  4. Run 'make switch-bluegreen' to switch traffic"
