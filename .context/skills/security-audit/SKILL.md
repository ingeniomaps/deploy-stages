---
name: security-audit
description: Auditoría de seguridad de la infraestructura de despliegue. Revisa secretos, privilegios, redes, puertos, TLS y configuración.
argument-hint: "[ruta-o-etapa opcional]"
context: fork
agent: general-purpose
---

Ejecuta una auditoría de seguridad sobre la infraestructura de despliegue del proyecto.

## Instrucciones

1. **Alcance**: Si `$ARGUMENTS` indica una etapa o ruta, limita el análisis. Si está vacío, audita todo el proyecto (excluyendo `./app` y `./copy`).

2. **Categorías de auditoría**:

### 2.1 Secretos y credenciales
- **Buscar en archivos**: Usa Grep para buscar patrones de secretos en todos los archivos del proyecto:
  - Passwords: `password`, `passwd`, `secret`, `token`, `api_key`, `apikey`
  - Credenciales hardcodeadas: strings que parecen tokens (base64 largo, hex largo, JWT)
  - Claves privadas: `BEGIN.*PRIVATE KEY`, `BEGIN RSA`
- **`.env` raíz vs `.env.example`**: Verificar que `.env` no está en git (`git ls-files .env`). Si lo está, es CRITICO.
- **`.gitignore`**: Verificar que `.env`, `*.pem`, `*.key`, `backup/`, `backup_prev/` están ignorados
- **Imágenes Docker**: Verificar que no hay `COPY .env` o `ADD .env` en Dockerfiles
- **Backup de env**: `deploy/2.5-swarm/backup/` y `backup_prev/` pueden contener secretos — verificar que están en `.gitignore`

### 2.2 Contenedores y privilegios
- **Usuario root**: Buscar en compose files si hay `user:` definido. Sin él, los contenedores corren como root.
- **Privilegios**: Buscar `privileged: true`, `cap_add`, `security_opt` en compose/stack files
- **Read-only filesystem**: Verificar si algún compose usa `read_only: true` (recomendado)
- **Límites de recursos**: Buscar `deploy.resources.limits` en compose/stack, `resources.limits` en K8s
- **Imagen base**: Verificar si se usa `:latest` en producción (compose, stack, K8s)

### 2.3 Red y exposición
- **Puertos expuestos**: Listar todos los `ports:` en compose/stack/K8s. Verificar que solo se exponen los necesarios.
- **Bind a 0.0.0.0**: Puertos tipo `5000:3000` se exponen a todas las interfaces. Verificar si debería ser `127.0.0.1:5000:3000`.
- **Redes Docker**: Verificar aislamiento entre servicios. ¿Los contenedores de app están aislados de otras redes?
- **Nginx headers de seguridad**: Verificar en `nginx.conf.template`:
  - `X-Frame-Options`
  - `X-Content-Type-Options`
  - `X-XSS-Protection`
  - `Strict-Transport-Security` (HSTS)
  - `Content-Security-Policy`
  - `Referrer-Policy`
- **TLS/HTTPS**: Verificar si hay configuración de TLS en nginx. Si no la hay, señalar como gap.

### 2.4 Scripts y ejecución
- **Eval y source**: Buscar `eval`, `source`, `. ./` en scripts que procesen input externo
- **Permisos de archivos**: Verificar que los scripts `.sh` tienen permisos `755` o `700`, no `777`
- **Archivos temporales**: Verificar uso seguro de `mktemp` y limpieza en traps
- **Inyección de comandos**: Buscar variables sin comillas en contextos peligrosos (`xargs`, `find -exec`, backticks)
- **parse-env.sh**: Verificar que el parser de `.env` no ejecuta código (validación de nombres de variable)

### 2.5 Kubernetes específico
- **RBAC**: Verificar si hay ServiceAccounts, Roles, o RoleBindings definidos
- **NetworkPolicies**: Verificar si hay políticas de red
- **SecurityContext**: Buscar `securityContext` en deployments (runAsNonRoot, readOnlyRootFilesystem, etc.)
- **Secrets vs ConfigMap**: Verificar que datos sensibles no están en ConfigMaps (deberían ser Secrets)

### 2.6 Supply chain
- **Imágenes base**: ¿Se usan tags inmutables (SHA digest) o tags mutables (`:latest`, `:alpine`)?
- **Acciones de CI**: Si hay workflows de GitHub Actions, ¿están pineadas por SHA?
- **Dependencias de scripts**: ¿Los scripts descargan algo de internet en runtime? (`curl | bash`, `wget`, etc.)

3. **Clasificación de hallazgos**:

| Severidad | Criterio |
|-----------|----------|
| **CRITICO** | Secretos expuestos, ejecución como root sin necesidad, inyección de comandos |
| **ALTO** | Sin TLS, puertos expuestos innecesariamente, sin límites de recursos, imágenes con `:latest` |
| **MEDIO** | Sin headers de seguridad, sin NetworkPolicies, sin SecurityContext |
| **BAJO** | Mejoras de hardening opcionales, documentación faltante |

4. **Formato de salida**:

```
## Auditoría de Seguridad
Fecha: [timestamp]
Alcance: [todo el proyecto | etapa N | ruta específica]

### Puntuación: [X/10] — [CRITICO | NECESITA MEJORAS | ACEPTABLE | ROBUSTO]

### Hallazgos CRITICOS
[lista con detalle, evidencia y fix]

### Hallazgos ALTOS
[lista con detalle, evidencia y fix]

### Hallazgos MEDIOS
[lista con detalle, evidencia y fix]

### Hallazgos BAJOS
[lista con detalle, evidencia y fix]

### Resumen por categoría
| Categoría            | Estado     | Hallazgos |
|---------------------|------------|-----------|
| Secretos            | [estado]   | N         |
| Privilegios         | [estado]   | N         |
| Red/Exposición      | [estado]   | N         |
| Scripts             | [estado]   | N         |
| K8s hardening       | [estado]   | N         |
| Supply chain        | [estado]   | N         |

### Plan de remediación priorizado
1. [CRITICO] ...
2. [ALTO] ...
3. ...
```

5. **Solo lectura**: No modifiques archivos. Presenta hallazgos y espera confirmación del usuario para aplicar correcciones.
