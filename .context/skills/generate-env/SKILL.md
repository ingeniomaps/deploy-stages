---
name: generate-env
description: Genera interactivamente un archivo .env completo para la etapa seleccionada, preguntando por cada variable y validando valores.
argument-hint: "[etapa: 0|1|2|2.5|k8s]"
context: fork
agent: general-purpose
---

Genera un archivo `.env` completo para la etapa indicada en `$ARGUMENTS`, preguntando interactivamente por cada variable.

## Instrucciones

1. **Determinar etapa**: Si `$ARGUMENTS` indica una etapa, usa esa. Si está vacío, pregunta al usuario qué etapa quiere configurar, con una breve descripción de cada una:
   - 0: Manual (sin Docker)
   - 1: Simple Compose (un contenedor)
   - 2: Blue-Green Compose (dos stacks + nginx)
   - 2.5: Docker Swarm (réplicas, rolling update)
   - k8s: Kubernetes (blue-green con Kind)

2. **Leer `.env.example`** de la etapa seleccionada y el `.env` actual (si existe) para usar valores actuales como defaults.

3. **Agrupar variables** por categoría y preguntar al usuario grupo por grupo usando AskUserQuestion cuando sea posible, o presentando los valores por defecto y pidiendo confirmación:

### Grupo 1: Proyecto (todas las etapas)
- `PROJECT_NAME`: nombre de la app (default: nombre del directorio del proyecto)
- `PROJECT_IMAGE`: nombre de la imagen Docker (default: igual que PROJECT_NAME)
- `PROJECT_VERSION`: tag de la imagen (default: `latest`)
- `PROJECT_PORT`: puerto interno de la app (default: detectar del Dockerfile si existe)
- `PROJECT_SOURCE`: ruta al código fuente (default: vacío = raíz del repo)
- `DOCKERFILE_PATH`: ruta al Dockerfile (default: `Dockerfile`)

### Grupo 2: Red (etapas 1+)
- `NETWORK`: nombre de la red Docker (default: `my-network`)
- `NETWORK_SUBNET`: CIDR del subnet (default: vacío)
- `CONTAINER_IP`: IP fija (default: vacío)
- `NETWORK_NAME`: redes adicionales para nginx (default: vacío, solo etapa 2)
- `NETWORK_SWARM`: overlay network (default: vacío, solo etapa 2.5)

### Grupo 3: Exposición (etapas 1+)
- `PORTS`: mapeo host:container (default: `PROJECT_PORT:PROJECT_PORT`)
- `HEALTH_PATH`: endpoint de health (default: `/health`)

### Grupo 4: Env y hosts (etapas 1+)
- `ENV_FILE`: archivos .env adicionales (default: vacío)
- `HOST_*`: hosts extra (preguntar si necesita alguno)

### Grupo 5: Etapa específica
- Etapa 2: `PROJECT_PREFIX`, `NETWORK_DEFAULT`, `PROJECT_NGINX_DIR`
- Etapa 2.5: `REPLICAS`, `UPDATE_DELAY`
- K8s: `K8S_NODE_PORT`, `REPLICAS`

4. **Validar cada valor** según las reglas de validate-env:
   - Puertos: entero 1-65535
   - IPs: formato IPv4 válido
   - CIDR: formato válido
   - Rutas: verificar existencia si es posible
   - K8S_NODE_PORT: 30000-32767
   Si un valor es inválido, informar y pedir corrección.

5. **Generar el archivo .env**:
   - Incluir comentarios descriptivos para cada sección
   - Variables requeridas sin comentar
   - Variables opcionales no definidas comentadas con su descripción
   - Mantener el formato del `.env.example` como referencia

6. **Formato de salida**:

```
## .env generado para Etapa [N]

```env
# [contenido completo del .env generado]
```

### Validación
- Variables requeridas: [todas presentes]
- Formatos: [todos válidos]
- Archivos referenciados: [todos existen / algunos faltantes]
```

7. **Escribir el archivo**: Pregunta al usuario si quiere:
   - (a) Escribir como `.env` en la raíz (sobrescribe el actual)
   - (b) Escribir como `.env.new` para revisar antes
   - (c) Solo mostrar (no escribir)

   Si ya existe `.env`, haz backup automático como `.env.backup` antes de sobrescribir.
