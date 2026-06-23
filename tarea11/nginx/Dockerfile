# tarea11/nginx/Dockerfile
# Balanceador de carga Nginx - unico punto de entrada publico (Tarea 11)

FROM nginx:1.26-alpine

RUN apk add --no-cache curl iputils \
    && rm -rf /var/cache/apk/*

COPY nginx.conf /etc/nginx/nginx.conf

RUN mkdir -p /var/cache/nginx /var/log/nginx /var/run \
    && chown -R nginx:nginx /var/cache/nginx /var/log/nginx /var/run

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
