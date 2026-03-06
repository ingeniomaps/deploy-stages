---
name: code-review
description: Revisión exhaustiva de código siguiendo buenas prácticas actualizadas. Usa cuando el usuario pida revisar código, auditar scripts, o buscar problemas de calidad.
argument-hint: [ruta-o-directorio]
context: fork
agent: general-purpose
---

Realiza una revisión exhaustiva de código sobre `$ARGUMENTS`.

## Instrucciones

1. **Descubrimiento**: Usa Glob y Read para encontrar y leer TODOS los archivos relevantes en la ruta indicada (scripts `.sh`, `Dockerfile`, `docker-compose*.yml`, `Makefile`, `.env.example`, `README.md`, y cualquier otro archivo de configuración).

2. **Análisis por categoría**: Revisa cada archivo evaluando las siguientes categorías. Solo reporta hallazgos concretos — no repitas lo que ya está bien.

### Shell Scripts (.sh)
- **Seguridad**: inyección de comandos, expansión sin comillas, eval peligroso, uso de `xargs` sin `-0`
- **Robustez**: `set -euo pipefail`, variables sin protección `${VAR:-}`, comandos que fallan silenciosamente
- **Portabilidad**: bashisms en scripts con shebang `#!/bin/sh`, dependencias no declaradas
- **Buenas prácticas**: uso de `readonly` para constantes, `local` en funciones, quoting consistente (`"${var}"` no `$var`), redirecciones seguras, limpieza de archivos temporales
- **ShellCheck**: identifica problemas que ShellCheck (SC2086, SC2034, SC2155, etc.) detectaría
- **Lógica**: race conditions, orden de operaciones, manejo de errores en pipelines

### Docker & Compose
- **Dockerfile**: multi-stage builds, capas innecesarias, usuario no-root, COPY vs ADD, .dockerignore, orden de capas para cache, health checks
- **Compose**: versión obsoleta (`version:` ya no es necesario en Compose V2+), restart policies, health checks, dependencias entre servicios, volúmenes innecesarios, redes
- **Seguridad**: imágenes base con tag fijo (no `latest` en producción), secrets expuestos, privilegios innecesarios

### Makefiles
- **Targets**: uso de `.PHONY`, variables escapadas correctamente, dependencias entre targets
- **Portabilidad**: comandos POSIX vs GNU-only
- **Mantenibilidad**: DRY, variables reutilizables, documentación de targets

### Configuración (nginx, env, etc.)
- **Nginx**: headers de seguridad, timeouts, buffer sizes, logging
- **Variables de entorno**: valores por defecto sensatos, documentación, secretos en `.env.example`

3. **Formato de salida**: Organiza los hallazgos así:

```
## Resumen
[Resumen ejecutivo: X archivos revisados, Y hallazgos]

## Hallazgos críticos 🔴
[Problemas de seguridad o bugs que deben corregirse]

## Mejoras recomendadas 🟡
[Buenas prácticas que mejorarían la calidad]

## Sugerencias menores 🟢
[Optimizaciones opcionales o estilo]

## Por archivo
### [archivo]
- [hallazgo]: [explicación concisa] → [fix sugerido]
```

4. **No reportes**: cosas que ya están bien hechas, preferencias de estilo subjetivas, o mejoras teóricas sin impacto real.
