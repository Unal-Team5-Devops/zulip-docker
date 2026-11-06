# Runbook — GameDay 1: PostgreSQL no disponible

## 1. Alcance y resultado esperado

Se simula la indisponibilidad de la dependencia PostgreSQL de Zulip. El escenario detiene el servicio Compose `database`; no elimina datos, no borra volúmenes y no detiene intencionalmente el gateway ni los servicios de observabilidad.

El resultado esperado es detectar degradación en la aplicación y en la sonda de PostgreSQL, identificar la condición real del contenedor, decidir la recuperación y comprobar que la aplicación vuelve a operar. No se debe concluir que PostgreSQL es la causa únicamente porque exista una alerta.

**Severidad de ejercicio:** incidente de dependencia con impacto potencial en las operaciones que requieren persistencia. La severidad real se determina por el impacto HTTP, los SLO y el presupuesto observado.

## 2. Roles sugeridos

- **Incident Commander:** mantiene la línea de tiempo, coordina decisiones y decide cuándo se autoriza la recuperación.
- **Technical Operator:** ejecuta comandos de diagnóstico y, una vez autorizada, la recuperación manual.
- **Observability / Scribe:** revisa Grafana, Prometheus y Alertmanager; registra tiempos, hipótesis y evidencias.

En un equipo de dos personas, se pueden combinar coordinación y registro.

## 3. Preparación y línea base

1. Abrir el dashboard `http://localhost:3000/d/zulip-sre`, Prometheus `http://localhost:9090` y Alertmanager `http://localhost:9093`.
2. Ejecutar `gameday.sh check`. No inyectar la falla si PostgreSQL, la ruta HTTPS de Zulip o Prometheus ya están degradados.
3. Registrar el estado de las cuatro Golden Signals: tráfico, latencia, errores y saturación.
4. Registrar disponibilidad, SLO de latencia, burn rate y presupuesto restante. En un entorno recién desplegado, las ventanas largas son provisionales y reflejan solo el historial disponible.
5. Asignar roles y anotar hora UTC de inicio.

## 4. Detección: empezar por los síntomas

No asumir que la base de datos está detenida. Observar primero qué cambió y qué señales siguen disponibles.

### Grafana

En el dashboard `zulip-sre`, revisar:

- **Traffic:** si siguen llegando solicitudes al gateway y si el volumen cambió respecto de la línea base.
- **Errors:** crecimiento de respuestas 5xx y rutas afectadas.
- **Latency:** aumento del p95 y de las respuestas por encima de 500 ms.
- **Saturation:** conexiones PostgreSQL frente a `max_connections`, conexiones activas del gateway y recursos de contenedores.
- **Dependencies:** estado de `postgres`, Redis, Memcached, RabbitMQ y gateway.
- **SLO / Error Budget:** burn rate de cinco minutos y una hora, cumplimiento y presupuesto restante de 30 días.

Una señal vacía o antigua no equivale a cero. Confirmar que Prometheus sigue scrapeando el job `zulip` y que el colector continúa operativo.

Para producir solicitudes observables durante el ejercicio, desde otra terminal y después de `inject`:

```bash
./observability/gameday/postgres-failure/scripts/gameday.sh load 180 5
```

Esto envía GET a `/login/` por el gateway, no crea ni modifica datos y guarda el reporte en la carpeta `incident` de la ejecución. Mientras se ejecuta, el equipo puede revisar el dashboard y PromQL, o consultar `gameday.sh status` desde una tercera terminal. El gateway puede mantener `/login/` disponible parcialmente; no asumir que todas las rutas de Zulip fallan igual. Correlacionar los códigos HTTP y latencias sintéticos con la sonda PostgreSQL, el estado Compose y los logs.

### Alertmanager

Consultar `http://localhost:9093`. Buscar `ZulipDependencyUnavailable`, `ZulipErrorBudgetFastBurn`, `ZulipErrorBudgetSlowBurn` o `ZulipTelemetryMissing`. Una alerta de dependencia es una señal de investigación; por sí sola no demuestra que toda la aplicación esté fuera de servicio.

### PromQL de apoyo

Consultas alineadas con las métricas y reglas presentes en este repositorio:

```promql
# ¿Prometheus sigue recibiendo telemetría del colector?
up{job="zulip"}

# ¿Qué dependencias responden?
zulip_dependency_up

# ¿Qué proporción de solicitudes está fallando?
sum(rate(zulip_http_requests_total{status_class="5xx"}[5m]))
/
sum(rate(zulip_http_requests_total[5m]))

# Latencia p95 registrada por el gateway.
histogram_quantile(0.95,
  sum by (le) (rate(zulip_http_request_duration_seconds_bucket[5m])))

# Saturación de conexiones PostgreSQL (solo tiene sentido si la sonda responde).
zulip_postgres_connections / zulip_postgres_max_connections

# Consumo reciente del presupuesto para cada SLO.
zulip:slo_burn_rate:5m
zulip:slo_burn_rate:1h
```

Para la causa de este ejercicio, la señal más específica es:

```promql
zulip_dependency_up{dependency="postgres"}
```

Se espera que pase a `0`, mientras `up{job="zulip"}` puede seguir en `1`: el colector continúa vivo, pero no logra completar la sonda de PostgreSQL.

## 5. Investigación: formular y descartar hipótesis

Trabajar desde señales externas hacia la dependencia. Registrar hipótesis y evidencia que las confirma o descarta.

### Hipótesis A — El contenedor PostgreSQL está detenido

```bash
./observability/scripts/compose.sh ps database
./observability/scripts/compose.sh ps
```

Si el servicio aparece `Exited` o detenido, comprobarlo con la sonda y los logs. Esta es la condición inyectada en el ejercicio, pero el operador debe llegar a ella mediante observación.

### Hipótesis B — PostgreSQL está activo, pero no acepta conexiones

```bash
./observability/scripts/compose.sh exec -T database pg_isready -U zulip -d zulip
./observability/scripts/compose.sh logs --since 10m --tail 150 database
```

Buscar errores de arranque, recuperación, autenticación o rechazo de conexiones. No reiniciar el contenedor antes de conservar el estado y los logs.

### Hipótesis C — Agotamiento de conexiones o bloqueo

Solo si PostgreSQL acepta conexiones:

```bash
./observability/scripts/compose.sh exec -T database \
  psql -U zulip -d zulip -c \
  "SELECT state, wait_event_type, count(*) FROM pg_stat_activity GROUP BY 1,2 ORDER BY 1,2;"

./observability/scripts/compose.sh exec -T database \
  psql -U zulip -d zulip -c \
  "SELECT pid, now()-query_start AS duration, state, wait_event_type FROM pg_stat_activity WHERE state <> 'idle' ORDER BY query_start;"

./observability/scripts/compose.sh exec -T database \
  psql -U zulip -d zulip -c 'SHOW max_connections;'
```

No cancelar sesiones sin identificar primero su propietario, consulta y efecto. No terminar todas las conexiones.

### Hipótesis D — Falta de espacio o presión de recursos

```bash
docker stats --no-stream
./observability/scripts/compose.sh exec -T database df -h /var/lib/postgresql/data
```

Considerar espacio de almacenamiento, memoria, CPU y reinicios. No borrar archivos del directorio de datos para liberar espacio.

### Hipótesis E — El problema está fuera de PostgreSQL

Si `zulip_dependency_up{dependency="postgres"} == 1`, pero continúa el 5xx o la latencia, investigar `zulip`, `gateway`, Redis, Memcached y RabbitMQ. Comparar las alertas, logs y estado de cada dependencia; no atribuir el incidente a PostgreSQL sin evidencia.

## 6. Evaluación del impacto y decisión

Antes de actuar, responder y registrar:

- ¿La telemetría sigue disponible?
- ¿Hay solicitudes de usuarios/sintéticas durante el incidente?
- ¿Aumentaron 5xx, p95 o ambas señales?
- ¿Qué SLO está consumiendo presupuesto y con qué burn rate?
- ¿La causa está confirmada y el volumen de datos permanece intacto?
- ¿Es seguro iniciar el contenedor existente?

No esperar que el presupuesto de error vuelva inmediatamente a su nivel anterior. Las ventanas de SLO incluyen el periodo degradado hasta que las muestras salgan de la ventana móvil.

## 7. Mitigación y recuperación manual

**La recuperación solo se ejecuta cuando Incident Commander la autoriza.** En este ejercicio, la mitigación consiste en iniciar el contenedor PostgreSQL existente, conservando su volumen:

```bash
./observability/gameday/postgres-failure/scripts/gameday.sh recover
```

El comando realiza explícitamente `docker compose start database`, espera a que `pg_isready` responda, ejecuta una consulta SQL de solo lectura y espera a que la sonda `zulip_dependency_up{dependency="postgres"}` vuelva a `1`. No borra datos ni recrea el contenedor.

Si la recuperación no se completa, detener la ejecución y volver al diagnóstico. No usar `docker compose down -v`, `docker volume rm`, `docker compose rm -v` ni reinicializar PostgreSQL.

## 8. Validación posterior

1. Confirmar que `database` está en ejecución y `pg_isready` responde.
2. Confirmar `zulip_dependency_up{dependency="postgres"} == 1`.
3. Comprobar la ruta de login por el gateway HTTPS.
4. Revisar si los 5xx y la latencia vuelven a su patrón de referencia.
5. Verificar que las alertas pasan a `resolved` y que el burn rate deja de aumentar. Las ventanas largas pueden continuar reflejando el incidente.
6. Guardar la fase `recovery` y comparar con `pre-incident` e `incident`.

La ruta `/login/` comprueba disponibilidad HTTP básica; no demuestra por sí sola todos los flujos funcionales de Zulip.

Las capturas y `snapshot.json` quedan bajo `observability/gameday/postgres-failure/evidence/<fase>/<run-id>/`. El snapshot contiene respuestas de las APIs de Prometheus y Alertmanager, incluidas muestras de SLO; interpretar ventanas largas como provisionales si todavía no hay 30 días de historial.

## 9. Cierre y aprendizaje

Registrar hora de detección, reconocimiento, confirmación de causa, autorización de mitigación y recuperación. Calcular MTTD/MTTA/MTTR según los hitos registrados. Documentar impacto real en SLIs/SLOs, hipótesis descartadas, evidencias, acciones preventivas, responsables y fecha objetivo.

## 10. Límites del escenario

Este GameDay reproduce una dependencia PostgreSQL detenida en un único host. No simula corrupción de datos, pérdida del volumen, failover, caída del host ni partición de red. No usar datos reales ni ejecutar el ejercicio en producción.
