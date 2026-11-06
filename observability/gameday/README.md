# GameDay de Zulip

Este directorio contiene los escenarios reproducibles del ejercicio SRE. Cada escenario mantiene separados su procedimiento, sus comandos y las evidencias.

| Escenario | Propósito | Estado |
| --- | --- | --- |
| [`postgres-failure/`](postgres-failure/README.md) | Pérdida de disponibilidad de PostgreSQL y recuperación manual | Implementado |
| [`high-traffic/`](high-traffic/README.md) | Incremento progresivo de tráfico y diagnóstico de saturación | Implementado |

## Principio operativo

La inyección puede automatizarse; la recuperación no. El equipo debe detectar el síntoma, investigar las hipótesis, confirmar la causa, decidir la mitigación y ejecutar explícitamente la recuperación. Ningún script de inyección inicia de nuevo PostgreSQL automáticamente.

Los comandos se ejecutan desde la raíz del repositorio o desde otra ubicación, siempre que se invoquen con su ruta completa. Los scripts usan el Compose principal y `observability/compose.yml` mediante `observability/scripts/compose.sh`. Cada GameDay conserva sus propias capturas dentro de su carpeta `evidence/`.

## Ejecución en AWS

En el entorno de la Entrega 4 los escenarios corren dentro de la instancia EC2, sobre `/opt/zulip`, de dos formas equivalentes:

- **GitHub Actions** → *Actions → GameDay → Run workflow*, eligiendo escenario y paso (`check`, `inject`, `load`, `status`, `recover`). Corre en el runner self-hosted de la instancia, deja la salida en el resumen del job y la evidencia como artefacto. Comparte la cola con `Deploy`, así que nunca se ejecuta durante un despliegue.
- **Terminal SSM** → `sudo -iu ubuntu && cd /opt/zulip`, y los mismos comandos `gameday.sh`.

Diferencias frente al entorno local:

- Los scripts siguen usando `https://zulip.localhost:8080` contra `127.0.0.1`; el gateway reescribe ese nombre al nombre público de Zulip (`deploy/deploy.sh`), por lo que no requieren cambios.
- cAdvisor observa directamente los contenedores de la instancia (no una VM de Docker Desktop).
- En `high-traffic`, el generador de carga corre en la misma instancia de 2 vCPU que Zulip y compite por CPU: el umbral de degradación observado incluye ese efecto y debe mencionarse al interpretar los resultados.
