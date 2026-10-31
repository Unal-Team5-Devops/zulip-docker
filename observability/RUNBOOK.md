# Runbook: PostgreSQL no disponible o errores HTTP sostenidos

Servicio: Zulip. Severidad: crítica si `ZulipErrorBudgetFastBurn` o `ZulipErrorBudgetSlowBurn` está firing y hay impacto HTTP. Una sonda fallida por sí sola abre investigación, no demuestra caída de toda la aplicación.

## 1. Reconocer y delimitar

Asignar coordinación, diagnóstico y registro. Anotar hora de inicio, alerta, SLO afectado y último cambio. Abrir `http://localhost:3000/d/zulip-sre` y revisar 5xx, p95, tráfico, conexiones PostgreSQL, recursos y estado de targets. Consultar Alertmanager en `http://localhost:9093`. Confirmar si los errores afectan lectura, escritura o ambas; la API de información puede funcionar aunque una operación con base de datos falle.

Desde la raíz del repositorio:

```bash
./observability/scripts/compose.sh ps
curl -k -i --max-time 10 https://zulip.localhost:8080/login/
curl -fsSG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=zulip_dependency_up'
curl -fsSG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=zulip:slo_burn_rate:5m'
python3 observability/scripts/snapshot.py triage
```

Si no hay telemetría, comprobar primero Prometheus, el colector y el gateway. Un panel vacío no significa cero errores.

## 2. Diagnosticar sin modificar datos

```bash
./observability/scripts/compose.sh logs --since 10m --tail 150 database zulip collector
./observability/scripts/compose.sh exec -T database pg_isready -U zulip -d zulip
./observability/scripts/compose.sh exec -T database \
  psql -U zulip -d zulip -c 'SELECT now(), pg_postmaster_start_time();'
./observability/scripts/compose.sh exec -T database \
  psql -U zulip -d zulip -c "SELECT state, wait_event_type, count(*) FROM pg_stat_activity GROUP BY 1,2;"
./observability/scripts/compose.sh exec -T database \
  psql -U zulip -d zulip -c "SELECT pid, now()-query_start AS duration, state, wait_event_type FROM pg_stat_activity WHERE state <> 'idle' ORDER BY query_start;"
./observability/scripts/compose.sh exec -T database df -h /var/lib/postgresql/data
./observability/scripts/compose.sh stats --no-stream
```

Buscar contenedor detenido, falta de disco, reinicios por memoria, errores de autenticación y conexiones agotadas. El panel de latencia PostgreSQL mide consultas de diagnóstico y conexión; para encontrar una consulta problemática usar `pg_stat_activity`. No publicar logs con credenciales o contenido de usuarios.

## 3. Mitigar según la causa

Si el contenedor fue detenido, conserva su volumen y el disco tiene espacio:

```bash
./observability/scripts/compose.sh start database
./observability/scripts/compose.sh exec -T database pg_isready -U zulip -d zulip
```

Si está en ejecución pero no responde, conservar primero logs y estado. Revisar recursos y bloqueos antes de decidir un reinicio. Si fue una regresión de la aplicación, fijar en `.env` la última etiqueta `ZULIP_IMAGE=...:sha-...` que funcionaba y recrear únicamente Zulip:

```bash
./observability/scripts/compose.sh up -d --no-deps zulip
```

Un cambio de esquema puede impedir la reversión de la imagen; revisar las migraciones antes. Ante bloqueo, identificar la sesión y su impacto antes de cancelarla; no finalizar todas las conexiones. Ante disco lleno, liberar solo archivos prescindibles identificados, nunca archivos del directorio de datos PostgreSQL. Ante memoria agotada, detener la carga de prueba y corregir capacidad. Evitar `down -v`, borrar volúmenes, reinicializar la base o restaurar una copia sin analizar la pérdida de datos.

## 4. Verificar el restablecimiento

```bash
curl -k -f --max-time 10 https://zulip.localhost:8080/login/
python3 observability/scripts/load.py --url https://zulip.localhost:8080/login/ \
  --seconds 360 --rps 5 --output observability/evidence/manual-recovery-load.json
python3 observability/scripts/snapshot.py manual-recovery
./observability/scripts/compose.sh logs --since 10m alert-receiver
```

Exigir PostgreSQL healthy, sonda en 1, respuestas esperadas en la ruta afectada y ausencia de nuevos 5xx. Revisar tráfico para evitar interpretar una aplicación sin peticiones como recuperada. Confirmar que el burn rate de cinco minutos baja y FastBurn sale de firing; las ventanas largas y el presupuesto mensual pueden seguir afectados. Verificar el evento resolved. En una organización ya creada, comprobar además inicio de sesión, lectura y envío de un mensaje de prueba; la prueba pública de `/login/` no valida ese recorrido completo.

## 5. Cerrar y prevenir

Registrar duración e impacto observado, guardar las capturas, anotar si hubo pérdida de datos y aplicar la política de presupuesto antes de reanudar funcionalidades. Crear acciones con responsable y fecha: capacidad, conexiones, recuperación o control del cambio según la causa. La plataforma sigue teniendo un único PostgreSQL y un único host; un reinicio exitoso no elimina esos puntos de fallo.
