# Las credenciales no se escriben aquí: en local salen del perfil de la CLI
# (aws configure / AWS_PROFILE) y en GitHub Actions de OIDC (aws-infra.yml).
provider "aws" {
  region = var.aws_region

  # Todas las piezas quedan etiquetadas igual que los contenedores del entorno
  # local, así se pueden filtrar en la consola y en el reporte de costos.
  default_tags {
    tags = {
      project     = var.project
      environment = var.environment
      managed-by  = "terraform"
      repository  = var.github_repository
    }
  }
}
