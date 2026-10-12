# zulip-docker

Empaquetado y CI de [Zulip](https://zulip.com) para la primero entrega de *Fundamentos de DevOps y SRE* (UNAL, 2026-02).

**Equipo:** 

```
Equipo 5

JONATHAN DAVID MONCALEANO ANGEL
ANDRÉS FELIPE LUGO RODRIGUEZ
CAMILO ALFONSO MOSQUERA BENAVIDES
```


## Arquitectura

```
usuario --HTTPS 443--> zulip --5432--> database (PostgreSQL 14)
                         |--11211--> memcached (SASL)
                         |--5672---> rabbitmq (AMQP)
                         '--6379---> redis (auth)
```

Redes `frontend` y `backend` (esta última `internal`). Todos los servicios son instancia única (SPOFs, a tratar en entregas posteriores).

## Uso local

```bash
./scripts/generate-env.sh      # crea .env con una serie de secretos aleatorios
docker compose up -d --build   # primera vez: el build desde fuente tarda >20 min
docker compose ps
docker compose exec -u zulip zulip /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

Requiere apróximadamente 2 GB de RAM para ejecutar y 4 GB para construir.

## Imagen

`Dockerfile` multi-stage: `base` → `build` (zulip/zulip `12.3`, tarball de producción) → `runtime-files` (entrypoint de docker-zulip `12.3-0`) → `final`.

## CI (`.github/workflows/ci.yml`)

PR y `main`: hadolint, yamllint, `docker compose config` → build → Trivy (HIGH/CRITICAL con fix) → push a GHCR solo desde `main`.
Variable de repo `TRIVY_EXIT_CODE=1` hace que Trivy falle el job.

## Procedencia y licencias

Zulip y docker-zulip son Apache-2.0. El Dockerfile está modelado sobre el de [zulip/docker-zulip](https://github.com/zulip/docker-zulip).
