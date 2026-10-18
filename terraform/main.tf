locals {
  # Los archivos contienen los secretos; Terraform solo conoce las rutas.
  # El directorio está excluido del control de versiones mediante .gitignore.
  secrets_dir = abspath("${path.root}/secrets")
}

module "network" {
  source = "./modules/network"
}

module "persistence" {
  source = "./modules/persistence"
}

module "services" {
  source = "./modules/services"

  frontend_network_name = module.network.frontend_name
  backend_network_name  = module.network.backend_name

  zulip_volume_name    = module.persistence.zulip_volume_name
  postgres_volume_name = module.persistence.postgres_volume_name
  rabbitmq_volume_name = module.persistence.rabbitmq_volume_name
  redis_volume_name    = module.persistence.redis_volume_name

  secrets_dir         = local.secrets_dir
  zulip_image         = var.zulip_image
  zulip_external_host = var.zulip_external_host
  zulip_admin_email   = var.zulip_admin_email
  bind_address        = var.bind_address
  http_port           = var.http_port
  https_port          = var.https_port
}
