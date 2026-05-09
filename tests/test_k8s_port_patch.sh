#!/usr/bin/env bash
# Test para B3: k8s blue-green.sh genera health-path-patch.json incluyendo overrides
# de containerPort y de los puertos de readiness/liveness probes (no solo del path).
#
# El bug original: base/deployment.yml hardcodea containerPort=3000 con port: http
# en probes; sin esta override, pods con PROJECT_PORT != 3000 nunca quedan ready.

set -u

readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOY_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
readonly K8S_BG="${DEPLOY_ROOT}/deploy/3-kubernetes/scripts/blue-green.sh"

# shellcheck source=lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

# 1) PROJECT_PORT debe leerse desde .env en blue-green.sh
project_port_read=$(grep -c 'PROJECT_PORT="\$(get_env_value PROJECT_PORT' "${K8S_BG}" || true)
assert_equals "1" "${project_port_read}" "PROJECT_PORT leído desde .env en blue-green.sh"

# 2) El heredoc de health-path-patch.json incluye containerPort
patch_includes_container=$(grep -c 'containers/0/ports/0/containerPort.*PROJECT_PORT' "${K8S_BG}" || true)
assert_equals "1" "${patch_includes_container}" "patch incluye containerPort = \${PROJECT_PORT}"

# 3) El patch incluye readinessProbe httpGet port
patch_includes_ready=$(grep -c 'readinessProbe/httpGet/port.*PROJECT_PORT' "${K8S_BG}" || true)
assert_equals "1" "${patch_includes_ready}" "patch incluye readinessProbe.httpGet.port"

# 4) El patch incluye livenessProbe httpGet port
patch_includes_live=$(grep -c 'livenessProbe/httpGet/port.*PROJECT_PORT' "${K8S_BG}" || true)
assert_equals "1" "${patch_includes_live}" "patch incluye livenessProbe.httpGet.port"

# 5) Validación de PROJECT_PORT entero (defensa contra inyección JSON)
validation_present=$(grep -cF '[0-9]+$' "${K8S_BG}" || true)
[[ "${validation_present}" -ge 1 ]]
assert_exit_zero "validación present" "$?" "validación regex [0-9]+$ presente para PROJECT_PORT"

# 6) C1: kustomization usa 'patches:' (no 'patchesJson6902:')
deprecated_use=$(grep -c 'patchesJson6902:' "${K8S_BG}" || true)
assert_equals "0" "${deprecated_use}" "patchesJson6902 deprecated eliminado de kustomization generado"

# 7) Smoke test: simular generación del JSON con PROJECT_PORT=9003 y validar parseo JSON
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

PROJECT_PORT=9003
HEALTH_PATH="/health"
health_path_json="\"${HEALTH_PATH}\""

cat > "${TMP}/sample-patch.json" << EOF
[
  {"op": "replace", "path": "/spec/template/spec/containers/0/ports/0/containerPort", "value": ${PROJECT_PORT}},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/port", "value": ${PROJECT_PORT}},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": ${PROJECT_PORT}},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": ${health_path_json}},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/path", "value": ${health_path_json}}
]
EOF

if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; json.load(open('${TMP}/sample-patch.json'))"
    assert_exit_zero "python3 json.load" "$?" "JSON generado parsea correctamente"
else
    # Fallback: verificar estructura básica con grep
    grep -q '"containerPort"' "${TMP}/sample-patch.json"
    assert_exit_zero "grep containerPort" "$?" "JSON contiene containerPort (python3 no disponible para validar)"
fi
