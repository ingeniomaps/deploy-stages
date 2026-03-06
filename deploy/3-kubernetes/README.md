# Etapa 3: Kubernetes (Blue-Green con Kind)

Despliegue blue-green en Kubernetes usando Kustomize. Pensado para cluster local con **Kind**; con imagen en registro también puedes usar otro cluster (cambiar imagen en overlays o usar `make push-k8s` y apuntar el cluster al registro).

## ¿Como 2-blue-green-compose o como 2.5-swarm?

**Kubernetes (etapa 3) funciona como la etapa 2 (2-blue-green-compose), no como 2.5-swarm.**

| | **2-blue-green-compose** | **2.5-swarm** | **3-kubernetes** |
|---|--------------------------|---------------|-------------------|
| Modelo | Dos stacks (blue + green), switch de tráfico | Un solo servicio, rolling update | Dos stacks (blue + green), switch del Service |
| Deploy | Levanta inactivo, health, switch | `deploy-swarm` / `update-swarm` | `deploy-k8s` (ambos stacks); opcionalmente RECREATE=1 en switch |
| Switch | Cambia nginx al otro stack (sin tocar contenedores) | No aplica | Cambia selector del Service al otro color |
| Rollback | `switch STACK=blue` (solo mueve tráfico) | `rollback-swarm` (restaura .env desde backup y redeploy) | `switch-k8s` (solo mueve tráfico; el inactivo conserva su ConfigMap) |
| RECREATE | `switch RECREATE=1` recrea el stack destino con .env actual | No aplica | `switch-k8s RECREATE=1` actualiza solo el stack destino y hace el switch |

En K8s, igual que en 2-blue-green: **switch = solo mover tráfico** (rollback inmediato); **RECREATE=1** = aplicar .env nuevo al stack al que vas y luego hacer el switch.

## Requisitos

- **kubectl**
- **kind** (Kind Kubernetes in Docker)
- **.env** en la raíz del repo con las variables necesarias (mismo esquema que etapas 0–2.5). Si no tienes `.env`, copia la plantilla: `cp deploy/3-kubernetes/.env.example .env` y ajusta.

## Variables (.env)

Compartidas con otras etapas: `PROJECT_NAME`, `PROJECT_IMAGE`, `PROJECT_VERSION`, `PROJECT_PORT`, `PORTS`, `HEALTH_PATH`, `ENV_FILE`. Específicas de K8s:

- **K8S_NODE_PORT** — NodePort del Service (30000–32767). Por defecto 30080.
- **K8S_PROJECT_DIR** — (Opcional) Ruta a k8s del proyecto (p. ej. `app/k8s`) para deployment-patch o service-patch. Si usas **K8S_IMAGE_PATH**, en deploy y en switch RECREATE=1 se extrae de la imagen y se usa `deploy/3-kubernetes/projects/PROJECT_NAME`.
- **K8S_IMAGE_PATH** — (Opcional) Ruta dentro de la **imagen** donde está la carpeta k8s (ej. `/app/k8s`). Si está definida, en **deploy-k8s** y en **switch-k8s RECREATE=1** se extrae de la imagen a `deploy/3-kubernetes/projects/PROJECT_NAME` (no hace falta clonar el repo). En **switch-k8s** (sin RECREATE) no se extrae.
- **REPLICAS** — Réplicas iniciales por color (por defecto 1). El HPA puede escalar entre **HPA_MIN_REPLICAS** y **HPA_MAX_REPLICAS**.
- **HPA_MIN_REPLICAS** — Mínimo de pods por color (default 1). Nunca baja de este valor.
- **HPA_MAX_REPLICAS** — Máximo de pods por color (default 5). Límite para no pasarse de presupuesto.
- **HPA_CPU_PERCENT** — Uso de CPU (%) que dispara escalado (default 80). El HPA mantiene el promedio por debajo de este valor.

Para que el HPA escale por CPU, el cluster debe tener **metrics-server** instalado (en muchos clusters ya viene; en Kind a veces hay que instalarlo). El deployment base define `resources.requests.cpu` para que el porcentaje sea calculable.

Detalle en `deploy/3-kubernetes/.env.example`.

## Flujo típico (Kind local)

```bash
make setup-k8s          # Crea cluster Kind (nombre: ${PROJECT_PREFIX}-${PROJECT_NAME}-cluster)
make build              # Construye imagen
make deploy-k8s         # Despliega blue + green, tráfico en blue
make status-k8s         # Estado de pods y color activo
make switch-k8s         # Cambia tráfico al otro color (auto)
make switch-k8s STACK=green   # Fuerza cambio a green
make switch-k8s STACK=blue REPLICAS=2   # Cambia a blue y escala a 2
make switch-k8s RECREATE=1    # Regenera ConfigMap desde .env, reinicia el stack destino y luego cambia tráfico (para aplicar nuevas variables)
make down-k8s           # Elimina recursos (STACK=blue|green para solo uno)
```

**Comportamiento blue-green y rollback:** Cada color tiene su **propio ConfigMap** (`-config-blue`, `-config-green`). Así, al hacer **`make switch-k8s`** solo se mueve el tráfico; el stack inactivo **conserva su env**. Si algo falla, **`make switch-k8s`** de nuevo devuelve el tráfico al estado anterior (rollback).

- **`make switch-k8s RECREATE=1`**: actualiza **solo** el stack al que vas a cambiar (regenera su ConfigMap desde `.env`, reinicia ese deployment y hace el switch). El otro color **no se toca** → al hacer **`make switch-k8s`** sin RECREATE vuelves al env anterior.
- **`make deploy-k8s`**: aplica Service y **solo el ConfigMap del color activo** (o ambos en el primer deploy); **nunca pisa el ConfigMap inactivo**, así el rollback con `switch-k8s` sigue disponible.

## Uso con registro de imágenes

Para un cluster que no sea Kind (o para usar imagen remota):

```bash
make push-k8s REGISTRY_URL=myregistry.com   # Sube imagen al registro
# Ajusta en .env o en overlays la imagen a myregistry.com/mi-aplicacion:tag
make deploy-k8s   # (en cluster con acceso al registro)
```

## Estructura

- **base/** — Deployment base (Kustomize).
- **overlays/blue**, **overlays/green** — Parches por color (réplicas, imagen, version label).
- **service/** — Service NodePort y dos ConfigMaps por color (`configmap-blue.yml`, `configmap-green.yml`, generados desde `.env` + `ENV_FILE` por `scripts/generate-configmap.sh`).
- **kind/** — Configuración y setup del cluster Kind.
- **scripts/blue-green.sh** — Deploy, switch, status, down (interfaz alineada con 2-blue-green-compose).
