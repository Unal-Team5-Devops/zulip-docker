# Pre-Mortem — Zulip en producción

**Equipo 5** · Fundamentos de DevOps y SRE · UNAL 2026-02
Jonathan David Moncaleano Ángel · Andrés Felipe Lugo Rodríguez · Camilo Alfonso Mosquera Benavides

## 1. Supuesto y método

> *Es 7 de diciembre de 2026. Zulip lleva un mes en producción sobre la arquitectura de la Entrega 4 y sufrió una falla catastrófica. Escribimos esto como si ya hubiera ocurrido, para explicar por qué ocurrió.*

Un pre-mortem invierte el postmortem: en lugar de preguntar "¿qué podría salir mal?", se da por hecho el fracaso y se reconstruye la historia que lo hace inevitable. Eso obliga a señalar debilidades concretas de **nuestra** plataforma, no riesgos genéricos.

Para cada escenario se presentan: la narrativa del incidente, el análisis de causa raíz con los **5 Porqués**, el **impacto sobre los SLI/SLO y el presupuesto de error**, y el plan de **prevención, detección y mitigación** ligado al runbook.

### Contexto que usan los cálculos

| Elemento | Valor (Entrega 3) |
|---|---|
| SLI de disponibilidad | Respuestas no 5xx / total, medidas en el gateway NGINX |
| SLO de disponibilidad | ≥ 99 % en 30 días → presupuesto = 1 % de las peticiones |
| SLI de latencia | Respuestas ≤ 500 ms / total |
| SLO de latencia | ≥ 95 % en 30 días → presupuesto = 5 % de las peticiones |
| Burn rate | `B = tasa de error observada / tasa permitida` |
| Consumo del presupuesto | `B × duración / 720 h`. Con B = 100 (caída total) el presupuesto mensual se agota en **7,2 h** |
| Alertas | FastBurn: B(1h) y B(5m) > 14,4 · SlowBurn: B(6h) y B(30m) > 6 · Ticket: B(3d) y B(6h) > 1 |
| Arquitectura | Una instancia EC2 `m7i-flex.large` (2 vCPU, 8 GiB, disco gp3 de 30 GiB), una réplica de Zulip, PostgreSQL, Redis, Memcached y RabbitMQ en contenedores, observabilidad en el mismo host |

### Matriz de modos de falla considerados

| # | Modo de falla | Probabilidad | Impacto | Elegido |
|---|---|---|---|---|
| 1 | **Disco lleno: PostgreSQL deja de escribir y no hay respaldo restaurable** | Media | Catastrófico (caída total + posible pérdida de datos) | ✅ |
| 2 | **Pico de tráfico satura la única réplica de Zulip** | Alta | Alto (5xx y latencia; observabilidad degradada) | ✅ |
| 3 | Despliegue de una imagen de Zulip defectuosa por el pipeline | Media | Alto (recrea la única réplica) | Controles en §5 |
| 4 | Agotamiento de créditos o suspensión de la cuenta AWS | Baja | Catastrófico | Controles en §5 |
| 5 | Runner self-hosted comprometido desde un PR de un fork (repo público) | Baja | Catastrófico (código arbitrario en producción) | Controles en §5 |

---

## 2. Escenario 1 — El disco se llena, PostgreSQL se detiene y no hay respaldo

### Narrativa

Durante cuatro semanas el disco raíz de 30 GiB fue llenándose sin que nadie lo mirara: imágenes de Zulip de cada versión desplegada (~2–3 GiB cada una, nunca se borraron), la base de Prometheus con retención de 35 días, el crecimiento normal de PostgreSQL y los archivos subidos por los usuarios. Un martes a las 10:40, con el disco al 100 %, PostgreSQL no puede escribir WAL y aborta. Zulip responde 5xx a todo, incluida la página de login. FastBurn dispara a los 2 minutos.

El operador libera espacio y reinicia PostgreSQL, pero el último checkpoint quedó incompleto y la base no arranca de forma consistente. Al buscar un respaldo descubre que **no existe ninguno**: no hay `pg_dump` programado ni snapshots del volumen EBS, y el volumen tiene `delete_on_termination = true`. La recuperación con las herramientas de PostgreSQL toma 6 horas y se pierden los mensajes de las últimas horas.

### 5 Porqués

| # | Pregunta | Respuesta |
|---|---|---|
| 1 | ¿Por qué Zulip devolvió 5xx durante 6 horas? | PostgreSQL se detuvo con `No space left on device` y, al reiniciar, no recuperó un estado consistente. |
| 2 | ¿Por qué se llenó el disco? | Un solo volumen de 30 GiB comparte imágenes de Docker, volúmenes de datos, la base de métricas (35 días) y logs, y nada limita ni limpia su crecimiento (`deploy.sh` nunca ejecuta `docker image prune`). |
| 3 | ¿Por qué no se detectó antes de llegar al 100 %? | No medimos el sistema de archivos del host: cAdvisor reporta contenedores, el colector mide dependencias y ningún SLI ni alerta cubre capacidad de disco. Solo vimos el síntoma (5xx) cuando ya era tarde. |
| 4 | ¿Por qué la recuperación tomó horas y perdió datos? | No hay respaldos ni procedimiento de restauración probado. El runbook cubre "PostgreSQL detenido" (reiniciar el contenedor), no "PostgreSQL corrupto". |
| 5 | ¿Por qué no existían respaldos ni alertas de capacidad? | Nunca definimos **RPO/RTO** ni una política de datos. El diseño optimizó costo (instancia única del plan gratuito) y tiempo de entrega; el estado persistente se trató igual que el resto de contenedores. |

**Causa raíz:** el estado persistente no tiene objetivos de recuperación (RPO/RTO) ni gestión de capacidad; la arquitectura asume que el único disco nunca falla ni se llena.

### Impacto en SLI/SLO y presupuesto

| Fase | Duración | SLI disponibilidad | Burn rate (disponibilidad) | Presupuesto consumido |
|---|---|---|---|---|
| Caída total (todas las peticiones 5xx) | 6 h | 0 % | B = 100 | 100 × 6 / 720 = **83 %** del presupuesto mensual |
| Arranque degradado (≈ 20 % de errores) | 1 h | 80 % | B = 20 | 20 × 1 / 720 = 2,8 % |
| **Total del incidente** | 7 h | — | — | **≈ 86 %** → el SLO de 99 % queda prácticamente agotado |

- **Latencia:** mientras PostgreSQL está detenido las respuestas son 500 rápidas (≈ 33 ms en la Entrega 3), así que el SLI de latencia apenas se mueve. En la repetición del GameDay 1 (5 de noviembre), con la base caída por más tiempo, el gateway devolvió **502 y timeouts** (961 respuestas 502, 237 sin respuesta, p95 del cliente de 10 s): si la caída se prolonga, también se quema el presupuesto de latencia (B hasta 1 / 0,05 = 20).
- **Alertas que habrían disparado:** `ZulipDependencyUnavailable{dependency="postgres"}` (2 min), `ZulipErrorBudgetFastBurn` (≈ 2 min), `ZulipErrorBudgetSlowBurn` (5 min). Ninguna antes del incidente: es el problema.
- **Política de presupuesto (SRE.md):** queda ≈ 14 % del presupuesto, en la franja 0–25 %: se pausan las funcionalidades nuevas y el equipo prioriza confiabilidad (respaldos y alertas de capacidad); postmortem sin culpables en dos días hábiles. Un segundo incidente similar en el mes lo llevaría a ≤ 0 % y al congelamiento total.
- **Datos:** pérdida irreversible de mensajes (RPO real = "desde el último respaldo" = infinito).

### Plan

**Prevención**
- Separar los datos del sistema: volumen EBS dedicado para los volúmenes de Docker con `delete_on_termination = false` (en producción: Amazon RDS Multi-AZ con backups automáticos y recuperación a un punto en el tiempo).
- Respaldos: `pg_dump` diario a S3 cifrado con versionado y snapshots diarios del EBS con Data Lifecycle Manager. Objetivos propuestos: **RPO 24 h, RTO 1 h** en el laboratorio; RPO 5 min con RDS en producción.
- Probar la restauración una vez al mes (un respaldo no probado no es un respaldo).
- Limitar el crecimiento: `--storage.tsdb.retention.size` en Prometheus, `docker image prune` al final de `deploy.sh` y la rotación de logs ya configurada en `daemon.json`.

**Detección**
- Agregar `node_exporter` y alertas de capacidad:
  - `DiskWillFillIn4h`: `predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 4*3600) < 0` (warning).
  - `DiskAlmostFull`: espacio libre < 10 % (critical).
- Alerta de respaldo: hora del último `pg_dump` exitoso > 26 h.

**Mitigación (extensión del runbook `RUNBOOK.md`)**
1. Confirmar la causa: `df -h /`, `docker system df`, logs de `database` con `No space left on device`.
2. Liberar espacio sin tocar datos: `docker image prune -a` (imágenes sin uso) y logs antiguos.
3. Si no alcanza, ampliar el disco en caliente: `aws ec2 modify-volume --size 50`, luego `growpart` y `resize2fs` en la instancia; no requiere reiniciar.
4. Reiniciar PostgreSQL y validar con `pg_isready` y una consulta de lectura; confirmar en Grafana que la sonda vuelve a 1 y los 5xx a 0.
5. Si la base no arranca de forma consistente, restaurar el último `pg_dump` y comunicar la ventana de datos perdidos.

---

## 3. Escenario 2 — Un pico de tráfico satura la única réplica de Zulip

### Narrativa

La universidad anuncia por Zulip las notas finales y 300 estudiantes entran al mismo tiempo. El tráfico pasa de unas 5 a más de 250 peticiones por segundo. A los pocos segundos el gateway empieza a devolver **502** y las respuestas exitosas tardan más de un segundo. El host de 2 vCPU queda al 100 %: Zulip compite por CPU con PostgreSQL y con los siete contenedores de observabilidad. Prometheus retrasa sus recolecciones y algunos paneles muestran huecos justo cuando más se necesitan. Los usuarios recargan la página, lo que agrava la carga.

### 5 Porqués

| # | Pregunta | Respuesta |
|---|---|---|
| 1 | ¿Por qué los usuarios recibieron 502 y respuestas lentas? | El NGINX interno de Zulip no pudo entregar peticiones al socket de uWSGI: `connect() to unix:/home/zulip/deployments/uwsgi-socket failed (11: Resource temporarily unavailable)`. Lo reprodujimos en el GameDay 2: 100 RPS estable, 250 RPS con 502. |
| 2 | ¿Por qué el socket de uWSGI rechazó conexiones? | Una sola réplica de Zulip tiene un número fijo de workers y un backlog limitado; con todos ocupados, las conexiones nuevas se rechazan de inmediato. |
| 3 | ¿Por qué no se repartió ni se limitó la carga? | Hay una sola instancia, sin balanceador ni autoescalado, y el gateway no aplica límites de tasa ni control de admisión: toda la demanda llega a Zulip. |
| 4 | ¿Por qué no sabíamos cuánta carga soportábamos? | No hay pruebas de capacidad en el pipeline ni un SLO o alerta de saturación. El único dato de capacidad (≈ 100–250 RPS) salió del GameDay, en otro hardware. |
| 5 | ¿Por qué todo depende de una sola máquina? | La arquitectura priorizó costo y simplicidad: aplicación, datos y observabilidad comparten 2 vCPU, así que una saturación degrada al mismo tiempo el servicio y la capacidad de verlo. |

**Causa raíz:** no hay gestión de capacidad: ni límites de admisión, ni escalado horizontal, ni separación entre la aplicación y su observabilidad.

### Impacto en SLI/SLO y presupuesto (hipótesis del incidente)

| Señal | Durante el pico (45 min) | Burn rate | Alerta | Presupuesto consumido |
|---|---|---|---|---|
| Disponibilidad | 30 % de respuestas 502 | B = 0,30 / 0,01 = **30** | FastBurn (> 14,4) dispara en ≈ 2 min | 30 × 0,75 / 720 = **3,1 %** |
| Latencia | 60 % de respuestas > 500 ms | B = 0,60 / 0,05 = **12** | SlowBurn (> 6) dispara en ≈ 5 min | 12 × 0,75 / 720 = 1,3 % |

- **El costo real no está en el presupuesto mensual sino en la experiencia:** 45 minutos con un tercio de las peticiones fallidas en el momento de mayor uso. Si los picos se repiten cada semana (anuncios, entregas), el presupuesto de disponibilidad baja a ≈ 88 % en un mes sin que la alerta `Ticket` (B(3d) > 1) llegue a disparar: un pico de 45 min diluido en 3 días da B(3d) ≈ 0,3. Las alertas de burn rate detectan cada pico, pero no el patrón semanal; eso se ve en la tendencia del presupuesto y en la revisión mensual del SLO.
- **Golden signals, en orden de aparición:** tráfico ↑ (primero), saturación ↑ (conexiones del gateway, CPU de `zulip`), latencia ↑, errores 5xx ↑. Que el tráfico suba **antes** que los errores distingue este escenario de una falla de dependencia (escenario 1), donde el tráfico no cambia.
- **Riesgo de ceguera:** con la CPU saturada, Prometheus y el colector pueden retrasarse. La alerta `ZulipTelemetryMissing` existe para no confundir un panel vacío con "cero errores".

### Plan

**Prevención**
- Control de admisión en el gateway: `limit_req` por IP y un límite global que responda **503 rápido** antes de saturar uWSGI (*load shedding*). Se despliega como cambio de configuración con recarga en caliente por el pipeline actual, sin reiniciar Zulip.
- Capacidad: ajustar workers de uWSGI con base en mediciones; separar la observabilidad en otra instancia; en producción, un Auto Scaling Group en dos zonas detrás de un Application Load Balancer, con PostgreSQL en RDS.
- Prueba de capacidad (por ejemplo, k6 o el perfil del GameDay 2) en el pipeline antes de cada versión, con un umbral de RPS mínimo.

**Detección**
- Alertas de saturación antes del error:
  - `GatewaySaturation`: `zulip_gateway_connections{state="active"} / 1024 > 0.7` durante 5 min.
  - `HostCpuSaturation`: CPU de los contenedores > 85 % durante 5 min (cAdvisor).
- Mantener FastBurn y SlowBurn como red de seguridad sobre el síntoma.

**Mitigación (runbook del GameDay 2)**
1. Confirmar el patrón: el tráfico subió primero; las dependencias siguen en 1 (descarta el escenario 1).
2. Revisar el log interno de Zulip buscando el rechazo del socket de uWSGI y correlacionar con CPU por contenedor.
3. Contener: activar `limit_req` (PR → pipeline → `nginx -s reload`, sin reinicio). Si el origen es un cliente abusivo, bloquearlo.
4. Si la demanda es legítima y persiste: escalar verticalmente la instancia (implica una ventana de reinicio) o, en producción, aumentar réplicas.
5. Verificar que los 5xx vuelvan a 0 y el p95 a su línea base (≈ 30 ms); dejar registro para el postmortem.

---

## 4. Conclusiones

1. **Los dos escenarios nacen de la misma decisión:** todo vive en una máquina. Fue correcto para un laboratorio (costo y tiempo), pero concentra el riesgo: un disco o una CPU saturados tumban a la vez el servicio y, en parte, su observabilidad.
2. **Detectamos síntomas, no causas tempranas.** Las alertas de burn rate funcionan (lo comprobamos en los GameDays), pero no hay alertas de capacidad (disco, CPU, conexiones) que avisen horas antes.
3. **Un respaldo no probado no existe.** La brecha más grave es la de datos: no hay RPO/RTO, ni respaldos, ni restauración ensayada.
4. **Lo prioritario por costo/beneficio:** (1) respaldos diarios con restauración probada, (2) alertas de disco y saturación, (3) control de admisión en el gateway. Las tres caben en la arquitectura actual; el escalado horizontal y RDS quedan para un entorno productivo con presupuesto.

## 5. Controles para los demás modos de falla

| Modo de falla | Control existente | Control propuesto |
|---|---|---|
| Imagen de Zulip defectuosa desplegada por el pipeline | La versión se fija en `.env.example` por PR; `deploy.sh` verifica Zulip, targets y dependencias y deja el job en rojo si fallan | Despliegue blue-green con una segunda réplica detrás del gateway; rollback automático a la imagen anterior si la verificación falla |
| Créditos de AWS agotados o cuenta suspendida | Instancia de bajo costo; el plan gratuito no permite exceder el límite | Alerta de AWS Budgets al 50 % y 80 %; plan de migración a una cuenta de pago antes del vencimiento |
| Runner self-hosted comprometido desde un PR de un fork | `deploy.yml` solo corre en push a `main` o manualmente; los otros workflows usan runners de GitHub | Aprobación obligatoria para workflows de colaboradores externos; runners efímeros; rol de la instancia con permisos mínimos (hoy solo SSM) |
