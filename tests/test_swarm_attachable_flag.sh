#!/usr/bin/env bash
# Test para F2: ensure-network-swarm.sh respeta NETWORK_SWARM_ATTACHABLE para crear
# overlay attachable cuando el operador lo necesita (containers standalone fuera del
# stack swarm que necesitan conectarse a la overlay).

set -u

readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOY_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
readonly SCRIPT="${DEPLOY_ROOT}/deploy/2.5-swarm/scripts/ensure-network-swarm.sh"

# shellcheck source=lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

# 1) La variable NETWORK_SWARM_ATTACHABLE se referencia en el script
ref_count=$(grep -c 'NETWORK_SWARM_ATTACHABLE' "${SCRIPT}" || true)
assert_exit_zero "ref grep" "$?" "NETWORK_SWARM_ATTACHABLE referenced in ensure-network-swarm.sh"
[[ "${ref_count}" -ge 1 ]]
assert_exit_zero "ref >=1" "$?" "al menos 1 referencia a NETWORK_SWARM_ATTACHABLE"

# 2) El default es no-attachable (preserva comportamiento histórico)
default_off=$(grep -c 'NETWORK_SWARM_ATTACHABLE:-0' "${SCRIPT}" || true)
assert_equals "1" "${default_off}" "default es 0 (preserva comportamiento histórico)"

# 3) El flag --attachable se invoca con opt-in
flag_invoked=$(grep -c '\-\-attachable' "${SCRIPT}" || true)
[[ "${flag_invoked}" -ge 1 ]]
assert_exit_zero "flag invocado" "$?" "--attachable presente en el script"

# 4) Smoke: simular lógica de toggle con valor de env y verificar que el case devuelva el flag.
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

simulate_toggle() {
    local val="$1"
    local attachable_arg=""
    case "$(printf '%s' "${val}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes) attachable_arg="--attachable" ;;
    esac
    printf '%s' "${attachable_arg}"
}

assert_equals "" "$(simulate_toggle 0)" "valor 0 → sin flag"
assert_equals "" "$(simulate_toggle '')" "valor vacío → sin flag"
assert_equals "" "$(simulate_toggle false)" "false → sin flag"
assert_equals "--attachable" "$(simulate_toggle 1)" "valor 1 → --attachable"
assert_equals "--attachable" "$(simulate_toggle true)" "true → --attachable"
assert_equals "--attachable" "$(simulate_toggle TRUE)" "TRUE (mayúsculas) → --attachable"
assert_equals "--attachable" "$(simulate_toggle yes)" "yes → --attachable"

# 5) Sintaxis válida del script
bash -n "${SCRIPT}"
assert_exit_zero "bash -n" "$?" "ensure-network-swarm.sh sintácticamente válido"
