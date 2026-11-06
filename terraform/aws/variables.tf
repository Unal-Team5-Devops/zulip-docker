variable "aws_region" {
  description = "Región de AWS donde se crea el entorno."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Nombre del proyecto; prefijo de los recursos y etiqueta project."
  type        = string
  default     = "zulip"
}

variable "environment" {
  description = "Nombre del entorno; etiqueta environment."
  type        = string
  default     = "aws"
}

variable "github_repository" {
  description = "Repositorio (owner/nombre) autorizado a asumir el rol de GitHub Actions por OIDC."
  type        = string
  default     = "Unal-Team5-Devops/zulip-docker"
}

variable "instance_type" {
  description = "Tipo de instancia. Debe ser x86 (la imagen de Zulip es amd64) y con al menos 8 GiB para Zulip más la observabilidad."
  type        = string
  default     = "m7i-flex.large"

  # Las cuentas en el plan gratuito de AWS solo pueden lanzar tipos marcados
  # como Free Tier; de ellos, solo estos dos son x86 con 8 GiB o más de memoria.
  validation {
    condition     = contains(["m7i-flex.large", "c7i-flex.large", "t3.large", "t3.xlarge", "m7i.large"], var.instance_type)
    error_message = "Use un tipo x86 con memoria suficiente (m7i-flex.large en el plan gratuito)."
  }
}

variable "root_volume_size_gb" {
  description = "Tamaño en GiB del disco raíz (imágenes, volúmenes de Docker y métricas)."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size_gb >= 25
    error_message = "Zulip y sus imágenes necesitan al menos 25 GiB."
  }
}

variable "vpc_cidr" {
  description = "Rango de la VPC del entorno."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Rango de la subred pública donde vive la instancia."
  type        = string
  default     = "10.40.1.0/24"
}

variable "public_cidrs" {
  description = "Orígenes que pueden abrir Zulip a través del gateway medido (puerto 8080)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_cidrs" {
  description = "IP del equipo (formato x.x.x.x/32) con acceso a Grafana, Prometheus y Alertmanager. No hay valor por defecto: los paneles nunca quedan abiertos a internet por omisión."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "Indique al menos una IP del equipo y no use 0.0.0.0/0 para los paneles."
  }
}

variable "create_github_oidc_provider" {
  description = "Crea el proveedor OIDC de GitHub en la cuenta. Ponga false si la cuenta ya tiene uno para token.actions.githubusercontent.com."
  type        = bool
  default     = true
}

variable "state_bucket" {
  description = "Bucket S3 del estado; el rol de GitHub recibe acceso solo a este bucket."
  type        = string
}

variable "runner_version" {
  description = "Versión del runner self-hosted de GitHub Actions que se descarga en la instancia."
  type        = string
  default     = "2.338.2"
}
