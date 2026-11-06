output "instance_id" {
  description = "ID de la instancia (para SSM Session Manager)."
  value       = aws_instance.zulip.id
}

output "public_ip" {
  description = "IP elástica del entorno."
  value       = aws_eip.zulip.public_ip
}

output "external_host" {
  description = "Nombre público de Zulip: sslip.io resuelve <ip-con-guiones>.sslip.io a la IP, sin comprar dominio."
  value       = "${replace(aws_eip.zulip.public_ip, ".", "-")}.sslip.io:8080"
}

output "zulip_url" {
  description = "URL pública de Zulip a través del gateway medido."
  value       = "https://${replace(aws_eip.zulip.public_ip, ".", "-")}.sslip.io:8080"
}

output "grafana_url" {
  description = "Grafana (solo desde admin_cidrs)."
  value       = "http://${aws_eip.zulip.public_ip}:3000/d/zulip-sre"
}

output "prometheus_url" {
  description = "Prometheus (solo desde admin_cidrs)."
  value       = "http://${aws_eip.zulip.public_ip}:9090"
}

output "alertmanager_url" {
  description = "Alertmanager (solo desde admin_cidrs)."
  value       = "http://${aws_eip.zulip.public_ip}:9093"
}

output "ssm_session_command" {
  description = "Comando para abrir una terminal en la instancia sin SSH."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.zulip.id}"
}

output "github_plan_role_arn" {
  description = "Rol que asume aws-infra.yml por OIDC; guardarlo como variable AWS_PLAN_ROLE_ARN del repositorio. Nulo si enable_github_oidc = false."
  value       = try(aws_iam_role.github_plan[0].arn, null)
}
