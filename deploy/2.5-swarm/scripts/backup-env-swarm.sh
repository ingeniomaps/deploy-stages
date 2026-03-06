#!/usr/bin/env bash
# Guarda el estado actual de .env y ENV_FILE en deploy/2.5-swarm/backup/
# después de un deploy/update exitoso. Antes de sobrescribir, copia backup -> backup_prev
# para que rollback-swarm restaure desde backup_prev (estado anterior al último deploy/update).

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SWARM_DIR="${SCRIPT_DIR}/.."
readonly PROJECT_ROOT="$(cd "${SWARM_DIR}/../.." && pwd)"
readonly ROOT_ENV="${PROJECT_ROOT}/.env"
readonly BACKUP_DIR="${SWARM_DIR}/backup"
readonly BACKUP_PREV_DIR="${SWARM_DIR}/backup_prev"

if [[ ! -f "${ROOT_ENV}" ]]; then
    exit 0
fi

# Rotar: el backup actual pasa a ser el "anterior" para rollback
if [[ -d "${BACKUP_DIR}" ]]; then
    rm -rf "${BACKUP_PREV_DIR}"
    cp -r "${BACKUP_DIR}" "${BACKUP_PREV_DIR}"
fi

mkdir -p "${BACKUP_DIR}"
cp "${ROOT_ENV}" "${BACKUP_DIR}/.env"

# Copiar cada archivo listado en ENV_FILE (desde .env actual)
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
        if [[ "${part}" == /* ]]; then
            src="${part}"
        else
            src="${PROJECT_ROOT}/${part}"
        fi
        if [[ -f "${src}" ]]; then
            # Guardar en backup con el mismo path relativo (ej. .env-algo -> backup/.env-algo)
            dest="${BACKUP_DIR}/${part}"
            mkdir -p "$(dirname "${dest}")"
            cp "${src}" "${dest}"
        fi
    done
    break
done < "${ROOT_ENV}"
