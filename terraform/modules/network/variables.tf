variable "name_prefix" {
  description = "Prefijo para los nombres de las redes."
  type        = string
}

variable "labels" {
  description = "Etiquetas comunes que se aplican a cada red."
  type        = map(string)
}

variable "frontend_subnet" {
  description = "Subred IPv4 de la red frontend."
  type        = string
}

variable "backend_subnet" {
  description = "Subred IPv4 de la red backend."
  type        = string
}
