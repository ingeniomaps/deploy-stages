---
name: shellcheck-all
description: Ejecuta ShellCheck sobre todos los scripts .sh del proyecto (excluyendo ./app), reporta hallazgos por severidad y sugiere correcciones.
argument-hint: "[ruta-opcional]"
context: fork
agent: general-purpose
---

Ejecuta un análisis ShellCheck exhaustivo sobre los scripts shell del proyecto.

- Si `$ARGUMENTS` contiene una ruta, analiza solo esa ruta.
- Si `$ARGUMENTS` está vacío, analiza todos los `.sh` bajo `deploy/` (excluyendo `./app`).

## Instrucciones

1. **Verificar ShellCheck**: Comprueba que `shellcheck` está instalado (`which shellcheck`). Si no lo está, informa al usuario cómo instalarlo (`sudo apt install shellcheck` o `brew install shellcheck`) y detente.

2. **Descubrimiento de scripts**: Usa Glob para encontrar todos los archivos `.sh` en la ruta objetivo. Excluye siempre `./app/**` y `./copy/**`.

3. **Ejecución**: Para cada script encontrado, ejecuta:
   ```
   shellcheck -f gcc -S warning <archivo>
   ```
   Captura la salida. Si el script tiene shebang `#!/bin/sh`, añade `-s sh`. Si tiene `#!/bin/bash`, añade `-s bash`.

4. **Clasificación**: Agrupa los hallazgos por severidad:
   - **error**: Bugs probables o problemas de sintaxis
   - **warning**: Problemas que pueden causar comportamiento inesperado
   - **info**: Sugerencias de estilo y mejores prácticas

5. **Análisis contextual**: Para cada hallazgo, lee el código fuente alrededor de la línea reportada (3 líneas de contexto) y proporciona:
   - Qué hace el código actual
   - Por qué es problemático
   - El fix concreto (código corregido)

6. **Formato de salida**:

```
## Resumen ShellCheck
- Scripts analizados: N
- Errores: X | Warnings: Y | Info: Z

## Errores (bugs probables)
### archivo.sh:línea — SCxxxx
[descripción + fix]

## Warnings (comportamiento inesperado)
### archivo.sh:línea — SCxxxx
[descripción + fix]

## Info (mejoras de estilo)
### archivo.sh:línea — SCxxxx
[descripción + fix]

## Scripts limpios
[lista de scripts sin hallazgos]
```

7. **Ofrecer corrección**: Al final, pregunta al usuario si desea que apliques las correcciones automáticamente. Si acepta, usa Edit para aplicar cada fix uno por uno, verificando que cada cambio no rompa la lógica del script.
