# Composición de las tres capas. Cada módulo recibe solo lo que necesita:
#   network     -> redes frontend y backend
#   persistence -> volúmenes; su ciclo de vida no depende de los contenedores
#   data        -> PostgreSQL, memcached, RabbitMQ y Redis, solo en la red backend
#   compute     -> Zulip, el único contenedor en las dos redes y con puertos
locals {
  name_prefix = "${var.project}-${var.environment}"

  labels = {
    project     = var.project
    environment = var.environment
    managed-by  = "terraform"
  }
}

module "network" {
  source = "./modules/network"

  name_prefix     = local.name_prefix
  labels          = local.labels
  frontend_subnet = var.frontend_subnet
  backend_subnet  = var.backend_subnet
}

module "persistence" {
  source = "./modules/persistence"

  name_prefix = local.name_prefix
  labels      = local.labels
}

module "data" {
  source = "./modules/data"

  name_prefix          = local.name_prefix
  labels               = local.labels
  backend_network_name = module.network.backend_name
  images               = var.data_images

  postgres_volume_name = module.persistence.postgres_volume_name
  rabbitmq_volume_name = module.persistence.rabbitmq_volume_name
  redis_volume_name    = module.persistence.redis_volume_name

  secrets = {
    postgres_password  = local.secrets["postgres_password"]
    memcached_password = local.secrets["memcached_password"]
    rabbitmq_password  = local.secrets["rabbitmq_password"]
    redis_password     = local.secrets["redis_password"]
  }
}

module "compute" {
  source = "./modules/compute"

  name_prefix           = local.name_prefix
  labels                = local.labels
  frontend_network_name = module.network.frontend_name
  backend_network_name  = module.network.backend_name
  zulip_volume_name     = module.persistence.zulip_volume_name

  # Los endpoints usan los nombres de los contenedores de datos, así Terraform
  # crea Zulip solo después de que los cuatro servicios estén healthy.
  endpoints = module.data.endpoints
  secrets   = local.secrets

  image         = var.zulip_image
  external_host = var.zulip_external_host
  admin_email   = var.zulip_admin_email
  certificates  = var.zulip_certificates
  bind_address  = var.bind_address
  http_port     = var.http_port
  https_port    = var.https_port
}
