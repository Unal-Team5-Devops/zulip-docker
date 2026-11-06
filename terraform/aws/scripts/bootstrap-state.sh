#!/usr/bin/env bash
# Crea (una sola vez) el bucket S3 del estado de terraform/aws: versionado,
# cifrado y sin acceso público. Uso:
#   ./terraform/aws/scripts/bootstrap-state.sh            # zulip-tfstate-<cuenta>
#   ./terraform/aws/scripts/bootstrap-state.sh mi-bucket
set -euo pipefail

region="${AWS_REGION:-us-east-2}"
account="$(aws sts get-caller-identity --query Account --output text)"
bucket="${1:-zulip-tfstate-${account}}"

if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  echo "El bucket $bucket ya existe; no se modifica."
else
  aws s3api create-bucket --bucket "$bucket" --region "$region" \
    --create-bucket-configuration "LocationConstraint=$region"
fi

aws s3api put-public-access-block --bucket "$bucket" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$bucket" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo
echo "Bucket listo: $bucket"
echo "Siguiente paso:"
echo "  cd terraform/aws"
echo "  terraform init -backend-config=\"bucket=$bucket\" -backend-config=\"region=$region\""
