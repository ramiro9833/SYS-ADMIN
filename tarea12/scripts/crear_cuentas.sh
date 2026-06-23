#!/usr/bin/env bash
# tarea12/scripts/crear_cuentas.sh
# Crea cuentas de correo iniciales (Prueba 12.1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$TAREA_DIR"

if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

DIRECTOR="${DIRECTOR_EMAIL:-director@reprobados.com}"
DIR_PASS="${DIRECTOR_PASSWORD:-Director@Mail2026!}"
ADMIN="${ADMIN_EMAIL:-admin@reprobados.com}"
ADM_PASS="${ADMIN_PASSWORD:-Admin@Mail2026!}"

echo "======================================================"
echo "  CREACION DE CUENTAS DE CORREO - TAREA 12"
echo "======================================================"

if ! docker ps --filter name=tarea12_mailserver --filter status=running -q | grep -q .; then
    echo "[ERROR] El contenedor tarea12_mailserver no esta en ejecucion."
    echo "        Ejecute primero: docker compose up -d"
    exit 1
fi

crear_cuenta() {
    local email="$1"
    local pass="$2"
    if docker exec tarea12_mailserver setup email list 2>/dev/null | grep -q "$email"; then
        echo "[INFO] Cuenta '$email' ya existe."
        docker exec tarea12_mailserver setup email update "$email" "$pass" 2>/dev/null || true
    else
        docker exec tarea12_mailserver setup email add "$email" "$pass"
        echo "[OK] Cuenta creada: $email"
    fi
}

crear_cuenta "$DIRECTOR" "$DIR_PASS"
crear_cuenta "$ADMIN" "$ADM_PASS"

echo ""
echo "[OK] Cuentas listas para Prueba 12.1:"
echo "  Director: $DIRECTOR"
echo "  Admin:    $ADMIN"
echo ""
docker exec tarea12_mailserver setup email list 2>/dev/null || true
