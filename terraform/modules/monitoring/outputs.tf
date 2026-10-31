output "prometheus_url" {
  description = "Interfaz web local de Prometheus."
  value       = "http://${var.bind_address}:${var.prometheus_port}"
}

output "blackbox_exporter_url" {
  description = "Endpoint local de diagnóstico del Blackbox Exporter."
  value       = "http://${var.bind_address}:${var.blackbox_port}"
}

output "container_names" {
  value = {
    prometheus        = docker_container.prometheus.name
    blackbox_exporter = docker_container.blackbox_exporter.name
    postgres_exporter = docker_container.postgres_exporter.name
    redis_exporter    = docker_container.redis_exporter.name
    grafana           = docker_container.grafana.name
  }
}


output "grafana_url" {
  description = "Interfaz web local de Grafana."
  value       = "http://${var.bind_address}:${var.grafana_port}"
}
