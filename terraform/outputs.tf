output "zulip_url" {
  description = "URL local de Zulip. El navegador advertirá que el certificado es autofirmado."
  value       = var.https_port == 443 ? "https://${var.zulip_external_host}" : "https://${var.zulip_external_host}:${var.https_port}"
}

output "published_ports" {
  description = "Puertos de Zulip publicados en el host."
  value = {
    bind_address = var.bind_address
    http         = var.http_port
    https        = var.https_port
  }
}

output "networks" {
  description = "Redes Docker con su subred."
  value       = module.network.networks
}

output "volumes" {
  description = "Volúmenes Docker de la capa de persistencia."
  value       = module.persistence.volume_names
}

output "data_endpoints" {
  description = "Host y puerto de cada servicio de datos dentro de la red backend."
  value       = module.data.endpoints
}

output "containers" {
  description = "Nombres de los contenedores por capa."
  value = {
    data    = module.data.container_names
    compute = module.compute.container_name
  }
}

output "realm_creation_command" {
  description = "Comando para generar el enlace de creación de la primera organización de Zulip."
  value       = "docker exec -u zulip ${module.compute.container_name} /home/zulip/deployments/current/manage.py generate_realm_creation_link"
}
