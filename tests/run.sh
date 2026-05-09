#!/usr/bin/env bash
# Test runner: corre todos los archivos test_*.sh en este directorio.
# Cada archivo es un script bash que usa tests/lib/assert.sh y reporta resultados.
#
# Uso desde la raíz del repo deploy-stages:
#   bash tests/run.sh
#
# Exit:
#   0 si todos los tests pasan, 1 si algún test falla.

set -u  # NO -e — queremos correr todos los archivos aunque alguno falle.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

TOTAL_RUN=0
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_FILES=()

shopt -s nullglob
test_files=("${SCRIPT_DIR}"/test_*.sh)
shopt -u nullglob

if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "No se encontraron tests en ${SCRIPT_DIR}/test_*.sh"
    exit 0
fi

# Cada archivo escribe sus totales a un archivo temporal individual (más robusto que pipes).
TOTALS_DIR="$(mktemp -d)"
trap 'rm -rf "${TOTALS_DIR}"' EXIT

for f in "${test_files[@]}"; do
    name="$(basename "${f}")"
    totals_file="${TOTALS_DIR}/${name}.totals"
    printf '\n%bRunning %s%b\n' "${YELLOW}" "${name}" "${NC}"

    (
        TESTS_RUN=0 TESTS_PASSED=0 TESTS_FAILED=0 FAILED_NAMES=""
        # shellcheck disable=SC1090
        source "${f}"
        printf '%d %d %d\n' "${TESTS_RUN}" "${TESTS_PASSED}" "${TESTS_FAILED}" > "${totals_file}"
    )

    file_run=0 file_pass=0 file_fail=0
    if [[ -f "${totals_file}" ]]; then
        read -r file_run file_pass file_fail < "${totals_file}"
    fi
    printf '%d run, %d pass, %d fail\n' "${file_run}" "${file_pass}" "${file_fail}"

    TOTAL_RUN=$((TOTAL_RUN + file_run))
    TOTAL_PASSED=$((TOTAL_PASSED + file_pass))
    TOTAL_FAILED=$((TOTAL_FAILED + file_fail))
    if [[ "${file_fail}" -gt 0 ]]; then
        FAILED_FILES+=("${name}")
    fi
done

echo ""
echo "============================================"
if [[ "${TOTAL_FAILED}" -eq 0 ]]; then
    printf '%bAll tests passed%b: %d run, %d pass\n' "${GREEN}" "${NC}" "${TOTAL_RUN}" "${TOTAL_PASSED}"
    exit 0
else
    printf '%bFailures%b: %d run, %d pass, %d fail\n' "${RED}" "${NC}" "${TOTAL_RUN}" "${TOTAL_PASSED}" "${TOTAL_FAILED}"
    if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
        printf 'Files with failures:\n'
        printf '  %s\n' "${FAILED_FILES[@]}"
    fi
    exit 1
fi
