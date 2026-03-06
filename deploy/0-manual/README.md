# Despliegue manual (sin Docker)

Ejecución directa de la app en la máquina, sin contenedores ni orquestador. El script `run.sh` ejecuta el setup del proyecto (si existe) y arranca la app. El comando de arranque se resuelve en este orden:

1. Si `DOCKER_COMPOSE_APP` apunta a un archivo docker-compose con `command: [...]`, usa ese comando.
2. En otro caso, extrae el `CMD` del Dockerfile del proyecto.

La app corre en **foreground**: se detiene con `Ctrl+C` o al cerrar la terminal.

## Requisitos

- Bash.
- Las dependencias del proyecto deben estar resueltas. Si existe `scripts/setup/setup.sh` dentro del directorio del proyecto, `run.sh` lo ejecuta automáticamente **antes** de arrancar. Ese script es el que **instala y valida las herramientas** (p. ej. Bun, Node/NVM) y las dependencias; el kit de despliegue no comprueba runtimes.

## Configuración

Copiar la plantilla a **`.env` en la raíz del repo** y ajustar según el proyecto:

```bash
cp deploy/0-manual/.env.example .env
```

| Variable             | Descripción                                                                                       | Default              |
| -------------------- | ------------------------------------------------------------------------------------------------- | -------------------- |
| `PROJECT_SOURCE`     | Ruta al código fuente. Relativa (al repo) o absoluta.                                             | Raíz del repo        |
| `DOCKERFILE_PATH`    | Ruta al Dockerfile, relativa al proyecto resuelto.                                                | `Dockerfile`         |
| `DOCKER_COMPOSE_APP` | Archivo docker-compose de desarrollo. Si tiene `command: [...]`, se usa en lugar del CMD del Dockerfile. Ruta relativa al proyecto resuelto o absoluta. | _(no se usa)_ |
| `ENV_FILE`           | Lista de archivos `.env` adicionales (separados por coma). Rutas relativas a la raíz del repo o absolutas. Se cargan después del `.env` de la raíz. | _(ninguno)_ |
| `PROJECT_PORT`       | Puerto del servicio. Si no está definido `PORT`, run.sh exporta `PORT=${PROJECT_PORT}` para la app. | _(no se usa)_ |

Todas las variables son opcionales. Sin `.env`, el script asume que el proyecto está en la raíz del repo y el Dockerfile en `<proyecto>/Dockerfile`.

### Ejemplos

```bash
# Proyecto en subcarpeta "app" del repo
PROJECT_SOURCE=app

# Proyecto en ruta absoluta externa
PROJECT_SOURCE=/home/user/my-project

# Dockerfile en ubicación no estándar
PROJECT_SOURCE=app
DOCKERFILE_PATH=docker/Dockerfile.prod

# Usar el comando de un docker-compose de desarrollo (ej. hot-reload con bun)
PROJECT_SOURCE=app
DOCKER_COMPOSE_APP=docker-compose.dev.yml
```

## Uso

```bash
# Desde la raíz del repo
make run-manual

# O directamente
./deploy/0-manual/run.sh
```

## Qué hace `run.sh`

1. Carga `.env` de la raíz del repo si existe; si está definido `ENV_FILE` (lista de archivos separados por coma), carga cada uno; si no hay `PORT` pero sí `PROJECT_PORT`, exporta `PORT=${PROJECT_PORT}`.
2. Resuelve el directorio del proyecto (`PROJECT_SOURCE`) y la ubicación del Dockerfile (`DOCKERFILE_PATH`).
3. Ejecuta **`scripts/setup/setup.sh`** del proyecto si existe; ese script es quien instala/valida Bun, Node, etc., y las dependencias.
4. Si `DOCKER_COMPOSE_APP` está definido y el archivo tiene `command: [...]`, usa ese comando.
5. Si no, extrae el `CMD` del Dockerfile.
6. `exec` del comando extraído (la app reemplaza al script y recibe señales directamente).
