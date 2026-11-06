# Entorno de Zulip en AWS: una VPC propia con una subred pública y una sola
# instancia EC2 con Docker. Terraform aprovisiona la infraestructura; la pila
# (Zulip, datos y observabilidad) la despliega el pipeline deploy.yml mediante
# el runner self-hosted que corre dentro de la instancia.
locals {
  name = "${var.project}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
#trivy:ignore:AVD-AWS-0178 Flow logs no se habilitan en el laboratorio (costo); el tráfico HTTP queda en el access log del gateway.
resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:Flow logs fuera de alcance del laboratorio; el gateway registra cada petición.
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

# El security group por defecto queda sin reglas: nada puede usarlo por descuido.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-default-closed" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Cómputo
# ---------------------------------------------------------------------------
# AMI oficial de Canonical publicada en SSM: siempre la última de Ubuntu 24.04
# para x86. ignore_changes evita que una AMI nueva reemplace la instancia viva.
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "zulip" {
  #checkov:skip=CKV_AWS_126:El monitoreo detallado de CloudWatch tiene costo; las métricas las recolecta Prometheus.
  #checkov:skip=CKV_AWS_88:IP pública al arrancar para que cloud-init instale Docker antes de asociar la IP elástica.
  ami                         = data.aws_ssm_parameter.ubuntu_ami.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.zulip.id]
  iam_instance_profile        = aws_iam_instance_profile.zulip.name
  associate_public_ip_address = true
  ebs_optimized               = true
  monitoring                  = false

  # Solo IMDSv2 y un salto: los contenedores no pueden pedir las credenciales
  # del rol de la instancia.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    runner_version = var.runner_version
  })

  tags = { Name = "${local.name}-host" }

  lifecycle {
    # La instancia es el entorno vivo: ni una AMI nueva ni un ajuste del script
    # de arranque deben recrearla por sorpresa. Para reconstruir, usar -replace.
    ignore_changes = [ami, user_data]
  }
}

# IP fija: el nombre <ip>.sslip.io de Zulip no cambia si la instancia se detiene.
resource "aws_eip" "zulip" {
  domain   = "vpc"
  instance = aws_instance.zulip.id

  tags = { Name = "${local.name}-eip" }

  depends_on = [aws_internet_gateway.main]
}
