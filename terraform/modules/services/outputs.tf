output "container_names" {
  value = {
    application = docker_container.zulip.name
    database    = docker_container.database.name
    memcached   = docker_container.memcached.name
    rabbitmq    = docker_container.rabbitmq.name
    redis       = docker_container.redis.name
  }
}
