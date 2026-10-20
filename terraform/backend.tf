# Estado local, declarado de forma explícita. Es suficiente para un entorno
# Docker de un solo host: el estado vive junto al daemon que administra.
# El archivo contiene los secretos generados en secrets.tf, por eso está en
# .gitignore y no se comparte. Para trabajo en equipo o en la nube se puede
# migrar a un backend remoto (S3, GCS, Terraform Cloud) con:
#   terraform init -migrate-state
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
