#!/usr/bin/env bash
# tarea12/scripts/mostrar_dkim.sh
# Muestra clave DKIM para registro DNS

set -euo pipefail

echo "=== Clave DKIM para DNS (reprobados.com) ==="
docker exec tarea12_mailserver cat /etc/opendkim/keys/reprobados.com/mail.txt 2>/dev/null || \
docker exec tarea12_mailserver setup config dkim display 2>/dev/null || \
echo "[INFO] Ejecute tras el primer arranque del mailserver cuando OpenDKIM genere las claves."
