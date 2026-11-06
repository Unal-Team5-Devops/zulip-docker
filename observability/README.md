# Entrega 3: SRE y observabilidad de Zulip

Los manifiestos de este directorio amplían el Compose existente. Grafana y Prometheus se provisionan sin crear dashboards manualmente. El despliegue de Terraform de la entrega 2 permanece disponible; esta entrega se ejecuta con Compose y no requiere aplicar ambos sobre los mismos puertos.

## Arranque

Requisitos: Docker con Compose, Python 3, OpenSSL y al menos 6 GB de memoria disponibles para el conjunto. cAdvisor necesita un host Docker Linux; en Docker Desktop observa su máquina virtual Linux, no macOS. Zulip puede necesitar emulación amd64 en Apple Silicon.

```bash
./scripts/generate-env.sh
```

El script `start.sh` puede crear directamente un `.env` nuevo con el host local del gateway. Si `.env` ya existe, conservarlo. Definir `ZULIP_EXTERNAL_HOST=zulip.localhost:8080`, `ZULIP_CERTIFICATES=self-signed` y un `GRAFANA_ADMIN_PASSWORD` aleatorio de al menos 16 caracteres. El generador ya crea esa contraseña para entornos nuevos. Las contraseñas no se incluyen en las evidencias.

```bash
./observability/scripts/start.sh
./observability/scripts/compose.sh ps
```

| Servicio | Dirección |
| --- | --- |
| Zulip a través del gateway medido | https://zulip.localhost:8080 |
| Grafana, usuario `admin` y contraseña de `.env` | http://localhost:3000/d/zulip-sre |
| Prometheus | http://localhost:9090 |
| Alertmanager | http://localhost:9093 |

El arranque reutiliza las imágenes existentes y construye el colector si falta. Después de modificar su código o dependencias, ejecutar `./observability/scripts/compose.sh build collector alert-receiver` y volver a iniciar. Los certificados locales son autofirmados. Los servicios se publican en loopback. El gateway mantiene TLS también hacia Zulip y no valida su certificado autofirmado dentro de la red local. Para uso público se requiere dominio, certificados válidos, autenticación en las interfaces operativas y una revisión de la confianza entre proxies. La imagen de Zulip se fija por etiqueta de commit. Prometheus, Grafana, Alertmanager y cAdvisor usan etiquetas de versión; las imágenes base y las dependencias conservan las familias de versión del despliegue.

La creación inicial de una organización sigue el procedimiento del proyecto:

```bash
./observability/scripts/compose.sh exec -u zulip zulip \
  /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

La construcción del colector admite los argumentos estándar `PIP_FIND_LINKS`, `PIP_NO_INDEX` y `PIP_TRUSTED_HOST` para usar un repositorio local de paquetes. Sin argumentos descarga las versiones fijadas desde PyPI.

## Recolección

```text
cliente HTTPS → NGINX gateway → Zulip → PostgreSQL / Redis / Memcached / RabbitMQ
                     │                         │
                 access JSON             sondas autenticadas
                     └────────────→ collector:9105
RabbitMQ:15692 ────────────────────────────────┤
cAdvisor:8080 ─────────────────────────────────┤
                                              ↓
                                  Prometheus (15 s, 35 días)
                                      │              │
                                   Grafana      Alertmanager
                                                     ↓
                                           receptor JSON local
```

El colector lee logs solo por el extremo nuevo del archivo y expone contadores e histogramas. Reiniciarlo reinicia sus contadores; `rate` maneja los resets. Las peticiones completadas mientras está detenido no se reconstruyen: es una limitación visible de este laboratorio. El volumen del log debe rotarse con `copytruncate` en un despliegue duradero; no eliminar o renombrar el archivo abierto. El colector registra solo estado, duración, ruta sin query string y método. Las etiquetas no contienen rutas arbitrarias.

PostgreSQL se consulta mediante el secreto existente. Redis usa INFO autenticado y Memcached, STATS binario con SASL. El diagnóstico de RabbitMQ consulta su endpoint de métricas; no certifica una publicación AMQP. Sus contadores de mensajes y memoria se recogen además mediante el plugin nativo. Las latencias de dependencias son sondas periódicas, diferentes de la latencia de operaciones de usuarios. Rollback, cache miss y mensajes pendientes requieren contexto: no son todos errores de servicio.

cAdvisor usa acceso privilegiado y montajes del host en modo lectura, incluidos los sockets de Docker y containerd. Estos sockets permiten acceso a sus API aun cuando el montaje sea de solo lectura; forman parte del perímetro de confianza local. No se expone su puerto al host. Las métricas de CPU y memoria corresponden a contenedores de la VM en Docker Desktop. Los volúmenes de métricas y Grafana sobreviven a la recreación de contenedores; no usar `down -v` para una recuperación.

## Verificación y evidencia

```bash
python3 -m venv /tmp/zulip-observability-check
/tmp/zulip-observability-check/bin/pip install -r observability/collector/requirements.txt
PATH="/tmp/zulip-observability-check/bin:$PATH" ./observability/scripts/validate.sh
python3 observability/scripts/load.py --url https://zulip.localhost:8080/login/ --seconds 180 --rps 5 \
  --output observability/evidence/nominal-load.json
python3 observability/scripts/snapshot.py nominal
```

`validate.sh` comprueba Compose, reglas Prometheus, casos nominales, consumo sostenido, ausencia de tráfico, un pico corto, configuración de Alertmanager y el lector binario de Memcached. El workflow `.github/workflows/observability.yml` ejecuta estas comprobaciones; un workflow escrito localmente no implica que ya haya corrido en GitHub.
La simulación detiene únicamente PostgreSQL de este proyecto y genera carga durante cuatro minutos. Usar una instancia de laboratorio y conservar el volumen:

```bash
./observability/scripts/simulate.sh
```

El `trap` intenta reactivar PostgreSQL incluso si la prueba se interrumpe. Los JSON de `evidence/` contienen valores obtenidos de las API, tiempos y estados de carga. `notifications.log` registra la recepción real de alertas y su resolución. Las capturas muestran Grafana durante tráfico nominal y durante la degradación. El historial del taller no sustituye la ventana de 30 días.

### GameDay
El GameDay de PostgreSQL conserva por ejecución las capturas, logs, estados y reportes de carga en el directorio del escenario. Siga su flujo controlado y realice la recuperación manual solo después del diagnóstico:
```bash
./observability/gameday/postgres-failure/scripts/gameday.sh check
./observability/gameday/postgres-failure/scripts/gameday.sh inject
./observability/gameday/postgres-failure/scripts/gameday.sh load 180 5
# Tras el diagnóstico y la decisión del equipo:
./observability/gameday/postgres-failure/scripts/gameday.sh recover
```

La carga GET a `/login/` no modifica datos. Ajuste duración y tasa a los límites documentados del escenario. Los snapshots, logs JSON del gateway, eventos del receptor y reporte de carga quedan bajo `observability/gameday/postgres-failure/evidence/`; el historial del taller no sustituye la ventana de 30 días.

El segundo escenario solicita 100 → 250 RPS y tiene una etapa de respaldo de 350 RPS, con concurrencia y cola acotadas. Mide la tasa realmente entregada y detiene la rampa cuando el gateway supera 1% de 5xx o 500 ms de p95, o cuando el generador llega a su límite. Sus instrucciones y evidencias están en [`gameday/high-traffic/`](gameday/high-traffic/README.md); exige cAdvisor disponible y no reinicia servicios al cerrar la práctica.

## Informe de Word

Después de conservar las capturas y los JSON de la prueba, el informe se genera con:

```bash
python3 -m pip install -r observability/scripts/report-requirements.txt
python3 observability/scripts/report.py --output ~/Downloads/delivery3-team-5.docx
```

El PDF requerido por el enunciado se puede exportar desde Word. Para convertir con Calibre, `scripts/report-pdf.css` conserva una tipografía uniforme y ajusta los saltos de página de la conversión. Los archivos Word y PDF de esta ejecución quedaron en Downloads con el nombre `delivery3-team-5`.

## Documentación

- [SLIs, SLOs, presupuesto y política](SRE.md)
- [Runbook de PostgreSQL y errores HTTP](RUNBOOK.md)
- [Reglas de grabación y alerta](prometheus/rules.yml)
- [Dashboard provisionado](grafana/dashboards/zulip-sre.json)
- [Resultados de la ejecución](evidence/RESULTS.md)

Repositorio: https://github.com/Unal-Team5-Devops/zulip-docker/tree/feature/observability/observability

Para revisar esta entrega antes de integrarla a `main`, utilizar la rama `feature/observability`.
