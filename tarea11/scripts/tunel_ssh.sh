#!/usr/bin/env bash
# tarea11/scripts/tunel_ssh.sh
# Guia y lanzamiento de tunel SSH hacia pgAdmin (Prueba 11.3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$TAREA_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$TAREA_DIR/.env"
    set +a
fi

LOCAL_PORT="${SSH_TUNNEL_LOCAL_PORT:-8080}"
REMOTE_HOST="${SSH_TUNNEL_REMOTE_HOST:-127.0.0.1}"
REMOTE_PORT="${SSH_TUNNEL_REMOTE_PORT:-${PGADMIN_HOST_PORT:-5050}}"

echo "======================================================"
echo "  TUNEL SSH - GESTION SEGURA DE pgAdmin (Tarea 11)"
echo "======================================================"
echo ""
echo "Desde su maquina LOCAL (Linux Mint), ejecute:"
echo ""
echo -e "  \033[1;36mssh -L ${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT} USUARIO@IP_SERVIDOR\033[0m"
echo ""
echo "Luego abra en el navegador local:"
echo ""
echo -e "  \033[1;32mhttp://localhost:${LOCAL_PORT}\033[0m"
echo ""
echo "Credenciales pgAdmin (ver .env):"
echo "  Email:    ${PGADMIN_EMAIL:-admin@sysadmin.local}"
echo "  Password: (valor de PGADMIN_PASSWORD en .env)"
echo ""

read -rp "¿Desea iniciar el tunel ahora desde esta maquina? [s/N]: " resp
if [[ "${resp,,}" == "s" ]]; then
    read -rp "Usuario SSH: " ssh_user
    read -rp "IP del servidor: " ssh_host
    echo "[INFO] Estableciendo tunel... (Ctrl+C para cerrar)"
    exec ssh -N -L "${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}" "${ssh_user}@${ssh_host}"
fi
