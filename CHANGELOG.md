# Changelog

Todos los cambios relevantes de este proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es/1.1.0/).

## [1.0.0] - 2026-03-05

### Agregado

- Etapa 0: ejecución directa sin Docker.
- Etapa 1: despliegue con un contenedor usando Docker Compose.
- Etapa 2: blue-green con Compose + Nginx (switch, rollback, RECREATE).
- Etapa 2.5: Docker Swarm con rolling updates, escalado y rollback.
- Etapa 3: Kubernetes con Kind + Kustomize (blue-green, HPA, ConfigMaps por color).
- `.env` compartido como única fuente de verdad para todas las etapas.
- `parse-env.sh`: parser seguro de `.env` sin eval/source.
- `Makefile` como punto de entrada único (`make help`).
- Documentación por etapa con README y `.env.example`.
- Docs de arquitectura, integración de proyectos y checklist de producción.
