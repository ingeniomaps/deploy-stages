---
name: generate-runbook
description: Genera runbooks operativos para escenarios específicos (deploy, rollback, incident, escalado, backup). Incluye comandos, decisiones y escalación.
argument-hint: "[escenario: deploy|rollback|incident|scale|backup|all] [etapa: 1|2|2.5|k8s]"
context: fork
agent: general-purpose
---

Genera documentación operativa (runbook) para el escenario y etapa indicados en `$ARGUMENTS`.

## Instrucciones

1. **Parsear argumentos**: Extrae escenario y etapa. Escenarios válidos: `deploy`, `rollback`, `incident`, `scale`, `backup`, `all`. Si `$ARGUMENTS` es vacío o `all`, genera todos los runbooks.

2. **Leer contexto**: Lee el `.env` raíz, el Makefile, los scripts de la etapa, y `docs/production-checklist.md` para entender la configuración actual.

3. **Generar runbook(s)**: Cada runbook sigue esta estructura:

```markdown
# Runbook: [Nombre del escenario]
**Etapa**: [N] — [nombre de la etapa]
**Última actualización**: [fecha]
**Autor**: Generado automáticamente

## Cuándo usar este runbook
[Situaciones que disparan este procedimiento]

## Prerequisitos
- [ ] Acceso SSH al servidor / kubeconfig configurado
- [ ] .env configurado correctamente
- [ ] [otros prerequisitos]

## Procedimiento

### Paso 1: [nombre del paso]
**Qué hace**: [explicación]
**Comando**:
```bash
[comando exacto]
```
**Resultado esperado**: [qué deberías ver]
**Si falla**: [qué hacer]

### Paso 2: ...
[...]

## Verificación
- [ ] Health check responde 200: `curl -sf http://HOST:PORT/HEALTH_PATH`
- [ ] Contenedores en estado healthy: `docker ps`
- [ ] [otras verificaciones]

## Rollback
[Cómo revertir si algo sale mal durante este procedimiento]

## Contactos de escalación
- Nivel 1: [operador]
- Nivel 2: [desarrollador senior]
- Nivel 3: [arquitecto/SRE]
```

4. **Escenarios específicos**:

### Deploy
- Paso a paso desde build hasta verificación
- Incluir pre-checks (espacio en disco, red, imagen)
- Incluir post-checks (health, logs limpios, métricas)

### Rollback
- Cuándo activar rollback (criterios claros)
- Procedimiento según etapa:
  - Etapa 2: `make switch-bluegreen STACK=<anterior>`
  - Etapa 2.5: `make rollback-swarm`
  - K8s: `kubectl rollout undo` o switch de servicio
- Tiempo máximo aceptable (SLO)
- Verificación post-rollback

### Incident Response
- Triage: cómo identificar qué está mal
- Clasificación: P1 (servicio caído), P2 (degradado), P3 (warning)
- Comandos de diagnóstico rápido por etapa
- Árbol de decisión: escenario → acción
- Comunicación: qué informar y a quién

### Scale (escalado)
- Cuándo escalar (métricas de CPU, memoria, latencia)
- Cómo escalar según etapa:
  - Etapa 2: `GREEN=N BLUE=M make deploy-bluegreen`
  - Etapa 2.5: `make scale-swarm REPLICAS=N`
  - K8s: `kubectl scale deployment` o modificar REPLICAS
- Verificar que el escalado fue efectivo
- Cómo volver a la escala original

### Backup
- Qué respaldar: `.env`, `backup/`, `backup_prev/`, datos de volúmenes
- Frecuencia recomendada
- Cómo restaurar desde backup
- Verificar integridad del backup

5. **Formato de salida**:
   - Si `$ARGUMENTS` es `all`: genera un documento consolidado con todos los runbooks
   - Si es un escenario específico: genera solo ese runbook
   - Usa Markdown con checkboxes para pasos verificables

6. **Escritura**: Pregunta al usuario si quiere guardar los runbooks en `docs/runbooks/`. Si confirma, crea los archivos:
   - `docs/runbooks/deploy.md`
   - `docs/runbooks/rollback.md`
   - `docs/runbooks/incident-response.md`
   - `docs/runbooks/scaling.md`
   - `docs/runbooks/backup.md`
