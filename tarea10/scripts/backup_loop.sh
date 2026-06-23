#!/bin/sh
# tarea10/scripts/backup_loop.sh
# Respaldo automatizado de PostgreSQL hacia carpeta del host (/backups)

set -e
INTERVAL="${BACKUP_INTERVAL:-3600}"

echo "[BACKUP] Servicio de respaldo iniciado (intervalo: ${INTERVAL}s)"
echo "[BACKUP] Destino: /backups/"

# Esperar a que PostgreSQL este listo
until pg_isready -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" 2>/dev/null; do
    echo "[BACKUP] Esperando PostgreSQL en $PGHOST..."
    sleep 5
done

while true; do
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    FILE="/backups/sysadmin_db_${TIMESTAMP}.sql.gz"
    echo "[BACKUP] Generando respaldo: $FILE"
    pg_dump -h "$PGHOST" -U "$PGUSER" "$PGDATABASE" | gzip > "$FILE"
    echo "[BACKUP] OK - $(du -h "$FILE" | cut -f1)"
    # Conservar ultimos 10 respaldos
    ls -t /backups/sysadmin_db_*.sql.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
    sleep "$INTERVAL"
done
