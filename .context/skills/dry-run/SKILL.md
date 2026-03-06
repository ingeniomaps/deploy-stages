---
name: dry-run
description: Simula un despliegue sin ejecutarlo. Muestra qué overlays se generarían, qué imagen se construiría y qué comandos se ejecutarían.
argument-hint: "[etapa: 1|2|2.5|k8s] [acción: deploy|switch|update|rollback]"
context: fork
agent: general-purpose
---

Simula un despliegue para la etapa y acción indicadas en `$ARGUMENTS` sin ejecutar ningún comando destructivo.

## Instrucciones

1. **Parsear argumentos**: Extrae etapa y acción de `$ARGUMENTS`. Si falta alguno, pregunta al usuario. Acciones válidas:
   - Etapa 1: `deploy`, `down`
   - Etapa 2: `deploy`, `switch`, `down`
   - Etapa 2.5: `deploy`, `update`, `rollback`, `scale`, `down`
   - K8s: `deploy`, `switch`, `down`

2. **Leer `.env`**: Lee el `.env` raíz y extrae todas las variables relevantes para la etapa.

3. **Simular por etapa**:

### Etapa 1 — Simple Compose
- Mostrar el `docker build` que se ejecutaría (imagen, tag, contexto, Dockerfile)
- Leer `deploy/1-simple-compose/scripts/generate-extra-hosts.sh` y simular qué `docker-compose.override.yml` generaría con las variables actuales
- Listar los compose files que se combinarían (`-f` flags)
- Mostrar el comando `docker-compose up -d` final completo
- Si hay `DOCKER_COMPOSE_APP`, leer ese archivo y mostrar qué servicios/overrides añade

### Etapa 2 — Blue-Green Compose
- Simular qué archivos generarían los scripts:
  - `generate-nginx-override.sh` → `docker-compose.override.yml`
  - `generate-extra-hosts.sh` → `docker-compose.extra-hosts-blue.yml` / `green.yml`
  - `generate-env-file-include.sh` → `docker-compose.env-include-blue.yml` / `green.yml`
  - `generate-extra-networks.sh` → `docker-compose.extra-networks.yml`
- Mostrar la configuración nginx que se generaría (upstream blocks, servidor activo)
- Si acción=deploy: mostrar el flujo completo (build → start inactive → health check → switch)
- Si acción=switch: mostrar qué cambiaría en la config nginx

### Etapa 2.5 — Swarm
- Simular `generate-env-file-include.sh` → `docker-stack.env-include.yml`
- Mostrar el comando `docker stack deploy` con todos los `-c` flags
- Mostrar las variables de entorno que se inyectarían al servicio
- Si acción=rollback: mostrar qué archivos se restaurarían de `backup_prev/`
- Mostrar la configuración del rolling update (parallelism, delay, order)

### Etapa K8s — Kubernetes
- Simular `generate-configmap.sh` → mostrar el ConfigMap que se generaría
- Mostrar los kustomization.yaml que se usarían (con imagen, réplicas, patches)
- Para cada overlay (blue, green): mostrar el `kubectl apply -k` resultante
- Si acción=switch: mostrar el `kubectl patch service` que cambiaría el selector

4. **Verificaciones previas** (sin ejecutar):
- Verificar que los archivos referenciados existen (Dockerfiles, compose files, env files)
- Verificar que las redes Docker mencionadas existen (`docker network ls`)
- Verificar que la imagen referenciada existe localmente (`docker images`)
- Para K8s: verificar que el cluster Kind/K8s está accesible (`kubectl cluster-info`)

5. **Formato de salida**:

```
## Dry Run — Etapa [N]: [acción]

### Variables de entorno
| Variable        | Valor          |
|-----------------|----------------|
| PROJECT_NAME    | mi-aplicacion  |
| ...             | ...            |

### Verificaciones previas
- [check]: [PASS | MISSING | WARNING]

### Archivos que se generarían
#### [nombre-archivo]
```yaml
[contenido simulado]
```

### Comandos que se ejecutarían (en orden)
1. `docker build -f ... -t ... .`
2. `docker-compose -f ... -f ... up -d`
3. ...

### Diagrama de flujo
[descripción paso a paso de lo que ocurriría]
```

6. **NUNCA ejecutes comandos destructivos**: No hagas `docker build`, `docker-compose up`, `docker stack deploy`, `kubectl apply`, ni ningún comando que modifique estado. Solo usa comandos de lectura (`docker ps`, `docker network ls`, `docker images`, `kubectl get`, `cat`, etc.).
