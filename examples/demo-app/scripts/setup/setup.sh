#!/bin/bash
# Configuración del proyecto: NVM/Node (si aplica) e instalación de dependencias con Bun.
# Ejecutar desde la raíz del repo o desde app/.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_NVM="${SCRIPT_DIR}/install-nvm-node.sh"
INSTALL_BUN="${SCRIPT_DIR}/install-bun.sh"

echo "Configurando proyecto (${APP_ROOT})..."

if [ -f "${INSTALL_BUN}" ]; then
    bash "${INSTALL_BUN}"
    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    export PATH="${BUN_INSTALL}/bin:$PATH"
fi

echo ""
# echo "--- Dependencias con Bun ---"
cd "${APP_ROOT}"
if command -v bun &> /dev/null; then
    bun install
fi

echo ""
echo "Configuración completada."
