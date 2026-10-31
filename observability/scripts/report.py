import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import struct

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=Path.home() / 'Downloads' / 'delivery3-team-5.docx')
args = parser.parse_args()
doc = Document()
section = doc.sections[0]
section.page_height, section.page_width = Cm(29.7), Cm(21)
section.top_margin, section.bottom_margin = Cm(2), Cm(1.8)
section.left_margin, section.right_margin = Cm(2), Cm(2)
styles = doc.styles
for name in ['Normal', 'Body Text', 'List Bullet', 'List Number']:
    styles[name].font.name = 'Calibri'
    styles[name].font.size = Pt(10)
    styles[name].font.color.rgb = RGBColor.from_string('202B33')
    styles[name].paragraph_format.space_after = Pt(6)
styles['Normal'].paragraph_format.line_spacing = 1.12
for name, size in [('Title', 30), ('Heading 1', 19), ('Heading 2', 13), ('Heading 3', 11)]:
    styles[name].font.name = 'Calibri'
    styles[name].font.size = Pt(size)
    styles[name].font.color.rgb = RGBColor.from_string('16364B')
styles['Caption'].font.size = Pt(9)
styles['Caption'].font.color.rgb = RGBColor.from_string('526675')
header = section.header.paragraphs[0]
header.text = 'EQUIPO 5  /  ZULIP                                      FUNDAMENTOS DE DEVOPS Y SRE'
header.style = styles['Caption']
footer = section.footer.paragraphs[0]
footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
footer.add_run('Entrega 3 · ')
field = OxmlElement('w:fldSimple')
field.set(qn('w:instr'), 'PAGE')
footer._p.append(field)
properties = doc.core_properties
properties.title = 'Entrega 3 — Operación SRE y observabilidad de Zulip'
properties.author = 'Equipo 5'
properties.subject = 'SLIs, SLOs, presupuesto de error, Grafana, alertas y runbook'
properties.keywords = 'Zulip, SRE, Grafana, Prometheus, Equipo 5'

def text(value, style=None):
    p = doc.add_paragraph(style=style)
    for i, part in enumerate(re.split(r'(`[^`]+`|\*\*[^*]+\*\*)', value)):
        run = p.add_run(part.strip('`*') if part.startswith(('`', '**')) else part)
        if part.startswith('`'):
            run.font.name = 'Consolas'
            run.font.size = Pt(8.5)
        if part.startswith('**'):
            run.bold = True
    return p

def heading(value, level=1):
    return doc.add_heading(value, level)

def table(headers, rows):
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = 'Light Shading Accent 1'
    for cell, value in zip(t.rows[0].cells, headers):
        cell.text = value
    for row in rows:
        for cell, value in zip(t.add_row().cells, row):
            cell.text = str(value)
    repeat = OxmlElement('w:tblHeader')
    t.rows[0]._tr.get_or_add_trPr().append(repeat)
    for row in t.rows:
        row._tr.get_or_add_trPr().append(OxmlElement('w:cantSplit'))
        for cell in row.cells:
            for p in cell.paragraphs:
                for run in p.runs:
                    run.font.size = Pt(9)
    doc.add_paragraph()
    return t

def code(value):
    p = doc.add_paragraph()
    p.paragraph_format.keep_together = True
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(7)
    p.paragraph_format.line_spacing = 1
    shading = OxmlElement('w:shd')
    shading.set(qn('w:fill'), 'EFF3F6')
    p._p.get_or_add_pPr().append(shading)
    r = p.add_run(value)
    r.font.name = 'Consolas'
    r.font.size = Pt(7.5)

def image(name, caption):
    path = ROOT / 'evidence' / name
    if not path.exists():
        raise FileNotFoundError('Falta evidencia requerida: ' + str(path))
    width, height = struct.unpack('>II', path.read_bytes()[16:24])
    doc.add_picture(str(path), width=Cm(min(17, 22 * width / height)))
    doc.paragraphs[-1].paragraph_format.keep_with_next = True
    text(caption, 'Caption')

def markdown(path, start=None, stop=None):
    lines = path.read_text().splitlines()
    if start:
        lines = lines[next(i for i,l in enumerate(lines) if l.startswith(start)):]
    if stop:
        lines = lines[:next(i for i,l in enumerate(lines) if l.startswith(stop))]
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('```'):
            block = []
            i += 1
            while i < len(lines) and not lines[i].startswith('```'):
                block.append(lines[i]); i += 1
            code('\n'.join(block))
        elif line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                row = [x.strip() for x in lines[i].strip('|').split('|')]
                if not all(re.fullmatch(r'[:\- ]+', x or ' ') for x in row):
                    rows.append(row)
                i += 1
            table(rows[0], rows[1:]); continue
        elif line.startswith('#'):
            depth = len(line) - len(line.lstrip('#'))
            heading(line.lstrip('# '), min(3, max(2, depth)))
        elif line.startswith('- '):
            text(line[2:], 'List Bullet')
        elif line.strip():
            text(line)
        i += 1

heading('Operación SRE y\nobservabilidad de Zulip', 0)
text('Entrega 3 · Periodo académico 2026-02', 'Subtitle')
text('Facultad de Ingeniería\nPosgrados en Ingeniería de Sistemas y Computación\nFundamentos de DevOps y SRE')
doc.add_paragraph()
heading('1. Datos del equipo')
table(['Grupo', 'Integrantes'], [['Equipo 5', 'Jonathan David Moncaleano Angel\nAndrés Felipe Lugo Rodriguez\nCamilo Alfonso Mosquera Benavides']])
text('Fecha de elaboración: 30 de octubre de 2026.')
text('La plataforma conserva el despliegue de Zulip de las entregas anteriores. En esta entrega incorporamos una frontera de medición HTTP, métricas de las dependencias, un dashboard provisionado en Grafana y reglas que relacionan las alertas con el presupuesto de error. La prueba operativa detiene PostgreSQL, mantiene peticiones de lectura y comprueba la recuperación del mismo volumen.')
text('El resultado corresponde a una ejecución de laboratorio. Los SLOs se definieron sobre 30 días, pero las evidencias cubren la sesión de prueba. No se presenta ese historial corto como una medición mensual.')
doc.add_page_break()
heading('2. SLIs, SLOs y presupuesto de error')
markdown(ROOT / 'SRE.md', start='## Alcance', stop='## Alertamiento')
doc.add_page_break()
heading('3. Pila de observabilidad')
text('NGINX recibe el tráfico HTTPS y lo reenvía a Zulip. Al completar cada petición registra la duración y el estado HTTP. El colector convierte esos registros en contadores e histogramas y, en paralelo, consulta PostgreSQL, Redis y Memcached con sus credenciales. RabbitMQ expone sus métricas mediante el plugin nativo. cAdvisor aporta CPU y memoria de los contenedores.')
image('architecture.png', 'Figura 1. Ruta del tráfico, recolección de métricas y distribución de alertas.')
text('Prometheus recoge muestras cada 15 segundos, evalúa las reglas con la misma frecuencia y conserva 35 días. Grafana recibe la fuente de datos y el dashboard desde archivos versionables; no depende de una configuración manual. Los volúmenes conservan métricas, configuración y eventos al recrear contenedores.')
table(['Señal', 'Zulip', 'PostgreSQL y dependencias'], [
    ['Latencia', 'p95 HTTP y proporción de respuestas ≤ 500 ms', 'p95 de sondas autenticadas; no equivale a la duración de consultas de usuarios'],
    ['Tráfico', 'Peticiones/s por clase de ruta', 'Transacciones/s, comandos Redis/Memcached y mensajes publicados RabbitMQ'],
    ['Errores', 'Proporción HTTP 5xx', 'Rollback/deadlocks, errores Redis, sondas fallidas; los misses se muestran como diagnóstico de caché'],
    ['Saturación', 'Conexiones NGINX, CPU y memoria', 'Conexiones PostgreSQL/máximo, memoria y ocupación de cachés, colas y memoria RabbitMQ'],
])
text('La ejecución se realizó en Docker Desktop 29.3.1 sobre Apple Silicon, con 11 CPU y aproximadamente 7,65 GiB disponibles para la máquina virtual. La imagen de Zulip se ejecutó como amd64 y el resto de la pila utilizó imágenes compatibles con el host. Estas condiciones describen el laboratorio; no constituyen un dimensionamiento para producción.')
text('El montaje de cAdvisor es privilegiado y queda dentro de la red de monitoreo. En Docker Desktop, los recursos observados pertenecen a la máquina virtual Linux, no a todo macOS. Las interfaces operativas se publican únicamente en 127.0.0.1. Los secretos y el certificado local se excluyen de Git.')
heading('3.1. Tráfico nominal', 2)
image('nominal-grafana.png', 'Figura 2. Dashboard operativo: objetivos, saldo de presupuesto y Golden Signals durante carga nominal.')
image('nominal-dependencies.png', 'Figura 3. Métricas de PostgreSQL y dependencias durante la misma ejecución.')
nominal = json.loads((ROOT / 'evidence/nominal-load.json').read_text())
table(['Prueba', 'Resultado observado'], [
    ['Ruta consultada', nominal['url']], ['Peticiones completadas', nominal['requests']],
    ['Estados HTTP', json.dumps(nominal['statuses'])], ['p95 del generador', f"{nominal['p95_seconds']:.4f} s"],
    ['Carga programada', f"{nominal['configured_rps']} peticiones/s"],
])
text('El p95 del generador incluye la conexión y el recorrido desde el cliente; el p95 del dashboard se calcula a partir del histograma registrado por NGINX. Sus valores pueden diferir por la frontera de medición y la resolución de los buckets. El generador sigue redirecciones, por lo que una solicitud del cliente puede producir más de una respuesta en el gateway.')
doc.add_page_break()
heading('4. Alertamiento y simulación')
markdown(ROOT / 'SRE.md', start='## Alertamiento', stop='## Fuentes')
heading('4.1. Regla implementada', 2)
code('''- alert: ZulipErrorBudgetFastBurn
  expr: >-
    (zulip:slo_burn_rate:1h > 14.4)
    and on(slo) (zulip:slo_burn_rate:5m > 14.4)
  for: 2m
  labels:
    severity: critical
    service: zulip''')
text('La misma regla sirve para ambos SLOs mediante la etiqueta slo. Las reglas de grabación dividen la tasa de errores por 0,01 para disponibilidad y por 0,05 para latencia. El archivo completo también incluye el consumo lento, el aviso de investigación y la pérdida de telemetría.')
heading('4.2. Ejecución de la falla y recuperación', 2)
text('Primero se confirmó carga nominal con respuestas correctas. Después se detuvo únicamente el contenedor PostgreSQL del proyecto y se mantuvo carga durante cuatro minutos. Se guardaron el estado de Prometheus, las alertas y el resultado de las peticiones. A continuación se inició el mismo contenedor, sin borrar su volumen, y se continuó la carga para comprobar la recuperación y la resolución de la alerta.')
for name, title in [('incident-load.json', 'PostgreSQL detenido'), ('recovery-load.json', 'PostgreSQL restablecido')]:
    result = json.loads((ROOT / 'evidence' / name).read_text())
    text(f"{title}: {result['requests']} peticiones; estados {json.dumps(result['statuses'])}; p95 del generador {result['p95_seconds']:.4f} s.")
image('incident-grafana.png', 'Figura 4. Degradación observada durante la interrupción de PostgreSQL.')
image('incident-alerts.png', 'Figura 5. Estado de las reglas en Prometheus durante la falla; la evidencia JSON conserva también los tiempos y etiquetas.')
image('recovery-grafana.png', 'Figura 6. Servicio restablecido y evolución de las ventanas de consumo después de reactivar PostgreSQL.')
heading('4.3. Resultados y límites de la prueba', 2)
markdown(ROOT / 'evidence/RESULTS.md')
doc.add_page_break()
heading('5. Runbook operativo')
markdown(ROOT / 'RUNBOOK.md', start='Servicio:')
doc.add_page_break()
heading('6. Enlaces del proyecto y archivos entregados')
text('Repositorio: https://github.com/Unal-Team5-Devops/zulip-docker')
text('Directorio de manifiestos: https://github.com/Unal-Team5-Devops/zulip-docker/tree/main/observability')
text('Los cambios se dejan en el área de trabajo, sin commits ni publicación remota. Los enlaces identifican el repositorio y la ubicación prevista para su revisión y posterior publicación por el equipo.')
table(['Archivo', 'Contenido'], [
    ['observability/compose.yml', 'Servicios y conexiones con el despliegue existente'],
    ['observability/prometheus/rules.yml', 'Cálculo de SLIs, SLOs, presupuesto y alertas'],
    ['observability/grafana/dashboards/zulip-sre.json', 'Dashboard de Golden Signals y SLOs'],
    ['observability/alertmanager/alertmanager.yml', 'Agrupación, inhibición y receptor local'],
    ['observability/SRE.md y RUNBOOK.md', 'Acuerdos y procedimiento operativo'],
    ['observability/scripts y tests', 'Carga, simulación, snapshots y validación'],
    ['observability/evidence', 'Capturas y resultados obtenidos en la ejecución'],
])
heading('Referencias', 2)
for reference in [
    'Google. The Site Reliability Workbook: Alerting on SLOs. https://sre.google/workbook/alerting-on-slos/',
    'Prometheus. Histograms and summaries. https://prometheus.io/docs/practices/histograms/',
    'Grafana Labs. Provision Grafana. https://grafana.com/docs/grafana/latest/administration/provisioning/',
    'RabbitMQ. Monitoring with Prometheus and Grafana, versión 4.2. https://www.rabbitmq.com/docs/4.2/prometheus',
    'Zulip. Docker environment variables. https://zulip.readthedocs.io/projects/docker/en/latest/reference/environment-vars.html',
]:
    text(reference)
text('Se conserva el identificador Equipo 5 del repositorio. El enunciado utiliza una letra genérica para el nombre de entrega; al no registrar una letra asignada, los archivos se nombran delivery3-team-5. La fecha límite del PDF contiene campos sin diligenciar y no permite establecer un vencimiento concreto.')
args.output.parent.mkdir(parents=True, exist_ok=True)
doc.save(args.output)
print(args.output)
