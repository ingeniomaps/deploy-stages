#!/usr/bin/env bash
# Ejecuta el setup (si existe) y arranca la app.
# Orden de resolución del comando:
#   1) Si DOCKER_COMPOSE_APP está definido en .env y el YAML tiene `command:` en el servicio principal,
#      se usa ese comando.
#   2) En otro caso, se usa el CMD del Dockerfile del proyecto.
# Uso: desde la raíz del repo, ./deploy/0-manual/run.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Cargar .env si existe (raíz del repo)
ENV_FILE_ROOT="${REPO_ROOT}/.env"
if [[ -f "${ENV_FILE_ROOT}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE_ROOT}"
    set +a
fi

# Cargar archivos adicionales si ENV_FILE está definido (lista separada por comas)
if [[ -n "${ENV_FILE:-}" ]]; then
    while IFS= read -r -d ',' f || [[ -n "${f:-}" ]]; do
        f="${f#"${f%%[![:space:]]*}"}"
        f="${f%"${f##*[![:space:]]}"}"
        [[ -z "${f}" ]] && continue
        if [[ "${f}" != /* ]]; then
            f="${REPO_ROOT}/${f}"
        fi
        if [[ -f "${f}" ]]; then
            set -a
            # shellcheck disable=SC1090
            source "${f}"
            set +a
        fi
    done <<< "${ENV_FILE},"
fi

# Alinear PORT con PROJECT_PORT si la app espera PORT (p. ej. paridad con compose)
if [[ -z "${PORT:-}" && -n "${PROJECT_PORT:-}" ]]; then
    export PORT="${PROJECT_PORT}"
fi

# Resolver directorio del proyecto
if [[ -n "${PROJECT_SOURCE:-}" ]]; then
    if [[ "${PROJECT_SOURCE}" == /* ]]; then
        readonly PROJECT_ROOT="${PROJECT_SOURCE}"
    else
        readonly PROJECT_ROOT="${REPO_ROOT}/${PROJECT_SOURCE}"
    fi
else
    readonly PROJECT_ROOT="${REPO_ROOT}"
fi

# Resolver Dockerfile
if [[ -n "${DOCKERFILE_PATH:-}" ]]; then
    readonly DOCKERFILE="${PROJECT_ROOT}/${DOCKERFILE_PATH}"
else
    readonly DOCKERFILE="${PROJECT_ROOT}/Dockerfile"
fi

readonly SETUP_SH="${PROJECT_ROOT}/scripts/setup/setup.sh"

cd "${PROJECT_ROOT}"

if [[ -f "${SETUP_SH}" ]]; then
    bash "${SETUP_SH}"
fi

# 1) Intentar obtener el comando desde DOCKER_COMPOSE_APP (si está definido y el archivo existe)
RUN_CMD=""
if [[ -n "${DOCKER_COMPOSE_APP:-}" ]]; then
    if [[ "${DOCKER_COMPOSE_APP}" == /* ]]; then
        compose_main="${DOCKER_COMPOSE_APP}"
    else
        # Ruta relativa se interpreta dentro de PROJECT_ROOT (no de la raíz del repo)
        compose_main="${PROJECT_ROOT}/${DOCKER_COMPOSE_APP}"
    fi
    if [[ -f "${compose_main}" ]]; then
        # Tomar la primera línea con `command:` del YAML
        COMPOSE_CMD_LINE="$(grep -E '^[[:space:]]*command:' "${compose_main}" | head -1 || true)"
        if [[ -n "${COMPOSE_CMD_LINE}" ]]; then
            # Extraer contenido dentro de los corchetes y convertir a comando shell
            # Ejemplo: command: ['bun', 'run', 'scripts/dev-watch.js']
            RUN_CMD="$(echo "${COMPOSE_CMD_LINE}" \
                | awk -F'[][]' '{print $2}' \
                | tr -d "\"'" \
                | sed 's/, / /g')"
        fi
    fi
fi

if [[ -n "${RUN_CMD}" ]]; then
    read -ra RUN_ARRAY <<< "${RUN_CMD}"
    echo ""
    echo "--- Arrancando app (${RUN_CMD}) (desde ${DOCKER_COMPOSE_APP}) ---"
    exec "${RUN_ARRAY[@]}"
fi

# 2) Fallback: usar el CMD del Dockerfile
if [[ ! -f "${DOCKERFILE}" ]]; then
    echo "Error: no se encontró ${DOCKERFILE}" >&2
    exit 1
fi

CMD_LINE="$(grep '^CMD ' "${DOCKERFILE}" | tail -1)"
if [[ -z "${CMD_LINE}" ]]; then
    echo "Error: no se encontró CMD en el Dockerfile" >&2
    exit 1
fi

RUN_CMD="$(echo "${CMD_LINE}" | sed 's/^CMD \[//;s/\]$//;s/"//g;s/, / /g')"
read -ra RUN_ARRAY <<< "${RUN_CMD}"

echo ""
echo "--- Arrancando app (${RUN_CMD}) ---"
exec "${RUN_ARRAY[@]}"
