# tarea10/ftp/Dockerfile
# Servidor FTP (vsftpd) sobre Alpine - Tarea 10
# Comparte volumen web_content con el servidor web

FROM alpine:3.19

LABEL maintainer="SYS-ADMIN Tarea10"
LABEL description="Servidor FTP vsftpd Alpine para carga de instaladores"

RUN apk add --no-cache vsftpd shadow \
    && addgroup -S ftpusers \
    && adduser -S -G ftpusers -s /sbin/nologin -h /var/ftp/uploads ftpuser \
    && mkdir -p /var/ftp/uploads /etc/vsftpd \
    && chown -R ftpuser:ftpusers /var/ftp/uploads \
    && chmod 755 /var/ftp/uploads

COPY vsftpd.conf /etc/vsftpd/vsftpd.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh

# vsftpd requiere root para iniciar, luego baja privilegios internamente
EXPOSE 21 30000-30009

ENTRYPOINT ["/docker-entrypoint.sh"]
