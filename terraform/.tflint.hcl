config {
  # Analiza también las llamadas a módulos locales.
  call_module_type = "all"
}

plugin "terraform" {
  enabled = true
  # "all" activa también las reglas de documentación, tipos y estructura estándar.
  preset = "all"
}
