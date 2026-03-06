---
name: migrate-stage
description: Asistente interactivo para migrar de una etapa de despliegue a otra. Verifica prerequisitos, adapta .env y guía el proceso.
argument-hint: "[etapa-origen] [etapa-destino] (ej. 1 2, 2 2.5, 2.5 k8s)"
context: fork
agent: general-purpose
---

Guía la migración del despliegue de una etapa a otra indicadas en `$ARGUMENTS`.

## Instrucciones

1. **Parsear argumentos**: Extrae etapa origen y destino. Si falta alguna, pregunta al usuario.

2. **Verificar prerequisitos** del entorno para la etapa destino:

### Prerequisitos por etapa destino
| Etapa destino | Prerequisitos |
|---------------|---------------|
| 1 (Simple Compose) | Docker Engine, Docker Compose v2, red Docker creada |
| 2 (Blue-Green) | Todo de etapa 1 + imagen buildable, HEALTH_PATH definido |
| 2.5 (Swarm) | Docker Swarm inicializado (`docker info \| grep "Swarm: active"`), red overlay |
| K8s | kubectl, kind (o cluster accesible), kustomize, imagen cargable en cluster |

Para cada prerequisito, ejecuta el check correspondiente y reporta PASS/FAIL:
```bash
# Docker
docker --version
docker compose version
# Swarm
docker info 2>/dev/null | grep -q "Swarm: active"
# K8s
kubectl version --client
kind version
kubectl cluster-info 2>/dev/null
```

3. **Analizar `.env` actual**: Lee el `.env` raíz y compara con el `.env.example` de la etapa destino.

4. **Generar plan de migración**:

```
## Plan de migración: Etapa [A] → Etapa [B]

### Prerequisitos
| Check                        | Estado | Acción si falta           |
|------------------------------|--------|---------------------------|
| Docker Engine                | PASS   | -                         |
| Docker Swarm activo          | FAIL   | `docker swarm init`       |
| ...                          | ...    | ...                       |

### Cambios en .env
#### Variables nuevas (añadir)
- `REPLICAS=2` — número de réplicas del servicio
- `UPDATE_DELAY=60s` — delay entre actualizaciones rolling

#### Variables a modificar
- `NETWORK` → considerar `NETWORK_SWARM` para overlay (actualmente bridge)

#### Variables que ya no aplican
- `CONTAINER_IP` — Swarm asigna IPs automáticamente

### Pasos de migración
1. [Preparar entorno: instalar/configurar lo necesario]
2. [Bajar despliegue actual: `make down-<etapa-origen>`]
3. [Actualizar .env con las nuevas variables]
4. [Ejecutar setup de etapa destino si existe]
5. [Desplegar en nueva etapa: `make deploy-<etapa-destino>`]
6. [Verificar: `make status-<etapa-destino>` + smoke test]
7. [Rollback si falla: volver a desplegar en etapa origen]
```

5. **Ejecución guiada**: Presenta el plan completo al usuario y pregunta si quiere:
   - (a) Solo ver el plan (sin ejecutar nada)
   - (b) Ejecutar paso a paso (confirmando cada paso)
   - (c) Ejecutar automáticamente (todos los pasos)

6. **Si el usuario elige ejecutar**:
   - Para cada paso, muestra qué se va a ejecutar y espera confirmación (en modo paso a paso)
   - Tras cada paso, verifica que fue exitoso antes de continuar
   - Si un paso falla, detente e informa al usuario con opciones: reintentar, saltar, abortar
   - Al final, ejecuta el smoke-test para verificar que todo funciona

7. **Precauciones**:
   - Antes de bajar el despliegue actual, confirma con el usuario
   - Si la migración falla a mitad, siempre ofrece volver a la etapa origen
   - No borres archivos de configuración de la etapa origen (podrían necesitarse para rollback)
   - Haz backup del `.env` antes de modificarlo (`cp .env .env.backup.migrate`)
