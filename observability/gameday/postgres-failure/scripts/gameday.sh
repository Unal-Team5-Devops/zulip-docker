#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<EOF
GameDay 1 — PostgreSQL no disponible

Uso:
  $0 check
  $0 inject
  $0 load [seconds] [requests-per-second]
  $0 status
  $0 evidence <pre-incident|incident|recovery>
  $0 recover
  $0 help

Flujo recomendado: check -> inject -> investigación/status -> recover.
La recuperación nunca se ejecuta automáticamente.
EOF
}

COMMAND="${1:-help}"
case "$COMMAND" in
  check)
    exec "$GAMEDAY_SCRIPTS_DIR/health-check.sh"
    ;;
  inject)
    exec "$GAMEDAY_SCRIPTS_DIR/inject.sh"
    ;;
  load)
    [[ $# -le 3 ]] || gd::die "Uso: $0 load [seconds] [requests-per-second]"
    shift
    exec "$GAMEDAY_SCRIPTS_DIR/run-load.sh" "$@"
    ;;
  status)
    exec "$GAMEDAY_SCRIPTS_DIR/status.sh"
    ;;
  evidence)
    [[ $# -ge 2 ]] || gd::die "Indique la fase: pre-incident, incident o recovery."
    gd::capture "$2"
    ;;
  recover)
    exec "$GAMEDAY_SCRIPTS_DIR/recover.sh"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    gd::die "Comando desconocido: $COMMAND"
    ;;
esac
