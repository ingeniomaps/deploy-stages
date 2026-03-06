# Bun oficial, Alpine para imagen pequeña y segura (producción)
# https://hub.docker.com/r/oven/bun
FROM oven/bun:1-alpine AS base
WORKDIR /app

# Dependencias (capa cacheable)
FROM base AS deps
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile --no-cache

# Imagen final de producción
FROM base AS release
ENV NODE_ENV=production

COPY --from=deps /app/node_modules node_modules/
COPY package.json bun.lock* ./
COPY index.js ./
# Snippet nginx para blue-green (opcional: PROJECT_NGINX_DIR=/app/nginx/snippet.conf)
COPY nginx/snippet.conf /app/nginx/snippet.conf
# Manifests K8s del proyecto (opcional: K8S_IMAGE_PATH=/app/k8s)
COPY k8s/ /app/k8s/

# Usuario no root; ownership de los archivos de la app
RUN addgroup -g 1001 -S app && adduser -u 1001 -S app -G app && chown -R app:app /app
USER app

# Bun ejecuta el entrypoint; un solo proceso, sin shell
CMD ["bun", "run", "start"]
