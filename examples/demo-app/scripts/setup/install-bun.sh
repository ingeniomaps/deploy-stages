#!/bin/bash
# Instala Bun (última versión estable) solo si no está instalado.
# Uso: ejecutar una vez; requiere curl y unzip. No modifica instalaciones existentes.

set -e

BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"

bun_installed() {
    command -v bun &> /dev/null || [ -x "${BUN_INSTALL}/bin/bun" ]
}

install_bun() {
    echo "Instalando Bun (última versión estable)..."
    curl -fsSL https://bun.sh/install | bash
    [ -s "${BUN_INSTALL}/bin/bun" ] && export PATH="${BUN_INSTALL}/bin:$PATH"
}

load_bun() {
    if [ -x "${BUN_INSTALL}/bin/bun" ]; then
        export BUN_INSTALL
        export PATH="${BUN_INSTALL}/bin:$PATH"
    fi
}

if ! bun_installed; then
    install_bun
    load_bun
else
    echo "Bun: $(bun -v 2>/dev/null || echo 'ejecuta: source ~/.bashrc')"
    load_bun
fi
