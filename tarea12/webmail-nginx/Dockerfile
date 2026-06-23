# tarea12/webmail-nginx/Dockerfile
# Proxy HTTPS para Roundcube — fuerza TLS (Tarea 12 Parte 2)

FROM nginx:1.26-alpine

RUN apk add --no-cache curl \
    && rm -rf /var/cache/apk/*

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -fk https://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
