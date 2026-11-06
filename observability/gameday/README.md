# GameDay de Zulip

Este directorio contiene los escenarios reproducibles del ejercicio SRE. Cada escenario mantiene separados su procedimiento, sus comandos y las evidencias.

| Escenario | Propósito | Estado |
| --- | --- | --- |
| [`postgres-failure/`](postgres-failure/README.md) | Pérdida de disponibilidad de PostgreSQL y recuperación manual | Implementado |
| [`high-traffic/`](high-traffic/README.md) | Incremento progresivo de tráfico y diagnóstico de saturación | Implementado |

## Principio operativo

La inyección puede automatizarse; la recuperación no. El equipo debe detectar el síntoma, investigar las hipótesis, confirmar la causa, decidir la mitigación y ejecutar explícitamente la recuperación. Ningún script de inyección inicia de nuevo PostgreSQL automáticamente.

Los comandos se ejecutan desde la raíz del repositorio o desde otra ubicación, siempre que se invoquen con su ruta completa. Los scripts usan el Compose principal y `observability/compose.yml` mediante `observability/scripts/compose.sh`. Cada GameDay conserva sus propias capturas dentro de su carpeta `evidence/`.
