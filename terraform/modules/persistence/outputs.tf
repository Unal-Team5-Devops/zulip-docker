output "zulip_volume_name" {
  description = "Volumen de Zulip (/data: archivos subidos, certificados y configuración)."
  value       = docker_volume.this["zulip"].name
}

output "postgres_volume_name" {
  description = "Volumen de PostgreSQL."
  value       = docker_volume.this["postgres"].name
}

output "rabbitmq_volume_name" {
  description = "Volumen de RabbitMQ."
  value       = docker_volume.this["rabbitmq"].name
}

output "redis_volume_name" {
  description = "Volumen de Redis."
  value       = docker_volume.this["redis"].name
}

output "volume_names" {
  description = "Todos los volúmenes, por servicio."
  value       = { for k, v in docker_volume.this : k => v.name }
}
