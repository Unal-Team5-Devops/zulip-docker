variable "zulip_image" {
  description = "Imagen de Zulip publicada en GHCR. Para reproducibilidad, use la etiqueta sha-<7 caracteres> generada por CI."
  type        = string
  default     = "ghcr.io/unal-team5-devops/zulip-docker:latest"
}

variable "zulip_external_host" {
  description = "Nombre con el que se abrirá Zulip desde el equipo local."
  type        = string
  default     = "zulip.localhost"
}

variable "zulip_admin_email" {
  description = "Correo que será configurado como administrador inicial de Zulip."
  type        = string
  default     = "admin@example.com"
}

variable "bind_address" {
  description = "Dirección local donde se publican HTTP/HTTPS. 127.0.0.1 evita exposición a la LAN."
  type        = string
  default     = "127.0.0.1"
}

variable "http_port" {
  description = "Puerto HTTP en el host Docker."
  type        = number
  default     = 80
}

variable "https_port" {
  description = "Puerto HTTPS en el host Docker."
  type        = number
  default     = 443
}
