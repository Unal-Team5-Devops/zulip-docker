# GameDay 1 — PostgreSQL no disponible

## Objetivo

Simular una falla de dependencia deteniendo únicamente el servicio Compose `database`, observar su efecto sobre Zulip y recuperar PostgreSQL mediante una decisión explícita del operador. El volumen `postgresql-14` no se elimina ni se recrea.

## Requisitos

- Stack de Zulip y observabilidad iniciado con `./observability/scripts/start.sh`.
- Docker con Docker Compose, Bash, Python 3 y `curl` disponibles. En Windows, ejecutar los `.sh` desde WSL2 o Git Bash con Docker Desktop disponible; no desde PowerShell directamente.
- Ejecutar la práctica sobre el entorno local de laboratorio, no sobre un servicio con usuarios reales.
- Verificar que el tráfico de prueba y las capturas no incluyan datos personales ni secretos.

## Comandos

Desde la raíz del repositorio:

```bash
# Comprobar que el escenario parte de un estado saludable.
./observability/gameday/postgres-failure/scripts/gameday.sh check

# Capturar la línea base y detener PostgreSQL. No hay recuperación automática.
./observability/gameday/postgres-failure/scripts/gameday.sh inject

# En otra terminal: generar carga durante el diagnóstico (por defecto 180 s a 5 RPS).
./observability/gameday/postgres-failure/scripts/gameday.sh load

# Consultar el estado en otra terminal mientras el equipo investiga.
./observability/gameday/postgres-failure/scripts/gameday.sh status

# Después de confirmar la causa y decidir la mitigación, recuperar manualmente.
./observability/gameday/postgres-failure/scripts/gameday.sh recover
```

`recover` inicia el contenedor existente, espera `pg_isready`, comprueba una consulta SQL y verifica la sonda de PostgreSQL en Prometheus. Si una comprobación falla, conserva el identificador de la ejecución para permitir diagnóstico y reintento.

`load [segundos] [solicitudes-por-segundo]` genera solicitudes GET sintéticas a `/login/` a través del gateway medido. El valor predeterminado es 180 segundos a 5 solicitudes por segundo; se permiten de 15 a 300 segundos y hasta 10 solicitudes por segundo. Úselo después de la inyección y mantenga abierta otra terminal para observar Grafana, Prometheus y ejecutar `status`. El reporte incluye conteos por estado HTTP y p95 de duración, y queda asociado a la ejecución. Esta carga no crea cuentas ni modifica datos.

También se puede capturar evidencia de una fase mientras el escenario está activo:

```bash
./observability/gameday/postgres-failure/scripts/gameday.sh evidence incident
```

Fases válidas: `pre-incident`, `incident` y `recovery`. Las capturas se guardan en subdirectorios con el identificador UTC de la ejecución, dentro de `evidence/`.

## Evidencia producida

Cada fase incluye:

- `snapshot.json`: consultas Prometheus, alertas de Alertmanager y targets.
- `compose-ps.txt`: estado de los servicios.
- `compose-stats.txt`: uso instantáneo de recursos de contenedores activos.
- `database-health.txt`: resultado de `pg_isready` y de una consulta de solo lectura, cuando la base está disponible.
- `gateway-check.txt`: código HTTP y duración de la ruta de login, sin guardar el cuerpo.
- `gateway-access.jsonl`: últimas 200 entradas de access log estructuradas del gateway. El formato registra estado, duración, URI sin query string y método.
- `database-collector-logs.txt`: logs recientes de PostgreSQL y del colector.
- `alert-receiver-logs.txt`: eventos firing/resolved recibidos durante los últimos diez minutos.
- `load-report.json` (fase `incident`, si se ejecuta `load`): duración, tasa objetivo, códigos HTTP y p95 de las solicitudes sintéticas.

Todas las capturas de este escenario, incluido `snapshot.json`, se guardan en `observability/gameday/postgres-failure/evidence/<fase>/<run-id>/`; no se escriben snapshots del GameDay en `observability/evidence/`. Las evidencias son archivos del laboratorio. Revisarlas antes de publicarlas o versionarlas; no se deben adjuntar archivos `.env`, secretos ni logs con información sensible.

## Demostración en diez minutos

1. Mostrar la línea base en el dashboard y ejecutar `check`.
2. Ejecutar `inject`; solo se detiene PostgreSQL y queda guardado el estado de ejecución.
3. Iniciar `load` en una terminal y, mientras corre, revisar tráfico, latencia, errores, dependencia PostgreSQL, targets y alertas. `status` permite consultar sin recuperar.
4. Explicar qué evidencia confirma la causa y qué hipótesis alternativas se descartaron.
5. Decidir y ejecutar `recover`; verificar salud de PostgreSQL, sonda, login y evento resuelto.

El comando de carga puede tardar hasta 300 segundos y el alertamiento de dependencia tiene una persistencia de dos minutos. Ajuste la duración para el tiempo disponible; una alerta todavía pendiente no invalida la evidencia de la sonda ni el estado del contenedor.

## Procedimiento de investigación

El procedimiento detallado está en [`runbook.md`](runbook.md). La causa de la inyección es conocida por quien prepara el ejercicio, pero la persona que opera el incidente debe tratarla como desconocida y demostrarla con señales independientes antes de recuperar.
