variable "project" {
  description = "Nombre del proyecto. Se usa como prefijo de todos los recursos y como etiqueta."
  type        = string
  default     = "zulip"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project))
    error_message = "project debe empezar con una letra y tener solo minúsculas, dígitos o guiones (2 a 21 caracteres)."
  }
}

variable "environment" {
  description = "Entorno de despliegue (dev, test, prod). Forma parte del prefijo de nombres."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment debe ser dev, test o prod."
  }
}

variable "docker_host" {
  description = "Dirección del daemon Docker. null usa DOCKER_HOST o el socket local."
  type        = string
  default     = null
}

variable "frontend_subnet" {
  description = "Subred IPv4 de la red frontend (expuesta al host)."
  type        = string
  default     = "172.30.10.0/24"

  validation {
    condition     = can(cidrhost(var.frontend_subnet, 1))
    error_message = "frontend_subnet debe ser un bloque CIDR IPv4 válido."
  }
}

variable "backend_subnet" {
  description = "Subred IPv4 de la red backend (interna, sin salida al exterior)."
  type        = string
  default     = "172.30.20.0/24"

  validation {
    condition     = can(cidrhost(var.backend_subnet, 1))
    error_message = "backend_subnet debe ser un bloque CIDR IPv4 válido."
  }
}

variable "zulip_image" {
  description = "Imagen de Zulip publicada por el CI en GHCR. Use una etiqueta fija sha-<7 caracteres>, nunca latest."
  type        = string
  default     = "ghcr.io/unal-team5-devops/zulip-docker:sha-2699602"

  validation {
    condition     = can(regex(":[A-Za-z0-9._-]+$", var.zulip_image)) && !endswith(var.zulip_image, ":latest")
    error_message = "zulip_image debe llevar una etiqueta explícita distinta de latest."
  }
}

variable "data_images" {
  description = "Imágenes de los servicios de datos, con etiqueta fija."
  type = object({
    postgres  = string
    memcached = string
    rabbitmq  = string
    redis     = string
  })
  default = {
    postgres  = "zulip/zulip-postgresql:14"
    memcached = "memcached:1.6-alpine"
    rabbitmq  = "rabbitmq:4.2"
    redis     = "redis:7-alpine"
  }
}

variable "zulip_external_host" {
  description = "Nombre con el que se abre Zulip desde el navegador (SETTING_EXTERNAL_HOST)."
  type        = string
  default     = "zulip.localhost"
}

variable "zulip_admin_email" {
  description = "Correo del administrador inicial de Zulip (SETTING_ZULIP_ADMINISTRATOR)."
  type        = string
  default     = "admin@example.com"
}

variable "zulip_certificates" {
  description = "Modo TLS de Zulip: self-signed, certbot, manual o vacío (solo HTTP detrás de un proxy)."
  type        = string
  default     = "self-signed"

  validation {
    condition     = contains(["self-signed", "certbot", "manual", ""], var.zulip_certificates)
    error_message = "zulip_certificates debe ser self-signed, certbot, manual o una cadena vacía."
  }
}

variable "bind_address" {
  description = "IP del host donde se publican HTTP y HTTPS. 127.0.0.1 evita exponer Zulip a la red local."
  type        = string
  default     = "127.0.0.1"

  validation {
    condition     = can(cidrhost("${var.bind_address}/32", 0)) && var.bind_address != "0.0.0.0"
    error_message = "bind_address debe ser una IPv4 concreta; 0.0.0.0 no está permitido."
  }
}

variable "http_port" {
  description = "Puerto HTTP publicado en el host."
  type        = number
  default     = 80

  validation {
    condition     = var.http_port > 0 && var.http_port < 65536
    error_message = "http_port debe estar entre 1 y 65535."
  }
}

variable "https_port" {
  description = "Puerto HTTPS publicado en el host."
  type        = number
  default     = 443

  validation {
    condition     = var.https_port > 0 && var.https_port < 65536
    error_message = "https_port debe estar entre 1 y 65535."
  }
}

variable "secrets" {
  description = "Secretos opcionales que sustituyen a los generados (claves: postgres_password, memcached_password, rabbitmq_password, redis_password, secret_key, email_password). Páselos con TF_VAR_secrets, nunca en archivos versionados."
  type        = map(string)
  default     = {}
  sensitive   = true

  validation {
    condition = alltrue([for k in keys(var.secrets) : contains([
      "postgres_password", "memcached_password", "rabbitmq_password",
      "redis_password", "secret_key", "email_password",
    ], k)])
    error_message = "secrets solo admite las claves postgres_password, memcached_password, rabbitmq_password, redis_password, secret_key y email_password."
  }
}
