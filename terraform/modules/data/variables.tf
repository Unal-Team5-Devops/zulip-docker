variable "name_prefix" {
  description = "Prefijo para los nombres de los contenedores."
  type        = string
}

variable "labels" {
  description = "Etiquetas comunes; el módulo agrega layer = data."
  type        = map(string)
}

variable "backend_network_name" {
  description = "Red interna a la que se conectan los servicios de datos."
  type        = string
}

variable "images" {
  description = "Imágenes de los servicios de datos, con etiqueta fija."
  type = object({
    postgres  = string
    memcached = string
    rabbitmq  = string
    redis     = string
  })
}

variable "postgres_volume_name" {
  description = "Volumen para /var/lib/postgresql/data."
  type        = string
}

variable "rabbitmq_volume_name" {
  description = "Volumen para /var/lib/rabbitmq."
  type        = string
}

variable "redis_volume_name" {
  description = "Volumen para /data de Redis."
  type        = string
}

variable "secrets" {
  description = "Contraseñas de los servicios de datos."
  type = object({
    postgres_password  = string
    memcached_password = string
    rabbitmq_password  = string
    redis_password     = string
  })
  sensitive = true
}
