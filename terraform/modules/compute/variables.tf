variable "name_prefix" {
  description = "Prefijo para el nombre del contenedor."
  type        = string
}

variable "labels" {
  description = "Etiquetas comunes; el módulo agrega layer = compute."
  type        = map(string)
}

variable "frontend_network_name" {
  description = "Red expuesta al host."
  type        = string
}

variable "backend_network_name" {
  description = "Red interna donde están los servicios de datos."
  type        = string
}

variable "zulip_volume_name" {
  description = "Volumen montado en /data."
  type        = string
}

variable "endpoints" {
  description = "Host y puerto de cada servicio de datos (salida del módulo data)."
  type = object({
    postgres  = object({ host = string, port = number })
    memcached = object({ host = string, port = number })
    rabbitmq  = object({ host = string, port = number })
    redis     = object({ host = string, port = number })
  })
}

variable "secrets" {
  description = "Secretos de Zulip: las cuatro contraseñas de datos, secret_key y email_password."
  type        = map(string)
  sensitive   = true
}

variable "image" {
  description = "Imagen de Zulip con etiqueta fija."
  type        = string
}

variable "external_host" {
  description = "SETTING_EXTERNAL_HOST de Zulip."
  type        = string
}

variable "admin_email" {
  description = "SETTING_ZULIP_ADMINISTRATOR de Zulip."
  type        = string
}

variable "certificates" {
  description = "Modo TLS de Zulip (CERTIFICATES)."
  type        = string
}

variable "bind_address" {
  description = "IP del host donde se publican los puertos."
  type        = string
}

variable "http_port" {
  description = "Puerto HTTP en el host."
  type        = number
}

variable "https_port" {
  description = "Puerto HTTPS en el host."
  type        = number
}
