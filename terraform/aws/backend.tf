# Estado remoto en S3. A diferencia del entorno local, aquí el estado no puede
# vivir en el PC de un integrante: lo comparten el equipo y el pipeline.
# El bucket se crea una sola vez con scripts/bootstrap-state.sh (cifrado,
# versionado y sin acceso público) y se pasa en el init:
#   terraform init -backend-config="bucket=<bucket>" -backend-config="region=us-east-2"
# use_lockfile crea un .tflock en el mismo bucket: dos applies no pueden
# ejecutarse a la vez y no hace falta una tabla DynamoDB.
terraform {
  backend "s3" {
    key          = "zulip/aws/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
