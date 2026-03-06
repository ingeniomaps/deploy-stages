---
name: generate-ci
description: Genera pipelines CI/CD (GitHub Actions o GitLab CI) para automatizar build, test, push y deploy según la etapa de despliegue.
argument-hint: "[plataforma: github|gitlab] [etapa: 1|2|2.5|k8s]"
context: fork
agent: general-purpose
---

Genera un pipeline CI/CD completo para la plataforma y etapa indicadas en `$ARGUMENTS`.

## Instrucciones

1. **Parsear argumentos**: Extrae plataforma (`github` o `gitlab`) y etapa de `$ARGUMENTS`. Si falta alguno, pregunta al usuario con opciones claras.

2. **Leer contexto del proyecto**: Lee `.env`, el Makefile, y los scripts de la etapa correspondiente para entender las variables, comandos y flujo actual.

3. **Generar pipeline según plataforma y etapa**:

### Estructura común (todas las etapas)

#### Jobs/Stages:
1. **lint**: ShellCheck sobre scripts `.sh` (si la etapa lo amerita)
2. **build**: `docker build` de la imagen
3. **test**: Tests de la aplicación (si hay `test` script en package.json o similar)
4. **push**: Push de la imagen al registry (configurable)
5. **deploy**: Deploy según la etapa
6. **smoke-test**: Health check post-deploy

#### Secretos/variables requeridos:
- `REGISTRY_URL`, `REGISTRY_USER`, `REGISTRY_PASSWORD` (para push)
- `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY` (para etapas 1, 2, 2.5 con deploy remoto)
- Variables del `.env` que sean secretas (detectar `HOST_*`, `ENV_FILE` paths, etc.)

### GitHub Actions

Generar `.github/workflows/deploy.yml` con:
- **Trigger**: `push` a `main`/`master`, manual `workflow_dispatch` con inputs (etapa, acción)
- **Concurrency**: `concurrency: { group: deploy-${{ github.ref }}, cancel-in-progress: false }` (no cancelar deploys en progreso)
- **Jobs**: secuenciales con `needs:` entre ellos
- **Cache**: Docker layer cache con `docker/build-push-action` y `cache-from/cache-to`
- **Health check**: paso final que ejecuta `curl` contra el endpoint de salud

### GitLab CI

Generar `.gitlab-ci.yml` con:
- **Stages**: `lint`, `build`, `test`, `push`, `deploy`, `verify`
- **Rules**: deploy solo en `main`/`master`, manual para rollback
- **Cache**: Docker layer cache
- **Environments**: `production` con `url` y `on_stop` para rollback

### Detalle por etapa

#### Etapa 1 — Simple Compose
```yaml
# Deploy: SSH al servidor, copiar .env, ejecutar make deploy-simple
deploy:
  script:
    - ssh $DEPLOY_USER@$DEPLOY_HOST "cd $REMOTE_APP_DIR && make deploy-simple"
```

#### Etapa 2 — Blue-Green Compose
```yaml
# Deploy: SSH al servidor, ejecutar make deploy-bluegreen
# Rollback: job manual que ejecuta make switch-bluegreen STACK=<anterior>
deploy:
  script:
    - ssh $DEPLOY_USER@$DEPLOY_HOST "cd $REMOTE_APP_DIR && make deploy-bluegreen GREEN=$GREEN BLUE=$BLUE"

rollback:
  when: manual
  script:
    - ssh $DEPLOY_USER@$DEPLOY_HOST "cd $REMOTE_APP_DIR && make switch-bluegreen STACK=$ROLLBACK_STACK"
```

#### Etapa 2.5 — Swarm
```yaml
# Deploy: SSH al nodo manager, ejecutar make deploy-swarm o update-swarm
# Rollback: make rollback-swarm
deploy:
  script:
    - ssh $DEPLOY_USER@$DEPLOY_HOST "cd $REMOTE_APP_DIR && make update-swarm"

rollback:
  when: manual
  script:
    - ssh $DEPLOY_USER@$DEPLOY_HOST "cd $REMOTE_APP_DIR && make rollback-swarm"
```

#### Etapa K8s — Kubernetes
```yaml
# Deploy: kubectl apply desde CI (con kubeconfig como secreto)
# Rollback: kubectl rollout undo o switch al color anterior
deploy:
  script:
    - kubectl apply -k deploy/3-kubernetes/service/
    - bash deploy/3-kubernetes/scripts/blue-green.sh deploy $REPLICAS $REPLICAS

rollback:
  when: manual
  script:
    - bash deploy/3-kubernetes/scripts/blue-green.sh switch
```

4. **Buenas prácticas de seguridad**:
- Nunca hardcodear secretos en el pipeline
- Usar secretos del CI (GitHub Secrets / GitLab CI Variables)
- SSH con clave, no password
- Limitar permisos del token de CI (`contents: read`, `packages: write`)
- Pinear acciones/imágenes por SHA, no por tag mutable

5. **Formato de salida**:

```
## Pipeline CI/CD generado — [plataforma] para Etapa [N]

### Archivos generados
- `.github/workflows/deploy.yml` (o `.gitlab-ci.yml`)

### Secretos/variables a configurar
| Nombre           | Dónde configurar        | Descripción            |
|-----------------|-------------------------|------------------------|
| REGISTRY_URL    | Settings > Secrets      | URL del registry       |
| ...             | ...                     | ...                    |

### Flujo del pipeline
[diagrama ASCII del flujo: lint → build → test → push → deploy → smoke-test]

### Próximos pasos
1. Configurar los secretos en [plataforma]
2. Revisar y ajustar el pipeline generado
3. Hacer push y verificar la primera ejecución
```

6. **Escribir los archivos**: Tras mostrar el contenido generado, pregunta al usuario si quiere que se escriban los archivos. Si confirma, usa Write para crearlos.
