#!/usr/bin/env bash
# Restaura .env y archivos de ENV_FILE desde deploy/2.5-swarm/backup/
# (estado anterior al último deploy-swarm/update-swarm). Luego hay que ejecutar
# generate-env-file-include y docker stack deploy para aplicar en el servicio.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SWARM_DIR="${SCRIPT_DIR}/.."
readonly PROJECT_ROOT="$(cd "${SWARM_DIR}/../.." && pwd)"
readonly BACKUP_PREV_DIR="${SWARM_DIR}/backup_prev"
readonly BACKUP_PREV_ENV="${BACKUP_PREV_DIR}/.env"

# Rollback restaura desde backup_prev (estado anterior al último deploy/update)
if [[ ! -f "${BACKUP_PREV_ENV}" ]]; then
    echo "Error: no existe backup anterior (${BACKUP_PREV_ENV}). Haz al menos un deploy-swarm y un update-swarm antes de rollback." >&2
    exit 1
fi

readonly TARGET_ENV="${ENV_FILE:-${PROJECT_ROOT}/.env}"
cp -f "${BACKUP_PREV_ENV}" "${TARGET_ENV}"

# Restaurar cada archivo listado en ENV_FILE del backup (leer desde el .env que acabamos de copiar)
while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" != ENV_FILE=* ]] && continue
    env_file_list="${line#ENV_FILE=}"
    env_file_list="$(printf '%s' "${env_file_list}" | sed "s/^['\"]//;s/['\"]$//" | tr -d '\r\n' | xargs)"
    [[ -z "${env_file_list}" ]] && break
    IFS=',' read -ra PARTS <<< "${env_file_list}"
    for part in "${PARTS[@]}"; do
        part="$(printf '%s' "${part}" | xargs)"
        [[ -z "${part}" ]] && continue
        backup_file="${BACKUP_PREV_DIR}/${part}"
        if [[ -f "${backup_file}" ]]; then
            if [[ "${part}" == /* ]]; then
                dest="${part}"
            else
                dest="${PROJECT_ROOT}/${part}"
            fi
            mkdir -p "$(dirname "${dest}")"
            cp "${backup_file}" "${dest}"
        fi
    done
    break
done < "${BACKUP_PREV_ENV}"

echo "Restaurado .env y ENV_FILE desde backup. Reaplicando stack..."