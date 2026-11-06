# ---------------------------------------------------------------------------
# Rol de la instancia: solo SSM, para administrarla sin abrir el puerto 22.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${local.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "zulip" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name
}

# ---------------------------------------------------------------------------
# GitHub Actions -> AWS con OIDC: sin llaves de acceso guardadas en GitHub.
# Cada job pide un token firmado por GitHub y AWS lo cambia por credenciales
# temporales, solo si viene de este repositorio (main o un pull request).
# Se desactiva con enable_github_oidc = false cuando una SCP de la organización
# lo prohíbe (caso de las cuentas del plan gratuito de AWS).
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc && var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc && !var.create_github_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.enable_github_oidc ? (
    var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  ) : null
}

data "aws_iam_policy_document" "github_assume" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${var.github_repository}:pull_request",
      ]
    }
  }
}

# El pipeline solo planifica (lectura + estado). Los applies de infraestructura
# los ejecuta un integrante con sus credenciales tras revisar el plan del PR:
# la instancia es el entorno vivo y un reemplazo accidental lo apagaría.
resource "aws_iam_role" "github_plan" {
  count = var.enable_github_oidc ? 1 : 0

  name                 = "${local.name}-github-plan"
  assume_role_policy   = data.aws_iam_policy_document.github_assume[0].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "github_read_only" {
  count = var.enable_github_oidc ? 1 : 0

  role       = aws_iam_role.github_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_state" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }

  # Escritura solo del archivo de bloqueo (.tflock) que usa terraform plan.
  statement {
    sid       = "StateLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/zulip/aws/terraform.tfstate.tflock"]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/zulip/aws/terraform.tfstate"]
  }
}

resource "aws_iam_role_policy" "github_state" {
  count = var.enable_github_oidc ? 1 : 0

  name   = "terraform-state"
  role   = aws_iam_role.github_plan[0].id
  policy = data.aws_iam_policy_document.github_state[0].json
}
