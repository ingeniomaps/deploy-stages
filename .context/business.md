# Explicación del negocio — Blue-Green (kit de despliegue)

## Qué hace el producto

**Blue-Green** es un **framework de despliegue evolutivo** para aplicaciones Docker. Permite llevar una misma aplicación desde un entorno local o de desarrollo hasta producción, pasando por varios mecanismos (un contenedor, blue-green con Nginx, Docker Swarm, Kubernetes), **sin cambiar de herramienta ni de archivo de configuración**: un único `.env` en la raíz y un único punto de entrada (`make`).

## Problema que resuelve

- Equipos que quieren **empezar simple** (un contenedor, Compose) y **evolucionar** hacia blue-green, Swarm o Kubernetes sin reescribir configs ni mantener varios “mundos” (uno para dev, otro para prod).
- Necesidad de **una sola fuente de verdad** para variables (imagen, puertos, red, health, réplicas) compartida por todas las etapas.
- Despliegues **predecibles** con convenciones claras (switch, rollback, RECREATE) iguales en Compose y en Kubernetes.

## Qué ofrece

1. **Etapas consecutivas**  
   Misma app, mismo `.env`, distintos mecanismos según la etapa:
   - **0** — Ejecución manual sin Docker (local).
   - **1** — Un contenedor con Docker Compose.
   - **2** — Blue-green con Compose y Nginx (switch de tráfico, rollback).
   - **2.5** — Docker Swarm (réplicas, rolling update, rollback desde backup).
   - **3** — Kubernetes (Kind u otro cluster) con blue-green, ConfigMaps por color, HPA, opción de extraer k8s desde la imagen.

2. **Un solo `.env`**  
   Las variables se van añadiendo por etapa; no se renombran entre etapas. Permite pasar de “solo Compose” a “K8s en producción” sin duplicar configuraciones.

3. **Comportamiento blue-green consistente**  
   En Compose y en K8s: *switch* = solo cambiar tráfico; *RECREATE* = actualizar el stack destino (env/imagen) y luego cambiar tráfico; rollback = volver a hacer switch al otro color.

4. **Uso con imagen de artifact**  
   En Kubernetes se puede definir `K8S_IMAGE_PATH` y extraer la carpeta k8s desde la imagen en deploy y en switch RECREATE=1, sin clonar el repo de la app.

## A quién va dirigido

- Desarrolladores o equipos que desplegaban “a mano” o con scripts sueltos y quieren un camino claro hacia Compose, Swarm o Kubernetes.
- Proyectos que ya usan Docker y quieren introducir blue-green o K8s sin rehacer todo el flujo.
- Quienes quieren **controlar coste** en K8s (HPA con mínimo y máximo de réplicas) y tener rollback de configuración (env) además de rollback de tráfico.

## Resumen en una frase

Un **kit de despliegue** que toma cualquier aplicación Docker y la despliega de forma progresiva (Compose → blue-green → Swarm → Kubernetes), con un único `.env` y las mismas convenciones de switch y rollback en todas las etapas.
