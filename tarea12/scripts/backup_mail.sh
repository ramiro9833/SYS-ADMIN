#!/usr/bin/env bash
# tarea12/scripts/backup_mail.sh
# Respaldo manual inmediato de buzones (/var/mail)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="${TAREA_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILE="${BACKUP_DIR}/mail_data_manual_${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "[BACKUP] Generando respaldo manual de buzones..."
docker run --rm \
    -v mail_data:/var/mail:ro \
    -v "${BACKUP_DIR}:/backups" \
    alpine:3.19 \
    tar -czf "/backups/mail_data_manual_${TIMESTAMP}.tar.gz" -C /var/mail .

echo "[OK] Respaldo: $FILE ($(du -h "$FILE" | cut -f1))"
