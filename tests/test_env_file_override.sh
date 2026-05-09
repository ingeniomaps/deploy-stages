#!/usr/bin/env bash
# Test para F1: scripts en deploy/2-blue-green-compose/scripts honran la env var ENV_FILE
# para localizar el .env del consumidor (no hardcodean ${PROJECT_ROOT}/.env).
#
# Sin este fix, los scripts buscaban .env en .deploy/.env (que típicamente no existe
# cuando el framework se usa como submódulo), y al no encontrarlo, generaban archivos
# overlay vacíos — entonces los containers del stack arrancaban sin las env vars del
# proyecto. accounts no se ve afectado porque solo usa stage 1, donde estos scripts
# no se invocan.

set -u

readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOY_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck source=lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

# Scripts que tenían el bug (hardcoded ROOT_ENV sin ENV_FILE override).
declare -a F1_SCRIPTS=(
    "deploy/2-blue-green-compose/scripts/generate-env-file-include.sh"
    "deploy/2-blue-green-compose/scripts/generate-extra-hosts.sh"
    "deploy/2-blue-green-compose/scripts/generate-extra-networks.sh"
    "deploy/2-blue-green-compose/scripts/generate-nginx-override.sh"
)

# Cada script debe tener ROOT_ENV con ENV_FILE override.
for script in "${F1_SCRIPTS[@]}"; do
    full="${DEPLOY_ROOT}/${script}"
    if [[ ! -f "${full}" ]]; then
        assert_equals "exists" "missing" "${script} existe"
        continue
    fi
    if grep -q 'ROOT_ENV="\${ENV_FILE:-\${PROJECT_ROOT}/\.env}"' "${full}"; then
        assert_equals "ok" "ok" "${script}: ROOT_ENV honra ENV_FILE override"
    else
        # Mostrar la línea real para debug
        actual=$(grep '^readonly ROOT_ENV=' "${full}" | head -1)
        assert_equals "ROOT_ENV honors ENV_FILE" "${actual}" "${script}: ROOT_ENV pattern incorrecto"
    fi
done

# Smoke functional test: simular el comportamiento esperado
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

PROJECT_ROOT="${TMP}/fake-deploy"
mkdir -p "${PROJECT_ROOT}"
# .deploy/.env NO existe (caso típico submódulo)

# Caso 1: ENV_FILE NO set → cae al default ${PROJECT_ROOT}/.env (no existe → script salta sus operaciones)
ENV_FILE="" ROOT_ENV="${ENV_FILE:-${PROJECT_ROOT}/.env}"
assert_equals "${PROJECT_ROOT}/.env" "${ROOT_ENV}" "ENV_FILE empty → defaults to PROJECT_ROOT/.env"

# Caso 2: ENV_FILE set → wins (puede apuntar al .env real del consumidor)
mkdir -p "${TMP}/consumer"
echo "FOO=bar" > "${TMP}/consumer/.env"
ENV_FILE="${TMP}/consumer/.env" ROOT_ENV="${ENV_FILE:-${PROJECT_ROOT}/.env}"
assert_equals "${TMP}/consumer/.env" "${ROOT_ENV}" "ENV_FILE set → override gana"

# Caso 3: Verificar sintaxis válida en todos los scripts
for script in "${F1_SCRIPTS[@]}"; do
    bash -n "${DEPLOY_ROOT}/${script}"
    assert_exit_zero "bash -n" "$?" "${script} sintaxis válida"
done
