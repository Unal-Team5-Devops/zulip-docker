# Reglas de entrada:
#   8080 (gateway NGINX medido) -> público: es Zulip, y todo pasa por el SLO.
#   3000/9090/9093 (Grafana, Prometheus, Alertmanager) -> solo IP del equipo.
#   22 -> cerrado: la administración entra por SSM Session Manager.
# Zulip publica 80/443 únicamente en 127.0.0.1 de la instancia, así que no hay
# forma de saltarse el gateway y quedar fuera de la medición.
locals {
  admin_ports = {
    grafana      = 3000
    prometheus   = 9090
    alertmanager = 9093
  }

  admin_rules = merge([
    for name, port in local.admin_ports : {
      for cidr in var.admin_cidrs : "${name}-${cidr}" => { port = port, cidr = cidr, name = name }
    }
  ]...)
}

resource "aws_security_group" "zulip" {
  name        = "${local.name}-host"
  description = "Zulip publico por el gateway; paneles solo para el equipo"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-host" }
}

#trivy:ignore:AVD-AWS-0107 Zulip es un servicio público; el 8080 es el gateway medido por los SLO.
resource "aws_vpc_security_group_ingress_rule" "gateway" {
  for_each = toset(var.public_cidrs)

  security_group_id = aws_security_group.zulip.id
  description       = "Zulip via gateway NGINX medido"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "admin" {
  for_each = local.admin_rules

  security_group_id = aws_security_group.zulip.id
  description       = "Panel ${each.value.name} solo para el equipo"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# Salida abierta: la instancia descarga paquetes, imágenes de GHCR/Docker Hub
# y se conecta a GitHub (runner) y a SSM. No existe una lista fija de destinos.
#trivy:ignore:AVD-AWS-0104 La salida a internet es necesaria para paquetes, imágenes, el runner y SSM.
resource "aws_vpc_security_group_egress_rule" "all" {
  #checkov:skip=CKV_AWS_382:La salida a internet es necesaria para paquetes, imágenes, el runner y SSM.
  security_group_id = aws_security_group.zulip.id
  description       = "Salida a internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
