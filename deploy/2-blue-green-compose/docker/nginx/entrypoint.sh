#!/bin/sh
set -e

# Si el proyecto tiene snippet.conf, usarlo; si no, crear archivo vacío para que el include no falle.
if [ -f /etc/nginx/conf.d/project/snippet.conf ]; then
  cp /etc/nginx/conf.d/project/snippet.conf /etc/nginx/conf.d/project-snippet.conf
else
  echo '# no project snippet' > /etc/nginx/conf.d/project-snippet.conf
fi

# Substitute PROJECT_NAME and PROJECT_PORT in the nginx template
# shellcheck disable=SC2016
envsubst '${PROJECT_NAME} ${PROJECT_PORT}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf

nginx -t
exec nginx -g "daemon off;"
