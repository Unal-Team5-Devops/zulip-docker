output "zulip_url" {
  description = "URL local de Zulip. El navegador advertirá que el certificado es autofirmado."
  value       = "https://${var.zulip_external_host}"
}

output "published_ports" {
  description = "Puertos publicados en la dirección local configurada."
  value = {
    bind_address = var.bind_address
    http         = var.http_port
    https        = var.https_port
  }
}

output "container_names" {
  description = "Nombres de los contenedores gestionados por Terraform."
  value       = module.services.container_names
}

output "docker_networks" {
  description = "Redes Docker creadas por Terraform."
  value       = module.network.network_names
}

output "docker_volumes" {
  description = "Volúmenes Docker creados por Terraform."
  value       = module.persistence.volume_names
}
