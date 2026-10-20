output "frontend_name" {
  description = "Nombre de la red frontend."
  value       = docker_network.frontend.name
}

output "backend_name" {
  description = "Nombre de la red backend."
  value       = docker_network.backend.name
}

output "networks" {
  description = "Redes creadas con su subred y si son internas."
  value = {
    frontend = {
      name     = docker_network.frontend.name
      subnet   = var.frontend_subnet
      internal = docker_network.frontend.internal
    }
    backend = {
      name     = docker_network.backend.name
      subnet   = var.backend_subnet
      internal = docker_network.backend.internal
    }
  }
}
