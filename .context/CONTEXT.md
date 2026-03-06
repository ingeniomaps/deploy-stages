# CONTEXT.md — Mapa para la IA

Este archivo define **cómo debe actuar la IA** en este repositorio: qué es el proyecto, qué tocar y qué no, dónde buscar y qué convenciones seguir. Se basa en `CLAUDE.md` y en el resto del proyecto.

---

## 1. Qué es este proyecto

- **Kit de despliegue evolutivo** (framework) para aplicaciones Docker.
- **No es** una aplicación de producto: es la herramienta que despliega aplicaciones en varias etapas (manual → Compose → blue-green → Swarm → Kubernetes) con un único `.env` y un único punto de entrada (`make`).
- **Referencia principal:** `CLAUDE.md` en la raíz (resumen del proyecto, etapas, estructura, comandos).

**Documentos en `.context/` que debes usar:**

| Archivo | Uso para la IA |
|---------|-----------------|
| **business.md** | Entender qué problema resuelve el producto, a quién va dirigido y qué ofrece (etapas, .env único, blue-green, artifact). |
| **rules.md** | Reglas de código: idioma (español), .env (parser seguro), scripts (Bash), Makefile, qué incluir/excluir. **Aplicar en cambios de código del kit.** |
| **architecture.md** | Diagramas y flujos: etapas, .env → etapas, blue-green, K8s (Service, ConfigMaps, HPA), deploy/switch, extracción desde imagen. **Consultar para diseño o dudas de flujo.** |
| **CONTEXT.md** (este) | Mapa de actuación: qué tocar, qué ignorar, dónde buscar, cómo responder. |

---

## 2. Alcance: qué incluir y qué ignorar

### Incluir (kit de despliegue)

- **Raíz:** `Makefile`, `.env.example`, `CLAUDE.md`, `docs/`, `rules.md` (si existe en raíz; si no, `.context/rules.md`).
- **deploy/:** Todas las etapas (`0-manual/`, `1-simple-compose/`, `2-blue-green-compose/`, `2.5-swarm/`, `3-kubernetes/`) con sus scripts, compose/stack/k8s, README y `.env.example`.
- **deploy/scripts/lib/:** Parser y utilidades compartidas (p. ej. `parse-env.sh`).
- **.context/:** `business.md`, `rules.md`, `architecture.md`, `CONTEXT.md`, y skills en `.context/skills/` cuando apliquen.

Al modificar el kit (nuevas variables, nuevos targets, cambios en etapas), mantener **consistencia entre etapas**: mismo significado de variables, convenciones de nombres, y comportamiento blue-green alineado (Compose y K8s).

### Ignorar o tratar como demo

- **`app/`** — Aplicación **demo** para probar el framework. No forma parte del kit. Las reglas de código de `rules.md` no aplican a `app/`; si el usuario pide cambios en la app, se pueden hacer, pero no son el foco del proyecto. El kit está pensado para desplegar **cualquier** imagen Docker, no solo la de `app/`.
- Archivos generados (en `.gitignore`): `projects/`, overrides, patches generados por scripts. No versionar ni asumir que existen en el repo.

---

## 3. Dónde buscar según la tarea

| Si la tarea es… | Buscar en… |
|-----------------|------------|
| Añadir o cambiar una variable de entorno | `.env.example` de la etapa correspondiente, `parse-env.sh` o script que lea .env, y `rules.md` (no renombrar entre etapas). |
| Añadir o cambiar un target del Makefile | `Makefile` (documentar con `##` para `make help`); dependencias entre targets; variables desde .env cuando aplique. |
| Cambiar el flujo de deploy/switch (Compose o K8s) | Script principal de la etapa (p. ej. `deploy/2-blue-green-compose/scripts/blue-green.sh`, `deploy/3-kubernetes/scripts/blue-green.sh`) y `architecture.md` para no romper el flujo. |
| Cambios en Kubernetes (ConfigMaps, HPA, overlays) | `deploy/3-kubernetes/` (base, overlays, service, scripts); no pisar ConfigMap inactivo en deploy; RECREATE solo en switch RECREATE=1. |
| Documentación o README | README de la etapa; idioma español; rutas actuales (p. ej. `deploy/2-blue-green-compose/`). |
| Validar .env, CI, runbook, seguridad, etc. | Skills en `.context/skills/` (validate-env, generate-ci, generate-runbook, security-audit, etc.); usar cuando el usuario lo pida o sea relevante. |
| Entender el negocio o el valor del producto | `business.md` y `CLAUDE.md`. |

---

## 4. Cómo responder y proponer cambios

1. **Idioma:** Respuestas y comentarios en **español** (salvo nombres técnicos o código).
2. **Consistencia:** Al cambiar una etapa, comprobar que no se rompe la convención de variables compartidas ni el comportamiento blue-green (switch vs RECREATE vs rollback). Ver `rules.md` y `architecture.md`.
3. **Seguridad del .env:** No usar `source .env` ni `eval` sobre contenido de usuario; usar el parser seguro (`parse-env.sh` o equivalente por etapa). Ver `rules.md`.
4. **Makefile:** Targets documentados con `##`; sufijos por etapa (`-simple`, `-bluegreen`, `-swarm`, `-k8s`); no hardcodear imagen/versión en comandos.
5. **Generados:** Lo que generen los scripts (projects/, configmaps generados, etc.) no se versiona; debe estar en `.gitignore`.
6. **app/:** Si el usuario pide cambios en la app demo, hacerlos; si la petición es ambigua, priorizar el **kit** (deploy/) y mencionar que `app/` es solo demo.

---

## 5. Resumen rápido para la IA

- **Proyecto:** Kit de despliegue evolutivo (0 → 1 → 2 → 2.5 → 3); un `.env`, un `make`.
- **No confundir:** El “producto” es el **kit**; `app/` es demo y se puede ignorar para reglas del kit.
- **Antes de tocar código del kit:** Revisar `rules.md` y, si afecta flujos, `architecture.md`.
- **Referencia raíz:** `CLAUDE.md`.
- **Contexto de negocio:** `business.md`.
- **Skills:** `.context/skills/` para validate-env, smoke-test, diff-stages, generate-env, security-audit, add-project, code-review, dry-run, generate-runbook, generate-ci, debug-deploy, shellcheck-all, migrate-stage; usarlos cuando encajen con la petición del usuario.
