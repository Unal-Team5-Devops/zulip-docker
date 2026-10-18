variable "frontend_network_name" {
  type = string
}

variable "backend_network_name" {
  type = string
}

variable "zulip_volume_name" {
  type = string
}

variable "postgres_volume_name" {
  type = string
}

variable "rabbitmq_volume_name" {
  type = string
}

variable "redis_volume_name" {
  type = string
}

variable "secrets_dir" {
  type = string
}

variable "zulip_image" {
  type = string
}

variable "zulip_external_host" {
  type = string
}

variable "zulip_admin_email" {
  type = string
}

variable "bind_address" {
  type = string
}

variable "http_port" {
  type = number
}

variable "https_port" {
  type = number
}
