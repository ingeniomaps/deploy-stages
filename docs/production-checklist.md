# Checklist de producción

Verificaciones recomendadas antes de llevar el framework a
producción.

## Seguridad

- [ ] Secretos fuera del repositorio (Vault, Secrets Manager,
      variables de CI)
- [ ] `.env` en `.gitignore` (no comitear valores reales)
- [ ] TLS terminado en el proxy (Let's Encrypt, cloud LB)
- [ ] Renovación automática de certificados
- [ ] Headers de seguridad en nginx (`X-Content-Type-Options`,
      `X-Frame-Options`, `server_tokens off`)
- [ ] Escaneo de vulnerabilidades en imágenes (Trivy, Snyk)
- [ ] Permisos mínimos en contenedores (no ejecutar como root
      en producción)

## Observabilidad

- [ ] Logs centralizados (ELK, Loki, cloud logging)
- [ ] Formato de logs estructurado (JSON)
- [ ] Métricas de CPU, memoria, latencia, error rate
- [ ] Alertas configuradas (error rate > X, latencia p99 > Y)
- [ ] Tracing distribuido si hay múltiples servicios

## Despliegue

- [ ] Health checks configurados en la app y en el proxy
- [ ] Rollback probado y documentado (`make switch-bluegreen
      STACK=blue` o `make rollback-swarm`)
- [ ] Tiempo de rollback < 5 minutos
- [ ] Pipeline CI/CD que ejecute tests antes del deploy
- [ ] Entorno de staging con configuración similar a producción

## Estabilidad

- [ ] Límites de CPU y memoria en contenedores
- [ ] Rotación de logs configurada (`json-file` con `max-size`
      y `max-file`)
- [ ] App stateless (sesión en Redis/DB, no en memoria)
- [ ] Restart policy configurado (`always` o `on-failure`)

## Datos

- [ ] Backups automáticos de bases de datos
- [ ] Pruebas periódicas de restauración
- [ ] Estrategia de DR documentada si el SLA lo requiere

## Operación

- [ ] Runbooks para deploy, rollback e incidentes
      (generar con `/generate-runbook`)
- [ ] Diagrama de arquitectura actualizado
- [ ] Decisiones de diseño documentadas
