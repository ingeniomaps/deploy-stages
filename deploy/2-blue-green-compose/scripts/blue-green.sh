#!/usr/bin/env bash
# Blue-Green Deployment Script
# Switches traffic between blue and green deployments.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly PROJECT_ROOT
readonly DOCKER_DIR="${SCRIPT_DIR}/../docker"
readonly ENV_FILE="${PROJECT_ROOT}/.env"

# shellcheck source=../../scripts/lib/parse-env.sh
source "${PROJECT_ROOT}/deploy/scripts/lib/parse-env.sh"
readonly COMPOSE_BLUE="${DOCKER_DIR}/docker-compose.blue.yml"
readonly COMPOSE_GREEN="${DOCKER_DIR}/docker-compose.green.yml"
readonly COMPOSE_OVERRIDE="${DOCKER_DIR}/docker-compose.override.yml"
readonly COMPOSE_ENV_INCLUDE_BLUE="${DOCKER_DIR}/docker-compose.env-include-blue.yml"
readonly COMPOSE_ENV_INCLUDE_GREEN="${DOCKER_DIR}/docker-compose.env-include-green.yml"
readonly COMPOSE_EXTRA_NETS="${DOCKER_DIR}/docker-compose.extra-networks.yml"
readonly COMPOSE_EXTRA_HOSTS_BLUE="${DOCKER_DIR}/docker-compose.extra-hosts-blue.yml"
readonly COMPOSE_EXTRA_HOSTS_GREEN="${DOCKER_DIR}/docker-compose.extra-hosts-green.yml"

# Resuelto tras load_env_safe
NGINX_CONTAINER=""

readonly CLR_RED='\033[0;31m'
readonly CLR_GREEN='\033[0;32m'
readonly CLR_YELLOW='\033[1;33m'
readonly CLR_BLUE='\033[0;34m'
readonly NC='\033[0m'

# Carga .env de forma segura (solo VAR=value; no ejecuta el archivo como script).
# Valida nombres de variable, resuelve NETWORK y exporta COMPOSE_PROJECT_NAME/NGINX_CONTAINER.
load_env_safe() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        export NETWORK="$("${SCRIPT_DIR}/resolve-network.sh")"
        return 0
    fi
    load_env_export "${ENV_FILE}"
    export NETWORK="$("${SCRIPT_DIR}/resolve-network.sh")"
    export COMPOSE_PROJECT_NAME="${PROJECT_PREFIX:+${PROJECT_PREFIX}-}${PROJECT_NAME:-docker}"
    export NGINX_CONTAINER="${COMPOSE_PROJECT_NAME}-nginx-blue-green"
}

print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

# Genera archivos overlay dinámicos: env_file, redes extras (nginx), hosts extras (app).
generate_env_file_include() {
    "${SCRIPT_DIR}/generate-env-file-include.sh"
    "${SCRIPT_DIR}/generate-extra-networks.sh"
    "${SCRIPT_DIR}/generate-extra-hosts.sh"
}

# Rellena COMPOSE_F_ARGS para docker compose. Modo: blue | green | both.
build_compose_f_args() {
    local mode="${1:?}"
    generate_env_file_include
    COMPOSE_F_ARGS=()
    case "${mode}" in
        blue)  COMPOSE_F_ARGS=(-f "${COMPOSE_BLUE}")
               if [[ -f "${COMPOSE_ENV_INCLUDE_BLUE}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_ENV_INCLUDE_BLUE}"); fi
               if [[ -f "${COMPOSE_EXTRA_HOSTS_BLUE}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_EXTRA_HOSTS_BLUE}"); fi
               if [[ -f "${COMPOSE_EXTRA_NETS}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_EXTRA_NETS}"); fi
               if [[ -f "${COMPOSE_OVERRIDE}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_OVERRIDE}"); fi ;;
        green) COMPOSE_F_ARGS=(-f "${COMPOSE_GREEN}")
               if [[ -f "${COMPOSE_ENV_INCLUDE_GREEN}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_ENV_INCLUDE_GREEN}"); fi
               if [[ -f "${COMPOSE_EXTRA_HOSTS_GREEN}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_EXTRA_HOSTS_GREEN}"); fi ;;
        both)  COMPOSE_F_ARGS=(-f "${COMPOSE_BLUE}" -f "${COMPOSE_GREEN}")
               if [[ -f "${COMPOSE_ENV_INCLUDE_BLUE}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_ENV_INCLUDE_BLUE}"); fi
               if [[ -f "${COMPOSE_ENV_INCLUDE_GREEN}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_ENV_INCLUDE_GREEN}"); fi
               if [[ -f "${COMPOSE_EXTRA_HOSTS_BLUE}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_EXTRA_HOSTS_BLUE}"); fi
               if [[ -f "${COMPOSE_EXTRA_HOSTS_GREEN}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_EXTRA_HOSTS_GREEN}"); fi
               if [[ -f "${COMPOSE_EXTRA_NETS}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_EXTRA_NETS}"); fi
               if [[ -f "${COMPOSE_OVERRIDE}" ]]; then COMPOSE_F_ARGS+=(-f "${COMPOSE_OVERRIDE}"); fi ;;
        *)     echo "build_compose_f_args: mode must be blue|green|both" >&2; exit 1 ;;
    esac
}

# Ejecuta docker compose con los -f apropiados. Modo: blue | green | both.
run_compose() {
    local mode="${1:?}"
    shift
    build_compose_f_args "${mode}"
    docker compose "${COMPOSE_F_ARGS[@]}" --env-file "${ENV_FILE}" "$@"
}

run_compose_blue()  { run_compose blue "$@"; }
run_compose_green() { run_compose green "$@"; }
run_compose_both()  { run_compose both "$@"; }

# Lee un valor del .env (usa parser seguro sin grep/regex).
_get_env() {
    get_env_value "${ENV_FILE}" "$@"
}

get_project_port()  { _get_env "PROJECT_PORT" "3000"; }
get_health_path()   { _get_env "HEALTH_PATH" "/health"; }

# Extrae snippet.conf de la imagen del proyecto a deploy/2-blue-green-compose/projects/${PROJECT_NAME}/.
# PROJECT_NGINX_DIR = ruta dentro de la imagen (ej. /app/nginx/snippet.conf). Si no existe, no extrae y deja archivo vacío.
# Se llama en cada deploy y switch para dejar siempre el snippet actualizado desde la imagen.
extract_snippet_from_image() {
    local snippet_dir snippet_file
    snippet_dir="${SCRIPT_DIR}/../projects/${PROJECT_NAME:-my-app}"
    snippet_file="${snippet_dir}/snippet.conf"
    mkdir -p "${snippet_dir}"

    if [ -z "${PROJECT_IMAGE:-}" ]; then
        echo '# no snippet (PROJECT_IMAGE not set)' > "${snippet_file}"
        return 0
    fi

    if [ -z "${PROJECT_NGINX_DIR:-}" ]; then
        echo '# no snippet (PROJECT_NGINX_DIR not set)' > "${snippet_file}"
        return 0
    fi

    local img="${PROJECT_IMAGE:-}:${PROJECT_VERSION:-latest}"
    local temp_id
    temp_id=$(docker create "${img}" 2> /dev/null) || true
    if [ -z "${temp_id}" ]; then
        echo '# no snippet (image not found)' > "${snippet_file}"
        return 0
    fi
    if ! docker cp "${temp_id}:${PROJECT_NGINX_DIR}" "${snippet_file}" 2> /dev/null; then
        echo '# no snippet (file not in image)' > "${snippet_file}"
    fi
    docker rm "${temp_id}" > /dev/null 2>&1 || true
    return 0
}

# Primer contenedor en ejecución del stack (blue o green).
# Usage: get_first_container blue|green
get_first_container() {
    local service="${1}"
    local pattern="app-${service}|app_${service}"
    docker ps --format '{{.Names}}' | grep -E "${pattern}" | head -1
}

# Function to check if container is healthy
check_health() {
    local container_name="${1}"
    local max_attempts=30
    local attempt=0
    local port health_path health_url state container_ip external_url
    local inspect_format_ip='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

    print_message "${CLR_YELLOW}" "Checking health of ${container_name}..."

    port=$(get_project_port)
    health_path=$(get_health_path)
    health_url="http://127.0.0.1:${port}${health_path}"

    while [ "${attempt}" -lt "${max_attempts}" ]; do
        if docker inspect "${container_name}" > /dev/null 2>&1; then
            state=$(docker inspect --format='{{.State.Status}}' "${container_name}" 2>/dev/null)
            if [ "${state}" = "running" ]; then
                container_ip=$(docker inspect --format="${inspect_format_ip}" "${container_name}" 2>/dev/null | head -1)
                if [ -n "${container_ip}" ]; then
                    if docker exec "${container_name}" wget --quiet --tries=1 --spider \
                        "${health_url}" 2>/dev/null; then
                        print_message "${CLR_GREEN}" "✓ ${container_name} is healthy"
                        return 0
                    fi
                    external_url="http://${container_ip}:${port}${health_path}"
                    if curl -f -s --max-time 2 "${external_url}" > /dev/null 2>&1; then
                        print_message "${CLR_GREEN}" "✓ ${container_name} is healthy"
                        return 0
                    fi
                fi
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    print_message "${CLR_RED}" "✗ ${container_name} is not healthy after ${max_attempts} attempts"
    return 1
}

# Function to get running instances count for a service
# Los contenedores se llaman {project}_app-{color}_N o tienen hostname {project}-{color} (1 instancia)
get_instance_count() {
    local service_name="${1}"  # "blue" or "green"
    local compose_service="app-${service_name}"
    local count
    count=$(docker ps --format '{{.Names}}' | grep -c -E "${compose_service}|${PROJECT_NAME:-my-app}-${service_name}" 2> /dev/null) || count=0
    echo "${count:-0}"
}

# Function to generate nginx upstream with multiple instances
# Con 1 instancia: hostname en compose es ${PROJECT_NAME}-blue/-green. Con más: Compose nombra contenedores {project}-app-{color}-{i}.
generate_upstream() {
    local target="${1}"  # "blue" or "green"
    local instances="${2:-1}"
    local project_port="${PROJECT_PORT:-3000}"
    local pname="${PROJECT_NAME:-my-app}"
    local compose_pname="${COMPOSE_PROJECT_NAME:-${pname}}"
    local i

    if [ "${instances}" -eq 1 ]; then
        echo "        server ${pname}-${target}:${project_port} max_fails=3 fail_timeout=30s;"
    else
        for i in $(seq 1 "${instances}"); do
            echo "        server ${compose_pname}-app-${target}-${i}:${project_port} max_fails=3 fail_timeout=30s;"
        done
    fi
}

# Function to switch nginx configuration
switch_nginx() {
    local target="${1}"  # "blue" or "green"
    local instances="${2:-1}"  # Number of instances (default: 1)

    if [ "${target}" != "blue" ] && [ "${target}" != "green" ]; then
        print_message "${CLR_RED}" "Error: target must be 'blue' or 'green'"
        return 1
    fi

    print_message "${CLR_YELLOW}" "Switching nginx to ${target} (${instances} instance(s))..."

    load_env_safe

    local nginx_container="${NGINX_CONTAINER:-${PROJECT_PREFIX:-${PROJECT_NAME:-my-app}}-nginx-blue-green}"

    # Upstream del stack al que vamos: 'instances'. Del otro: número real en ejecución (evita host not found).
    local blue_count green_count blue_upstream green_upstream active_upstream
    blue_count=$([ "${target}" = "blue" ] && echo "${instances}" || get_instance_count "blue")
    green_count=$([ "${target}" = "green" ] && echo "${instances}" || get_instance_count "green")
    active_upstream=$(generate_upstream "${target}" "${instances}")
    if [ "${blue_count:-0}" -eq 0 ]; then
        blue_upstream="${active_upstream}"
    else
        blue_upstream=$(generate_upstream "blue" "${blue_count}")
    fi
    if [ "${green_count:-0}" -eq 0 ]; then
        green_upstream="${active_upstream}"
    else
        green_upstream=$(generate_upstream "green" "${green_count}")
    fi

    # Create new nginx config with active backend (global so trap can access it on RETURN)
    _nginx_temp_conf=$(mktemp)
    trap 'rm -f "${_nginx_temp_conf:-}"' RETURN
    cat > "${_nginx_temp_conf}" << EOF
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    server_tokens off;

    upstream app_blue {
${blue_upstream}
    }

    upstream app_green {
${green_upstream}
    }

    upstream app_active {
${active_upstream}
    }

    server {
        listen 80;
        server_name _;

        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;

        location /health {
            access_log off;
            proxy_pass http://app_active;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location / {
            proxy_pass http://app_active;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header X-Forwarded-Port \$server_port;

            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;

            proxy_buffering on;
            proxy_buffer_size 4k;
            proxy_buffers 8 4k;
        }

        # Snippet por proyecto (montado desde PROJECT_NGINX_DIR/snippet.conf). Si no existe, el entrypoint crea archivo vacío.
        include /etc/nginx/conf.d/project-snippet.conf;
    }
}
EOF

    # Copy to container and reload nginx
    docker cp "${_nginx_temp_conf}" "${nginx_container}:/etc/nginx/nginx.conf"
    docker exec "${nginx_container}" nginx -t
    docker exec "${nginx_container}" nginx -s reload

    print_message "${CLR_GREEN}" "✓ Nginx switched to ${target} (${instances} instance(s))"
}

# Function to deploy new version (blue-green: only rebuild inactive stack, then switch traffic)
# First deploy: start both blue and green. Subsequent: rebuild only the inactive stack and switch to it.
deploy_green() {
    local green_instances=${1:-1}
    local blue_instances=${2:-1}
    local active green_containers blue_containers

    load_env_safe
    extract_snippet_from_image

    cd "${DOCKER_DIR}"

    active=$(get_active_stack)

    if [ -z "${active}" ]; then
        print_message "${CLR_BLUE}" "First deploy: starting both blue and green stacks..."
        print_message "${CLR_YELLOW}" "Starting green stack (${green_instances} instance(s))..."
        run_compose_green up -d --scale app-green="${green_instances}"
        print_message "${CLR_YELLOW}" "Starting blue stack (${blue_instances} instance(s))..."
        run_compose_blue up -d --scale app-blue="${blue_instances}"
        green_containers=$(get_first_container "green")
        if [ -n "${green_containers}" ]; then
            if check_health "${green_containers}"; then
                print_message "${CLR_GREEN}" \
                    "✓ First deploy ready. Blue has traffic (default). " \
                    "Use 'make switch' to switch to green."
                return 0
            fi
        fi
        print_message "${CLR_RED}" "✗ Green deployment failed health check"
        return 1
    fi

    if [ "${active}" = "blue" ]; then
        print_message "${CLR_BLUE}" \
            "Deploying new version to green (inactive). Blue keeps traffic until switch..."
        print_message "${CLR_YELLOW}" "Starting green stack (${green_instances} instance(s))..."
        run_compose_green up -d --scale app-green="${green_instances}"
        green_containers=$(get_first_container "green")
        if [ -z "${green_containers}" ]; then
            print_message "${CLR_RED}" "✗ Green stack failed to start"
            return 1
        fi
        if ! check_health "${green_containers}"; then
            print_message "${CLR_RED}" "✗ Green deployment failed health check"
            return 1
        fi
        print_message "${CLR_GREEN}" "✓ Green is healthy. Switching traffic to green..."
        switch_nginx "green" "${green_instances}"
        print_message "${CLR_GREEN}" "✓ Deploy complete. Traffic is now on green (${green_instances})."
    else
        print_message "${CLR_BLUE}" \
            "Deploying new version to blue (inactive). Green keeps traffic until switch..."
        print_message "${CLR_YELLOW}" "Starting blue stack (${blue_instances} instance(s))..."
        run_compose_blue up -d --scale app-blue="${blue_instances}"
        blue_containers=$(get_first_container "blue")
        if [ -z "${blue_containers}" ]; then
            print_message "${CLR_RED}" "✗ Blue stack failed to start"
            return 1
        fi
        if ! check_health "${blue_containers}"; then
            print_message "${CLR_RED}" "✗ Blue deployment failed health check"
            return 1
        fi
        print_message "${CLR_GREEN}" "✓ Blue is healthy. Switching traffic to blue..."
        switch_nginx "blue" "${blue_instances}"
        print_message "${CLR_GREEN}" "✓ Deploy complete. Traffic is now on blue (${blue_instances})."
    fi
    return 0
}

# Function to switch to green
switch_to_green() {
    local green_instances="${1:-}"

    load_env_safe
    extract_snippet_from_image
    if [ -z "${green_instances}" ]; then
        green_instances=$(get_instance_count "green")
        [ "${green_instances:-0}" -eq 0 ] && green_instances=1
    fi
    print_message "${CLR_BLUE}" "Switching traffic to green (${green_instances} instance(s))..."

    cd "${DOCKER_DIR}"
    local blue_keep
    blue_keep=$(get_instance_count "blue")
    if [ -n "${SCALE_DOWN:-}" ]; then
        blue_keep=1
        print_message "${CLR_YELLOW}" "SCALE_DOWN=1: stack blue se escalará a 1 instancia."
    fi
    if [ -n "${RECREATE:-}" ]; then
        print_message "${CLR_YELLOW}" "RECREATE=1: recreating green stack with current image and .env..."
        run_compose_green up -d --force-recreate --scale app-green="${green_instances}"
    else
        run_compose_both up -d --scale app-green="${green_instances}" --scale app-blue="${blue_keep}" --no-recreate
    fi

    local green_containers
    green_containers=$(get_first_container "green")
    if [ -z "${green_containers}" ]; then
        print_message "${CLR_RED}" "Cannot switch to green: no green containers running"
        return 1
    fi
    if ! check_health "${green_containers}"; then
        print_message "${CLR_RED}" "Cannot switch to green: service is not healthy"
        return 1
    fi

    switch_nginx "green" "${green_instances}"
    print_message "${CLR_GREEN}" "✓ Traffic switched to green (${green_instances} instance(s))"
    print_message "${CLR_YELLOW}" \
        "Monitor the application. If issues occur, run: make switch-bluegreen STACK=blue"
}

# Function to switch to blue
switch_to_blue() {
    local blue_instances="${1:-}"

    load_env_safe
    extract_snippet_from_image
    if [ -z "${blue_instances}" ]; then
        blue_instances=$(get_instance_count "blue")
        [ "${blue_instances:-0}" -eq 0 ] && blue_instances=1
    fi
    print_message "${CLR_BLUE}" "Switching traffic to blue (${blue_instances} instance(s))..."

    cd "${DOCKER_DIR}"
    local green_keep
    green_keep=$(get_instance_count "green")
    if [ -n "${SCALE_DOWN:-}" ]; then
        green_keep=1
        print_message "${CLR_YELLOW}" "SCALE_DOWN=1: stack green se escalará a 1 instancia."
    fi
    if [ -n "${RECREATE:-}" ]; then
        print_message "${CLR_YELLOW}" "RECREATE=1: recreating blue stack with current image and .env..."
        run_compose_blue up -d --force-recreate --scale app-blue="${blue_instances}"
    else
        run_compose_both up -d --scale app-blue="${blue_instances}" --scale app-green="${green_keep}" --no-recreate
    fi

    local blue_containers
    blue_containers=$(get_first_container "blue")
    if [ -z "${blue_containers}" ]; then
        print_message "${CLR_RED}" "Cannot switch to blue: no blue containers running"
        return 1
    fi
    if ! check_health "${blue_containers}"; then
        print_message "${CLR_RED}" "Cannot switch to blue: service is not healthy"
        return 1
    fi

    switch_nginx "blue" "${blue_instances}"
    print_message "${CLR_GREEN}" "✓ Traffic switched to blue (${blue_instances} instance(s))"
}

# Get currently active stack from nginx config (blue or green)
get_active_stack() {
    local nginx_container
    nginx_container=$(docker ps --format '{{.Names}}' | grep -Fx "${NGINX_CONTAINER}" | head -1)
    if [ -z "${nginx_container}" ]; then
        echo ""
        return
    fi
    local active_block
    active_block=$(
        docker exec "${nginx_container}" cat /etc/nginx/nginx.conf 2>/dev/null \
        | grep -A2 "upstream app_active" || true
    )
    if echo "${active_block}" | grep -qE "\-blue|app-blue"; then
        echo "blue"
    elif echo "${active_block}" | grep -qE "\-green|app-green"; then
        echo "green"
    else
        echo ""
    fi
}

# Switch traffic to the inactive stack (if blue is active, switch to green, and vice versa)
# Usage: switch_to_other [instances]  (instances vacío = mantener la cantidad actual del stack destino)
switch_to_other() {
    local instances="${1:-}"

    load_env_safe

    local active
    active=$(get_active_stack)
    if [ -z "${active}" ]; then
        print_message "${CLR_RED}" \
            "Could not determine active stack (nginx not running or config unreadable). " \
            "Use switch:green or switch:blue explicitly."
        return 1
    fi

    local target
    if [ "${active}" = "blue" ]; then
        target="green"
    else
        target="blue"
    fi
    if [ -z "${instances}" ]; then
        instances=$(get_instance_count "${target}")
        [ "${instances:-0}" -eq 0 ] && instances=1
        print_message "${CLR_YELLOW}" "Keeping current scale: ${target} has ${instances} instance(s)."
    fi

    if [ "${active}" = "blue" ]; then
        print_message "${CLR_YELLOW}" "Active stack is blue. Switching traffic to green (${instances} instance(s))..."
        switch_to_green "${instances}"
    else
        print_message "${CLR_YELLOW}" "Active stack is green. Switching traffic to blue (${instances} instance(s))..."
        switch_to_blue "${instances}"
    fi
}

# Function to show current status
show_status() {
    load_env_safe

    print_message "${CLR_BLUE}" "Blue-Green Deployment Status:"
    echo ""

    local blue_count green_count blue_containers green_containers
    blue_count=$(get_instance_count "blue")
    if [ "${blue_count}" -gt 0 ]; then
        blue_containers=$(get_first_container "blue")
        if [ -n "${blue_containers}" ]; then
            local blue_status
            blue_status=$(docker ps --format '{{.Status}}' --filter "name=${blue_containers}" | head -1)
            print_message "${CLR_BLUE}" "Blue: ${blue_count} instance(s) - ${blue_status}"
        else
            print_message "${CLR_BLUE}" "Blue: ${blue_count} instance(s) running"
        fi
    else
        print_message "${CLR_RED}" "Blue: Not running (0 instances)"
    fi

    green_count=$(get_instance_count "green")
    if [ "${green_count}" -gt 0 ]; then
        green_containers=$(get_first_container "green")
        if [ -n "${green_containers}" ]; then
            local green_status
            green_status=$(docker ps --format '{{.Status}}' --filter "name=${green_containers}" | head -1)
            print_message "${CLR_GREEN}" "Green: ${green_count} instance(s) - ${green_status}"
        else
            print_message "${CLR_GREEN}" "Green: ${green_count} instance(s) running"
        fi
    else
        print_message "${CLR_RED}" "Green: Not running (0 instances)"
    fi

    local nginx_container
    nginx_container=$(docker ps --format '{{.Names}}' | grep -Fx "${NGINX_CONTAINER}" | head -1)
    if [ -n "${nginx_container}" ]; then
        local nginx_status active
        nginx_status=$(docker ps --format '{{.Status}}' --filter "name=${nginx_container}")
        print_message "${CLR_YELLOW}" "Nginx: Running - ${nginx_status}"
        active=$(get_active_stack)
        if [ "${active}" = "blue" ]; then
            print_message "${CLR_BLUE}" "Active: Blue (traffic is routed to blue stack)"
        elif [ "${active}" = "green" ]; then
            print_message "${CLR_GREEN}" "Active: Green (traffic is routed to green stack)"
        else
            print_message "${CLR_YELLOW}" "Active: unknown (could not read nginx config)"
        fi
    else
        print_message "${CLR_RED}" "Nginx: Not running"
    fi
}

# Bring down one stack (blue or green). If that stack is active, switch traffic to the other first.
# Only stops/removes the app service for that color; nginx is left running.
# Usage: down_stack blue|green
down_stack() {
    local stack="${1:-}"
    if [ "${stack}" != "blue" ] && [ "${stack}" != "green" ]; then
        print_message "${CLR_RED}" "Error: down requires blue or green (e.g. down blue)"
        return 1
    fi

    load_env_safe
    cd "${DOCKER_DIR}"

    local active
    active=$(get_active_stack)
    if [ -n "${active}" ] && [ "${active}" = "${stack}" ]; then
        local other_instances
        if [ "${stack}" = "blue" ]; then
            other_instances=$(get_instance_count "green")
            if [ "${other_instances:-0}" -gt 0 ]; then
                print_message "${CLR_YELLOW}" "Stack ${stack} is active. Redirecting traffic to green (${other_instances} instance(s))..."
                switch_nginx "green" "${other_instances}"
            fi
        else
            other_instances=$(get_instance_count "blue")
            if [ "${other_instances:-0}" -gt 0 ]; then
                print_message "${CLR_YELLOW}" "Stack ${stack} is active. Redirecting traffic to blue (${other_instances} instance(s))..."
                switch_nginx "blue" "${other_instances}"
            fi
        fi
    fi

    print_message "${CLR_YELLOW}" "Stopping and removing ${stack} stack (app-${stack})..."
    if [ "${stack}" = "blue" ]; then
        run_compose_blue stop app-blue
        run_compose_blue rm -f app-blue 2>/dev/null || true
    else
        run_compose_green stop app-green
        run_compose_green rm -f app-green 2>/dev/null || true
    fi

    # Actualizar nginx para que no referencie al stack detenido (evita fallo en restart).
    local remaining
    remaining=$(get_active_stack)
    if [ -n "${remaining}" ]; then
        local remaining_count
        remaining_count=$(get_instance_count "${remaining}")
        [ "${remaining_count:-0}" -eq 0 ] && remaining_count=1
        switch_nginx "${remaining}" "${remaining_count}"
    fi

    print_message "${CLR_GREEN}" "✓ Stack ${stack} stopped."
}

# Baja todo: blue + green + nginx.
down_all() {
    load_env_safe
    cd "${DOCKER_DIR}"
    print_message "${CLR_YELLOW}" "Stopping all stacks (blue + green + nginx)..."
    run_compose_both down --remove-orphans
    print_message "${CLR_GREEN}" "✓ All stacks stopped."
}

# Main script logic
case "${1:-}" in
    deploy)
        deploy_green "${2:-1}" "${3:-1}"  # green_instances, blue_instances
        ;;
    switch)
        switch_to_other "${2:-}"  # instances; vacío = mantener cantidad actual del stack destino
        ;;
    switch:green | switch-to-green)
        switch_to_green "${2:-}"  # green_instances; vacío = cantidad actual de green
        ;;
    switch:blue | switch-to-blue)
        switch_to_blue "${2:-}"  # blue_instances; vacío = cantidad actual de blue
        ;;
    status)
        show_status
        ;;
    down)
        if [ -n "${2:-}" ]; then
            down_stack "${2}"
        else
            down_all
        fi
        ;;
    *)
        echo "Usage: ${0} deploy|switch|switch:green|switch:blue|status|down [instances|blue|green]"
        echo ""
        echo "Commands:"
        echo "  deploy [green_instances] [blue_instances]"
        echo "    - Deploy new version to green stack"
        echo "    - Default: 1 green, 1 blue"
        echo ""
        echo "  switch [instances]"
        echo "    - Switch traffic to the inactive stack (blue<->green)"
        echo "    - Detects which is active and switches to the other"
        echo "    - Default: 1 instance"
        echo ""
        echo "  switch:green [instances]"
        echo "    - Switch traffic to green (new version)"
        echo "    - Default: 1 instance"
        echo ""
        echo "  switch:blue [instances]"
        echo "    - Switch traffic to blue (rollback)"
        echo "    - Default: 1 instance"
        echo ""
        echo "  status"
        echo "    - Show current deployment status"
        echo ""
        echo "  down"
        echo "    - Stop and remove all stacks (blue + green + nginx)."
        echo ""
        echo "  down blue|green"
        echo "    - Stop and remove only that stack (app-blue or app-green)."
        echo "    - If that stack is active, traffic is switched to the other first."
        exit 1
        ;;
esac
