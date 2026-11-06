# Despliegue en AWS (Entrega 4)

## Arquitectura

```
                         ┌──────────────────────── AWS us-east-2 · VPC 10.40.0.0/16 ────────────────────────┐
                         │  Security group                                                                  │
Usuarios ── 8080 ───────►│  ┌──────────────── EC2 m7i-flex.large · Ubuntu 24.04 · Docker ────────────────┐  │
                         │  │ gateway NGINX :8080 (medido) ─► Zulip (80/443 solo en 127.0.0.1)          │  │
Equipo ── 3000/9090/9093►│  │ PostgreSQL · Redis · Memcached · RabbitMQ (red backend interna)           │  │
 (solo admin_cidrs)      │  │ colector · Prometheus · Grafana · Alertmanager · receptor · cAdvisor      │  │
                         │  │ runner self-hosted de GitHub Actions ──(sale por 443)──► GitHub           │  │
                         │  └───────────────────────────────────────────────────────────────────────────┘  │
Operador ── SSM ────────►│  sin puerto 22                                          IP elástica (sslip.io)    │
                         └──────────────────────────────────────────────────────────────────────────────────┘
GitHub Actions ── OIDC ─► rol de solo lectura (plan de terraform/aws)     Estado: S3 cifrado + bloqueo .tflock
```

| Capa | Herramienta | Archivos |
|---|---|---|
| Infraestructura (VPC, SG, EC2, IP, IAM, OIDC) | Terraform + estado en S3 | `terraform/aws/` |
| Aplicación y observabilidad | Docker Compose sobre la EC2 | `docker-compose.yml`, `observability/`, `deploy/compose.aws.yml` |
| Despliegue continuo | GitHub Actions + runner self-hosted en la EC2 | `.github/workflows/deploy.yml`, `deploy/deploy.sh` |
| Plan de infraestructura en PR | GitHub Actions + OIDC | `.github/workflows/aws-infra.yml` |

El entorno local de la Entrega 2 (`terraform/` con el proveedor Docker) se mantiene sin cambios.

## 1. Aprovisionar (una vez, desde un PC con la CLI de AWS)

Requisitos: AWS CLI v2 con credenciales de la cuenta (`aws configure`), Terraform ≥ 1.10.

```bash
# Bucket del estado (cifrado, versionado, sin acceso público)
AWS_REGION=us-east-2 ./terraform/aws/scripts/bootstrap-state.sh

cd terraform/aws
cp terraform.tfvars.example terraform.tfvars
# editar: state_bucket = "<bucket impreso>", admin_cidrs = ["<tu IP>/32", ...]
#   tu IP: curl -s https://checkip.amazonaws.com
terraform init -backend-config="bucket=<bucket>" -backend-config="region=us-east-2"
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

Cloud-init tarda unos 3 minutos en instalar Docker y descargar el runner (`/var/lib/zulip-bootstrap.done` indica que terminó). Versionar `terraform/aws/.terraform.lock.hcl` después del primer `init`.

## 2. Registrar el runner (una vez)

1. GitHub → repositorio → *Settings → Actions → Runners → New self-hosted runner* → Linux x64. Copiar solo el **token**.
2. Abrir una terminal en la instancia sin SSH: consola de AWS → EC2 → la instancia → *Connect → Session Manager*, o `terraform output -raw ssm_session_command`.
3. En esa terminal:

```bash
sudo -iu ubuntu
cd /opt/actions-runner
./config.sh --unattended --url https://github.com/Unal-Team5-Devops/zulip-docker \
  --token <TOKEN> --name zulip-aws --labels aws
sudo ./svc.sh install ubuntu
sudo ./svc.sh start
```

El runner aparece como *Idle* con las etiquetas `self-hosted, linux, x64, aws`.

## 3. Primer despliegue

GitHub → *Actions → Deploy → Run workflow* (o un push a `main`). La primera vez descarga imágenes y Zulip inicializa la base: 6–10 minutos. El resumen del job muestra la URL, la imagen, los targets y el estado de cada servicio.

Crear la organización de Zulip (en la terminal SSM, como `ubuntu`):

```bash
cd /opt/zulip
./observability/scripts/compose.sh exec -u zulip zulip \
  /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

El entorno no tiene SMTP: Zulip guarda los correos como archivos (`deploy/compose.aws.yml`). Para leer el último, por ejemplo la confirmación de la cuenta al crear la organización, y abrir su enlace:

```bash
./observability/scripts/compose.sh exec zulip bash -c \
  'cat "$(ls -t /var/log/zulip/emails/* | head -1)"' | grep -o 'https://[^ ]*confirm[^ ]*'
```

Contraseña de Grafana (usuario `admin`): `grep GRAFANA_ADMIN_PASSWORD /opt/zulip/.env`.

## 4. Variables del repositorio para `aws-infra.yml`

> **Hallazgo en la cuenta del equipo:** las cuentas del plan gratuito de AWS pertenecen a una organización cuya SCP niega `iam:CreateOpenIDConnectProvider`, incluso para un usuario con `AdministratorAccess`. En ese caso se aplica con `enable_github_oidc = false`: no se crea el rol y `aws-infra.yml` se omite (su job exige `AWS_PLAN_ROLE_ARN`). El despliegue continuo no depende de OIDC, porque el runner corre dentro de la instancia. En una cuenta de producción, el administrador de la organización habilitaría la acción en la SCP y el plan correría en cada PR.

*Settings → Secrets and variables → Actions → Variables*:

| Variable | Valor |
|---|---|
| `AWS_PLAN_ROLE_ARN` | `terraform output -raw github_plan_role_arn` |
| `TF_STATE_BUCKET` | nombre del bucket |
| `ADMIN_CIDRS` | lista HCL, p. ej. `["203.0.113.10/32"]` |

## 5. Cómo se aplica un cambio sin pérdida de disponibilidad

`deploy.sh` sincroniza el repositorio en `/opt/zulip` (donde viven `.env`, certificados y evidencias, fuera del checkout del runner) y aplica cada tipo de cambio de la forma menos disruptiva:

| Cambio | Mecanismo | ¿Reinicia Zulip? |
|---|---|---|
| Reglas, umbrales o configuración de Prometheus | `POST /-/reload` | No |
| Configuración de Alertmanager | `POST /-/reload` | No |
| Configuración del gateway o certificado | `nginx -s reload` (las conexiones abiertas terminan) | No |
| Dashboard de Grafana | Grafana relee el directorio cada 10 s | No |
| Código del colector | Compose recrea solo el colector | No (hueco de telemetría de segundos) |
| Imagen de Zulip (`ZULIP_IMAGE` en `.env.example`) | Compose recrea Zulip | **Sí**: una sola réplica, 3–4 min de indisponibilidad |

Después verifica Zulip a través del gateway, `min(up) == 1`, las 5 sondas de dependencias y que Prometheus haya aceptado la configuración; si algo falla, el job termina en rojo y muestra logs.

Cambio sugerido para la demostración: ajustar un umbral o el `for:` de una alerta en `observability/prometheus/rules.yml` (o el título de un panel), abrir PR, ver el check `Observability`, fusionar y seguir el job `Deploy` mientras Grafana muestra la disponibilidad sin cambios.

## 6. GameDay en AWS

Los escenarios de `observability/gameday/` se ejecutan dentro de la instancia (terminal SSM, `cd /opt/zulip`). Usan `zulip.localhost:8080`; en AWS el gateway fija el `Host` hacia el nombre público, por lo que llegan a Zulip igual que en local.

## 7. Qué faltaría para producción

| Brecha | Hoy (laboratorio) | Producción |
|---|---|---|
| Disponibilidad | 1 instancia, 1 réplica de Zulip, 1 AZ | Auto Scaling Group en 2+ AZ detrás de un ALB; despliegue rolling o blue-green |
| Base de datos | PostgreSQL en contenedor, disco de la instancia | Amazon RDS Multi-AZ con backups automáticos y PITR |
| Caché y colas | Contenedores locales | ElastiCache (Redis/Memcached) y Amazon MQ (RabbitMQ) |
| TLS y dominio | Autofirmado, `sslip.io` | Route 53 + ACM en el ALB |
| Secretos | `.env` en la instancia (permisos 600) | AWS Secrets Manager / SSM Parameter Store, rotación |
| Apply de infraestructura | Manual tras revisar el plan del PR | Rol OIDC de escritura limitado + environment con aprobación requerida |
| Runner | Uno, en la misma máquina que sirve tráfico | Runners efímeros (p. ej. en ECS/CodeBuild) o despliegue con SSM/CodeDeploy |
| Observabilidad | Prometheus local, 35 días | Amazon Managed Prometheus/Grafana o almacenamiento remoto; alertas a un canal de guardia |
| Red | Subred pública, salida abierta | Subredes privadas + NAT, VPC endpoints, flow logs, WAF en el ALB |

## Costo y limpieza

`m7i-flex.large` está en la lista Free Tier de cuentas creadas desde el 15 de julio de 2025; el consumo se descuenta de los créditos. Al terminar: `terraform destroy` en `terraform/aws` (el bucket del estado se borra aparte).
