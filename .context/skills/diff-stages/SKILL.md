---
name: diff-stages
description: Compara la configuración, variables, arquitectura y scripts entre dos etapas del framework de despliegue.
argument-hint: "[etapa-origen] [etapa-destino] (ej. 1 2, 2 2.5, 2.5 k8s)"
context: fork
agent: general-purpose
---

Compara dos etapas del framework de despliegue indicadas en `$ARGUMENTS`.

## Instrucciones

1. **Parsear argumentos**: Extrae las dos etapas de `$ARGUMENTS`. Valores válidos: `0`, `1`, `2`, `2.5`, `k8s`. Si falta alguna, pregunta al usuario.

2. **Para cada etapa, recopilar**:

### Variables de entorno
- Lee el `.env.example` de cada etapa
- Clasifica cada variable como: requerida, opcional, nueva en esta etapa, eliminada respecto a la otra

### Archivos y scripts
- Lista todos los archivos en el directorio de cada etapa con Glob
- Identifica archivos nuevos, eliminados y modificados entre las dos etapas

### Arquitectura
- Describe la arquitectura de cada etapa (componentes, flujo de tráfico, mecanismo de despliegue)

### Comandos Make
- Extrae los targets del Makefile para cada etapa
- Identifica targets nuevos, eliminados y modificados

3. **Generar comparación**:

```
## Comparación: Etapa [A] vs Etapa [B]

### Resumen ejecutivo
[1-2 frases: qué cambia fundamentalmente al pasar de A a B]

### Arquitectura
| Aspecto             | Etapa [A]                    | Etapa [B]                     |
|---------------------|------------------------------|-------------------------------|
| Componentes         | [lista]                      | [lista]                       |
| Mecanismo de switch | [descripción]                | [descripción]                 |
| Escalado            | [descripción]                | [descripción]                 |
| Health checks       | [cómo se hacen]              | [cómo se hacen]               |
| Rollback            | [mecanismo]                  | [mecanismo]                   |
| Red                 | [tipo: bridge/overlay/k8s]   | [tipo]                        |

### Variables de entorno
| Variable         | Etapa [A]    | Etapa [B]    | Cambio              |
|-----------------|--------------|--------------|---------------------|
| PROJECT_NAME    | requerida    | requerida    | sin cambio          |
| REPLICAS        | -            | requerida    | nueva en etapa [B]  |
| CONTAINER_IP    | opcional     | -            | eliminada           |
| ...             | ...          | ...          | ...                 |

### Archivos y scripts
#### Nuevos en Etapa [B]
- [archivo]: [qué hace]

#### Eliminados respecto a Etapa [A]
- [archivo]: [qué hacía]

#### Equivalentes (mismo propósito, diferente implementación)
| Etapa [A]                    | Etapa [B]                    | Diferencia clave             |
|------------------------------|------------------------------|------------------------------|
| generate-extra-hosts.sh      | generate-env-file-include.sh | inline env vs env_file mount |

### Comandos Make
| Acción     | Etapa [A]            | Etapa [B]              |
|------------|----------------------|------------------------|
| Deploy     | make deploy-simple   | make deploy-bluegreen  |
| Down       | make down-simple     | make down-bluegreen    |
| Status     | -                    | make status-bluegreen  |
| Switch     | -                    | make switch-bluegreen  |
| Rollback   | -                    | make switch-bluegreen  |

### Prerequisitos para migrar
1. [qué necesitas tener/instalar/configurar antes de migrar de A a B]
2. ...

### Complejidad añadida
[qué conceptos nuevos introduce la etapa B que no existían en A]
```

4. **Solo lectura**: Este skill es puramente informativo. No modifica archivos.
