# GameDay 2 — Incremento de tráfico

## Objetivo

Aplicar un perfil reproducible de tráfico HTTP creciente a través del gateway medido para investigar las Golden Signals y la posible saturación de Zulip y sus dependencias. El escenario no cambia ni reinicia contenedores; la carga termina por duración o por interrupción manual.

## Requisitos y límites

- Iniciar el stack principal y observabilidad con `./observability/scripts/start.sh`.
- Ejecutar en el entorno local de laboratorio, no frente a usuarios reales.
- Docker Compose, Bash, Python 3 y `curl` disponibles. En Windows, usar WSL2 o Git Bash con Docker Desktop.
- `check` exige PostgreSQL, las demás dependencias, gateway, Prometheus, Grafana, Alertmanager y el target cAdvisor saludables; además verifica que la tasa de 5xx y el p95 del último minuto estén dentro de los umbrales antes de iniciar otra prueba.
- El perfil solicita 100 RPS durante 20 s y luego 250 RPS durante 30 s. Si no hay degradación, prueba 350 RPS durante 15 s. En la prueba de referencia, 100 RPS fue estable y 250 RPS produjo 5xx. El generador limita la concurrencia a 256 conexiones y la cola a 512 solicitudes. Ctrl+C interrumpe la generación y conserva evidencia parcial.

## Flujo

Desde la raíz del repositorio:

```bash
# Validar precondiciones y la línea base.
./observability/gameday/high-traffic/scripts/gameday.sh check

# Iniciar el perfil en primer plano.
./observability/gameday/high-traffic/scripts/gameday.sh inject

# Mientras corre, en otra terminal observar métricas y estado.
./observability/gameday/high-traffic/scripts/gameday.sh status

# Después de que termine o se interrumpa, validar recuperación y cerrar.
./observability/gameday/high-traffic/scripts/gameday.sh recover
```

Durante `inject`, observar `http://localhost:3000/d/zulip-sre`, Prometheus en `http://localhost:9090` y Alertmanager en `http://localhost:9093`. `status` muestra consultas PromQL de tráfico, tasa de 5xx, p95, CPU, memoria y sondas. También se puede guardar una captura durante la carga con `gameday.sh evidence incident`.

El generador reutiliza conexiones HTTPS y descarta solicitudes que no caben en su cola, en lugar de acumularlas durante minutos. Cada etapa informa tasa objetivo, tasa completada, descartes previos al envío, estados HTTP y p95 del cliente. `stage-XX-analysis.json` guarda las métricas del gateway medidas por Prometheus al terminar la etapa, incluidos tráfico, 5xx, p95, CPU y memoria. `profile-result.txt` distingue los 5xx HTTP de los errores de transporte del cliente. La rampa se detiene al superar 1% de 5xx o 500 ms de p95 **en el gateway**. También se detiene si falta telemetría, o si el generador descarta, deja de programar o sufre errores de transporte en más de 5% de las solicitudes. Las consultas de las seis métricas se ejecutan en paralelo para acortar la pausa entre etapas.

La tasa objetivo no equivale necesariamente a la tasa completada. Los paneles de CPU/memoria dependen de cAdvisor; en Docker Desktop describen la VM Linux. Si el host tolera la carga realmente entregada, el resultado lo indicará. Los 50 s de las dos primeras etapas, la captura de línea base y el análisis suelen permitir observar el fallo antes de dos minutos desde `inject` en este entorno; el tiempo exacto depende de Docker y del host.

## Evidencia

Cada ejecución guarda `snapshot.json`, estado de Compose, estadísticas reales de `docker stats`, salud PostgreSQL, chequeo del gateway, access logs JSON, logs de servicios y los últimos registros de errores internos de Zulip (`zulip-internal-errors.txt`), además de reportes de carga, análisis Prometheus por etapa y `profile-result.txt` en:

```text
observability/gameday/high-traffic/evidence/<fase>/<run-id>/
```

Si se interrumpe el perfil, los reportes de las etapas completadas y una captura de incidente se conservan. `recover` exige que termine la carga, verifica las dependencias y guarda la fase `recovery`; no reinicia servicios. Revisar logs antes de compartir evidencias y no incluir `.env` ni secretos.

## Interpretación

Comparar cada etapa con la línea base: solicitudes/s, proporción de 5xx, p95 y respuestas sobre 500 ms, CPU/memoria de contenedores, conexiones PostgreSQL y sondas de dependencias. Distinguir aumento de demanda de un fallo de dependencia; una alerta o un panel sin datos no demuestra por sí solo saturación. El procedimiento está en [`runbook.md`](runbook.md).
