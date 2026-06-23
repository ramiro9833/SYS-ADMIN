#!/usr/bin/env bash
# tarea11/scripts/configurar_firewall.sh
# Cierra puertos de BD y pgAdmin en el firewall del host (seguridad perimetral)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cargar variables
if [ -f "$TAREA_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$TAREA_DIR/.env"
    set +a
fi

PGADMIN_HOST_PORT="${PGADMIN_HOST_PORT:-5050}"
DB_PORT=5432

echo "======================================================"
echo "  FIREWALL HOST - TAREA 11 (Aislamiento perimetral)"
echo "======================================================"

if ! command -v ufw &>/dev/null; then
    echo "[INFO] Instalando ufw..."
    apt-get update -qq && apt-get install -y -qq ufw
fi

# Denegar acceso externo a PostgreSQL y pgAdmin
ufw deny "${DB_PORT}/tcp" comment "Tarea11: bloquear PostgreSQL externo" 2>/dev/null || true
ufw deny "${PGADMIN_HOST_PORT}/tcp" comment "Tarea11: bloquear pgAdmin externo" 2>/dev/null || true

# Permitir SSH (tunel de gestion) y HTTP publico del balanceador
ufw allow 22/tcp comment "SSH tunel gestion" 2>/dev/null || true
ufw allow "${NGINX_PUBLIC_PORT:-80}/tcp" comment "Nginx balanceador publico" 2>/dev/null || true

echo ""
echo "[OK] Reglas aplicadas:"
ufw status numbered 2>/dev/null || ufw status
echo ""
echo "[INFO] pgAdmin solo accesible via: ssh -L ${SSH_TUNNEL_LOCAL_PORT:-8080}:127.0.0.1:${PGADMIN_HOST_PORT} usuario@servidor"
