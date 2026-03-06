# Integrar una nueva aplicación

Guía para agregar cualquier aplicación Docker al framework de
despliegue.

## Requisitos del proyecto

La aplicación debe tener:

1. **Dockerfile** — en la raíz del proyecto o en una subruta
2. **Endpoint de health** — la app debe responder en una ruta
   configurable (ej. `/health`) con HTTP 200
3. **Puerto configurable** — idealmente via variable de entorno
   `PORT`

## Paso 1: Colocar el proyecto

Copiar o clonar el proyecto dentro del repositorio (o en cualquier
ruta accesible). Ejemplo:

```
blue-green/
├── app/              ← proyecto demo existente
├── mi-nuevo-proyecto/ ← nuevo proyecto
│   ├── Dockerfile
│   ├── ...
```

## Paso 2: Configurar el `.env`

Copiar el `.env.example` de la etapa deseada a la raíz y ajustar:

```bash
cp deploy/<etapa>/.env.example .env
```

Variables mínimas para todas las etapas:

```env
PROJECT_SOURCE=mi-nuevo-proyecto
PROJECT_NAME=mi-nuevo-proyecto
PROJECT_PORT=8080
```

### Variables por etapa

| Variable | Etapa 1+ | Etapa 2+ | Etapa 2.5+ |
|----------|----------|----------|------------|
| `NETWORK` | Requerida | Requerida | Requerida |
| `PORTS` | Opcional | Requerida | Opcional |
| `PROJECT_IMAGE` | — | Requerida | Requerida |
| `PROJECT_VERSION` | — | Opcional | Opcional |
| `HEALTH_PATH` | — | Requerida | — |
| `REPLICAS` | — | — | Requerida |

## Paso 3: Snippet nginx (solo etapa 2)

Si la app necesita configuración nginx especial (WebSocket,
archivos estáticos, streaming), crear un `snippet.conf` dentro
de la imagen Docker:

```dockerfile
COPY nginx/snippet.conf /app/nginx/snippet.conf
```

Y configurar en `.env`:

```env
PROJECT_NGINX_DIR=/app/nginx/snippet.conf
```

Ejemplo de snippet para WebSocket:

```nginx
location /ws {
    proxy_pass http://app_active;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

Si no se necesita snippet, omitir `PROJECT_NGINX_DIR`.

## Paso 4: Variables de entorno adicionales

Si la app necesita variables propias (credenciales de DB, API
keys, etc.), crear un archivo separado y referenciarlo:

```env
ENV_FILE=mi-nuevo-proyecto/.env.local
```

`ENV_FILE` acepta múltiples archivos separados por coma.

## Paso 5: Compose del proyecto (solo etapa 1)

Si el proyecto tiene un `docker-compose.yml` con servicios
auxiliares (DB, Redis, cache), referenciarlo:

```env
DOCKER_COMPOSE_APP=docker-compose.dev.yml
```

La ruta es relativa a `PROJECT_SOURCE`.

## Paso 6: Patches K8s (solo etapa 3)

Si el proyecto necesita configuración K8s específica (volúmenes,
init containers, etc.), crear manifiestos en un directorio `k8s/`
dentro del proyecto:

```
mi-nuevo-proyecto/
├── k8s/
│   ├── deployment-patch.yml
│   └── service-patch.yml
```

Y configurar en `.env`:

```env
K8S_PROJECT_DIR=mi-nuevo-proyecto/k8s
```

## Paso 7: Desplegar

```bash
make build
make deploy-<etapa>
make status-<etapa>
```

## Verificación

- [ ] `make build` construye la imagen sin errores
- [ ] `make deploy-<etapa>` levanta los contenedores
- [ ] `make status-<etapa>` muestra estado saludable
- [ ] El health check responde HTTP 200
- [ ] Las variables de entorno llegan al contenedor

## Skill automatizado

Para una integración guiada, usar el skill:

```
/add-project mi-nuevo-proyecto 2
```

Esto analiza el proyecto, detecta puerto, health endpoint y
tipo de app, y genera la configuración automáticamente.
