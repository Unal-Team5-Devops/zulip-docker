variable "frontend_network_name" {
  description = "Red Docker donde Zulip publica su endpoint y se conectan los componentes de monitoreo."
  type        = string
}

variable "config_dir" {
  description = "Ruta absoluta local de los archivos Prometheus y Blackbox Exporter."
  type        = string
}

variable "images" {
  description = "Imágenes de los contenedores de monitoreo, con etiqueta fija."
  type = object({
    prometheus        = string
    blackbox_exporter = string
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
