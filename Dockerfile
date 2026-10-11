# Imagen de Zulip construida desde el código fuente (multi-stage).
# Estructura modelada sobre zulip/docker-zulip (Apache-2.0), con etapas propias.
#
# Por qué multi-stage: compilar Zulip necesita Node, compiladores y cientos de MB
# de dependencias de desarrollo. Cada etapa hace un trabajo y solo la última
# ("final") llega a la imagen publicada, que así queda mucho más liviana.
#
#   base          -> Ubuntu 24.04 con lo mínimo
#   build         -> clona zulip/zulip y genera el tarball de producción
#   runtime-files -> descarga entrypoint y certbot de docker-zulip (tag fija)
#   final         -> instala el tarball y deja la imagen lista para ejecutar

# ---------------------------------------------------------------------------
# Etapa 1: base común. De aquí parten todas las demás etapas.
# ---------------------------------------------------------------------------
# Ubuntu 24.04 es la distribución que soporta la versión 12.x de Zulip.

FROM ubuntu:24.04 AS base

# Locale UTF-8: Zulip maneja texto en muchos idiomas y falla con locales ASCII.

ENV LANG="C.UTF-8"

# Una sola instrucción RUN = una sola capa. Qué hace:
#   - apt-get update/dist-upgrade: aplica parches de seguridad de la imagen base.
#   - --no-install-recommends: instala solo lo imprescindible (imagen más pequeña).
#       ca-certificates -> para descargas HTTPS; git -> clonar repos;
#       locales/tzdata  -> idioma y zona horaria; python3/sudo -> los usa provision.
#   - borra el usuario "ubuntu" (UID 1000) y crea "zulip" con UID 1000 fijo, para
#     poder usar "USER 1000" (numérico) más abajo sin que hadolint se queje.
# DL3008/DL3009: no se fijan versiones de apt ni se limpia la caché aquí porque
# esta etapa es intermedia; la limpieza se hace en la etapa final.
# hadolint ignore=DL3008,DL3009

RUN apt-get -q update && \
    apt-get -q dist-upgrade -y && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -q install --no-install-recommends -y ca-certificates git locales python3 sudo tzdata && \
    touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu && \
    useradd -d /home/zulip -m zulip -u 1000

# ---------------------------------------------------------------------------
# Etapa 2: build. Compila Zulip y produce el paquete de producción (tarball).
# Es la parte lenta (20+ min) y la que más memoria usa (~4 GB). Todo lo que
# se instala aquí se descarta al terminar: solo sobrevive el tarball.
# ---------------------------------------------------------------------------

FROM base AS build

# ARG = parámetro de build. Permite cambiar de versión sin editar el archivo:
#   docker build --build-arg ZULIP_GIT_REF=12.4.

ARG ZULIP_GIT_URL=https://github.com/zulip/zulip.git
ARG ZULIP_GIT_REF=12.3

# El script de provision de Zulip instala paquetes con sudo, por eso el usuario
# "zulip" necesita sudo sin contraseña. Solo existe en esta etapa descartable.

RUN echo 'zulip ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers

# Se compila con un usuario sin privilegios (UID 1000 = "zulip"), no como root.

USER 1000
WORKDIR /home/zulip

# --depth 1 baja solo el commit de esa etiqueta, no los ~72 mil commits del repo.

RUN git clone --branch "$ZULIP_GIT_REF" --depth 1 "$ZULIP_GIT_URL" zulip

WORKDIR /home/zulip/zulip

# 1) provision: instala el entorno de compilación (Node, Python, dependencias).
# 2) build-release-tarball: empaqueta Zulip listo para producción.
# 3) mv: deja el tarball en una ruta fija para copiarlo desde la etapa final.

RUN SKIP_VENV_SHELL_WARNING=1 ./tools/provision --build-release-tarball-only && \
    uv run --no-sync ./tools/build-release-tarball docker && \
    mv /tmp/tmp.*/zulip-server-docker.tar.gz /tmp/zulip-server-docker.tar.gz

# ---------------------------------------------------------------------------
# Etapa 3: runtime-files. Trae los scripts de arranque del proyecto oficial.
# No se copian al repo: se descargan en el build desde una etiqueta fija, así la
# imagen es reproducible y no versionamos código ajeno.
# ---------------------------------------------------------------------------

FROM base AS runtime-files

ARG DOCKER_ZULIP_URL=https://github.com/zulip/docker-zulip.git

# 12.3-0 = etiqueta de docker-zulip que corresponde a Zulip 12.3.

ARG DOCKER_ZULIP_REF=12.3-0

WORKDIR /src
RUN git clone --branch "$DOCKER_ZULIP_REF" --depth 1 "$DOCKER_ZULIP_URL" docker-zulip

# ---------------------------------------------------------------------------
# Etapa 4: final. Es la imagen que se publica en GHCR.
# ---------------------------------------------------------------------------

FROM base AS final

ARG ZULIP_GIT_REF=12.3

# Metadatos estándar OCI. GitHub los usa para enlazar el paquete con el repo
# y mostrar licencia y descripción en la pestaña Packages.

LABEL org.opencontainers.image.title="Zulip Server" \
      org.opencontainers.image.description="Zulip construido desde fuente (Fundamentos de DevOps y SRE, UNAL)" \
      org.opencontainers.image.source="https://github.com/Unal-Team5-Devops/zulip-docker" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="$ZULIP_GIT_REF" \
      org.opencontainers.image.documentation="https://zulip.readthedocs.io/projects/docker/en/latest/"

# Carpeta donde Zulip guarda su estado (subidas, certificados, configuración).

ENV DATA_DIR="/data"

# Trae SOLO el tarball de la etapa build; nada del entorno de compilación.

COPY --from=build /tmp/zulip-server-docker.tar.gz /root/

WORKDIR /root

# Todo en una sola capa para que lo temporal se borre en la misma capa en que se
# crea (si se borrara en otra capa, el peso seguiría dentro de la imagen).

RUN \
    # nginx debe arrancarlo supervisord, no init.d: se desvía su script de arranque
    # y se reemplaza por un enlace a /bin/true que no hace nada.
    dpkg-divert --add --rename /etc/init.d/nginx && \
    ln -s /bin/true /etc/init.d/nginx && \
    mkdir -p "$DATA_DIR" && \
    # descomprime el tarball y lo deja en /root/zulip
    tar -xf zulip-server-docker.tar.gz && \
    rm -f zulip-server-docker.tar.gz && \
    mv zulip-server-docker zulip && \
    # instalador oficial: el perfil "docker" prepara nginx, supervisord, workers y
    # el cliente de PostgreSQL 14. La BD NO se instala aquí: va en otro contenedor.
    /root/zulip/scripts/setup/install --hostname="docker-zulip.local" --email="docker-zulip" \
      --puppet-classes="zulip::profile::docker" --postgresql-version=14 && \
    # borra secretos y ajustes generados durante la instalación: se vuelven a crear
    # al arrancar el contenedor a partir de los secretos y variables SETTING_*.
    rm -f /etc/zulip/zulip-secrets.conf /etc/zulip/settings.py && \
    # marcador que Zulip usa para saber que corre en Docker y adaptar sus mensajes
    touch /.dockerenv && \
    # limpieza: quita paquetes huérfanos, caché de apt y temporales
    apt-get -qq autoremove --purge -y && \
    apt-get -qq clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Entrypoint = script que, al arrancar el contenedor, lee los secretos, genera la
# configuración, ejecuta migraciones y lanza Zulip. Certbot es para HTTPS real.

COPY --from=runtime-files /src/docker-zulip/entrypoint.sh /sbin/entrypoint.sh
COPY --from=runtime-files /src/docker-zulip/zulip-certbot-setup /usr/local/sbin/zulip-certbot-setup

# VOLUME y EXPOSE son documentación: marcan dónde está el estado y qué puertos
# usa la app. No publican nada por sí solos; eso lo hace el compose.

VOLUME ["$DATA_DIR"]
EXPOSE 25 80 443

# Docker consulta /health cada 10 s para saber si la app responde.
# start-period=300s: el primer arranque corre migraciones y tarda; durante ese
# tiempo los fallos no cuentan. --insecure porque el certificado es autofirmado.

HEALTHCHECK --interval=10s --timeout=5s --retries=3 --start-period=300s \
    CMD ["curl", "-isfL", "--insecure", "http://localhost/health"]

# Corre como root: el entrypoint necesita ajustar ulimit antes de bajar privilegios.
# hadolint ignore=DL3002

USER 0

# ENTRYPOINT = lo que siempre se ejecuta; CMD = argumento por defecto (app:run
# hace la configuración inicial, las migraciones y arranca todos los procesos).

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["app:run"]
