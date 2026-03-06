# Etapa 2.5: Docker Swarm (producción, réplicas, rolling update)

Servicio Swarm con réplicas y **rolling update**, alineado con **1-simple-compose** y **2-blue-green-compose** en variables y red.

## Qué aporta frente a Compose blue-green

- **Varias réplicas** activas (alta disponibilidad).
- **Rolling update**: al actualizar la imagen, Swarm sustituye contenedores de uno en uno.
- **Rollback** integrado si el update falla (`failure_action: rollback`).
- **Escalado**: `make scale-swarm REPLICAS=N`.
- Red **overlay** para varios nodos.

## Mismo .env que el resto del proyecto

Swarm usa el **`.env` de la raíz del repo** (el mismo que 1-simple-compose y 2-blue-green-compose). Si aún no tienes `.env`, copia la plantilla: `cp deploy/2.5-swarm/.env.example .env` y ajusta las variables.

**No es obligatorio exponer un puerto.** Si **PORTS** no está definido, el servicio no publica ningún puerto (solo interno). Si defines **PORTS** (ej. `5050`), se publica ese puerto en el host; el contenedor usa siempre **PROJECT_PORT** (una sola variable, sin repetir).

Swarm usa el mismo `.env` de la raíz y las mismas convenciones:

| Concepto | 1-simple-compose / 2-blue-green-compose | Swarm |
|----------|----------------------------|--------|
| **PORTS** | `host:container` (ej. `5050:80`) | Si está definido: se usa como puerto **publicado** en el host (parte izquierda de PORTS, o PORTS si no hay `:`). El contenedor usa siempre **PROJECT_PORT** (no se repite). |
| **ENV_FILE** | Varios .env inyectados en el contenedor | `scripts/generate-env-file-include.sh` genera `docker-stack.env-include.yml` con los archivos de `ENV_FILE` (mismo formato: lista separada por coma). |
| **Red** | `NETWORK`, `NETWORK_SUBNET`, `ensure-network.sh` (bridge) | `NETWORK_SWARM` (si distinto de NETWORK) o `NETWORK`, `NETWORK_SUBNET`, `ensure-network-swarm.sh` (overlay). Si `NETWORK` ya es bridge (local), define **NETWORK_SWARM** (ej. `my-network-swarm`) para la overlay. |
| **IP fija** | `CONTAINER_IP` en override (IP del contenedor) | La IP estable es la **VIP del servicio** (asignada por Swarm, estable mientras exista el servicio). No es la de cada contenedor; Swarm no permite fijar la IP del servicio, por eso `CONTAINER_IP` no se usa. |

## Variables (en .env de la raíz)

- **PROJECT_NAME**, **PROJECT_IMAGE**, **PROJECT_VERSION**, **PROJECT_PORT:** igual que en 2-blue-green-compose. **PROJECT_PORT** es el puerto en el que escucha la app dentro del contenedor (siempre usado).
- **PORTS:** si lo defines (ej. `5050`), el servicio publica ese puerto en el host (mapeado a **PROJECT_PORT** en el contenedor). Si no defines **PORTS**, no se expone puerto (servicio solo interno).
- **REPLICAS:** número de réplicas (por defecto 2).
- **UPDATE_DELAY:** tiempo de espera en el rolling update antes de detener la tarea antigua (p. ej. `60s`, `2m`). Por defecto `60s`. Debe ser mayor que el arranque de la app + health check para que el tráfico no llegue a tareas aún no listas (evita que el navegador se quede colgado tras un update).
- **HEALTH_PATH:** ruta del healthcheck (ej. `/health`).
- **NETWORK**, **NETWORK_SUBNET:** nombre y opcionalmente subnet de la red overlay; `ensure-network-swarm.sh` la crea si no existe. Si ya usas **NETWORK** para bridge (1-simple-compose / 2-blue-green-compose), define **NETWORK_SWARM** (ej. `my-network-swarm`) para la overlay y evita conflicto de ámbito (local vs swarm).
- **ENV_FILE:** archivos .env adicionales para el contenedor (comma-separated), como en 2-blue-green-compose. Se inyectan vía `docker-stack.env-include.yml` generado antes del deploy.

## Rollback y variables de entorno

- **update-swarm** aplica las variables actuales de `.env` y `ENV_FILE` y fuerza el rolling update (`docker service update --force`) para que el servicio use los valores nuevos.
- **rollback-swarm** no usa `docker service rollback`. Restaura `.env` y los archivos de `ENV_FILE` desde una copia guardada (**backup_prev**) —el estado que había antes del último `deploy-swarm` o `update-swarm`— y vuelve a ejecutar `docker stack deploy`. Así el servicio queda con las variables anteriores. Tras cada deploy/update exitoso se guarda el estado actual en **backup** y el backup anterior se mueve a **backup_prev**. Necesitas al menos un `deploy-swarm` y un `update-swarm` (o dos deploys) para que exista `backup_prev` y el rollback funcione.

## Uso

```bash
# Desde la raíz del repo
make setup-swarm
make deploy-swarm
make deploy-swarm REPLICAS=3

make status-swarm
make scale-swarm REPLICAS=4

make build && make update-swarm
make rollback-swarm   # vuelve a la spec anterior (incluidas variables)
make down-swarm
```

## Comprobar que el servicio publica el puerto

En Swarm el puerto **publicado** es a nivel de **servicio** (routing mesh), no de cada contenedor. Por eso `docker ps` puede no mostrar el mapeo en el contenedor.

- Comprueba que **PORTS** está definido en `.env` (ej. `5050`) antes de `make deploy-swarm` si quieres exponer el servicio.
- Ver los puertos del servicio:
  ```bash
  docker service inspect mi-aplicacion_app --format '{{json .Endpoint.Ports}}'
  ```
  o `docker service ls` y luego `docker service ps mi-aplicacion_app`.
- Si desplegaste antes sin **PORTS** y luego lo añadiste, haz `make down-swarm` y vuelve a `make deploy-swarm`.
