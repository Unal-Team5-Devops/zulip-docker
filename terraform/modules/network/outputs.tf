output "frontend_name" {
  value = docker_network.frontend.name
}

output "backend_name" {
  value = docker_network.backend.name
}

output "network_names" {
  value = {
    frontend = docker_network.frontend.name
    backend  = docker_network.backend.name
  }
}
