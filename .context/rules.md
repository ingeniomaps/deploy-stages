# Reglas generales de código — Blue-Green (kit de despliegue)

Este documento define reglas de código aplicadas al **proyecto del kit de despliegue**. La carpeta **`app/`** es una aplicación demo para probar el framework y **no forma parte del kit**; puede ignorarse al aplicar estas reglas.

---

## Alcance del proyecto

- **Incluido:** `deploy/` (todas las etapas), `Makefile`, `.env` raíz, `deploy/scripts/lib/`, `docs/`, configs en raíz (`.env.example`, etc.).
- **Excluido para reglas:** `app/` (demo; cada proyecto que use el kit tendrá su propio código).

---

## Idioma y documentación

- **Idioma del proyecto:** español (comentarios, mensajes de script, documentación en README y docs).
- Cada etapa debe tener su **README.md** y **`.env.example`** documentando variables y flujo.
- Rutas y nombres de carpeta en documentación deben coincidir con la estructura real (p. ej. `deploy/2-blue-green-compose/`, no rutas antiguas).

---

## Scripts y shell

- **Bash:** scripts en `deploy/**` usan Bash; primera línea `#!/usr/bin/env bash` y `set -euo pipefail` donde aplique.
- **Lectura de `.env`:** usar el parser seguro (`deploy/scripts/lib/parse-env.sh` o equivalente por etapa); no hacer `source .env` ni `eval` sobre contenido de usuario.
- **Portabilidad:** preferir sintaxis POSIX/sed/awk cuando no se dependa de extensiones Bash; evitar dependencias no estándar sin documentarlas.
- Comentarios en scripts en español; mensajes al usuario (echo/print) en español.

---

## Variables de entorno y etapas

- **Un solo `.env` en la raíz** compartido por todas las etapas; cada etapa **añade** variables sin renombrar las existentes.
- Mismo nombre de variable = mismo significado en todas las etapas (p. ej. `PROJECT_PORT`, `ENV_FILE`, `PROJECT_NAME`).
- Variables específicas de una etapa (p. ej. `PROJECT_NGINX_DIR`, `K8S_NODE_PORT`) se documentan en el `.env.example` de esa etapa.
- No introducir variables duplicadas o con nombre distinto para lo mismo entre etapas.

---

## Makefile

- Punto de entrada único: `make <target>`; cada target documentado con `##` para `make help`.
- Targets por etapa con sufijo claro: `-simple`, `-bluegreen`, `-swarm`, `-k8s`.
- Dependencias entre targets explícitas (p. ej. `deploy-k8s: load-image-k8s`); no asumir orden de ejecución implícito.
- Usar variables del Makefile o del `.env` (según el target) para imagen, versión, réplicas, etc., sin hardcodear en comandos.

---

## Estructura por etapa

- Cada etapa en su carpeta bajo `deploy/<etapa>/` con sus propios scripts, compose/stack/k8s y opcionalmente `scripts/`, `docker/`, etc.
- Archivos **generados** por scripts (overrides, patches, ConfigMaps generados, `projects/`) deben estar en **`.gitignore`**.
- No versionar secretos ni `.env` con valores reales; solo `.env.example` como plantilla.

---

## Kubernetes (etapa 3)

- Manifests con Kustomize; nombres de recursos desde `.env` (p. ej. `PROJECT_NAME`, `PROJECT_PREFIX`) vía scripts, no literales fijos.
- ConfigMap(s) generados desde `.env` (+ `ENV_FILE`); un ConfigMap por color (blue/green) para rollback.
- En deploy, no pisar el ConfigMap del color inactivo; en switch con RECREATE=1 solo actualizar el stack destino.
- Si se usa `K8S_IMAGE_PATH`, extraer k8s de la imagen a `deploy/3-kubernetes/projects/PROJECT_NAME` en deploy y en switch RECREATE=1, no en switch simple.

---

## Blue-green (etapas 2 y 3)

- Comportamiento alineado entre Compose y K8s: switch = solo cambiar tráfico; RECREATE = actualizar env/stack destino y luego cambiar tráfico.
- Rollback = volver a hacer switch al otro color sin recrear; el stack inactivo conserva su configuración hasta el siguiente deploy o RECREATE.

---

## Seguridad y buenas prácticas

- No ejecutar contenido del `.env` como código; validar existencia de `.env` (o variables críticas) antes de deploy cuando aplique.
- Rutas a archivos y directorios construidas de forma segura (sin concatenar entrada de usuario sin validar).
- Scripts que usen `docker` o `kubectl` asumen que el entorno está configurado; documentar requisitos en cada README de etapa.

---

## Resumen rápido

| Área              | Regla principal                                                |
|-------------------|-----------------------------------------------------------------|
| Idioma            | Español en comentarios, docs y mensajes                         |
| .env              | Un solo `.env` raíz; parser seguro; no eval/source              |
| Scripts           | Bash, set -euo pipefail; parse-env o equivalente               |
| Makefile          | Targets documentados; sufijos por etapa; variables desde .env   |
| Generados         | En .gitignore (projects/, overrides, patches generados)         |
| Etapas            | Añadir variables sin renombrar; mismas convenciones de nombres |
| app/              | No forma parte del kit; ignorar para estas reglas               |
