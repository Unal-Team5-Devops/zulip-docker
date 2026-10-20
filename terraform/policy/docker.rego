# Políticas de gobernanza que conftest evalúa sobre el plan en JSON:
#   terraform show -json tfplan > plan.json
#   conftest test plan.json -p policy
# deny bloquea el pipeline; warn solo avisa.
package main

import rego.v1

required_labels := {"project", "environment", "managed-by", "layer"}

secret_suffixes := ["password", "secret", "token", "api_key", "private_key"]

# Recursos que se crean o actualizan (los que se destruyen no se evalúan).
resources contains r if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
	r := {"address": rc.address, "type": rc.type, "after": rc.change.after}
}

labels_of(r) := {l.label: l.value | some l in r.after.labels}

layer_of(r) := labels_of(r).layer

# --- Exposición de red -------------------------------------------------------

deny contains msg if {
	some r in resources
	r.type == "docker_container"
	some p in r.after.ports
	p.ip in {"0.0.0.0", "::", ""}
	msg := sprintf("%s publica el puerto %v en todas las interfaces (%q); use una IP concreta como 127.0.0.1", [r.address, p.internal, p.ip])
}

deny contains msg if {
	some r in resources
	r.type == "docker_container"
	layer_of(r) == "data"
	count(r.after.ports) > 0
	msg := sprintf("%s es de la capa de datos y no debe publicar puertos en el host", [r.address])
}

deny contains msg if {
	some r in resources
	r.type == "docker_network"
	layer_of(r) == "data"
	not r.after.internal
	msg := sprintf("%s es la red de datos y debe ser interna (internal = true)", [r.address])
}

# --- Endurecimiento de contenedores ------------------------------------------

deny contains msg if {
	some r in resources
	r.type == "docker_container"
	r.after.privileged == true
	msg := sprintf("%s no puede correr en modo privilegiado", [r.address])
}

deny contains msg if {
	some r in resources
	r.type == "docker_image"
	not image_has_fixed_tag(r.after.name)
	msg := sprintf("%s usa la imagen %q sin etiqueta fija; latest no está permitido", [r.address, r.after.name])
}

image_has_fixed_tag(name) if {
	contains(name, "@sha256:")
}

image_has_fixed_tag(name) if {
	not contains(name, "@")
	parts := split(name, "/")
	last := parts[count(parts) - 1]
	contains(last, ":")
	not endswith(last, ":latest")
}

# --- Secretos ----------------------------------------------------------------

# Una variable de entorno con nombre de secreto tendría el valor en texto plano
# en "docker inspect". Se permiten las que apuntan a un archivo (*_FILE).
deny contains msg if {
	some r in resources
	r.type == "docker_container"
	some e in r.after.env
	key := lower(split(e, "=")[0])
	not endswith(key, "_file")
	some suffix in secret_suffixes
	endswith(key, suffix)
	msg := sprintf("%s define el secreto %q como variable de entorno; móntelo como archivo en /run/secrets", [r.address, split(e, "=")[0]])
}

# --- Etiquetado y separación de capas ----------------------------------------

deny contains msg if {
	some r in resources
	r.type in {"docker_container", "docker_network", "docker_volume"}
	missing := required_labels - {k | some k, _ in labels_of(r)}
	count(missing) > 0
	msg := sprintf("%s no tiene las etiquetas obligatorias %v", [r.address, sort(missing)])
}

deny contains msg if {
	some r in resources
	r.type == "docker_volume"
	layer_of(r) != "data"
	msg := sprintf("%s es un volumen y debe pertenecer a la capa de datos (layer = data)", [r.address])
}

# --- Avisos ------------------------------------------------------------------

warn contains msg if {
	some r in resources
	r.type == "docker_container"
	not r.after.restart in {"always", "unless-stopped", "on-failure"}
	msg := sprintf("%s no tiene política de reinicio", [r.address])
}

warn contains msg if {
	some r in resources
	r.type == "docker_container"
	layer_of(r) == "data"
	count(object.get(r.after, "healthcheck", [])) == 0
	msg := sprintf("%s es un servicio de datos sin healthcheck", [r.address])
}
