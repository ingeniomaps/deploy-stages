# Kit de despliegue evolutivo

![Estado: Estable](https://img.shields.io/badge/estado-estable-brightgreen) ![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-blue)

Framework de despliegue que lleva **cualquier aplicación Docker** desde un entorno local hasta producción, pasando por varias etapas (un contenedor, blue-green con Nginx, Docker Swarm, Kubernetes), con **un único `.env`** y un único punto de entrada: **`make`**.

---

## Qué resuelve

- Pasar de “un contenedor en mi máquina” a blue-green, Swarm o Kubernetes **sin reescribir configs** ni mantener varios mundos (dev vs prod).
- **Una sola fuente de verdad** para variables (imagen, puertos, red, health, réplicas) compartida por todas las etapas.
- Comportamiento **predecible**: mismo concepto de switch, rollback y RECREATE en Compose y en Kubernetes.

---

## Requisitos

- **make**
- **Docker** (y Docker Compose v2: `docker compose`)
- Para **etapa 3 (Kubernetes):** [Kind](https://kind.sigs.k8s.io/) y **kubectl** (opcional: cluster remoto y registro de imágenes)
- Para **etapa 2.5 (Swarm):** Docker en modo Swarm

---

## Inicio rápido

1. **Crea el `.env` en la raíz del repo.**
   Si no tienes uno, copia la plantilla de la etapa que vayas a usar, por ejemplo:

   ```bash
   cp deploy/0-manual/.env.example .env
   # o para un contenedor:
   cp deploy/1-simple-compose/.env.example .env
   # o para blue-green:
   cp deploy/2-blue-green-compose/.env.example .env
   # o para Swarm:
   cp deploy/2.5-swarm/.env.example .env
   # o para Kubernetes:
   cp deploy/3-kubernetes/.env.example .env
   ```

   Edita `.env` con los valores de tu proyecto (nombre, imagen, puertos, red, etc.).

2. **Lista los comandos disponibles:**

   ```bash
   make help
   ```

3. **Elige una etapa y desplega.**
   Por ejemplo:
   - Ejecución local (sin Docker): `make run-manual`
   - Un solo contenedor: `make build` y `make deploy-simple`
   - Blue-green con Compose: `make setup-bluegreen` (si es la primera vez) y `make deploy-bluegreen`
   - Docker Swarm: `make setup-swarm` y `make deploy-swarm`
   - Kubernetes (Kind): `make setup-k8s`, `make deploy-k8s`, luego `make switch-k8s` para cambiar tráfico

El kit despliega la imagen que indiques en `.env` (`PROJECT_IMAGE:PROJECT_VERSION`). Solo necesitas un Dockerfile y configurar las variables de la etapa que vayas a usar.

---

## Las cinco etapas

| Etapa   | Descripción                                                             | Comandos principales                                                                                                                            |
| ------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **0**   | Ejecución directa sin Docker (local)                                    | `make run-manual`                                                                                                                               |
| **1**   | Un contenedor con Docker Compose                                        | `make deploy-simple`, `make down-simple`                                                                                                        |
| **2**   | Blue-green con Compose + Nginx (dos stacks, switch de tráfico)          | `make setup-bluegreen`, `make deploy-bluegreen`, `make switch-bluegreen`, `make status-bluegreen`, `make down-bluegreen`                        |
| **2.5** | Docker Swarm (réplicas, rolling update, rollback desde backup)          | `make setup-swarm`, `make deploy-swarm`, `make update-swarm`, `make rollback-swarm`, `make scale-swarm`, `make status-swarm`, `make down-swarm` |
| **3**   | Kubernetes (Kind u otro cluster): blue-green, ConfigMaps por color, HPA | `make setup-k8s`, `make load-image-k8s`, `make deploy-k8s`, `make switch-k8s`, `make status-k8s`, `make down-k8s`, `make push-k8s`              |

Cada etapa tiene su **README** y **`.env.example`** en su carpeta dentro de `deploy/`. Las variables se **añaden** por etapa sin renombrar las anteriores.

---

## El archivo `.env`

- **Un solo `.env` en la raíz** del repositorio.
- Todas las etapas lo leen; cada etapa usa sus variables y añade las propias (por ejemplo `K8S_NODE_PORT` solo en etapa 3).
- No versiones el `.env` con secretos; solo versiona plantillas (`.env.example`).
- Origen recomendado: copiar desde el `.env.example` de la etapa que vayas a usar y ajustar valores.

---

## Blue-green (etapas 2 y 3)

Comportamiento **alineado** entre Compose y Kubernetes:

- **Switch** — Solo cambia el tráfico al otro color (blue ↔ green). No toca contenedores ni ConfigMaps. **Rollback** = volver a hacer switch al color anterior.
- **Switch con RECREATE=1** — Actualiza el stack al que vas (env/imagen), lo reinicia y luego hace el switch. El otro color **no se toca**, así el rollback sigue disponible.
- **Deploy** — En K8s solo se aplica el ConfigMap del color activo (o ambos en el primer deploy) para no pisar el inactivo.

---

## Estructura del proyecto

```
├── Makefile              # Punto de entrada (make help, make deploy-*, etc.)
├── .env                  # Configuración (no versionado con secretos)
├── examples/
│   └── demo-app/         # App de ejemplo (Express/Bun) para probar el framework
├── deploy/
│   ├── 0-manual/         # Etapa 0: ejecución sin Docker
│   ├── 1-simple-compose/ # Etapa 1: un contenedor
│   ├── 2-blue-green-compose/  # Etapa 2: blue-green con Nginx
│   ├── 2.5-swarm/       # Etapa 2.5: Docker Swarm
│   ├── 3-kubernetes/   # Etapa 3: Kubernetes (Kind + Kustomize)
│   └── scripts/lib/     # Scripts compartidos (p. ej. parse-env.sh)
├── docs/                 # Documentación (arquitectura, integración, producción)
└── .context/             # Contexto para IA (reglas, arquitectura, negocio)
```

Detalle de cada etapa: ver el **README** dentro de `deploy/<etapa>/`.

---

## Documentación adicional

- **`make help`** — Lista todos los targets por etapa.
- **`deploy/<etapa>/README.md`** — Variables, flujo y requisitos de esa etapa.
- **`docs/architecture.md`** — Diagramas y flujo de datos del framework.
- **`docs/adding-a-project.md`** — Cómo integrar una nueva aplicación al kit.
- **`docs/production-checklist.md`** — Checklist de producción (seguridad, observabilidad, despliegue).
- **`CLAUDE.md`** — Resumen del proyecto para uso con IA/asistentes.
- **Skills de Claude Code** — 13 skills disponibles en `.claude/skills/` para tareas operativas: validar `.env`, smoke tests, auditoría de seguridad, diagnóstico de deploys, dry-run, generación de CI/CD, runbooks y más. Ejecuta `/help` en Claude Code para ver los disponibles.

---

## Uso con imagen de artifact (Kubernetes)

Si desplegas desde una **imagen en un registry** (sin clonar el repo de la app), puedes definir **`K8S_IMAGE_PATH`** en el `.env`. En `deploy-k8s` y en `switch-k8s RECREATE=1` el kit **extrae** esa carpeta desde la imagen a `deploy/3-kubernetes/projects/PROJECT_NAME` y usa esos archivos (deployment-patch, service-patch, etc.). Así no necesitas el código del proyecto en el servidor.

```bash
# Ejemplo en .env
K8S_IMAGE_PATH=/app/k8s
```

Ver `deploy/3-kubernetes/README.md` para más detalles.

---

## Licencia

Este proyecto está bajo la licencia [MIT](LICENSE).
