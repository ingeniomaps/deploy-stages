#!/usr/bin/env bash
# Librería compartida para parsear archivos .env de forma segura.
# Uso: source deploy/scripts/lib/parse-env.sh
#
# Funciones disponibles:
#   parse_env_file <archivo> <callback>   — llama callback(key, value) por cada línea KEY=VALUE
#   get_env_value  <archivo> <key> [default] — devuelve el valor de una clave (o default)
#   load_env_export <archivo>             — exporta todas las variables del archivo (valida nombres)
#   trim_string <string>                  — recorta espacios de un string

# Recorta espacios al inicio y final (sin xargs, portátil).
trim_string() {
    local v="${1:-}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "${v}"
}

# Limpia un valor de .env: quita comentarios inline, comillas y espacios.
_clean_env_value() {
    local v="${1:-}"
    # Quitar comentario inline (solo si # no está dentro de comillas)
    v="${v%%#*}"
    # Quitar comillas envolventes
    v="$(printf '%s' "${v}" | sed "s/^['\"]//;s/['\"]$//" | tr -d '\r\n')"
    trim_string "${v}"
}

# Parsea un archivo .env y ejecuta un callback por cada par key=value válido.
# $1 = ruta al archivo .env
# $2 = nombre de función callback que recibe (key, value)
# Ignora líneas vacías, comentarios y claves vacías.
# Valida que la clave sea un nombre de variable válido [A-Za-z_][A-Za-z0-9_]*.
parse_env_file() {
    local env_file="${1:?parse_env_file: se requiere ruta al archivo}"
    local callback="${2:?parse_env_file: se requiere función callback}"
    [[ ! -f "${env_file}" ]] && return 0

    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" != *'='* ]] && continue
        key="${line%%=*}"
        key="$(trim_string "${key}")"
        [[ -z "${key}" ]] && continue
        # Validar nombre de variable
        [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && continue
        value="${line#*=}"
        value="$(_clean_env_value "${value}")"
        "${callback}" "${key}" "${value}"
    done < "${env_file}"
}

# Lee el valor de una clave específica de un archivo .env.
# $1 = ruta al archivo, $2 = clave, $3 = valor por defecto (opcional)
get_env_value() {
    local env_file="${1:?}" target_key="${2:?}" default="${3:-}"
    [[ ! -f "${env_file}" ]] && echo "${default}" && return 0

    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" != *'='* ]] && continue
        key="${line%%=*}"
        key="$(trim_string "${key}")"
        [[ "${key}" != "${target_key}" ]] && continue
        value="${line#*=}"
        value="$(_clean_env_value "${value}")"
        echo "${value}"
        return 0
    done < "${env_file}"
    echo "${default}"
}

# Exporta todas las variables de un .env (valida nombres, excluye ENV_FILE).
# $1 = ruta al archivo .env
load_env_export() {
    local env_file="${1:?load_env_export: se requiere ruta al archivo}"
    [[ ! -f "${env_file}" ]] && return 0

    _load_env_export_cb() {
        local key="${1}" value="${2}"
        [[ "${key}" == "ENV_FILE" ]] && return 0
        export "${key}=${value}"
    }
    set -a
    parse_env_file "${env_file}" _load_env_export_cb
    set +a
}
