#!/usr/bin/env bash
# tarea12/scripts/restore_mail.sh
# Restaura buzones desde respaldo comprimido (Prueba 12.4)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
    echo "Uso: $0 <archivo_backup.tar.gz>"
    echo ""
    echo "Respaldos disponibles:"
    ls -lh "$TAREA_DIR/backups/"mail_data_*.tar.gz 2>/dev/null || echo "  (ninguno)"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    BACKUP_FILE="$TAREA_DIR/backups/$BACKUP_FILE"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "[ERROR] No se encontro: $BACKUP_FILE"
    exit 1
fi

echo "[INFO] Deteniendo mailserver..."
cd "$TAREA_DIR"
docker compose stop mailserver

echo "[INFO] Restaurando desde: $BACKUP_FILE"
docker run --rm \
    -v mail_data:/var/mail \
    -v "$(dirname "$BACKUP_FILE"):/backups:ro" \
    alpine:3.19 \
    sh -c "rm -rf /var/mail/* && tar -xzf /backups/$(basename "$BACKUP_FILE") -C /var/mail"

echo "[INFO] Reiniciando mailserver..."
docker compose start mailserver
sleep 10

echo "[OK] Restauracion completada. Verifique buzones con Prueba 12.1/12.5."
