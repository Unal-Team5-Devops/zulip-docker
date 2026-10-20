variable "name_prefix" {
  description = "Prefijo para los nombres de los volúmenes."
  type        = string
}

variable "labels" {
  description = "Etiquetas comunes que se aplican a cada volumen."
  type        = map(string)
}
