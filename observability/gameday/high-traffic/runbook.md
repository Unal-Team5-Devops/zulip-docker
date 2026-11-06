# Runbook — GameDay 2: incremento de tráfico

## 1. Alcance y resultado esperado

El escenario solicita GET sintéticos a `/login/` a través de NGINX: 100 RPS durante 20 s, 250 RPS durante 30 s y, solo si no hubo degradación, 350 RPS durante 15 s. La prueba de referencia mostró 100 RPS sin errores y 250 RPS con 502. El generador admite como máximo 256 solicitudes simultáneas y una cola de 512. No crea cuentas ni modifica datos. Detiene la rampa si el gateway supera 1% de 5xx o p95 de 500 ms, si falta telemetría o si el generador alcanza su límite. También se puede interrumpir con Ctrl+C. El punto de fallo depende de la capacidad del host; comprobar siempre las mediciones reales.

## 2. Preparación

1. Asignar coordinación, operación y registro de la línea de tiempo.
2. Ejecutar `gameday.sh check`; no comenzar con señales degradadas o telemetría incompleta.
3. Registrar la línea base de tráfico, 5xx, p95, CPU/memoria, conexiones PostgreSQL y estado de dependencias.
4. Abrir Grafana, Prometheus y Alertmanager. Ejecutar `inject` en una terminal y `status` desde otra. La primera etapa debe servir como referencia sana de la misma sesión; la segunda busca mostrar el salto de 5xx y p95. En la prueba de referencia se detectó antes de dos minutos desde `inject`, incluida la captura previa.

## 3. Lectura de señales

Usar `/d/zulip-sre` y comparar etapas. Las consultas de `status` y del snapshot incluyen tráfico por minuto, 5xx, p95, CPU y memoria:

```promql
sum(rate(zulip_http_requests_total[1m]))
sum(rate(zulip_http_requests_total{status_class="5xx"}[1m])) / sum(rate(zulip_http_requests_total[1m]))
histogram_quantile(0.95, sum by (le) (rate(zulip_http_request_duration_seconds_bucket[5m])))
sum by(name) (rate(container_cpu_usage_seconds_total{name=~".*zulip.*"}[1m]))
sum by(name) (container_memory_working_set_bytes{name=~".*zulip.*"})
zulip_postgres_connections / zulip_postgres_max_connections
zulip_dependency_up
```

Confirmar `up{job="zulip"}` y `up{job="cadvisor"}` antes de interpretar huecos como ceros. cAdvisor observa los contenedores de la VM Linux de Docker Desktop. El dashboard muestra p95 de 5m; el análisis de cada etapa consulta una ventana de 1m para detectar antes una degradación. Comparar los reportes de cliente con el tráfico Prometheus: las solicitudes descartadas por la cola nunca llegaron al gateway.

Si sube el p95 del cliente pero el p95 del gateway sigue bajo, revisar `client_p95_queue_seconds`, `generator_drop_ratio`, tasa realmente completada y uso de CPU del equipo generador. Esa combinación apunta a un límite del generador o de la red local. Si suben el p95 o los 5xx **del gateway**, correlacionarlos con CPU, memoria, conexiones y logs de Zulip para sostener una hipótesis de saturación del servicio.

`gateway_rps` es una tasa media sobre 1 minuto: al medir una etapa de 20 o 30 segundos, será menor que el RPS completado durante esa etapa. Comparar además `client_5xx_ratio` con `client_transport_error_ratio`: los HTTP 502 son respuestas del servicio, mientras el código 0 corresponde a un error de conexión o transporte del cliente. El p95 del análisis de etapa usa 1 minuto; el dashboard y los snapshots usan 5 minutos.

Las reglas de Alertmanager exigen ventanas y tiempos de persistencia mayores que esta inyección breve. Es posible ver la anomalía inmediatamente en Grafana, Prometheus y los logs mientras una alerta aún está `pending`; explicarlo como parte del triaje y no esperar a que dispare para confirmar el incidente.

## 4. Diagnóstico

- **Demanda alta sin degradación:** el tráfico crece y latencia/errores permanecen estables; el host toleró este perfil.
- **CPU alta:** correlacionar `rate(container_cpu_usage_seconds_total)` por contenedor con p95/5xx. Distinguir Zulip, gateway, base de datos y colector.
- **Memoria creciente:** revisar `container_memory_working_set_bytes`, reinicios/estado de Compose y cAdvisor. No asumir fuga por una observación instantánea.
- **Base de datos saturada:** revisar conexiones frente a `max_connections`, `pg_stat_activity`, logs y sonda PostgreSQL. No cancelar sesiones sin identificar su efecto.
- **Dependencia caída:** confirmar la sonda específica, estado del contenedor y logs antes de atribuir causalidad.
- **Errores o latencia sin saturación local:** inspeccionar access logs JSON y logs de Zulip; verificar targets y red antes de reducir la carga.

En la prueba de referencia a 250 RPS, el NGINX **interno de Zulip** registró `connect() to unix:/home/zulip/deployments/uwsgi-socket failed (11: Resource temporarily unavailable) while connecting to upstream`. Esto explica el 502 inmediato: NGINX no consiguió entregar algunas solicitudes al socket de uWSGI en ese momento. Las respuestas 200 lentas evidencian que las solicitudes aceptadas también esperaron más. El mensaje demuestra saturación del punto de entrada a la aplicación, pero no basta por sí solo para afirmar si el límite específico fue el número de workers, el backlog del socket o CPU. Correlacionar con CPU, procesos y configuración antes de ajustar capacidad.

Para confirmar la causa durante una nueva ejecución, abrir `evidence/incident/<run-id>/zulip-internal-errors.txt` y buscar la hora de los 502. El archivo reúne los últimos 200 registros de `/var/log/nginx/error.log`, `/var/log/zulip/errors.log` y `/var/log/zulip/django.log` dentro del contenedor. Como usa `tail`, comparar siempre las marcas de tiempo con el run-id; la captura previa puede contener mensajes de ensayos anteriores. `service-logs.txt` puede quedar vacío si esos procesos no escriben en stdout/stderr.

La carga no debe escalarse fuera del perfil definido. Ante impacto inesperado, interrumpir con Ctrl+C; se conservan reportes completados y evidencia parcial.

## 5. Recuperación y cierre

Tras completar o interrumpir el perfil, ejecutar `gameday.sh recover`. El comando confirma que dependencias, gateway y cAdvisor están saludables, captura la fase `recovery` y cierra el estado local. No reinicia ni recrea servicios. Comparar las fases y registrar impacto HTTP, saturación observada, alertas y limitaciones del host. En el laboratorio, la mitigación inmediata es detener la fuente de carga; confirmar que 5xx y p95 regresan a la línea base. En producción, reducir la presión con límites de tasa o control de admisión y, si la demanda es legítima, aumentar capacidad de procesamiento de Zulip y revisar la configuración de uWSGI con mediciones. Reiniciar PostgreSQL no corrige el rechazo del socket uWSGI cuando la base de datos sigue saludable.

## 6. Guion oral de triaje

1. **Antes:** «La etapa a 100 RPS establece una referencia de esta sesión: mirar RPS realmente completados, 5xx y p95 del gateway; PostgreSQL y las demás dependencias están sanas».
2. **Durante:** «Al pasar a 250 RPS, contrasto RPS objetivo con completado y con la media de Prometheus. Si aparecen 502 y p95 supera 500 ms, detengo la rampa y guardo la evidencia».
3. **Causa:** «Los access logs muestran respuestas 502 rápidas y respuestas 200 más lentas. En el log interno de Zulip compruebo si NGINX rechazó la conexión al socket de uWSGI. La sonda de PostgreSQL en 1 descarta una caída de esa dependencia, aunque sigo revisando su carga».
4. **Mitigación:** «Corto la carga del laboratorio; en producción aplicaría control de admisión y ampliaría la capacidad de la aplicación según el cuello de botella medido. Verifico después que el error rate y la latencia vuelvan a sus valores normales».
