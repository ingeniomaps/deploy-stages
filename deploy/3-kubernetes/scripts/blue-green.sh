#!/usr/bin/env bash
# Blue-Green Deployment Script para Kubernetes (Kustomize + Kind)
# Interfaz compatible con 2-blue-green-compose/scripts/blue-green.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly K8S_DIR="${SCRIPT_DIR}/.."
readonly PROJECT_ROOT="$(cd "${K8S_DIR}/../.." && pwd)"
readonly ENV_FILE="${PROJECT_ROOT}/.env"

readonly RED='\033[0;31m'
readonly GREEN_C='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE_C='\033[0;34m'
readonly NC='\033[0m'

print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

# Lee un valor del .env (primera ocurrencia KEY=value). Default si no existe.
get_env_value() {
    local key="${1:?}"
    local default="${2:-}"
    if [[ -f "${ENV_FILE}" ]]; then
        local line
        line=$(grep "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1) || true
        if [[ -n "${line}" ]]; then
            echo "${line#*=}" | tr -d '\r\n' | sed "s/^['\"]//;s/['\"]$//"
            return
        fi
    fi
    echo "${default}"
}

# Variables del proyecto
PROJECT_NAME="$(get_env_value PROJECT_NAME "")"
if [[ -z "${PROJECT_NAME}" ]]; then
    print_message "${RED}" "Error: PROJECT_NAME no definido en .env"
    exit 1
fi
PROJECT_IMAGE="$(get_env_value PROJECT_IMAGE "${PROJECT_NAME}")"
PROJECT_VERSION="$(get_env_value PROJECT_VERSION latest)"
PROJECT_PREFIX="$(get_env_value PROJECT_PREFIX "")"
K8S_NODE_PORT="$(get_env_value K8S_NODE_PORT 30080)"
HEALTH_PATH="$(get_env_value HEALTH_PATH /health)"
# HPA: minimo/maximo de replicas y target CPU % (evita pasarse del limite = control de coste)
HPA_MIN_REPLICAS="$(get_env_value HPA_MIN_REPLICAS 1)"
HPA_MAX_REPLICAS="$(get_env_value HPA_MAX_REPLICAS 5)"
HPA_CPU_PERCENT="$(get_env_value HPA_CPU_PERCENT 80)"
# Carpeta de configuracion K8s especifica del proyecto (relativa a la raiz)
# Si K8S_IMAGE_PATH esta definido, en deploy y en switch RECREATE=1 se extrae de la imagen a projects/PROJECT_NAME
K8S_PROJECT_DIR="$(get_env_value K8S_PROJECT_DIR app/k8s)"
K8S_IMAGE_PATH="$(get_env_value K8S_IMAGE_PATH "")"

# Nombre base de Deployment / Service (PROJECT_PREFIX opcional, como en 2-blue-green-compose)
RESOURCE_PREFIX="${PROJECT_PREFIX:+${PROJECT_PREFIX}-}${PROJECT_NAME}"
DEPLOYMENT_BASE="${RESOURCE_PREFIX}-deployment"
SERVICE_NAME="${RESOURCE_PREFIX}-service"
NAMESPACE="${K8S_NAMESPACE:-default}"

# --- Funciones auxiliares ---

# Detecta el color activo leyendo el selector del Service
get_active_color() {
    kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo ""
}

# Extrae la carpeta k8s de la imagen a deploy/3-kubernetes/projects/PROJECT_NAME (como 2-blue-green-compose con snippet).
# Si K8S_IMAGE_PATH esta definido (ej. /app/k8s), no hace falta clonar el repo: se usa lo que trae la imagen.
# Tras extraer, K8S_PROJECT_DIR debe apuntar a deploy/3-kubernetes/projects/PROJECT_NAME (el llamador lo asigna).
extract_k8s_from_image() {
    [[ -n "${K8S_IMAGE_PATH:-}" ]] || return 0
    local dest="${K8S_DIR}/projects/${PROJECT_NAME:-my-app}"
    local img="${PROJECT_IMAGE:-}:${PROJECT_VERSION:-latest}"
    mkdir -p "${dest}"
    local temp_id
    temp_id=$(docker create "${img}" 2>/dev/null) || true
    if [[ -z "${temp_id}" ]]; then
        print_message "${YELLOW}" "Imagen ${img} no encontrada; se usara K8S_PROJECT_DIR existente si existe."
        return 0
    fi
    if docker cp "${temp_id}:${K8S_IMAGE_PATH}/." "${dest}/" 2>/dev/null; then
        print_message "${GREEN_C}" "k8s extraido de imagen a ${dest}"
    else
        print_message "${YELLOW}" "No hay ${K8S_IMAGE_PATH} en la imagen; se usara K8S_PROJECT_DIR existente si existe."
    fi
    docker rm "${temp_id}" >/dev/null 2>&1 || true
}

# Genera el kustomization.yaml y el patch de HEALTH_PATH en un overlay antes de aplicarlo.
# Kustomize solo permite archivos dentro del overlay; copiamos el patch del proyecto ahí.
generate_overlay_kustomization() {
    local color="${1:?}"
    local replicas="${2:-1}"
    local overlay_dir="${K8S_DIR}/overlays/${color}"
    local project_patch_abs="${PROJECT_ROOT}/${K8S_PROJECT_DIR}/deployment-patch.yml"
    local project_patch_inside="${overlay_dir}/project-deployment-patch.yml"
    local health_patch="${overlay_dir}/health-path-patch.json"
    # Escapar HEALTH_PATH para JSON (comillas y backslash)
    local health_path_json
    health_path_json="$(printf '%s' "${HEALTH_PATH}" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    health_path_json="\"${health_path_json}\""

    # JSON Patch (RFC 6902) para readiness/liveness path desde .env
    cat > "${health_patch}" << EOF
[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": ${health_path_json}},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/path", "value": ${health_path_json}}
]
EOF

    local deployment_name="${DEPLOYMENT_BASE}-${color}"

    # HPA por overlay (min/max replicas y target CPU desde .env)
    cat > "${overlay_dir}/hpa.yml" << EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${RESOURCE_PREFIX}-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${deployment_name}
  minReplicas: ${HPA_MIN_REPLICAS}
  maxReplicas: ${HPA_MAX_REPLICAS}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: ${HPA_CPU_PERCENT}
EOF

    if [[ -f "${project_patch_abs}" ]]; then
        cp -f "${project_patch_abs}" "${project_patch_inside}"
        cat > "${overlay_dir}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  - hpa.yml
nameSuffix: "-${color}"
patches:
  - path: deployment-patch.yml
    target:
      kind: Deployment
  - path: project-deployment-patch.yml
    target:
      kind: Deployment
patchesJson6902:
  - target:
      kind: Deployment
      name: ${deployment_name}
    path: health-path-patch.json
images:
  - name: mi-aplicacion
    newName: ${PROJECT_IMAGE}
    newTag: "${PROJECT_VERSION}"
replicas:
  - name: ${DEPLOYMENT_BASE}
    count: ${replicas}
EOF
    else
        rm -f "${project_patch_inside}"
        cat > "${overlay_dir}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  - hpa.yml
nameSuffix: "-${color}"
patches:
  - path: deployment-patch.yml
    target:
      kind: Deployment
patchesJson6902:
  - target:
      kind: Deployment
      name: ${deployment_name}
    path: health-path-patch.json
images:
  - name: mi-aplicacion
    newName: ${PROJECT_IMAGE}
    newTag: "${PROJECT_VERSION}"
replicas:
  - name: ${DEPLOYMENT_BASE}
    count: ${replicas}
EOF
    fi
}

# Aplica un overlay (genera kustomization.yaml + kubectl apply)
apply_overlay() {
    local color="${1:?}"
    local replicas="${2:-1}"

    generate_overlay_kustomization "${color}" "${replicas}"
    print_message "${YELLOW}" "Aplicando overlay ${color} (replicas=${replicas}, image=${PROJECT_IMAGE}:${PROJECT_VERSION})..."
    kubectl apply -k "${K8S_DIR}/overlays/${color}"
}

# Espera a que un Deployment termine el rollout
wait_for_rollout() {
    local deployment="${1:?}"
    print_message "${YELLOW}" "Esperando rollout de ${deployment}..."
    if kubectl rollout status deployment/"${deployment}" -n "${NAMESPACE}" --timeout=180s; then
        print_message "${GREEN_C}" "✓ ${deployment} listo."
    else
        print_message "${RED}" "✗ ${deployment} no alcanzo estado ready a tiempo."
        return 1
    fi
}

# Cambia el selector del Service a un color
switch_service() {
    local target="${1:?}"
    print_message "${YELLOW}" "Cambiando Service a version=${target}..."
    kubectl patch service "${SERVICE_NAME}" -n "${NAMESPACE}" \
        -p "{\"spec\":{\"selector\":{\"version\":\"${target}\"}}}"
    print_message "${GREEN_C}" "✓ Service apunta a ${target}."
}

# Ajusta nombres de Deployment/Service/ConfigMap, labels app y nodePort segun .env.
# Solo afecta a los manifests locales antes de aplicar (no al cluster existente).
patch_k8s_names() {
    local pname="${RESOURCE_PREFIX}"
    local files=(
        "${K8S_DIR}/base/deployment.yml"
        "${K8S_DIR}/service/service.yml"
        "${K8S_DIR}/service/configmap-blue.yml"
        "${K8S_DIR}/service/configmap-green.yml"
        "${K8S_DIR}/overlays/blue/deployment-patch.yml"
        "${K8S_DIR}/overlays/green/deployment-patch.yml"
    )

    # Incluir parches especificos del proyecto si existen
    local project_deploy_patch="${PROJECT_ROOT}/${K8S_PROJECT_DIR}/deployment-patch.yml"
    local project_service_patch="${PROJECT_ROOT}/${K8S_PROJECT_DIR}/service-patch.yml"
    if [[ -f "${project_deploy_patch}" ]]; then
        files+=("${project_deploy_patch}")
    fi
    if [[ -f "${project_service_patch}" ]]; then
        files+=("${project_service_patch}")
    fi

    for f in "${files[@]}"; do
        [[ -f "${f}" ]] || continue
        # Primero revertir al placeholder para evitar doble prefijo en ejecuciones repetidas
        sed -i \
            -e "s/${pname}-deployment/mi-aplicacion-deployment/g" \
            -e "s/${pname}-service/mi-aplicacion-service/g" \
            -e "s/${pname}-config/mi-aplicacion-config/g" \
            -e "s/app=${pname}/app=mi-aplicacion/g" \
            -e "s/app: ${pname}/app: mi-aplicacion/g" \
            "${f}"
        # Luego aplicar el nombre real
        sed -i \
            -e "s/mi-aplicacion-deployment/${pname}-deployment/g" \
            -e "s/mi-aplicacion-service/${pname}-service/g" \
            -e "s/mi-aplicacion-config/${pname}-config/g" \
            -e "s/app=mi-aplicacion/app=${pname}/g" \
            -e "s/app: mi-aplicacion/app: ${pname}/g" \
            "${f}"
    done

    # nodePort del Service: revertir y reaplicar (idempotente)
    for f in "${K8S_DIR}/service/service.yml" "${PROJECT_ROOT}/${K8S_PROJECT_DIR}/service-patch.yml"; do
        [[ -f "${f}" ]] || continue
        sed -i -e "s/nodePort: ${K8S_NODE_PORT}/nodePort: 30080/g" "${f}"
        sed -i -e "s/nodePort: 30080/nodePort: ${K8S_NODE_PORT}/g" "${f}"
    done
}

# --- Comandos principales ---

# deploy [green_N] [blue_N]
# Nunca pisa el ConfigMap del color inactivo: solo aplica Service + ConfigMap(s) del activo
# (o ambos ConfigMaps en primer deploy) para que el rollback con switch siga funcionando.
cmd_deploy() {
    local green_replicas="${1:-1}"
    local blue_replicas="${2:-1}"

    # 0. Si K8S_IMAGE_PATH esta definido, extraer k8s de la imagen a projects/PROJECT_NAME
    if [[ -n "${K8S_IMAGE_PATH:-}" ]]; then
        extract_k8s_from_image
        K8S_PROJECT_DIR="deploy/3-kubernetes/projects/${PROJECT_NAME}"
    fi

    # 1. Generar ConfigMap (nombre según PROJECT_NAME)
    print_message "${BLUE_C}" "Generando ConfigMap desde .env..."
    bash "${SCRIPT_DIR}/generate-configmap.sh"

    # 2. Ajustar nombres en manifests base/servicio según PROJECT_NAME (antes de aplicar)
    patch_k8s_names

    # 3. Aplicar Service (siempre) y solo el/los ConfigMap que toquen: no pisar el inactivo
    local active
    active=$(get_active_color)
    print_message "${BLUE_C}" "Aplicando Service..."
    kubectl apply -f "${K8S_DIR}/service/service.yml" -n "${NAMESPACE}"
    if [[ -n "${active}" ]]; then
        print_message "${BLUE_C}" "Aplicando solo ConfigMap del activo (${active}); el inactivo no se toca (rollback OK)."
        kubectl apply -f "${K8S_DIR}/service/configmap-${active}.yml" -n "${NAMESPACE}"
    else
        print_message "${BLUE_C}" "Primer deploy: aplicando ambos ConfigMaps..."
        kubectl apply -f "${K8S_DIR}/service/configmap-blue.yml" -n "${NAMESPACE}"
        kubectl apply -f "${K8S_DIR}/service/configmap-green.yml" -n "${NAMESPACE}"
    fi

    # 5. Aplicar recursos/patches específicos del proyecto (si existen)
    local project_service_dir="${PROJECT_ROOT}/${K8S_PROJECT_DIR}/service"
    local project_service_patch="${PROJECT_ROOT}/${K8S_PROJECT_DIR}/service-patch.yml"
    if [[ -d "${project_service_dir}" ]]; then
        print_message "${BLUE_C}" "Aplicando Service extra desde ${K8S_PROJECT_DIR}/service..."
        kubectl apply -k "${project_service_dir}"
    elif [[ -f "${project_service_patch}" ]]; then
        print_message "${BLUE_C}" "Aplicando service-patch.yml desde ${K8S_PROJECT_DIR}..."
        kubectl apply -f "${project_service_patch}"
    fi

    # 6. Aplicar ambos overlays
    apply_overlay "blue" "${blue_replicas}"
    apply_overlay "green" "${green_replicas}"

    # 7. Esperar rollouts
    wait_for_rollout "${DEPLOYMENT_BASE}-blue"
    wait_for_rollout "${DEPLOYMENT_BASE}-green"

    # 8. Mensaje final
    active=$(get_active_color)
    if [[ -z "${active}" || "${active}" == "blue" ]]; then
        print_message "${GREEN_C}" "✓ Deploy completo. Service apunta a blue (default)."
    else
        print_message "${GREEN_C}" "✓ Deploy completo. Service apunta a ${active}."
    fi
    print_message "${YELLOW}" "Usa 'blue-green.sh switch' para cambiar el trafico."
}

# Regenera solo el ConfigMap del color indicado y reinicia ese deployment. No toca el otro color (rollback intacto).
refresh_stack_env() {
    local color="${1:?}"
    if [[ -n "${K8S_IMAGE_PATH:-}" ]]; then
        extract_k8s_from_image
        K8S_PROJECT_DIR="deploy/3-kubernetes/projects/${PROJECT_NAME}"
    fi
    print_message "${YELLOW}" "RECREATE=1: actualizando solo ${color} con el .env actual (el otro stack no se toca)..."
    bash "${SCRIPT_DIR}/generate-configmap.sh" "${color}"
    patch_k8s_names
    kubectl apply -f "${K8S_DIR}/service/configmap-${color}.yml" -n "${NAMESPACE}"
    kubectl rollout restart deployment/"${DEPLOYMENT_BASE}-${color}" -n "${NAMESPACE}"
    wait_for_rollout "${DEPLOYMENT_BASE}-${color}"
}

# switch (detecta activo, cambia al otro)
cmd_switch() {
    local active
    active=$(get_active_color)
    if [[ -z "${active}" ]]; then
        print_message "${RED}" "No se pudo detectar el color activo. Usa switch:blue o switch:green."
        return 1
    fi

    local target
    if [[ "${active}" == "blue" ]]; then
        target="green"
    else
        target="blue"
    fi

    if [[ -n "${RECREATE:-}" ]]; then
        refresh_stack_env "${target}"
    fi
    print_message "${BLUE_C}" "Activo: ${active}. Cambiando a ${target}..."
    switch_service "${target}"
}

# switch:blue [N] / switch:green [N]
cmd_switch_color() {
    local target="${1:?}"
    local replicas="${2:-}"

    if [[ -n "${RECREATE:-}" ]]; then
        refresh_stack_env "${target}"
    fi
    if [[ -n "${replicas}" ]]; then
        print_message "${YELLOW}" "Escalando ${target} a ${replicas} replicas..."
        apply_overlay "${target}" "${replicas}"
        wait_for_rollout "${DEPLOYMENT_BASE}-${target}"
    fi

    switch_service "${target}"
}

# status
cmd_status() {
    echo ""
    print_message "${BLUE_C}" "=== Blue-Green Kubernetes Status ==="
    echo ""

    # Color activo
    local active
    active=$(get_active_color)
    if [[ -n "${active}" ]]; then
        if [[ "${active}" == "blue" ]]; then
            print_message "${BLUE_C}" "Activo: ${active} (Service selector)"
        else
            print_message "${GREEN_C}" "Activo: ${active} (Service selector)"
        fi
    else
        print_message "${RED}" "Service no encontrado o sin selector version."
    fi
    echo ""

    # Pods blue
    print_message "${BLUE_C}" "--- Blue ---"
    kubectl get pods -n "${NAMESPACE}" -l "app=${RESOURCE_PREFIX},version=blue" \
        -o wide --no-headers 2>/dev/null || echo "  (sin pods blue)"
    echo ""

    # Pods green
    print_message "${GREEN_C}" "--- Green ---"
    kubectl get pods -n "${NAMESPACE}" -l "app=${RESOURCE_PREFIX},version=green" \
        -o wide --no-headers 2>/dev/null || echo "  (sin pods green)"
    echo ""

    # Deployments
    print_message "${YELLOW}" "--- Deployments ---"
    kubectl get deployments -n "${NAMESPACE}" -l "app=${RESOURCE_PREFIX}" \
        -o wide --no-headers 2>/dev/null || echo "  (sin deployments)"
    echo ""

    # Service
    print_message "${YELLOW}" "--- Service ---"
    kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" \
        -o wide --no-headers 2>/dev/null || echo "  (sin service)"
    echo ""
}

# down [blue|green]
cmd_down() {
    local target="${1:-}"

    if [[ -z "${target}" ]]; then
        # Bajar todo: ambos deployments + service + configmap
        print_message "${YELLOW}" "Eliminando todos los recursos Kubernetes..."
        kubectl delete -k "${K8S_DIR}/overlays/blue" --ignore-not-found=true 2>/dev/null || true
        kubectl delete -k "${K8S_DIR}/overlays/green" --ignore-not-found=true 2>/dev/null || true
        kubectl delete -k "${K8S_DIR}/service" --ignore-not-found=true 2>/dev/null || true
        print_message "${GREEN_C}" "✓ Todos los recursos eliminados."
    elif [[ "${target}" == "blue" || "${target}" == "green" ]]; then
        # Si el target es el activo, cambiar al otro primero
        local active
        active=$(get_active_color)
        if [[ "${active}" == "${target}" ]]; then
            local other
            if [[ "${target}" == "blue" ]]; then other="green"; else other="blue"; fi
            print_message "${YELLOW}" "Stack ${target} esta activo. Cambiando trafico a ${other}..."
            switch_service "${other}"
        fi
        print_message "${YELLOW}" "Eliminando deployment ${target}..."
        kubectl delete -k "${K8S_DIR}/overlays/${target}" --ignore-not-found=true 2>/dev/null || true
        print_message "${GREEN_C}" "✓ Deployment ${target} eliminado."
    else
        print_message "${RED}" "Error: down acepta 'blue', 'green' o vacio (todo)."
        return 1
    fi
}

# --- Main ---
case "${1:-}" in
    deploy)
        cmd_deploy "${2:-1}" "${3:-1}"
        ;;
    switch)
        cmd_switch
        ;;
    switch:blue)
        cmd_switch_color "blue" "${2:-}"
        ;;
    switch:green)
        cmd_switch_color "green" "${2:-}"
        ;;
    status)
        cmd_status
        ;;
    down)
        cmd_down "${2:-}"
        ;;
    *)
        echo "Usage: ${0} deploy|switch|switch:blue|switch:green|status|down [args]"
        echo ""
        echo "Commands:"
        echo "  deploy [green_replicas] [blue_replicas]"
        echo "    - Genera ConfigMap, aplica Service, despliega ambos overlays"
        echo "    - Default: 1 replica por color"
        echo ""
        echo "  switch"
        echo "    - Detecta el color activo y cambia al otro"
        echo ""
        echo "  switch:blue [replicas]"
        echo "    - Cambia trafico a blue (opcionalmente escala)"
        echo ""
        echo "  switch:green [replicas]"
        echo "    - Cambia trafico a green (opcionalmente escala)"
        echo ""
        echo "  status"
        echo "    - Muestra pods, deployments, service y color activo"
        echo ""
        echo "  down [blue|green]"
        echo "    - Sin argumento: elimina todo (deployments + service + configmap)"
        echo "    - Con argumento: elimina solo ese deployment"
        exit 1
        ;;
esac
