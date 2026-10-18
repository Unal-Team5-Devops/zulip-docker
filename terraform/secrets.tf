# Un secreto aleatorio por servicio, generado por Terraform: no hay que crear
# archivos a mano antes del apply. Los valores viven solo en el estado (que no
# se versiona) y llegan a los contenedores como archivos en /run/secrets/.
# Cualquiera puede sustituirse con TF_VAR_secrets='{"postgres_password":"..."}'.
locals {
  secret_names = toset([
    "postgres_password",
    "memcached_password",
    "rabbitmq_password",
    "redis_password",
    "secret_key",
    "email_password",
  ])
}

resource "random_password" "secret" {
  for_each = local.secret_names

  length  = 32
  special = false
}

locals {
  secrets = merge(
    { for name, pw in random_password.secret : name => pw.result },
    var.secrets,
  )
}
