# Imagen de Zulip construida desde el código fuente (multi-stage).
# Estructura modelada sobre zulip/docker-zulip (Apache-2.0), con etapas propias.
#
#   base          -> Ubuntu 24.04 con lo mínimo
#   build         -> clona zulip/zulip y genera el tarball de producción
#   runtime-files -> descarga entrypoint y certbot de docker-zulip (tag fija)
#   final         -> instala el tarball y deja la imagen lista para ejecutar
FROM ubuntu:24.04 AS base

ENV LANG="C.UTF-8"

# hadolint ignore=DL3008,DL3009
RUN apt-get -q update && \
    apt-get -q dist-upgrade -y && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -q install --no-install-recommends -y ca-certificates git locales python3 sudo tzdata && \
    touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu && \
    useradd -d /home/zulip -m zulip -u 1000

# ---------------------------------------------------------------------------
FROM base AS build

ARG ZULIP_GIT_URL=https://github.com/zulip/zulip.git
ARG ZULIP_GIT_REF=12.3

RUN echo 'zulip ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers

USER zulip
WORKDIR /home/zulip

RUN git clone --branch "$ZULIP_GIT_REF" --depth 1 "$ZULIP_GIT_URL" zulip

WORKDIR /home/zulip/zulip

RUN SKIP_VENV_SHELL_WARNING=1 ./tools/provision --build-release-tarball-only && \
    uv run --no-sync ./tools/build-release-tarball docker && \
    mv /tmp/tmp.*/zulip-server-docker.tar.gz /tmp/zulip-server-docker.tar.gz

# ---------------------------------------------------------------------------
FROM base AS runtime-files

ARG DOCKER_ZULIP_URL=https://github.com/zulip/docker-zulip.git
ARG DOCKER_ZULIP_REF=12.3-0

WORKDIR /src
RUN git clone --branch "$DOCKER_ZULIP_REF" --depth 1 "$DOCKER_ZULIP_URL" docker-zulip

# ---------------------------------------------------------------------------
FROM base AS final

ARG ZULIP_GIT_REF=12.3

LABEL org.opencontainers.image.title="Zulip Server" \
      org.opencontainers.image.description="Zulip construido desde fuente (Fundamentos de DevOps y SRE, UNAL)" \
      org.opencontainers.image.source="https://github.com/Unal-Team5-Devops/zulip-docker" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="$ZULIP_GIT_REF" \
      org.opencontainers.image.documentation="https://zulip.readthedocs.io/projects/docker/en/latest/"

ENV DATA_DIR="/data"

COPY --from=build /tmp/zulip-server-docker.tar.gz /root/

WORKDIR /root
RUN \
    # nginx debe arrancarlo supervisord, no init.d
    dpkg-divert --add --rename /etc/init.d/nginx && \
    ln -s /bin/true /etc/init.d/nginx && \
    mkdir -p "$DATA_DIR" && \
    tar -xf zulip-server-docker.tar.gz && \
    rm -f zulip-server-docker.tar.gz && \
    mv zulip-server-docker zulip && \
    /root/zulip/scripts/setup/install --hostname="docker-zulip.local" --email="docker-zulip" \
      --puppet-classes="zulip::profile::docker" --postgresql-version=14 && \
    rm -f /etc/zulip/zulip-secrets.conf /etc/zulip/settings.py && \
    touch /.dockerenv && \
    apt-get -qq autoremove --purge -y && \
    apt-get -qq clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=runtime-files /src/docker-zulip/entrypoint.sh /sbin/entrypoint.sh
COPY --from=runtime-files /src/docker-zulip/zulip-certbot-setup /usr/local/sbin/zulip-certbot-setup

VOLUME ["$DATA_DIR"]
EXPOSE 25 80 443

HEALTHCHECK --interval=10s --timeout=5s --retries=3 --start-period=300s \
    CMD ["curl", "-isfL", "--insecure", "http://localhost/health"]

# Corre como root: el entrypoint necesita ajustar ulimit antes de bajar privilegios.
# hadolint ignore=DL3002
USER root
ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["app:run"]
