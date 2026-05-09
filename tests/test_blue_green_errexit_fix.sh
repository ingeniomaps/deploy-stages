#!/usr/bin/env bash
# Test para B2: blue-green.sh ya no aborta silenciosamente cuando DOCKER_COMPOSE_APP
# está set y compose.bluegreen-{color}.{ext} no existe.
#
# El bug era: `[[ -f "${c}" ]] && COMPOSE_F_ARGS+=(...)` con `set -e` causa exit 1
# cuando el archivo no existe (false retorna 1). El fix usa `if`/`fi` proper.

set -u

readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOY_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
readonly BG_SCRIPT="${DEPLOY_ROOT}/deploy/2-blue-green-compose/scripts/blue-green.sh"

# shellcheck source=lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

# Verifica que el patrón problemático NO esté en el script.
pattern_count=$(grep -cE '\[\[ -f "\$\{c\}" \]\] && COMPOSE_F_ARGS' "${BG_SCRIPT}" || true)
assert_equals "0" "${pattern_count}" "patrón [[ -f X ]] && Y eliminado de blue-green.sh"

# Verifica que el reemplazo (if/fi) está presente.
fix_present=$(grep -c 'if \[\[ -n "\${c}" \]\] && \[\[ -f "\${c}" \]\]; then' "${BG_SCRIPT}" || true)
assert_equals "1" "${fix_present}" "reemplazo if/fi presente"

# Smoke test estructural: extraer la función build_compose_f_args y verificar que
# sintácticamente es válida bash (parse-only via -n).
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Extraer cuerpo de la función (entre 'build_compose_f_args() {' y la primera '^}')
awk '
    /^build_compose_f_args\(\) \{/ { in_func=1 }
    in_func { print }
    in_func && /^\}/ { exit }
' "${BG_SCRIPT}" > "${TMP}/func.sh"

# La función referencia helpers; agregamos stubs mínimos para que parsee.
cat > "${TMP}/runner.sh" <<'EOF'
COMPOSE_BLUE=""
COMPOSE_GREEN=""
COMPOSE_OVERRIDE=""
COMPOSE_ENV_INCLUDE_BLUE=""
COMPOSE_ENV_INCLUDE_GREEN=""
ENV_FILE="/tmp/dummy.env"
generate_env_file_include() { :; }
EOF
cat "${TMP}/func.sh" >> "${TMP}/runner.sh"

# Verificar parse syntactico (no ejecuta).
bash -n "${TMP}/runner.sh"
assert_exit_zero "bash -n func extraída" "$?" "función build_compose_f_args sintácticamente válida"
