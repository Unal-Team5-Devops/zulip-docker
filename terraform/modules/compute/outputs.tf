output "container_name" {
  description = "Nombre del contenedor de Zulip."
  value       = docker_container.zulip.name
}
