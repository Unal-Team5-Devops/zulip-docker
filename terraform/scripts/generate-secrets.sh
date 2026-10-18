#!/usr/bin/env bash
set -euo pipefail
umask 077
SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/secrets"
mkdir -p "$SECRETS_DIR"
for name in \
  zulip__postgres_password \
  zulip__memcached_password \
  zulip__rabbitmq_password \
  zulip__redis_password \
  zulip__secret_key \
  zulip__email_password
do
  openssl rand -hex 32 > "$SECRETS_DIR/$name"
  chmod 600 "$SECRETS_DIR/$name"
  printf 'Secret file created: secrets/%s\n' "$name"
done
printf 'Secret values were not printed. Do not commit the secrets directory.\n'
