output "endpoints" {
  description = "Host (nombre del contenedor, resuelto por el DNS de Docker) y puerto de cada servicio."
  value = {
    postgres  = { host = docker_container.postgres.name, port = 5432 }
    memcached = { host = docker_container.memcached.name, port = 11211 }
    rabbitmq  = { host = docker_container.rabbitmq.name, port = 5672 }
    redis     = { host = docker_container.redis.name, port = 6379 }
  }
}

output "container_names" {
  description = "Nombres de los contenedores de datos."
  value = {
    postgres  = docker_container.postgres.name
    memcached = docker_container.memcached.name
    rabbitmq  = docker_container.rabbitmq.name
    redis     = docker_container.redis.name
  }
}
