---
name: validate-env
description: Valida que el .env raíz tenga las variables requeridas para la etapa seleccionada, detecta conflictos y verifica formatos.
argument-hint: "[etapa: 0|1|2|2.5|k8s]"
context: fork
agent: general-purpose
---

Valida la configuración del archivo `.env` raíz del proyecto contra la etapa `$ARGUMENTS`.

## Instrucciones

1. **Determinar etapa**: Si `$ARGUMENTS` indica una etapa (`0`, `1`, `2`, `2.5`, `k8s`, `kubernetes`), usa esa. Si está vacío, detecta la etapa analizando qué variables están definidas en `.env` (presencia de `K8S_NODE_PORT` → k8s, `REPLICAS` + `UPDATE_DELAY` → 2.5, `PROJECT_PREFIX` o `NETWORK_NAME` → 2, etc.). Si no puede determinarla, pregunta al usuario.

2. **Leer archivos**: Lee el `.env` raíz y el `.env.example` de la etapa correspondiente:
   - Etapa 0: `deploy/0-manual/.env.example`
   - Etapa 1: `deploy/1-simple-compose/.env.example`
   - Etapa 2: `deploy/2-blue-green-compose/.env.example`
   - Etapa 2.5: `deploy/2.5-swarm/.env.example`
   - K8s: `deploy/3-kubernetes/.env.example`

3. **Validaciones**:

### Variables requeridas (por etapa)
| Etapa | Requeridas |
|-------|-----------|
| 0     | (ninguna obligatoria, todo opcional) |
| 1     | `PROJECT_NAME`, `PROJECT_PORT`, `NETWORK` |
| 2     | `PROJECT_NAME`, `PROJECT_IMAGE`, `PROJECT_VERSION`, `PROJECT_PORT`, `NETWORK` o `NETWORK_DEFAULT`, `HEALTH_PATH` |
| 2.5   | `PROJECT_NAME`, `PROJECT_IMAGE`, `PROJECT_VERSION`, `PROJECT_PORT`, `NETWORK` (o `NETWORK_SWARM`), `HEALTH_PATH` |
| k8s   | `PROJECT_NAME`, `PROJECT_IMAGE`, `PROJECT_VERSION`, `PROJECT_PORT`, `HEALTH_PATH`, `K8S_NODE_PORT` |

### Formato de valores
- `PROJECT_PORT`: entero 1-65535
- `PORTS`: formato `host:container` (ambos enteros 1-65535), puede ser lista separada por comas
- `CONTAINER_IP`: IPv4 válida
- `NETWORK_SUBNET`: CIDR válido (ej. `172.28.0.0/16`)
- `HEALTH_PATH`: debe empezar con `/`
- `K8S_NODE_PORT`: entero 30000-32767
- `REPLICAS`: entero positivo
- `UPDATE_DELAY`: formato duración (`60s`, `2m`, etc.)
- `ENV_FILE`: cada ruta separada por coma debe existir como archivo
- `HOST_*`: formato `hostname:ip` donde ip es IPv4 válida

### Conflictos y coherencia
- Si `CONTAINER_IP` está definido, `NETWORK_SUBNET` debería estarlo y la IP debe caer dentro del rango
- Si `NETWORK_SWARM` está definido en etapa 2.5, verificar que no sea igual a `NETWORK` (bridge vs overlay)
- Si `DOCKER_COMPOSE_APP` está definido, verificar que el archivo existe (resolviendo contra `PROJECT_SOURCE`)
- Si `PROJECT_SOURCE` está definido, verificar que el directorio existe
- Si `PROJECT_NGINX_DIR` está definido (etapa 2), verificar que `PROJECT_IMAGE` también lo está

### Variables huérfanas
- Detectar variables en `.env` que no aparecen en ningún `.env.example` conocido (posibles typos o remanentes)

4. **Formato de salida**:

```
## Validación de .env para Etapa [N]

### Estado: [PASS | WARN | FAIL]

### Variables requeridas
- [VAR]: [valor] ... OK | FALTA | FORMATO INVÁLIDO (detalle)

### Variables opcionales detectadas
- [VAR]: [valor] ... OK | FORMATO INVÁLIDO (detalle)

### Conflictos
- [descripción del conflicto]

### Variables huérfanas
- [VAR]: no reconocida en .env.example de ninguna etapa

### Archivos referenciados
- ENV_FILE=[ruta]: existe | NO EXISTE
- PROJECT_SOURCE=[ruta]: existe | NO EXISTE
- DOCKER_COMPOSE_APP=[ruta]: existe | NO EXISTE
```

5. **No modifiques nada**: Este skill es solo de lectura. Si hay errores, sugiere los cambios pero no los apliques sin confirmación del usuario.
