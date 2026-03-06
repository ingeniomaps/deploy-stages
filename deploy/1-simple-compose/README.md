# Despliegue simple (un contenedor)

Flujo estándar reutilizable: un solo servicio `app`, red externa, override generado desde `.env` y complemento opcional por proyecto.

## Orden de fusión

Al ejecutar `make deploy-simple` se cargan los compose en este orden (el último gana en conflictos):

1. **`docker-compose.yml`** (base) — imagen, red, expose, logging, restart.
2. **`docker-compose.override.yml`** (generado) — extra_hosts, env_file, ports, ipv4_address, build context según `.env`.
3. **Complemento del proyecto** (opcional) — `DOCKER_COMPOSE_APP` en `.env` (p. ej. `docker-compose.prod.yml` o `docker-compose.dev.yml`, ruta relativa al proyecto). Healthcheck, recursos, volúmenes, etc. El compose base no define healthcheck; puede añadirse en este complemento.

## Scripts

| Script | Qué hace |
|--------|----------|
| **`scripts/generate-extra-hosts.sh`** | Lee `.env` de la raíz y escribe `docker-compose.override.yml`: HOST_*, ENV_FILE, PORTS, CONTAINER_IP, build context (PROJECT_SOURCE/DOCKERFILE_PATH) y opcionalmente env_file. Se ejecuta antes de `up` y de `down`. |
| **`scripts/validate-env.sh`** | Comprueba que en `.env` existan PROJECT_NAME, PROJECT_PORT y NETWORK. |

En la raíz del repo, **`deploy/scripts/ensure-network.sh`** asegura que la red exista (la crea si no está).

## Variables en `.env`

### Obligatorias (validadas por `validate-env.sh`)

- **PROJECT_NAME** — Nombre de la app (imagen, contenedor).
- **PROJECT_PORT** — Puerto interno (expose y PORT de la app).
- **NETWORK** — Nombre de la red Docker (se crea si no existe).

### Opcionales — Ubicación del proyecto

- **PROJECT_SOURCE** — Ruta al código fuente. Relativa (al repo) o absoluta. Sin definir, se usa la raíz del repo como contexto de build.
- **DOCKERFILE_PATH** — Ruta al Dockerfile, relativa al directorio del proyecto resuelto. Sin definir, se usa `Dockerfile`.

### Opcionales — Compose y red

- **DOCKER_COMPOSE_APP** — Ruta al complemento, **relativa al directorio del proyecto** (resuelto por `PROJECT_SOURCE`) o absoluta. Con `PROJECT_SOURCE=app` basta `docker-compose.prod.yml` (no hace falta `app/docker-compose.prod.yml`).
- **NETWORK_SUBNET** — Subred al crear la red (ej. `172.28.0.0/16`).
- **CONTAINER_IP** — IP fija del contenedor (dentro de NETWORK_SUBNET).
- **PORTS** — Mapeos host:contenedor separados por comas (ej. `5000:3000,5050:8080`).
- **ENV_FILE** — Ruta a un archivo de env para el contenedor.
- **HOST_*** — Cualquier variable cuyo nombre empiece por `HOST_` con valor `hostname:ip` se añade a `extra_hosts`.

Si existe **`deploy/1-simple-compose/.env`**, también se usa como `env_file` del servicio.

## Uso

```bash
# Desde la raíz del repo
cp deploy/1-simple-compose/.env.example .env
# Editar .env (mínimo: PROJECT_NAME, PROJECT_PORT, NETWORK)

make deploy-simple   # build, validar .env, red, generar override, up; luego elimina imágenes huérfanas (<none>)
make down-simple     # generar override (si no existe) y down
```

## Requisitos

- `.env` en la raíz con las variables obligatorias.
- Dockerfile accesible (por defecto en la raíz del repo, configurable con `PROJECT_SOURCE` y `DOCKERFILE_PATH`).
