# Complementos docker-compose del proyecto

Estos archivos **complementan** el estándar `deploy/simple-compose/docker-compose.yml`. No se usan solos; se fusionan con ese base al hacer `make deploy-simple`.

| Archivo | Uso | Volumen / hot reload | Healthcheck | Recursos (límites) |
|---------|-----|----------------------|-------------|--------------------|
| `docker-compose.dev.yml` | Desarrollo | Sí: código montado + `bun --watch` | 30s intervalo, 40s start_period | 2 CPU, 1G RAM |
| `docker-compose.prod.yml` | Producción | No | 15s intervalo, 30s start_period | 1 CPU, 512M RAM |

En **dev**, el directorio de la app se monta en el contenedor y el proceso usa `bun --watch`: al guardar cualquier archivo, la app se recarga sola sin reconstruir la imagen ni la VM.

En la raíz del repo, en `.env`, puedes definir qué complemento usar (opcional):

- `DOCKER_COMPOSE_APP=app/docker-compose.prod.yml` — healthcheck + recursos de producción
- `DOCKER_COMPOSE_APP=app/docker-compose.dev.yml` — healthcheck + recursos de desarrollo
- **No definir** `DOCKER_COMPOSE_APP` — no se usa ningún complemento; solo base + override (también válido)

El orden de fusión en `make deploy-simple` es:

1. `deploy/simple-compose/docker-compose.yml` (base)
2. `deploy/simple-compose/docker-compose.override.yml` (generado desde .env)
3. `app/docker-compose.prod.yml` o `app/docker-compose.dev.yml` (complemento del proyecto)
