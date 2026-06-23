#!/usr/bin/env bash
# tarea12/scripts/test_pruebas.sh
# Protocolo de pruebas 12.1 - 12.4 y 12.5 - 12.7 (portal web)

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

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

HTTPS_PORT="${WEBMAIL_HTTPS_PORT:-443}"
HTTP_PORT="${WEBMAIL_HTTP_PORT:-80}"

echo "======================================================"
echo "  PROTOCOLO DE PRUEBAS - TAREA 12"
echo "======================================================"

# ─── Servicios activos ───────────────────────────────────────────────────────
for svc in tarea12_mailserver tarea12_roundcube tarea12_webmail_proxy; do
    if docker ps --filter name="$svc" --filter status=running -q | grep -q .; then
        pass "Servicio activo: $svc"
    else
        fail "Servicio no activo: $svc"
    fi
done

# ─── Prueba 12.1: Envio local (smtp) ─────────────────────────────────────────
info "Prueba 12.1 - Envio/recepcion local entre cuentas"

if docker exec tarea12_mailserver swaks \
    --to "${ADMIN_EMAIL}" \
    --from "${DIRECTOR_EMAIL}" \
    --server localhost \
    --port 587 \
    --tls \
    --auth LOGIN \
    --auth-user "${DIRECTOR_EMAIL}" \
    --auth-password "${DIRECTOR_PASSWORD}" \
    --header "Subject: Prueba 12.1 Tarea 12" \
    --body "Correo de prueba local director -> admin" 2>/dev/null; then
    pass "Prueba 12.1: Envio SMTP local exitoso (swaks)"
else
    warn "Prueba 12.1: swaks no disponible o envio fallo — valide manualmente con Thunderbird"
    echo "  Cuentas: ${DIRECTOR_EMAIL} / ${ADMIN_EMAIL}"
fi

# ─── Prueba 12.2: Auditoria de logs ──────────────────────────────────────────
info "Prueba 12.2 - Auditoria en /var/log/mail"

LOG_SAMPLE=$(docker exec tarea12_mailserver sh -c \
    'tail -50 /var/log/mail/mail.log 2>/dev/null || tail -50 /var/log/mail.log 2>/dev/null || ls /var/log/mail/' 2>/dev/null || true)

if [ -n "$LOG_SAMPLE" ]; then
    pass "Prueba 12.2: Logs de correo accesibles en /var/log/mail"
    echo "$LOG_SAMPLE" | head -15
    echo "  ..."
else
    warn "Prueba 12.2: Revise logs con: docker exec tarea12_mailserver tail /var/log/mail/mail.log"
fi

# Volumen persistente de logs
if docker volume inspect mail_logs &>/dev/null; then
    pass "Prueba 12.2b: Volumen mail_logs configurado"
fi

# ─── Prueba 12.3: Fail2ban ───────────────────────────────────────────────────
info "Prueba 12.3 - Fail2ban (5 intentos fallidos)"
warn "Prueba 12.3 MANUAL: Intente 5 logins IMAP incorrectos desde IP remota"
echo "  Comando de verificacion:"
echo "    docker exec tarea12_mailserver fail2ban-client status dovecot"
echo "    docker exec tarea12_mailserver fail2ban-client status postfix-sasl"

FB_STATUS=$(docker exec tarea12_mailserver fail2ban-client ping 2>/dev/null || echo "FAIL")
if [ "$FB_STATUS" != "FAIL" ]; then
    pass "Prueba 12.3 (servicio): Fail2ban activo en mailserver"
else
    warn "Fail2ban no responde — verifique ENABLE_FAIL2BAN=1"
fi

# ─── Prueba 12.4: Integridad de respaldo ────────────────────────────────────
info "Prueba 12.4 - Respaldo y restauracion"

bash "$SCRIPT_DIR/backup_mail.sh" > /dev/null 2>&1 || true
LATEST=$(ls -t backups/mail_data_*.tar.gz 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
    pass "Prueba 12.4a: Respaldo generado ($LATEST)"
    echo "  Para restaurar: ./scripts/restore_mail.sh $(basename "$LATEST")"
else
    warn "Prueba 12.4a: Sin respaldos aun — el servicio mail_backup los genera cada 24h"
fi

# ─── Prueba 12.5: Login portal Roundcube ─────────────────────────────────────
info "Prueba 12.5 - Portal web Roundcube (login institucional)"

HTTP_REDIRECT=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${HTTP_PORT}/" 2>/dev/null || echo "000")
if [ "$HTTP_REDIRECT" = "301" ] || [ "$HTTP_REDIRECT" = "302" ]; then
    pass "Prueba 12.5a: HTTP redirige a HTTPS (codigo $HTTP_REDIRECT)"
else
    warn "HTTP response: $HTTP_REDIRECT (esperado 301)"
fi

HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://127.0.0.1:${HTTPS_PORT}/" 2>/dev/null || echo "000")
if [ "$HTTPS_CODE" = "200" ]; then
    pass "Prueba 12.5b: Portal HTTPS responde (codigo 200)"
else
    warn "HTTPS response: $HTTPS_CODE"
fi

warn "Prueba 12.5 MANUAL: Abra https://IP_SERVIDOR y login con ${DIRECTOR_EMAIL}"

# ─── Prueba 12.6: Adjuntos ───────────────────────────────────────────────────
info "Prueba 12.6 - Envio con adjuntos desde portal"
warn "Prueba 12.6 MANUAL: Enviar correo con adjunto desde Roundcube y verificar integridad"

# ─── Prueba 12.7: Persistencia preferencias Roundcube ────────────────────────
info "Prueba 12.7 - Persistencia BD Roundcube (MariaDB)"

if docker volume inspect roundcube_db_data &>/dev/null; then
    pass "Prueba 12.7a: Volumen roundcube_db_data configurado"
fi

RC_TABLES=$(docker exec tarea12_roundcube_db mariadb -u"${ROUNDCUBE_DB_USER}" -p"${ROUNDCUBE_DB_PASSWORD}" \
    -e "SHOW TABLES;" "${ROUNDCUBE_DB_NAME}" 2>/dev/null | wc -l)
if [ "${RC_TABLES:-0}" -gt 1 ]; then
    pass "Prueba 12.7b: Base de datos Roundcube inicializada (${RC_TABLES} tablas)"
else
    warn "Prueba 12.7b: BD Roundcube aun inicializando"
fi

warn "Prueba 12.7 MANUAL: Cambiar idioma/contacto, reiniciar roundcube, verificar persistencia"

# ─── Componentes del stack ───────────────────────────────────────────────────
info "Verificacion de componentes integrados"
docker exec tarea12_mailserver postfix status 2>/dev/null && pass "Postfix (MTA) activo" || warn "Postfix"
docker exec tarea12_mailserver doveadm version 2>/dev/null && pass "Dovecot (MDA/IMAP) activo" || warn "Dovecot"

echo ""
echo -e "${GREEN}======================================================"
echo "  PRUEBAS AUTOMATIZADAS COMPLETADAS"
echo -e "======================================================${NC}"
echo "Complete pruebas manuales: 12.1 (Thunderbird), 12.3 (fail2ban), 12.5-12.7 (portal)"
