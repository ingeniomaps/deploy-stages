# Blue-Green con Compose

Despliega **cualquier imagen Docker** en modo blue-green: dos pilas (blue y green), nginx delante que conmuta el tráfico, y healthchecks antes de hacer switch. Los contenedores usan **COMPOSE_PROJECT_NAME** como prefijo: si defines `PROJECT_PREFIX`, el nombre será `{PREFIX}-{PROJECT_NAME}` (ej. `rx-mi-aplicacion-app-blue-1`); si no, solo `{PROJECT_NAME}` (ej. `mi-aplicacion-app-blue-1`).

## ¿Trae cualquier imagen y le inyecta nuestra .env?

**Sí, con dos matices:**

1. **Imagen:** Usa la imagen que indiques en `.env` como `PROJECT_IMAGE:PROJECT_VERSION` (por ejemplo `mi-aplicacion:latest`). `make build` construye la imagen si existe un Dockerfile; si no existe (imagen externa/artifact registry), se omite el build sin error. Si la imagen la generas con `make build` o `deploy-simple`, basta con poner el mismo nombre en `PROJECT_IMAGE` y `PROJECT_VERSION=latest`.

2. **Variables de entorno para la app:**  
   - El `.env` que se pasa con `--env-file` (el de la raíz del proyecto) se usa para **sustitución en los compose** (PROJECT_IMAGE, NETWORK, PROJECT_PORT, etc.).  
   - La **inyección en los contenedores** app-blue y app-green se hace con **rutas absolutas**: `generate-env-file-include.sh` genera `docker-compose.env-include-blue.yml` y `docker-compose.env-include-green.yml` (uno por stack) con el .env del proyecto más los archivos listados en **ENV_FILE** (comma-separated). Así no dependes de rutas relativas si mueves la carpeta.

Resumen: **cualquier imagen** → blue-green; **.env del proyecto + ENV_FILE** → inyectados en app-blue/app-green por el include generado (rutas absolutas).

## Variables (ver .env.example)

- **PROJECT_IMAGE** / **PROJECT_VERSION:** imagen a desplegar (debe existir ya, p. ej. construida con simple-compose o descargada de un registry).
- **PROJECT_NAME**, **PROJECT_PORT**, **HEALTH_PATH:** mismo uso que en simple-compose. **PROJECT_PORT** es el puerto interno de la app; no obliga a nginx a exponer ese mismo puerto al host.
- **PROJECT_PREFIX:** opcional. Si se define, los contenedores se nombran `{PREFIX}-{PROJECT_NAME}-...` (ej. `rx-mi-aplicacion-app-blue-1`, `rx-mi-aplicacion-nginx-blue-green`). Si no se define, solo `{PROJECT_NAME}-...`.
- **PORTS:** puerto(s) que nginx expone al público (formato `host:80`, por ejemplo `5050:80`). Si no se define, se usa `PROJECT_PORT:80`.
- **Red principal** — prioridad: **NETWORK** > **NETWORK_DEFAULT** > primera de **NETWORK_NAME**. Al menos una de las tres debe estar definida. La red se crea automáticamente si no existe (con **NETWORK_SUBNET** si se define). El **CONTAINER_IP** se asigna a nginx en esta red.
- **NETWORK_NAME:** opcional. Lista de redes separadas por coma. La red principal se excluye y las restantes se agregan como **redes adicionales en nginx** (el punto de entrada). Útil cuando nginx debe ser alcanzable desde otras redes (ej. un reverse proxy externo). Las redes listadas deben existir como redes Docker externas.
- **NETWORK_SUBNET:** opcional. Subnet al crear la red principal (p. ej. `172.28.0.0/16`).
- **CONTAINER_IP:** opcional. IP fija del contenedor nginx dentro de la red principal. `generate-nginx-override.sh` escribe solo el bloque nginx en el override.
- **HOST_*:** opcional. Variables con formato `hostname:ip` (ej. `HOST_DB=db.local:172.20.0.2`). Se inyectan como `extra_hosts` en los contenedores app-blue y app-green.
- **PROJECT_NGINX_DIR:** opcional. **Ruta dentro de la imagen** del proyecto donde está `snippet.conf` (ej. `/app/nginx/snippet.conf`). Si no se define, no se extrae nada y nginx usa un snippet vacío. Si se define, en cada **deploy** y **switch** el script extrae ese archivo de la imagen a `deploy/2-blue-green-compose/projects/${PROJECT_NAME}/snippet.conf` y se monta en el contenedor nginx. El kit no guarda el snippet en su código; viene de la imagen del proyecto.

## Snippet nginx desde la imagen del proyecto

El snippet no vive en el código de blue-green-compose: **viene de la imagen** del proyecto. En el Dockerfile del proyecto debes copiar `snippet.conf` a una ruta (ej. `/app/nginx/snippet.conf`) y definir en `.env` **PROJECT_NGINX_DIR** con esa ruta. En cada **deploy** y **switch** el script extrae ese archivo de la imagen a `deploy/2-blue-green-compose/projects/${PROJECT_NAME}/snippet.conf`; si la variable no está definida o el archivo no existe en la imagen, se escribe un snippet vacío para que nginx no falle. La carpeta `projects/` se crea automáticamente y está en `.gitignore`. El volumen que monta nginx es `../projects/${PROJECT_NAME}`.

## Dos escenarios

1. **Nueva imagen (deploy)**  
   Construyes una nueva imagen (`make build` o actualizas `PROJECT_IMAGE`/`PROJECT_VERSION` en `.env`). Luego `make deploy-bluegreen GREEN=n BLUE=m`: el script levanta el stack **inactivo** con esa imagen, comprueba health y **pasa el tráfico** ahí. No hace falta otro comando para “cambiar a la nueva versión”.

2. **Rollback**  
   La versión nueva (p. ej. green) falla y quieres volver a la anterior (blue). **No** cambies imagen: solo mueves el tráfico con `make switch-bluegreen STACK=blue` (o `switch-bluegreen STACK=blue INSTANCES=1`). Nginx vuelve a apuntar a blue; no se reconstruye ni se levanta nada nuevo.

3. **Switch con recarga (RECREATE=1)**  
   Si cambiaste la imagen o el `.env` y quieres que el stack **al que vas a apuntar** se recree con lo actual antes de cambiar el tráfico: `make switch-bluegreen RECREATE=1` (o `switch-bluegreen STACK=green RECREATE=1` / `STACK=blue RECREATE=1`). Sin `RECREATE` el switch solo mueve el apuntador de nginx; con `RECREATE=1` se hace `docker-compose up -d --force-recreate` sobre ese stack y luego se hace el switch.

## Instancias por stack

- **deploy-bluegreen** usa `GREEN` y `BLUE` (por defecto 1 y 1):  
  `make deploy-bluegreen GREEN=2 BLUE=1` → 2 instancias green, 1 blue.
- **switch-bluegreen** usa `STACK=green|blue` (opcional; sin STACK cambia al stack inactivo) e `INSTANCES` (opcional; si no se pasa, mantiene la cantidad actual). **SCALE_DOWN=1** escala el stack que se abandona a 1 instancia; si no se pasa, el stack que se deja mantiene sus instancias.  
  `make switch-bluegreen STACK=green INSTANCES=2`. `make switch-bluegreen STACK=blue SCALE_DOWN=1` para rollback y bajar green a 1.

## Uso

`make setup-bluegreen` crea el archivo `.env` en la raíz del repositorio copiando `deploy/2-blue-green-compose/.env.example` si no existe, y luego ejecuta el script interactivo `setup.sh` que pregunta los valores necesarios (`PROJECT_NAME`, `PROJECT_IMAGE`, `NETWORK`).

```bash
# Desde la raíz del repo (el .env de la raíz se usa para blue-green)
make setup-bluegreen            # crea .env en la raíz (desde .env.example) y ejecuta setup interactivo
make deploy-bluegreen            # deploy con GREEN=1 BLUE=1
make deploy-bluegreen GREEN=2 BLUE=1

make switch-bluegreen                  # tráfico al stack inactivo (INSTANCES=1)
make switch-bluegreen STACK=green     # tráfico a green (nueva versión)
make switch-bluegreen STACK=blue      # rollback: tráfico a blue (blue mantiene sus instancias)
make switch-bluegreen STACK=blue SCALE_DOWN=1   # rollback y bajar green a 1 instancia
make switch-bluegreen RECREATE=1       # recrea el stack destino y hace el switch
make switch-bluegreen STACK=green RECREATE=1   # recrear green y luego pasar tráfico

make status-bluegreen            # estado de blue, green y nginx

make down-bluegreen              # baja todo (nginx + blue + green)
make down-bluegreen STACK=blue   # baja solo blue; si era el activo, tráfico pasa a green antes
make down-bluegreen STACK=green  # baja solo green; si era el activo, tráfico pasa a blue antes
```

## ¿Compose blue-green o un “service” con réplicas?

**Este setup (Compose + nginx + switch manual)** es adecuado para:
- Un solo host, despliegues controlados (blue/green con corte explícito).
- Entornos donde prefieres controlar cuándo se cambia el tráfico y hacer rollback en un comando.

**Para más disponibilidad y escalabilidad en producción** suele ser mejor un **servicio con réplicas** gestionado por un orquestador:

| Enfoque | Ventajas | Cuándo usarlo |
|--------|----------|----------------|
| **Este blue-green (Compose)** | Simple, sin orquestador, rollback claro (switch a blue/green). | Un host, pocas instancias, despliegues puntuales. |
| **Docker Swarm** (`docker service create --replicas N` + `docker service update`) | Varias réplicas activas, actualizaciones rolling, reinicio de fallos, escalado con `docker service scale`. | Varios nodos o un solo nodo con alta disponibilidad y cero-downtime. |
| **Kubernetes** (Deployment + Service) | Réplicas, rolling updates, healthchecks, escalado (HPA), múltiples nodos. | Producción con muchos servicios, escalado automático, ecosistema K8s. |

Recomendación breve: **mantener este blue-green** para entornos pequeños o cuando quieras el flujo blue/green explícito. Para **producción con alta disponibilidad y mejor escalabilidad** usa la etapa **Docker Swarm** de este mismo proyecto: **`deploy/2.5-swarm/`** (`make deploy-swarm`, rolling update, réplicas). Para máxima productividad, **Kubernetes** (`deploy/3-kubernetes/`).
