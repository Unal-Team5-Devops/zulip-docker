#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<EOF
GameDay 2 — Incremento de tráfico

Uso:
  $0 check
  $0 inject
  $0 status
  $0 evidence <pre-incident|incident|recovery>
  $0 recover
  $0 help

inject solicita 100 (20 s) -> 250 (30 s) -> 350 (15 s, solo si hace falta) solicitudes/s.
El perfil mide la tasa realmente completada y los SLO del gateway en cada etapa.
La carga corre en primer plano; Ctrl+C la interrumpe y conserva evidencia parcial.
recover cierra la ejecución después de verificar el retorno a la línea base.
EOF
}

COMMAND="${1:-help}"
case "$COMMAND" in
  check) exec bash "$GAMEDAY_SCRIPTS_DIR/health-check.sh" ;;
  inject) exec bash "$GAMEDAY_SCRIPTS_DIR/inject.sh" ;;
  status) exec bash "$GAMEDAY_SCRIPTS_DIR/status.sh" ;;
  evidence)
    [[ $# -ge 2 ]] || gd::die "Indique la fase: pre-incident, incident o recovery."
    gd::capture "$2"
    ;;
  recover) exec bash "$GAMEDAY_SCRIPTS_DIR/recover.sh" ;;
  help|-h|--help) usage ;;
  *) usage >&2; gd::die "Comando desconocido: $COMMAND" ;;
esac
