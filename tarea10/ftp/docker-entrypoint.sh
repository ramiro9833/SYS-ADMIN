#!/bin/sh
# tarea10/ftp/docker-entrypoint.sh
set -e

FTP_PASS="${FTP_PASS:-FtpUpload@1234}"

# Establecer contrasena del usuario ftpuser
echo "ftpuser:${FTP_PASS}" | chpasswd

# Asegurar permisos del volumen montado
chown -R ftpuser:ftpusers /var/ftp/uploads 2>/dev/null || true
chmod 755 /var/ftp/uploads

echo "[FTP] Iniciando vsftpd en puerto 21 (PASV 30000-30009)..."
exec /usr/sbin/vsftpd /etc/vsftpd/vsftpd.conf
