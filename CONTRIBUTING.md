# Contribuir al proyecto

Gracias por tu interés en contribuir. Estas son las pautas para hacerlo de forma ordenada.

## Reportar bugs

Abre un **issue** describiendo:

1. Qué etapa usas (1, 2, 2.5, 3).
2. Qué esperabas que pasara.
3. Qué pasó en realidad (incluye logs relevantes).
4. Tu entorno: OS, versión de Docker, versión de Make.

## Proponer cambios

1. Haz un fork del repositorio.
2. Crea una rama descriptiva: `fix/nginx-reload`, `feat/etapa-4-nomad`.
3. Haz tus cambios siguiendo las convenciones del proyecto (ver abajo).
4. Asegúrate de que `make help` sigue funcionando y los scripts no rompen etapas existentes.
5. Abre un Pull Request con una descripción clara de qué cambia y por qué.

## Convenciones

- **Idioma del proyecto:** español (código, comentarios, docs, commits).
- **Scripts:** usar `deploy/scripts/lib/parse-env.sh` para leer `.env` (nunca `eval` ni `source`).
- **Variables:** cada etapa añade variables al `.env` sin renombrar las existentes.
- **Archivos generados:** deben estar en `.gitignore`.
- **ShellCheck:** los scripts deben pasar `shellcheck` sin errores.

## Estructura de commits

Usa mensajes claros y en español:

```
fix: corregir reload de nginx en switch blue-green
feat: agregar soporte para health check TCP en etapa 2
docs: actualizar README de etapa 3 con ejemplo de registry remoto
```

## Código de conducta

Este proyecto sigue el [Contributor Covenant](CODE_OF_CONDUCT.md). Al participar, te comprometes a mantener un ambiente respetuoso.
