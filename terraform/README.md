# Zulip local con Docker + Terraform (sin AWS)

Esta variante aprovisiona la infraestructura sobre el Docker Engine local usando el proveedor `kreuzwerker/docker` de Terraform. No crea recursos cloud ni necesita credenciales de AWS.

El diseño conserva los cinco servicios del repositorio [Unal-Team5-Devops/zulip-docker](https://github.com/Unal-Team5-Devops/zulip-docker): Zulip, PostgreSQL, Memcached, RabbitMQ y Redis. Se apoya en las responsabilidades y variables que declara el `docker-compose.yml` del equipo, pero Terraform administra directamente los contenedores, redes y volúmenes.

## Arquitectura

```text
Navegador del equipo
       | HTTPS 443 / HTTP 80 (publicado solo en 127.0.0.1)
       v
[ zulip-app ]
   |      |        |         |
   v      v        v         v
database memcached rabbitmq redis
   
Red frontend: zulip-app
Red backend (internal=true): zulip-app + PostgreSQL + Memcached + RabbitMQ + Redis
```

- `modules/network`: crea la red `zulip-frontend` y la red `zulip-backend`, interna y aislada del exterior.
- `modules/persistence`: crea cuatro volúmenes Docker persistentes para los datos de Zulip, PostgreSQL, RabbitMQ y Redis. Memcached no necesita volumen, igual que en el Compose de origen.
- `modules/services`: crea las imágenes y contenedores, adjunta los servicios a sus redes, monta secretos como archivos y define healthchecks en las dependencias.
- `scripts/generate-secrets.ps1` y `scripts/generate-secrets.sh`: generan seis secretos aleatorios como archivos locales. Terraform solo administra las rutas y no lee los valores secretos.
- `.github/workflows/terraform-docker-validate.yml`: valida formato y configuración Terraform, ejecuta TFLint y Checkov. El workflow no despliega contenedores en GitHub; el despliegue se hace en el Docker Engine del equipo.

**Alcance:** es una instalación local de pruebas. Los datos están desacoplados del ciclo de vida de los contenedores mediante volúmenes nombrados, pero todos los servicios usan el mismo Docker Engine. No equivale a aislamiento físico de máquinas ni a alta disponibilidad.

## Requisitos previos

1. Docker Desktop instalado y abierto (Windows/macOS) o Docker Engine activo (Linux). Usar contenedores Linux.
2. Terraform CLI 1.6 o superior instalado y disponible en `PATH`.
3. Al menos 2 GB de RAM disponibles para ejecutar Zulip. Para compilar la imagen desde el `Dockerfile` del equipo, el README del repositorio estima cerca de 4 GB de RAM y más de 20 minutos; por eso primero se intentará usar la imagen publicada en GHCR.
4. Puertos TCP locales 80 y 443 libres. Si ya están ocupados, se pueden cambiar `http_port` y `https_port` en `terraform.tfvars`; en ese caso, la URL puede requerir ajuste y los enlaces de Zulip generados internamente podrían no incorporar esos puertos no estándar.

El proveedor Terraform usa la API de Docker. Si no detecta Docker automáticamente en Windows PowerShell, establece la variable de entorno antes de ejecutar Terraform:

```powershell
$env:DOCKER_HOST = 'npipe:////.//pipe//docker_engine'
docker version
```

En Linux suele ser suficiente la conexión al socket por defecto. Para diagnosticar el daemon, comprueba primero `docker version` y `docker info`.

## Paso a paso: Windows PowerShell

Ejecuta los siguientes comandos desde la carpeta `terraform` del repositorio original:

```powershell
Set-Location .\terraform
```

### 1. Comprobar herramientas y Docker Engine

```powershell
docker version
docker info
terraform version
```

Los dos primeros comandos deben mostrar tanto la información del cliente como la del servidor Docker. Si no aparece la parte del servidor, abre/inicia Docker Desktop antes de continuar.

Si es necesario, configura el host de Docker para esta sesión:

```powershell
$env:DOCKER_HOST = 'npipe:////.//pipe//docker_engine'
```

### 2. Crear secretos locales

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\generate-secrets.ps1
```

Esto crea seis archivos dentro de `secrets/`. Los valores no se imprimen y el directorio está excluido mediante `.gitignore`. **No reemplaces los archivos en redespliegues rutinarios:** al usar una nueva contraseña sin actualizar los datos existentes, PostgreSQL u otros servicios podrían dejar de autenticarse. En una instalación de prueba limpia puedes generar otros secretos antes del primer despliegue.

### 3. Elegir la imagen de Zulip

Por defecto, Terraform intenta descargar:

```text
ghcr.io/unal-team5-devops/zulip-docker:latest
```

Para mayor reproducibilidad, cambia `zulip_image` en `terraform.tfvars` por una etiqueta de commit de siete caracteres publicada por el workflow CI, por ejemplo `ghcr.io/unal-team5-devops/zulip-docker:sha-<7-caracteres>`. Sustituye el marcador por una etiqueta real. El pipeline del repositorio genera tanto `latest` en `main` como etiquetas `sha-...`.

Copia el archivo de ejemplo y edítalo:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Asegúrate de que `zulip_image` tenga una etiqueta que exista en GHCR. Si el paquete es privado, inicia sesión con un token de lectura de paquetes, sin ponerlo en archivos versionados:

```powershell
$secureToken = Read-Host 'GHCR read:packages token' -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $secureToken).Password
$token | docker login ghcr.io -u TU_USUARIO_GITHUB --password-stdin
$token = $null
$secureToken.Dispose()
Remove-Variable -Name token,secureToken
```

El token se solicita de forma interactiva y no queda escrito en el comando. Si el login falla, usa el procedimiento interactivo documentado por GitHub Container Registry; nunca escribas el token literal en el comando. Si la imagen no está accesible, otra opción es compilar el `Dockerfile` en el repositorio original y publicar una etiqueta local disponible para Terraform, o hacer público el paquete siguiendo las políticas del equipo.

### 4. Inicializar Terraform

```powershell
terraform fmt -recursive
terraform init
```

`terraform init` descarga el proveedor `kreuzwerker/docker` fijado en `versions.tf`. Versiona el archivo `.terraform.lock.hcl` que se genera; no lo incluyas en `.gitignore`.

### 5. Revisar el plan antes de crear recursos

```powershell
terraform validate
terraform plan -out=zulip.tfplan
```

Revisa que el plan cree dos redes, cuatro volúmenes, cinco imágenes y cinco contenedores. Los archivos secretos deben existir en `secrets/`. No copies los valores de los secretos a `terraform.tfvars` ni a HCL.

### 6. Crear la infraestructura

```powershell
terraform apply zulip.tfplan
```

Terraform descargará las imágenes y creará los contenedores. La primera descarga puede tardar algunos minutos; el arranque inicial de Zulip puede tardar más que el resto de servicios. Los healthchecks de PostgreSQL, Memcached, RabbitMQ y Redis tienen espera incorporada. La creación de Zulip finaliza cuando Docker lo marca como iniciado, no cuando necesariamente se completó todo el arranque interno.

### 7. Confirmar que los contenedores están ejecutándose

```powershell
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
terraform output
```

Deben aparecer `zulip-app`, `zulip-database`, `zulip-memcached`, `zulip-rabbitmq` y `zulip-redis`. Se espera que los cuatro servicios de datos estén `healthy`. La aplicación puede requerir algo más de tiempo antes de responder en HTTP.

Consulta logs si alguno reinicia o queda unhealthy:

```powershell
docker logs --tail 100 zulip-database
docker logs --tail 100 zulip-memcached
docker logs --tail 100 zulip-rabbitmq
docker logs --tail 100 zulip-redis
docker logs --tail 200 zulip-app
```

### 8. Ejecutar la verificación automática

```powershell
.\scripts\verify.ps1
o si no te deja ejecutar por permisos
powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

El script muestra estados de contenedores, confirma que los puertos de las dependencias no estén publicados en el host, lista redes y volúmenes e intenta consultar HTTPS. Un contenedor en `running` no garantiza que Zulip haya terminado de inicializarse; revisa los logs y repite la prueba HTTP si aún no responde.

### 9. Abrir Zulip

Comprueba primero `https://zulip.localhost`. Como el certificado es autofirmado, el navegador mostrará una advertencia de seguridad esperable en esta instalación local. Solo continúa si confirmas que la dirección apunta a tu propio entorno local.

En Windows, `.localhost` suele resolver a loopback. Si el navegador no encuentra el sitio, agrega la siguiente línea al archivo `C:\Windows\System32\drivers\etc\hosts` con permisos de administrador:

```text
127.0.0.1 zulip.localhost
```

Si los puertos 80/443 se cambiaron en `terraform.tfvars`, utiliza el puerto HTTPS configurado. Los enlaces internos de Zulip no siempre conservan puertos host no estándar, por lo que es preferible reservar 80/443 para esta prueba.

### 10. Crear el primer realm/organización de Zulip

Cuando el sitio cargue, genera el enlace de creación inicial:

```powershell
docker exec -u zulip zulip-app /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

Abre el enlace que imprima el comando, completa el proceso y comprueba que puedes iniciar sesión como administrador. Esta es una validación funcional adicional a comprobar que el contenedor está `running`.

## Verificación detallada

### A. Revisar salud de contenedores

```powershell
docker inspect --format='{{.Name}} {{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' zulip-database zulip-memcached zulip-rabbitmq zulip-redis zulip-app
```

Las dependencias deberían indicar `healthy`. `zulip-app` puede mostrar `running` si no se configuró un healthcheck HTTP en la imagen. Comprueba su respuesta de manera independiente:

```powershell
curl.exe -k -I https://zulip.localhost/
```

Una respuesta HTTP indica que Nginx está atendiendo. Los códigos 200, 301, 302, 401 o 403 pueden ser respuestas legítimas según el estado del inicio de sesión; una conexión rechazada o timeout es señal de que hay que revisar los logs.

### B. Confirmar que no se publican los puertos de los datos

```powershell
docker port zulip-database
docker port zulip-memcached
docker port zulip-rabbitmq
docker port zulip-redis
```

Estos comandos no deben mostrar asignaciones de puertos al host. Solo `zulip-app` publica 80 y 443, enlazados a `127.0.0.1` por defecto:

```powershell
docker port zulip-app
```

### C. Inspeccionar redes

```powershell
docker network inspect zulip-frontend
docker network inspect zulip-backend
```

La red frontend debe incluir únicamente a `zulip-app`; la red backend debe incluir a la aplicación y a los cuatro servicios de datos. `zulip-backend` se define con `internal = true`, lo que bloquea el acceso externo a través de esa red.

### D. Confirmar persistencia

```powershell
docker volume ls --filter name=zulip-
docker inspect --format '{{json .Mounts}}' zulip-database
docker inspect --format '{{json .Mounts}}' zulip-app
```

Los volúmenes `zulip-data`, `zulip-postgresql-14`, `zulip-rabbitmq` y `zulip-redis` se mantienen al detener o recrear contenedores, siempre que no se borren explícitamente. En un reinicio de prueba, ejecuta `terraform apply` tras un cambio inocuo y verifica que los volúmenes siguen allí. **No uses `terraform destroy` para comprobar persistencia**, porque el volumen es un recurso gestionado y Terraform lo elimina al destruirlo.

### E. Verificar idempotencia

Después de que el primer despliegue finalice correctamente, repite:

```powershell
terraform plan
```

Si no cambiaste variables, versiones, imágenes ni la configuración, Terraform debería proponer `No changes`. En aplicaciones que modifican el estado internamente, eso no debería ocasionar cambios en el plan.

### F. Verificar conectividad entre servicios

Puedes probar la resolución DNS dentro de la red backend ejecutando utilidades desde la propia aplicación si están disponibles; no se publican los puertos de PostgreSQL, Memcached, RabbitMQ ni Redis en el host. Si Zulip inicia pero presenta errores de conexión, revisa los logs de `zulip-app` y los de la dependencia afectada.

## Operaciones habituales

Detener temporalmente los servicios sin eliminar datos:

```powershell
docker stop zulip-app zulip-database zulip-memcached zulip-rabbitmq zulip-redis
```

Terraform puede volver a iniciar contenedores gestionados que detecte detenidos al ejecutar `terraform apply`.

Revisar desviaciones respecto al código:

```powershell
terraform plan
```

Eliminar todos los recursos creados por este proyecto:

```powershell
terraform destroy
```

**Advertencia:** `terraform destroy` elimina contenedores, redes y también los cuatro volúmenes administrados, con sus datos. Antes de ejecutar ese comando, haz un respaldo de los datos que quieras conservar. Los archivos en `secrets/` no los elimina Terraform; bórralos manualmente cuando ya no sean necesarios.

## Problemas frecuentes

- **`Cannot connect to the Docker daemon`:** abre Docker Desktop y vuelve a ejecutar `docker version`; verifica `DOCKER_HOST` si usas Windows.
- **Error de puerto ocupado:** detén el servicio que usa 80/443 o cambia `http_port`/`https_port`. Considera que los enlaces generados pueden asumir puertos estándar.
- **`manifest unknown` o `denied` al descargar Zulip:** confirma que la etiqueta existe en GHCR y que el paquete es público o que Docker está autenticado.
- **Zulip falla al arrancar:** comprueba primero que los cuatro servicios tienen estado healthy y revisa `docker logs zulip-app`. No regeneres secretos tras inicializar datos sin planear una rotación de credenciales.
- **GitHub Actions falla en Checkov/TFLint:** revisa los hallazgos en el log. No deshabilites controles indiscriminadamente; corrige la configuración o documenta una excepción justificada.

## Supuestos y límites conocidos

1. Docker Desktop/Engine está activo y puede ejecutar imágenes Linux.
2. El paquete GHCR `ghcr.io/unal-team5-devops/zulip-docker` y la etiqueta elegida están disponibles para pull. La visibilidad del paquete puede diferir de la visibilidad del repositorio.
3. La configuración replica las dependencias y variables descritas por el Compose actual; no se ha ejecutado en la cuenta/equipo del usuario, por lo que la primera instalación debe validarse con `terraform plan`, logs y healthchecks.
4. Las etiquetas de imágenes se fijan a versiones, pero no a digest binario. Para reproducibilidad estricta, registrar digests verificados para cada imagen.
5. Los secretos están en archivos locales montados como solo lectura y no se interpolan en variables HCL. Como cualquier bind mount local, Docker requiere que existan en el host y estén protegidos por permisos del sistema.
6. El estado Terraform local contiene metadatos de los recursos y rutas de los archivos de secretos, no los valores secretos. No compartas `terraform.tfstate` aunque no esté diseñado para contener contraseñas.
7. El workflow GitHub Actions valida Terraform y no ejecuta `apply`, porque el daemon Docker local no existe en los runners hospedados. Para validar el despliegue, `terraform apply` se ejecuta desde el equipo que controla el daemon local.
