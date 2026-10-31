variable "frontend_network_name" {
  description = "Red Docker frontend: Zulip, Blackbox Exporter, Prometheus y Grafana."
  type        = string
}

variable "backend_network_name" {
  description = "Red Docker backend interna: Prometheus la necesita para consultar exportadores de las dependencias."
  type        = string
}

variable "labels" {
  description = "Etiquetas comunes; el módulo agrega layer = observability y una etiqueta service específica."
  type        = map(string)
}

variable "config_dir" {
  description = "Ruta absoluta local de los archivos Prometheus y Blackbox Exporter."
  type        = string
}

variable "images" {
  description = "Imágenes de Prometheus, exportadores y Grafana, con etiqueta fija."
  type = object({
    prometheus        = string
    blackbox_exporter = string
    postgres_exporter = string
    redis_exporter    = string
    grafana           = string
  })
}

variable "bind_address" {
  description = "Dirección local en la que se publican las interfaces de monitoreo."
  type        = string
  default     = "127.0.0.1"
}

variable "prometheus_port" {
  description = "Puerto de Prometheus en el equipo local."
  type        = number
  default     = 9090
}

variable "blackbox_port" {
  description = "Puerto local de diagnóstico del Blackbox Exporter."
  type        = number
  default     = 9115
}

variable "grafana_config_dir" {
  description = "Directorio local con los archivos de provisioning y dashboards de Grafana."
  type        = string
}

variable "grafana_admin_password" {
  description = "Contraseña inicial del administrador de Grafana."
  type        = string
  sensitive   = true
}

variable "grafana_admin_user" {
  description = "Usuario administrador inicial de Grafana."
  type        = string
  default     = "admin"
}

variable "grafana_port" {
  description = "Puerto local de la interfaz web de Grafana."
  type        = number
  default     = 3000
}

variable "exporter_secrets" {
  description = "Credenciales generadas por Terraform para consultar PostgreSQL y Redis."
  type = object({
    postgres_password = string
    redis_password    = string
  })
  sensitive = true
}
