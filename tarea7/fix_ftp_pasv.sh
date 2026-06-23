#!/usr/bin/env bash
# tarea7/fix_ftp_pasv.sh
# CORRECCIÓN RÁPIDA: Agrega modo PASV a vsftpd existente y abre puertos en firewall.
# Ejecutar en el servidor FTP Linux (192.168.100.28) como root.
#
# Problema que resuelve:
#   "Exception calling 'GetResponse' with '0' arguments" en Windows PowerShell
#   cuando FtpWebRequest intenta conectarse en modo PASIVO (predeterminado en .NET)
#   y los puertos PASV no están habilitados/abiertos en vsftpd/firewall.

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Ejecutar como root: sudo ./fix_ftp_pasv.sh"
    exit 1
fi

VSFTPD_CONF="/etc/vsftpd.conf"

echo "======================================================="
echo "  CORRECCIÓN FTP - MODO PASIVO (PASV) PARA WINDOWS"
echo "======================================================="

# ─── Detectar IP del servidor ─────────────────────────────────────────────────
SERVER_IP=$(ip -o -4 addr show | grep -v "127.0.0.1" | awk '{print $4}' | cut -d/ -f1 | grep "192.168" | head -1)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi
echo "[INFO] IP del servidor detectada: ${SERVER_IP}"

# ─── Respaldar configuración actual ──────────────────────────────────────────
BACKUP="${VSFTPD_CONF}.bak.$(date +%s)"
cp "$VSFTPD_CONF" "$BACKUP"
echo "[OK] Respaldo creado: $BACKUP"

# ─── Eliminar directivas PASV anteriores (evitar duplicados) ─────────────────
sed -i '/^pasv_enable/d'    "$VSFTPD_CONF"
sed -i '/^pasv_min_port/d'  "$VSFTPD_CONF"
sed -i '/^pasv_max_port/d'  "$VSFTPD_CONF"
sed -i '/^pasv_address/d'   "$VSFTPD_CONF"
sed -i '/^pasv_promiscuous/d' "$VSFTPD_CONF"

# ─── Agregar bloque PASV al final ────────────────────────────────────────────
cat >> "$VSFTPD_CONF" <<EOF

# ── MODO PASIVO (PASV) - Requerido para clientes Windows / .NET ──
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=${SERVER_IP}
EOF

echo "[OK] Directivas PASV escritas en $VSFTPD_CONF"
echo "     pasv_address=${SERVER_IP}"
echo "     pasv_min_port=40000 / pasv_max_port=40100"

# ─── Abrir puertos en UFW ─────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow 21/tcp              comment "FTP-Control"   2>/dev/null && echo "[OK] Puerto 21/tcp abierto"
    ufw allow 40000:40100/tcp     comment "FTP-PASV-Data" 2>/dev/null && echo "[OK] Puertos 40000-40100/tcp abiertos"
    ufw reload 2>/dev/null || true
else
    echo "[WARN] UFW no instalado. Si usas iptables, abre los puertos manualmente:"
    echo "       iptables -A INPUT -p tcp --dport 21 -j ACCEPT"
    echo "       iptables -A INPUT -p tcp --dport 40000:40100 -j ACCEPT"
fi

# ─── Validar sintaxis y reiniciar ────────────────────────────────────────────
echo ""
echo "[INFO] Validando configuración..."
if vsftpd /etc/vsftpd.conf 2>&1 | grep -qi "error"; then
    echo "[ERROR] Hay errores en vsftpd.conf. Restaurando respaldo..."
    cp "$BACKUP" "$VSFTPD_CONF"
    exit 1
fi

systemctl restart vsftpd
sleep 1

if systemctl is-active --quiet vsftpd; then
    echo "[OK] vsftpd reiniciado y activo."
else
    echo "[ERROR] vsftpd no pudo reiniciarse. Revisa: journalctl -u vsftpd -n 20"
    exit 1
fi

# ─── Prueba de conexión local ─────────────────────────────────────────────────
echo ""
echo "======================================================="
echo "  PRUEBA DE CONEXIÓN FTP LOCAL"
echo "======================================================="

# Pedir usuario para probar
read -p "Usuario FTP para probar [ftprepo]: " TEST_USER
TEST_USER=${TEST_USER:-ftprepo}
read -s -p "Contraseña: " TEST_PASS
echo ""

echo "[INFO] Probando listado FTP con curl..."
RESULTADO=$(curl -s --connect-timeout 8 --max-time 15 \
    -l -u "${TEST_USER}:${TEST_PASS}" \
    "ftp://127.0.0.1/" 2>&1)

if [ $? -eq 0 ] && [ -n "$RESULTADO" ]; then
    echo -e "\e[32m[OK] Conexión FTP exitosa. Contenido del home:\e[0m"
    echo "$RESULTADO" | sed 's/^/  /'
    echo ""
    echo "[INFO] Probando carpeta del repositorio..."
    REPO=$(curl -s --connect-timeout 8 --max-time 15 \
        -l -u "${TEST_USER}:${TEST_PASS}" \
        "ftp://127.0.0.1/http/" 2>&1)
    if [ -n "$REPO" ]; then
        echo -e "\e[32m[OK] Carpeta /http/ accesible:\e[0m"
        echo "$REPO" | sed 's/^/  /'
    else
        echo -e "\e[33m[WARN] La carpeta /http/ no existe o está vacía.\e[0m"
        echo "       Ejecuta: sudo ./tarea7/setup_ftp_repo.sh ${TEST_USER} ${TEST_PASS}"
    fi
else
    echo -e "\e[31m[ERROR] La prueba FTP falló:\e[0m"
    echo "$RESULTADO"
    echo ""
    echo "Posibles causas:"
    echo "  1. El usuario '${TEST_USER}' no existe o la contraseña es incorrecta"
    echo "  2. El chroot root no es root:root 755 (ejecuta: ls -la /srv/ftp/usuarios/${TEST_USER})"
    echo "  3. /usr/sbin/nologin no está en /etc/shells"
fi

echo ""
echo "======================================================="
echo "  INSTRUCCIONES PARA WINDOWS"
echo "======================================================="
echo ""
echo "Desde PowerShell en Windows (SRV-WIN-SISTEMA):"
echo ""
echo '  $req = [System.Net.FtpWebRequest]::Create("ftp://'"${SERVER_IP}"'/http/")'
echo '  $req.Credentials = New-Object System.Net.NetworkCredential("'"${TEST_USER}"'","TuPass")'
echo '  $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory'
echo '  $req.UsePassive = $true'
echo '  $resp = $req.GetResponse()'
echo '  $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())'
echo '  $reader.ReadToEnd()'
echo ""
echo "Si ese test funciona, el orquestador tarea7.ps1 también funcionará."
echo "======================================================="
