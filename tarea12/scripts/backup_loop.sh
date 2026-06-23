#!/bin/sh
# tarea12/scripts/backup_loop.sh
# Respaldo automatizado comprimido de buzones cada 24 horas

set -e
INTERVAL="${BACKUP_INTERVAL:-86400}"

echo "[BACKUP] Servicio de respaldo de correo iniciado (intervalo: ${INTERVAL}s)"

while true; do
    if [ -d /var/mail ] && [ "$(ls -A /var/mail 2>/dev/null)" ]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        FILE="/backups/mail_data_${TIMESTAMP}.tar.gz"
        echo "[BACKUP] Generando: $FILE"
        tar -czf "$FILE" -C /var/mail . 2>/dev/null || tar -czf "$FILE" /var/mail
        echo "[BACKUP] OK - $(du -h "$FILE" | cut -f1)"
        ls -t /backups/mail_data_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
    else
        echo "[BACKUP] Esperando datos en /var/mail..."
    fi
    sleep "$INTERVAL"
done
