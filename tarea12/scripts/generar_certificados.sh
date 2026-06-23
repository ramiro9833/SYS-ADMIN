#!/usr/bin/env bash
# tarea12/scripts/generar_certificados.sh
# Genera certificados TLS autofirmados para mail + webmail (reprobados.com)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="${TAREA_DIR}/certs"

if [ -f "$TAREA_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$TAREA_DIR/.env"
    set +a
fi

DOMAIN="${MAIL_DOMAIN:-reprobados.com}"
HOSTNAME="${MAIL_HOSTNAME:-mail.reprobados.com}"

mkdir -p "$CERT_DIR"

if [ -f "$CERT_DIR/cert.pem" ] && [ -f "$CERT_DIR/key.pem" ]; then
    echo "[INFO] Certificados ya existen en $CERT_DIR"
    exit 0
fi

echo "[INFO] Generando certificado TLS para ${HOSTNAME} y ${DOMAIN}..."

openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_DIR/cert.pem" \
    -subj "/C=MX/ST=Local/L=Lab/O=Reprobados/CN=${HOSTNAME}" \
    -addext "subjectAltName=DNS:${HOSTNAME},DNS:${DOMAIN},DNS:webmail.${DOMAIN}"

chmod 600 "$CERT_DIR/key.pem"
chmod 644 "$CERT_DIR/cert.pem"

echo "[OK] Certificados generados:"
echo "  $CERT_DIR/cert.pem"
echo "  $CERT_DIR/key.pem"
echo ""
echo "[INFO] Importe cert.pem en Thunderbird/Mailspring como excepcion de confianza."
