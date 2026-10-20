# Zulip con Terraform sobre Docker (entrega 2)

Terraform aprovisiona el mismo sistema de la entrega 1 (Zulip, PostgreSQL, memcached, RabbitMQ y Redis) directamente sobre un Docker Engine, con el proveedor [`kreuzwerker/docker`](https://registry.terraform.io/providers/kreuzwerker/docker/4.6.0). No usa nube ni credenciales de proveedores: el "entorno virtualizado" es el daemon Docker local (o el del runner de GitHub Actions).

## Arquitectura

```text
                     Navegador (host)
                           │  HTTP 80 / HTTPS 443, solo en 127.0.0.1
┌──────────────────────────┼──────────────────────────────────────────┐
│ red zulip-dev-frontend   │  172.30.10.0/24  (bridge)                │
│                   ┌──────┴───────┐                                  │
│                   │ zulip-dev-   │  capa compute                    │
│                   │ zulip        │──── vol zulip-dev-zulip-data (/data)
│                   └──────┬───────┘                                  │
└──────────────────────────┼──────────────────────────────────────────┘
┌──────────────────────────┼──────────────────────────────────────────┐
│ red zulip-dev-backend    │  172.30.20.0/24  (internal = true)       │
│    ┌─────────────┬───────┴──────┬──────────────┐                    │
│ ┌──┴──────┐ ┌────┴─────┐ ┌──────┴─────┐ ┌──────┴───┐  capa data     │
│ │postgres │ │memcached │ │ rabbitmq   │ │ redis    │                │
│ │  :5432  │ │  :11211  │ │   :5672    │ │  :6379   │  sin puertos   │
│ └──┬──────┘ └──────────┘ └──────┬─────┘ └──────┬───┘  en el host    │
└────┼────────────────────────────┼──────────────┼────────────────────┘
  vol postgresql-14          vol rabbitmq     vol redis
```

| Capa | Módulo | Recursos | Por qué está separada |
|------|--------|----------|-----------------------|
| Red | `modules/network` | 2 `docker_network` con subred y gateway fijos | Aísla los datos: la red backend es interna y no tiene salida al exterior. |
| Persistencia | `modules/persistence` | 4 `docker_volume` | El ciclo de vida de los datos no depende de los contenedores; reemplazar uno no borra nada. |
| Datos | `modules/data` | 4 `docker_image` + 4 `docker_container` | Servicios con estado, solo en la red backend, sin puertos publicados y con healthcheck. |
| Cómputo | `modules/compute` | 1 `docker_image` + 1 `docker_container` | Zulip no guarda estado propio; es la única pieza en las dos redes y con puertos. |

Cada módulo tiene `main.tf`, `variables.tf`, `outputs.tf` y `versions.tf`. La raíz (`main.tf`) solo los compone: cómputo recibe de datos los endpoints (`module.data.endpoints`), y como estos son los nombres de los contenedores, Terraform crea Zulip después de que los cuatro servicios estén healthy (`wait = true`).

### Dimensionamiento

- Zulip pide al menos 2 GB de RAM y 2 núcleos; con las cuatro dependencias en el mismo host se recomiendan unos 4 GB.
- Las subredes son `/24` (254 direcciones) cada una: sobra para 5 contenedores y deja espacio para réplicas en entregas siguientes.
- No se fija un límite de memoria por contenedor: en Docker local el límite de `memory` provoca diferencias entre planes en `memory_swap` y el host ya es un único dominio de fallo.
- Memcached no tiene volumen porque es una caché en memoria.

## Organización del código

```
terraform/
├── versions.tf          # Terraform >= 1.6, docker 4.6.0, random ~> 3.9
├── providers.tf         # provider docker (host = var.docker_host)
├── backend.tf           # backend local explícito
├── variables.tf         # entradas de la raíz, con validaciones
├── secrets.tf           # random_password por secreto (o TF_VAR_secrets)
├── main.tf              # composición de módulos y etiquetas comunes
├── outputs.tf           # URL, redes, volúmenes, endpoints, contenedores
├── terraform.tfvars.example
├── .terraform.lock.hcl  # versiones exactas de los proveedores (se versiona)
├── .tflint.hcl
├── policy/docker.rego   # políticas OPA (conftest) sobre el plan
├── scripts/verify.sh    # verificación tras el apply (Linux/macOS)
├── scripts/verify.ps1   # lo mismo para Windows PowerShell
└── modules/{network,persistence,data,compute}/
```

### Variables

| Variable | Por defecto | Descripción |
|----------|-------------|-------------|
| `project` | `zulip` | Prefijo de nombres y etiqueta `project`. |
| `environment` | `dev` | `dev`, `test` o `prod`; parte del prefijo (`zulip-dev-*`). |
| `docker_host` | `null` | Daemon Docker; `null` usa `DOCKER_HOST` o el socket local. |
| `frontend_subnet` / `backend_subnet` | `172.30.10.0/24` / `172.30.20.0/24` | Subredes de las dos redes. |
| `zulip_image` | `ghcr.io/unal-team5-devops/zulip-docker:sha-2699602` | Imagen publicada por el CI; `latest` no se acepta. |
| `data_images` | `zulip/zulip-postgresql:14`, `memcached:1.6-alpine`, `rabbitmq:4.2`, `redis:7-alpine` | Imágenes de datos. |
| `zulip_external_host` | `zulip.localhost` | `SETTING_EXTERNAL_HOST`. |
| `zulip_admin_email` | `admin@example.com` | `SETTING_ZULIP_ADMINISTRATOR`. |
| `zulip_certificates` | `self-signed` | Modo TLS de Zulip. |
| `bind_address` | `127.0.0.1` | IP donde se publican 80/443; `0.0.0.0` no se acepta. |
| `http_port` / `https_port` | `80` / `443` | Puertos en el host. |
| `secrets` | `{}` (sensible) | Sustituye secretos generados; solo por `TF_VAR_secrets`. |

### Salidas

`zulip_url`, `published_ports`, `networks`, `volumes`, `data_endpoints`, `containers` y `realm_creation_command` (el comando para crear la primera organización).

### Estado y credenciales

- **Secretos:** `secrets.tf` genera con `random_password` las seis credenciales (contraseñas de PostgreSQL, memcached, RabbitMQ y Redis, `secret_key` y `email_password`). No hay ninguna en el código ni hay que crear archivos a mano. Llegan a los contenedores como archivos de solo lectura (`0400`) en `/run/secrets/` mediante bloques `upload`; los servicios los leen con `*_PASSWORD_FILE` y Zulip con `/run/secrets/zulip__<nombre>`. Ninguna contraseña queda en variables de entorno (lo comprueba una política).
- Para usar valores propios: `export TF_VAR_secrets='{"postgres_password":"..."}'`.
- **Estado:** backend `local` declarado en `backend.tf`. El estado contiene los secretos, por eso `*.tfstate` está en `.gitignore` y no se comparte. Si el equipo necesita estado compartido, se migra a un backend remoto con cifrado y bloqueo (`terraform init -migrate-state`).
- **No rote secretos a la ligera:** PostgreSQL y RabbitMQ guardan la contraseña en su volumen al inicializarse. Cambiarla en Terraform sin cambiarla dentro del servicio rompe la conexión.

## Uso

Requisitos: Docker Engine o Docker Desktop activo, Terraform >= 1.6, puertos 80 y 443 libres (apague el `docker compose` de la entrega 1 si está corriendo) y unos 4 GB de RAM.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # opcional
terraform init
terraform plan -out=tfplan        # Plan: 22 to add
terraform apply tfplan
terraform plan -detailed-exitcode # 0 = No changes (idempotencia)
./scripts/verify.sh
```

En Windows PowerShell los comandos son los mismos; si Terraform no encuentra Docker, ponga `docker_host = "npipe:////./pipe/docker_engine"` en `terraform.tfvars` y use `.\scripts\verify.ps1`. Si PowerShell no deja ejecutar el script por permisos:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

El primer arranque de Zulip tarda varios minutos (crea la base de datos y genera certificados). Siga el progreso con `docker logs -f zulip-dev-zulip` y luego:

1. Abra `https://zulip.localhost` (el certificado es autofirmado, el aviso del navegador es esperable). Si no resuelve, agregue `127.0.0.1 zulip.localhost` al archivo hosts.
2. Genere el enlace de la primera organización con el comando de `terraform output realm_creation_command`.

### Comprobar el desacoplamiento de datos

```bash
terraform apply -replace=module.compute.docker_container.zulip
```

Terraform destruye y recrea solo el contenedor de Zulip; los volúmenes, la red y los servicios de datos quedan intactos, y la organización y los mensajes siguen ahí.

### Destruir

`terraform destroy` elimina contenedores, redes **y los volúmenes con sus datos**. Haga respaldo antes si los necesita.

## Validación y gobernanza

| Herramienta | Qué revisa | Dónde |
|-------------|-----------|-------|
| `terraform fmt -check` | Formato canónico | CI |
| `terraform validate` | Sintaxis, tipos y referencias | CI |
| tflint 0.64 (preset `all`) | Variables y salidas documentadas y tipadas, estructura estándar de módulo, versiones fijadas, nombres | CI y local |
| checkov 3.3 (`terraform`, `secrets`) | Malas prácticas y credenciales escritas en el código | CI |
| Trivy (`misconfig`, `secret`) | Configuración insegura y secretos, MEDIUM o superior | CI |
| conftest 0.71 + `policy/docker.rego` | Reglas propias sobre el plan | CI y local |
| Segundo `terraform plan -detailed-exitcode` | Idempotencia | CI |

Políticas de `policy/docker.rego` (bloquean el pipeline):

1. Ningún puerto publicado en `0.0.0.0` o `::`.
2. Los contenedores de la capa de datos no publican puertos.
3. Ningún contenedor privilegiado.
4. Toda imagen lleva etiqueta fija distinta de `latest`.
5. Ninguna variable de entorno con nombre de secreto (`*PASSWORD`, `*SECRET`, `*TOKEN`, ...); las `*_FILE` sí se permiten.
6. Contenedores, redes y volúmenes llevan las etiquetas `project`, `environment`, `managed-by` y `layer`.
7. La red de la capa de datos es interna.
8. Todo volumen pertenece a la capa de datos.

Además avisa (sin bloquear) si un contenedor no tiene política de reinicio o un servicio de datos no tiene healthcheck.

Para correrlas en local:

```bash
terraform plan -out=tfplan && terraform show -json tfplan > plan.json
conftest test plan.json -p policy
```

### Pipeline (`.github/workflows/terraform.yml`)

Se ejecuta en cada PR o push a `main` que toque `terraform/**`, y a mano con `workflow_dispatch`.

1. **static-analysis:** fmt, init, validate, tflint, checkov y Trivy.
2. **plan:** `terraform plan` contra el Docker del runner, conftest sobre el plan y el plan en texto como artefacto `terraform-plan`. `plan.json` no se sube porque contiene los secretos.
3. **idempotency:** `apply` real en el runner, segundo `plan -detailed-exitcode` (falla si hay cambios), lista de recursos y `destroy` siempre al final.

## Problemas frecuentes

- **`Cannot connect to the Docker daemon`:** compruebe `docker version`; en Windows, `docker_host`.
- **`port is already allocated`:** algo usa 80/443 (por ejemplo el compose de la entrega 1). Deténgalo o cambie `http_port`/`https_port`.
- **`Pool overlaps with other one on this address space`:** cambie `frontend_subnet`/`backend_subnet`.
- **`manifest unknown` al bajar Zulip:** la etiqueta `sha-...` no existe en GHCR; use una publicada por el CI.
- **Zulip se reinicia en bucle:** revise `docker logs zulip-dev-zulip` y que los cuatro servicios estén `healthy`.

## Límites conocidos

Todo corre en un único host Docker: es un solo punto de fallo, sin réplicas de Zulip ni de PostgreSQL y con volúmenes locales. Es el punto de partida para la entrega de alta disponibilidad.
