#!/bin/bash
# Instala NVM (última release estable) y Node.js (última LTS estable) solo si no están instalados.
# Uso: ejecutar en la VM una vez; requiere curl. No modifica instalaciones existentes.

set -e

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# --- NVM: instalar solo si no existe
nvm_installed() {
    [ -s "${NVM_DIR}/nvm.sh" ]
}

install_nvm() {
    echo "Instalando NVM (última release estable)..."
    local tag
    tag=$(
        curl -sL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
            | grep '"tag_name"' \
            | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
    )
    if [ -z "$tag" ]; then
        echo "Error: no se pudo obtener la última versión de NVM. Usando v0.40.4 como respaldo."
        tag="v0.40.4"
    fi
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${tag}/install.sh" | bash
    [ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"
    [ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"
}

# --- Node: instalar solo si no está en PATH (tras cargar NVM si existe)
node_installed() {
    command -v node &> /dev/null
}

install_node() {
    echo "Instalando Node.js (última LTS estable)..."
    nvm install --lts
    nvm use --lts
    nvm alias default 'lts/*'
}

# --- Cargar NVM en esta sesión si está instalado
load_nvm() {
    if [ -s "${NVM_DIR}/nvm.sh" ]; then
        \. "${NVM_DIR}/nvm.sh"
        [ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"
    fi
}

# --- Main
if ! nvm_installed; then
    install_nvm
else
    load_nvm
fi

if ! node_installed; then
    install_node
else
    echo "Node: $(node -v 2>/dev/null || echo 'ejecuta: source ~/.bashrc')"
fi