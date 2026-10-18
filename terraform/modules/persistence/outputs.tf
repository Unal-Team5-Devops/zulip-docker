output "zulip_volume_name" {
  value = docker_volume.zulip.name
}

output "postgres_volume_name" {
  value = docker_volume.postgres.name
}

output "rabbitmq_volume_name" {
  value = docker_volume.rabbitmq.name
}

output "redis_volume_name" {
  value = docker_volume.redis.name
}

output "volume_names" {
  value = {
    zulip    = docker_volume.zulip.name
    postgres = docker_volume.postgres.name
    rabbitmq = docker_volume.rabbitmq.name
    redis    = docker_volume.redis.name
  }
}
