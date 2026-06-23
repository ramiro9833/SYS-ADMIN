#!/usr/bin/env bash
# tarea10/scripts/backup_db.sh
# Respaldo manual inmediato de PostgreSQL al host

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="${TAREA_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILE="${BACKUP_DIR}/sysadmin_db_manual_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[BACKUP] Generando respaldo manual..."
docker exec sysadmin_db pg_dump -U sysadmin sysadmin_db | gzip > "$FILE"
echo "[OK] Respaldo guardado: $FILE ($(du -h "$FILE" | cut -f1))"
