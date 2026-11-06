# Acuerdos de servicio de Zulip

Equipo 5 · Fundamentos de DevOps y SRE · 2026-02

## Alcance de la medición

La frontera de servicio es el gateway HTTPS de `https://zulip.localhost:8080`. Cada respuesta completada de la web y las API produce un contador y una observación de duración. NGINX incluye su espera por el upstream y registra también los 502/504 si Zulip no responde. Se usan dos clases de ruta (`web`, `api`) y cuatro clases de estado para mantener acotada la cardinalidad. No se guardan usuarios, mensajes, parámetros ni tokens en las etiquetas o en el access log.

Se excluyen `/static/`, `/user_uploads/`, `/json/events` y `/api/v1/events`. Las dos últimas rutas usan long polling: una conexión abierta puede ser saludable aunque dure decenas de segundos. Las peticiones 4xx cuentan como respuestas del servicio, porque normalmente corresponden a autenticación, permisos o entradas inválidas; su aumento exige revisar también la experiencia de usuario. Estas metas no prometen entrega de mensajes, funcionamiento de notificaciones ni disponibilidad del frontend en el navegador.

Las peticiones que eviten el gateway y entren por los puertos originales 80/443 no forman parte del SLI. La pérdida del gateway o del colector se detecta por alertas de telemetría/dependencias y no se convierte artificialmente en éxito. No se declara cumplimiento cuando el denominador es cero. La evaluación comienza con las muestras disponibles y permanece provisional hasta completar los 30 días. La carga del taller consulta la página pública de inicio de sesión mediante GET; es tráfico sintético identificado, no actividad de usuarios reales.

## Indicadores y objetivos

Ventana móvil W = 30 días = 2 592 000 segundos. N(W) es el número de respuestas elegibles; E(W), las respuestas 5xx; F(W), las respuestas de duración menor o igual a 0,5 segundos.

| Indicador | Definición | Objetivo | Presupuesto |
| --- | --- | --- | --- |
| Disponibilidad HTTP | A(W) = 1 − E(W) / N(W) | A ≥ 0,95 | 0,05 × N(W) respuestas fallidas |
| Latencia | L(W) = F(W) / N(W) | L ≥ 0,95; equivale a p95 ≤ 500 ms con la resolución del histograma | 0,05 × N(W) respuestas lentas |

La infraestructura es de instancia única: una meta de 95% permite estudiar fallos y recuperación sin afirmar alta disponibilidad que aún no existe. En la Entrega 3 la meta era 99%; para la Entrega 4 se bajó a 95% al pasar a una sola instancia en AWS que también corre los GameDays. Con 95% el burn rate de una caída total es 1 / 0,05 = 20, todavía mayor que el umbral de FastBurn (14,4), por lo que las alertas conservan sus umbrales; con 90% el máximo sería 10 y FastBurn no podría disparar nunca. La meta de 500 ms busca que las consultas cortas y la navegación resulten ágiles. Son acuerdos iniciales del laboratorio, pendientes de recalibrar con un mes de tráfico representativo; no proceden de una línea base mensual medida. La equivalencia del presupuesto de disponibilidad con 36 horas (2.160 minutos) en 30 días solo es válida si la carga se distribuye uniformemente: el presupuesto implementado cuenta peticiones, no minutos.

Consultas de disponibilidad y latencia, respectivamente:

```promql
1 - sum(rate(zulip_http_requests_total{status_class="5xx"}[30d]))
  / sum(rate(zulip_http_requests_total[30d]))

sum(rate(zulip_http_request_duration_seconds_bucket{le="0.5"}[30d]))
  / sum(rate(zulip_http_request_duration_seconds_count[30d]))
```

El archivo `prometheus/rules.yml` agrega la condición de denominador mayor que cero. `rate` corrige reinicios de contadores. El bucket de 500 ms mide directamente la meta; el percentil se presenta como diagnóstico:

```promql
histogram_quantile(0.95,
  sum by (le) (rate(zulip_http_request_duration_seconds_bucket[5m])))
```

Para cada SLO, con fracción permitida b = 0,05 en ambos SLO, e(W) = fracción observada de fallos o de respuestas lentas:

- Burn rate: B(W) = e(W) / b.
- Presupuesto restante: R(W) = 1 − B(W).
- Equivalente en respuestas restantes: b × N(W) − respuestas malas(W).

Un saldo negativo indica agotamiento; no se trunca a cero en el dashboard. El saldo de la ventana móvil se recupera cuando salen errores antiguos o cambia la proporción observada. No se resetean contadores para recuperar presupuesto. Las reglas de 30 días consultan tasas agregadas sobre esa ventana; equivalen a proporciones de incrementos con la extrapolación de Prometheus, no a un registro contable exacto de cada petición.

## Política de presupuesto de error

Desarrollo y operación comparten estos acuerdos. Durante cada semana, quien coordine la entrega revisa el peor saldo de los dos SLOs y registra la decisión en la incidencia o en la revisión del cambio.

| Estado | Decisión operativa | Responsable y salida |
| --- | --- | --- |
| Saldo > 50%, sin consumo acelerado | Cambios normales con CI y verificación posterior | Autor del cambio y revisor |
| Saldo entre 25% y 50% | Reducir el tamaño de los cambios; revisar capacidad y últimas regresiones | Desarrollo prioriza correcciones; operación vigila la siguiente ventana |
| Saldo entre 0% y 25%, o burn rate crítico | Pausar nuevas funcionalidades y cambios de infraestructura no urgentes; abrir incidente si existe impacto | Responsable del incidente coordina diagnóstico y recuperación |
| Saldo ≤ 0% en cualquiera de los SLOs | Congelar cambios no críticos; permitir solo recuperación, seguridad urgente y correcciones verificadas | Equipo acuerda las excepciones y deja justificación y reversión |
| Recuperación | Reabrir cambios cuando ambos saldos sean positivos, no haya alertas críticas y B(1h) < 1 durante una hora | Revisión conjunta de desarrollo y operación |

Un incidente crítico tiene una persona coordinadora y otra a cargo del diagnóstico; el tercer integrante registra tiempos y verifica recuperación. Los roles se asignan al comenzar el incidente, sin inventar una guardia permanente. Se redacta una revisión sin culpables dentro de dos días hábiles: impacto, línea de tiempo, causa, acciones y responsable de cada acción. Con menos de 30 días, los saldos sirven como señal operativa provisional y no como certificación de cumplimiento.

## Alertamiento

| Regla | Condición simultánea, para cada SLO | Persistencia | Acción |
| --- | --- | --- | --- |
| FastBurn | B(1h) > 14,4 y B(5m) > 14,4 | 2 min | Incidente crítico; consume aproximadamente 2% del presupuesto mensual en una hora |
| SlowBurn | B(6h) > 6 y B(30m) > 6 | 5 min | Incidente crítico; consume aproximadamente 5% del presupuesto en seis horas |
| HighErrorRatio | Errores 5xx en 5 min > 20% | 2 min | Incidente crítico por síntoma; con SLO de 95% detecta una caída total en ~3 min, mientras FastBurn necesita ~43 min de ventana con tráfico estable |
| Ticket | B(3d) > 1 y B(6h) > 1 | 15 min | Investigación en el siguiente bloque de trabajo |

Las equivalencias de consumo suponen carga aproximadamente uniforme. Las ventanas dobles exigen degradación reciente y sostenida; el `for` evita avisos por muestras aisladas. La configuración no acorta las ventanas para conseguir la evidencia: en un despliegue nuevo, Prometheus usa el historial disponible, por lo que las alertas pueden activarse antes de tener una hora completa.

Alertmanager agrupa por regla y SLO, espera 10 segundos, repite cada cuatro horas e inhibe avisos warning del mismo SLO cuando hay un critical. Envía eventos firing y resolved a `alert-receiver`, que guarda JSON en un volumen persistente y en stdout. Este receptor deja evidencia local; un servicio con guardia real debe sustituirlo por un canal atendido. No se configura un correo o chat ficticio.

## Fuentes técnicas

- Google SRE Workbook, alertas por ventanas múltiples: https://sre.google/workbook/alerting-on-slos/
- Prometheus, histogramas y SLOs: https://prometheus.io/docs/practices/histograms/
- Grafana, provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/
- RabbitMQ, métricas nativas: https://www.rabbitmq.com/docs/4.2/prometheus
