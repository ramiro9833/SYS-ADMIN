# tarea10/web/Dockerfile
# Servidor web Nginx sobre Alpine - imagen personalizada Tarea 10
# - Sin server tokens
# - Usuario no privilegiado (nginx)
# - Pagina con assets estaticos propios

FROM nginx:1.26-alpine

LABEL maintainer="SYS-ADMIN Tarea10"
LABEL description="Servidor web Alpine personalizado con hardening"

# Eliminar paquetes innecesarios y agregar utilidades minimas
RUN apk add --no-cache curl iputils \
    && rm -rf /var/cache/apk/*

# Configuracion endurecida (server_tokens off)
COPY nginx.conf /etc/nginx/nginx.conf

# Contenido web estatico (HTML, CSS, imagen SVG personalizada)
COPY html/ /usr/share/nginx/html/

# Directorio para archivos subidos via FTP (volumen web_content)
RUN mkdir -p /usr/share/nginx/html/uploads \
    && chown -R nginx:nginx /usr/share/nginx/html \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && touch /var/run/nginx.pid \
    && chown nginx:nginx /var/run/nginx.pid

# Verificar que nginx puede arrancar como usuario no root
USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
