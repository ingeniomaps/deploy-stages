---
name: smoke-test
description: Test de humo post-deploy. Verifica health checks HTTP, estado de contenedores, conectividad de red y configuración de nginx.
argument-hint: "[etapa: 1|2|2.5|k8s]"
context: fork
agent: general-purpose
---

Ejecuta tests de humo sobre el despliegue activo para verificar que todo funciona correctamente.

## Instrucciones

1. **Detectar etapa activa**: Si `$ARGUMENTS` indica una etapa, usa esa. Si está vacío, detecta automáticamente:
   - Ejecuta `kubectl get deployments 2>/dev/null` — si responde, probablemente es K8s.
   - Ejecuta `docker stack ls 2>/dev/null` — si hay stacks, probablemente es Swarm (2.5).
   - Ejecuta `docker ps --format '{{.Names}}' | grep -E 'blue|green'` — si hay contenedores blue/green, es etapa 2.
   - Si solo hay contenedores simples con el PROJECT_NAME, es etapa 1.
   - Si no hay nada corriendo, informa y detente.

2. **Leer `.env`**: Extrae `PROJECT_NAME`, `PROJECT_PORT`, `PORTS`, `HEALTH_PATH`, `NETWORK`, `REPLICAS` y otras variables necesarias.

3. **Tests por etapa**:

### Etapa 1 — Simple Compose
- **Contenedor corriendo**: `docker ps --filter name=PROJECT_NAME` — verificar estado `Up` y no `Restarting`
- **Health check HTTP**: `curl -sf http://localhost:PUERTO/HEALTH_PATH` (PUERTO = parte host de PORTS, o PROJECT_PORT)
- **Red**: `docker network inspect NETWORK` — verificar que el contenedor está conectado
- **Logs limpios**: `docker logs --tail 20 CONTAINER` — buscar errores/excepciones en las últimas 20 líneas

### Etapa 2 — Blue-Green Compose
- **Nginx corriendo**: `docker ps --filter name=nginx` — verificar estado `Up`
- **Stack activo**: Leer la config nginx activa (`docker exec NGINX cat /etc/nginx/conf.d/default.conf`) para determinar blue o green
- **Contenedores blue**: `docker ps --filter name=app-blue` — verificar estado
- **Contenedores green**: `docker ps --filter name=app-green` — verificar estado
- **Health check via nginx**: `curl -sf http://localhost:PUERTO/HEALTH_PATH`
- **Health check directo blue**: `curl -sf http://CONTAINER_IP_BLUE:PROJECT_PORT/HEALTH_PATH` (si accesible)
- **Health check directo green**: `curl -sf http://CONTAINER_IP_GREEN:PROJECT_PORT/HEALTH_PATH` (si accesible)
- **Nginx config válida**: `docker exec NGINX nginx -t`
- **Red**: Verificar que nginx y ambos stacks están en la misma red

### Etapa 2.5 — Swarm
- **Servicio activo**: `docker service ls --filter name=PROJECT_NAME`
- **Réplicas deseadas vs actuales**: Comparar replicas del servicio
- **Tareas healthy**: `docker service ps PROJECT_NAME_app` — verificar que no hay tareas en estado `Failed` o `Rejected`
- **Health check HTTP**: `curl -sf http://localhost:PUERTO/HEALTH_PATH`
- **Red overlay**: `docker network inspect NETWORK` — verificar tipo `overlay`
- **Rolling update status**: Verificar que no hay update en progreso

### Etapa K8s — Kubernetes
- **Deployments**: `kubectl get deployments -l app=PROJECT_NAME` — verificar READY = DESIRED
- **Pods**: `kubectl get pods -l app=PROJECT_NAME` — todos en estado `Running` y `Ready`
- **Service**: `kubectl get service PROJECT_NAME` — verificar selector activo (blue o green)
- **Health check HTTP**: `curl -sf http://localhost:NODE_PORT/HEALTH_PATH`
- **Events**: `kubectl get events --sort-by=.lastTimestamp` — buscar Warnings recientes
- **ConfigMap**: `kubectl get configmap PROJECT_NAME-config` — verificar que existe

4. **Formato de salida**:

```
## Smoke Test — Etapa [N]
Fecha: [timestamp]

### Resultado global: [PASS | FAIL | DEGRADED]

### Tests ejecutados
| # | Test                    | Resultado | Detalle              |
|---|-------------------------|-----------|----------------------|
| 1 | Contenedor corriendo    | PASS      | Up 2 hours (healthy) |
| 2 | Health check HTTP       | PASS      | 200 OK (45ms)        |
| 3 | Red configurada         | PASS      | my-network: connected|
| ...                                                           |

### Fallos detectados
[detalle de cada test fallido con el output real del comando]

### Warnings
[tests que pasaron pero con señales de alerta: restarts > 0, latencia alta, logs con warnings]

### Recomendaciones
[acciones sugeridas para resolver fallos o warnings]
```

5. **No modifiques nada**: Este skill es solo de lectura y diagnóstico. Si detecta problemas, sugiere los comandos correctivos pero no los ejecutes sin confirmación del usuario.
