# Arquitectura del framework

## Visión general

Framework de despliegue evolutivo que toma cualquier aplicación
Docker y la despliega progresivamente a través de 5 etapas,
compartiendo un único `.env` en la raíz del repositorio.

```
.env (raíz)          <── configuración compartida
├── deploy/
│   ├── 0-manual/          Etapa 0: sin Docker
│   ├── 1-simple-compose/  Etapa 1: un contenedor
│   ├── 2-blue-green-compose/  Etapa 2: blue-green + nginx
│   ├── 2.5-swarm/         Etapa 2.5: rolling updates
│   └── 3-kubernetes/      Etapa 3: Kustomize + Kind
├── app/                   App demo (Express/Bun)
└── Makefile               Punto de entrada único
```

## Decisiones de diseño

### Un solo `.env` para todas las etapas

Cada etapa reutiliza las variables de las anteriores y solo
agrega nuevas. No se renombran variables entre etapas.

```
Etapa 0: PROJECT_SOURCE, PROJECT_PORT, ENV_FILE
Etapa 1: + PROJECT_NAME, NETWORK, PORTS, HOST_*
Etapa 2: + PROJECT_IMAGE, PROJECT_VERSION, HEALTH_PATH
Etapa 2.5: + REPLICAS, NETWORK_SWARM
Etapa 3: + HPA_MIN_REPLICAS, HPA_MAX_REPLICAS, HPA_CPU_PERCENT
```

### Parseo seguro del `.env`

Todos los scripts usan `deploy/scripts/lib/parse-env.sh` para
leer el `.env` sin `source` ni `eval`, evitando inyección de
código. La librería provee:

- `parse_env_file` — itera pares key=value con un callback
- `get_env_value` — lee una clave específica con default
- `load_env_export` — exporta todas las variables de forma segura

### Nombre de la imagen

- Etapa 1 usa `PROJECT_NAME:latest`
- Etapas 2+ usan `PROJECT_IMAGE:PROJECT_VERSION`
- `make build` lee `PROJECT_NAME` del `.env` para nombrar la imagen
- `PROJECT_IMAGE` tiene como convención ser igual a `PROJECT_NAME`

### Docker Compose V2 con fallback a V1

El Makefile detecta automáticamente si `docker compose` (V2)
está disponible. Si no, usa `docker-compose` (V1).

## Etapas

### Etapa 0 — Manual (sin Docker)

Ejecuta la app directamente en el host. `run.sh` carga el `.env`,
resuelve `PROJECT_SOURCE`, ejecuta `scripts/setup/setup.sh` del
proyecto si existe, y arranca la app con el `CMD` del Dockerfile.

**Caso de uso:** desarrollo local, VMs sin Docker.

### Etapa 1 — Simple Compose

Un solo contenedor con Docker Compose. Soporta `DOCKER_COMPOSE_APP`
para incluir un compose del proyecto (servicios auxiliares como
DB, Redis). Red externa configurable con IP fija opcional.

**Caso de uso:** despliegue simple en un host.

### Etapa 2 — Blue-Green con Compose

Dos stacks (blue y green) detrás de nginx. El script
`blue-green.sh` maneja deploy, switch, status y down. Nginx
reconfigura upstreams dinámicamente al hacer switch. Soporta
snippet nginx por proyecto (extraído de la imagen Docker).

**Caso de uso:** zero-downtime en un solo host con rollback.

### Etapa 2.5 — Docker Swarm

Servicio con réplicas y rolling updates (`start-first` +
`failure_action: rollback`). Backup automático del `.env` en cada
deploy para rollback. Red overlay configurable.

**Caso de uso:** alta disponibilidad en uno o varios nodos.

### Etapa 3 — Kubernetes

Blue-green con Kustomize overlays y Kind. ConfigMap generado
desde `.env` + `ENV_FILE`. HPA dinámico. Switch de tráfico via
`kubectl patch service`.

**Caso de uso:** producción con escalado automático.

## Flujo de un deploy típico

```
make build            →  Construye imagen Docker
make deploy-<etapa>   →  Ejecuta scripts de la etapa
                          ├── Valida .env
                          ├── Crea red si no existe
                          ├── Genera overlays/overrides
                          └── Levanta contenedores/pods
make status-<etapa>   →  Muestra estado actual
make switch-<etapa>   →  Cambia tráfico (etapas 2, 3)
```
