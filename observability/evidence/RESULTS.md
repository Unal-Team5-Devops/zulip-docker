## Registro de la ejecución

La prueba se realizó el 30 de octubre de 2026, en horario de Bogotá (UTC−5). Los JSON y las notificaciones usan UTC; por esa diferencia, sus marcas corresponden al 31 de octubre. Se conserva la hora original en cada archivo.

La carga nominal principal completó 900 peticiones GET a `/login/`, todas con HTTP 200, con una tasa programada de cinco peticiones por segundo y p95 de 30,5 ms en el cliente. Se añadieron dos cargas de 300 peticiones para observar el dashboard durante las capturas; sus archivos se conservan por separado. No se sumaron a la prueba principal para cambiar su resultado.

Antes de detener PostgreSQL, los cuatro targets de Prometheus y las cinco sondas de dependencias estaban en 1. El snapshot `pre-incident.json`, tomado a las 19:10:10, registró disponibilidad de 99,9335%, latencia conforme de 100% y presupuesto restante de disponibilidad de 93,35%. El único 5xx anterior provenía de una comprobación durante el arranque del gateway. Se conservó ese error en los contadores; no se reinició la medición para mostrar un saldo perfecto.

## Interrupción controlada

La carga con PostgreSQL detenido comenzó a las 19:10:11 y terminó a las 19:14:11. Las 1.200 peticiones devolvieron HTTP 500. El p95 del cliente fue 33,2 ms: la aplicación rechazó rápidamente las operaciones al no poder consultar la base. Este resultado muestra por qué una respuesta rápida no basta para declarar el servicio saludable.

La condición FastBurn quedó pendiente a las 19:11:15 y pasó a firing a las 19:13:15, después de los dos minutos configurados. El receptor recibió el evento crítico a las 19:13:28. La captura `incident-alerts.png` muestra FastBurn y la alerta de PostgreSQL activas; `firing.json` conserva las etiquetas y los valores consultados.

Al terminar la interrupción, el burn rate de disponibilidad era 97,22 en cinco minutos y 40,91 en una hora. El saldo provisional de ese presupuesto era −3.991,27%. El valor negativo es correcto: expresa exceso respecto a una tolerancia del 1%, sobre un historial corto con una falla deliberada. El SLO de latencia seguía en 99,53% de respuestas dentro de 500 ms; la alerta crítica observada correspondió al SLO de disponibilidad.

La mitigación consistió en iniciar el mismo contenedor PostgreSQL y conservar su volumen. La comprobación posterior devolvió HTTP 200 y el contenedor recuperó el estado healthy. No se aplicaron migraciones, restauraciones ni borrados de datos durante la simulación.

## Comprobación de recuperación

Entre las 19:14:11 y las 19:20:11 se completaron otras 1.800 peticiones, todas con HTTP 200 y p95 de 29,8 ms. Al cerrar la prueba, los cuatro targets estaban up y las cinco sondas de dependencias respondían. El burn rate de cinco minutos era 0 para ambos SLOs. La alerta de dependencia recibió resolución a las 19:15:43; la resolución de FastBurn llegó al receptor a las 19:19:28.

SlowBurn se activó a las 19:15:45 y su notificación llegó a las 19:15:58. Continuaba firing al cierre porque las ventanas de 30 minutos y seis horas aún incluían la falla. Esto es consistente con la regla: la recuperación no elimina inmediatamente los errores históricos. No se afirmó que todas las alertas quedaran resueltas.

El snapshot final registró disponibilidad provisional de 72,30%, cumplimiento de latencia de 99,72%, saldo de disponibilidad de −2.669,59% y saldo de latencia de 94,47%. La captura de recuperación puede mostrar valores ligeramente distintos por su hora de toma y el refresco de 15 segundos. El servicio quedó restablecido; el presupuesto de disponibilidad quedó agotado y corresponde mantener la restricción de cambios no críticos.

## Alcance y acciones pendientes

La instancia de laboratorio no contiene una organización creada. Se verificaron la página pública de inicio de sesión y la dependencia real de PostgreSQL, no el envío de mensajes entre usuarios ni notificaciones de extremo a extremo. El tráfico de RabbitMQ y las cachés puede ser bajo en este escenario; sus paneles muestran métricas recogidas, no valores añadidos para llenar gráficos.

El colector procesa las líneas nuevas del gateway. Una interrupción del colector puede dejar peticiones sin contabilizar; las alertas de telemetría y la cobertura temporal permiten advertir ese límite, pero no reconstruyen los datos perdidos. El porcentaje de cobertura del dashboard describe muestras existentes, no disponibilidad mensual.

La validación local comprobó 33 reglas, cuatro escenarios de Prometheus, tres pruebas del lector y clasificador, la configuración de Alertmanager, Compose, sintaxis Python y shell, YAML y las 32 expresiones del dashboard contra Prometheus. `validation.log` conserva la salida de las comprobaciones.

Como seguimiento del ejercicio, el equipo debe asignar una persona responsable y una fecha a la verificación autenticada con usuarios, al canal de guardia, a la rotación de logs y a la reducción del punto único de fallo de PostgreSQL. Estas mejoras no se presentan como implementadas. El consumo deliberado de presupuesto obliga a aplicar la congelación de cambios no críticos definida en la política, aunque las respuestas HTTP ya se hayan recuperado.
