---
name: debug-deploy
description: Diagnóstico completo de un despliegue fallido o degradado. Recopila logs, estado, health checks, red y configuración.
argument-hint: "[etapa: 1|2|2.5|k8s] [síntoma opcional]"
context: fork
agent: general-purpose
---

Diagnostica un problema de despliegue recopilando toda la información relevante del sistema.

## Instrucciones

1. **Detectar etapa**: Igual que en smoke-test: usa `$ARGUMENTS` o auto-detecta. Si el usuario describe un síntoma (ej. "502", "no arranca", "health fail"), anótalo para priorizar la investigación.

2. **Recopilación de datos** (solo comandos de lectura):

### Etapa 1 — Simple Compose
```bash
# Estado de contenedores
docker ps -a --filter "name=PROJECT_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.State}}"
# Logs del contenedor (últimas 100 líneas)
docker logs --tail 100 CONTAINER_NAME
# Inspección del contenedor (health, restart count, exit code)
docker inspect CONTAINER_NAME --format '{{json .State}}'
# Red
docker network inspect NETWORK
# Variables de entorno efectivas
docker inspect CONTAINER_NAME --format '{{json .Config.Env}}'
# Overlay generado
cat deploy/1-simple-compose/docker-compose.override.yml
```

### Etapa 2 — Blue-Green Compose
```bash
# Todo lo de etapa 1, más:
# Estado de nginx
docker ps -a --filter "name=nginx"
docker logs --tail 50 NGINX_CONTAINER
# Config nginx activa
docker exec NGINX_CONTAINER cat /etc/nginx/conf.d/default.conf
# Test de config nginx
docker exec NGINX_CONTAINER nginx -t
# Snippet del proyecto
docker exec NGINX_CONTAINER cat /etc/nginx/conf.d/project-snippet.conf
# Estado de ambos stacks (blue y green)
docker ps -a --filter "name=app-blue"
docker ps -a --filter "name=app-green"
# Logs de app-blue y app-green
docker logs --tail 50 APP_BLUE_CONTAINER
docker logs --tail 50 APP_GREEN_CONTAINER
# Health checks directos
curl -sf http://localhost:PUERTO/HEALTH_PATH -w "\nHTTP %{http_code} (%{time_total}s)\n"
# Archivos generados
cat deploy/2-blue-green-compose/docker/docker-compose.override.yml
cat deploy/2-blue-green-compose/docker/docker-compose.env-include-blue.yml
cat deploy/2-blue-green-compose/docker/docker-compose.env-include-green.yml
cat deploy/2-blue-green-compose/docker/docker-compose.extra-hosts-blue.yml
cat deploy/2-blue-green-compose/docker/docker-compose.extra-hosts-green.yml
```

### Etapa 2.5 — Swarm
```bash
# Estado del servicio
docker service ls --filter "name=PROJECT_NAME"
docker service ps PROJECT_NAME_app --no-trunc
# Tareas fallidas (historial)
docker service ps PROJECT_NAME_app --filter "desired-state=shutdown" --no-trunc
# Logs del servicio
docker service logs --tail 100 PROJECT_NAME_app
# Inspección del servicio (config, update status)
docker service inspect PROJECT_NAME_app --pretty
# Red overlay
docker network inspect NETWORK
# Env generado
cat deploy/2.5-swarm/docker-stack.env-include.yml
# Backups
ls -la deploy/2.5-swarm/backup/ deploy/2.5-swarm/backup_prev/ 2>/dev/null
```

### Etapa K8s — Kubernetes
```bash
# Pods
kubectl get pods -l app=PROJECT_NAME -o wide
kubectl describe pods -l app=PROJECT_NAME
# Deployments
kubectl get deployments -l app=PROJECT_NAME
kubectl describe deployment PROJECT_NAME-blue PROJECT_NAME-green
# Service
kubectl get service PROJECT_NAME -o yaml
# Events (últimos 50)
kubectl get events --sort-by=.lastTimestamp --field-selector type=Warning | tail -50
# Logs de pods problemáticos
kubectl logs -l app=PROJECT_NAME --tail=50 --all-containers
# ConfigMap
kubectl get configmap PROJECT_NAME-config -o yaml
# Node status (Kind)
kubectl get nodes -o wide
```

3. **Análisis del síntoma**: Tras recopilar datos, analiza según patrones conocidos:

| Síntoma | Posibles causas | Dónde mirar |
|---------|----------------|-------------|
| 502 Bad Gateway | App no arrancó, upstream caído | Logs nginx, logs app, health check directo |
| Container restarting | OOM, crash en startup, health fail | `docker inspect .State`, logs, exit code |
| Health check timeout | App lenta, ruta incorrecta, puerto mal | HEALTH_PATH correcto, PROJECT_PORT correcto, curl directo |
| Network unreachable | Red no creada, contenedor en red incorrecta | `docker network inspect`, redes del contenedor |
| Image not found | No se hizo build, tag incorrecto | `docker images`, PROJECT_IMAGE/PROJECT_VERSION |
| Swarm task rejected | Recursos insuficientes, imagen no disponible | `docker service ps --no-trunc`, `docker node ls` |
| K8s CrashLoopBackOff | App falla al arrancar, config incorrecta | `kubectl logs`, `kubectl describe pod`, ConfigMap |
| K8s ImagePullBackOff | Imagen no cargada en Kind, registry inaccesible | `kind load`, `kubectl describe pod` |

4. **Formato de salida**:

```
## Diagnóstico de Despliegue — Etapa [N]
Fecha: [timestamp]
Síntoma reportado: [si lo hay]

### Diagnóstico: [CAUSA RAÍZ IDENTIFICADA | INVESTIGACIÓN NECESARIA]

### Estado actual del sistema
[resumen del estado: qué está corriendo, qué no, qué errores hay]

### Causa probable
[explicación de la causa raíz basada en los datos recopilados]

### Evidencia
[logs relevantes, estados, errores específicos que soportan el diagnóstico]

### Solución recomendada
[pasos concretos para resolver, con comandos exactos]

### Datos completos recopilados
[toda la salida de los comandos ejecutados, colapsable]
```

5. **Solo lectura**: No ejecutes acciones correctivas sin aprobación del usuario. Presenta el diagnóstico y espera confirmación antes de actuar.
