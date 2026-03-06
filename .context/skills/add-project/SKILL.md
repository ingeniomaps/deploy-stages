---
name: add-project
description: Guía para integrar una nueva aplicación al framework de despliegue. Configura .env, snippet nginx, ENV_FILE y valida la integración.
argument-hint: "[ruta-al-proyecto] [etapa: 1|2|2.5|k8s]"
context: fork
agent: general-purpose
---

Integra una nueva aplicación al framework de despliegue según `$ARGUMENTS`.

## Instrucciones

1. **Parsear argumentos**: Extrae la ruta al proyecto y la etapa objetivo. Si faltan, pregunta al usuario.

2. **Analizar el proyecto fuente**: Lee los archivos clave del proyecto a integrar:
   - `Dockerfile` (o variantes: `Dockerfile.prod`, `docker/Dockerfile`)
   - `docker-compose*.yml` (si existen)
   - `package.json`, `Gemfile`, `requirements.txt`, `go.mod` (para detectar el tipo de app)
   - `.env`, `.env.example` (variables del proyecto)
   - Archivos nginx si existen (para snippet)
   - Directorio `k8s/` si existe (para patches K8s)
   - `HEALTH_PATH` — buscar endpoint de health en el código (ej. `/health`, `/healthz`, `/api/health`)

3. **Detectar configuración automáticamente**:
   - **Puerto**: Del `EXPOSE` en Dockerfile, o del `ports:` en compose, o del framework (3000 para Node, 8080 para Go, 5000 para Python, etc.)
   - **Health endpoint**: Buscar rutas de health en el código fuente
   - **Comando de inicio**: Del `CMD` en Dockerfile o `command:` en compose
   - **Variables de entorno**: Del `.env.example` del proyecto o `environment:` en compose
   - **Volúmenes**: Del compose del proyecto (si aplica)
   - **Snippet nginx**: Si el proyecto tiene configuración nginx custom (WebSocket, streaming, static files, etc.)

4. **Generar configuración**:

### .env
Generar un `.env` completo para el proyecto basándose en el `.env.example` de la etapa destino, rellenando:
- `PROJECT_NAME`: nombre del directorio o del `name` en package.json
- `PROJECT_IMAGE`: igual que PROJECT_NAME (o el nombre de imagen si ya tiene una)
- `PROJECT_VERSION`: `latest` o el tag del Dockerfile
- `PROJECT_PORT`: puerto detectado
- `PROJECT_SOURCE`: ruta al proyecto
- `DOCKERFILE_PATH`: ruta relativa al Dockerfile dentro del proyecto
- `HEALTH_PATH`: endpoint detectado
- `ENV_FILE`: si el proyecto tiene su propio `.env`, incluirlo
- Otras variables según la etapa

### Snippet nginx (etapa 2)
Si el proyecto necesita configuración nginx especial, generar `snippet.conf`:
```nginx
# Ejemplo para WebSocket
location /ws {
    proxy_pass http://app_active;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

# Ejemplo para archivos estáticos
location /static/ {
    alias /app/static/;
    expires 30d;
    add_header Cache-Control "public, immutable";
}
```

### Docker Compose override (etapa 1)
Si el proyecto tiene un `docker-compose.yml` propio con servicios adicionales (DB, Redis, etc.), señalar que puede usarse como `DOCKER_COMPOSE_APP`.

### Patches K8s (etapa k8s)
Si el proyecto tiene manifiestos K8s propios, señalar cómo integrarlos vía `K8S_PROJECT_DIR`.

5. **Validación**: Tras generar la configuración:
   - Verificar que el Dockerfile existe y es buildable (sin ejecutar build)
   - Verificar que las rutas referenciadas existen
   - Verificar que el puerto no conflicta con otros proyectos en la misma red
   - Ejecutar mentalmente un dry-run del deploy

6. **Formato de salida**:

```
## Integración de [nombre-proyecto] — Etapa [N]

### Proyecto detectado
| Aspecto      | Valor                    |
|--------------|--------------------------|
| Tipo         | Node.js / Python / Go    |
| Puerto       | 3000                     |
| Health       | /health                  |
| Dockerfile   | Dockerfile               |
| Compose      | docker-compose.dev.yml   |

### Archivos a generar/modificar

#### .env (raíz del repo blue-green)
```env
PROJECT_NAME=nuevo-proyecto
PROJECT_IMAGE=nuevo-proyecto
...
```

#### snippet.conf (si aplica)
```nginx
...
```

### Pasos para completar la integración
1. Copiar/crear el .env mostrado arriba
2. [paso adicional según etapa]
3. `make deploy-<etapa>`
4. `make status-<etapa>`

### Advertencias
[conflictos de puerto, variables faltantes, etc.]
```

7. **Escribir archivos**: Tras presentar el plan, pregunta al usuario si quiere que se generen los archivos. Si confirma, escríbelos.
