# tarea11/web_app/Dockerfile
# Servidor de aplicaciones interno - SIN exposicion de puertos al host

FROM nginx:1.26-alpine

ARG INSTANCE_LABEL=A

RUN apk add --no-cache curl \
    && rm -rf /var/cache/apk/*

COPY nginx-app.conf /etc/nginx/nginx.conf
COPY html/ /usr/share/nginx/html/

RUN sed -i "s/INSTANCIA_PLACEHOLDER/${INSTANCE_LABEL}/g" /usr/share/nginx/html/index.html \
    && chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /var/log/nginx /var/run \
    && touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid

USER nginx
EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
