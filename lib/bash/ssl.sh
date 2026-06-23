#!/usr/bin/env bash
# lib/bash/ssl.sh - Generación de certificados y configuración SSL/TLS en Linux

CERT_PATH="/etc/ssl/certs/reprobados.crt"
KEY_PATH="/etc/ssl/private/reprobados.key"
DOMINIO="www.reprobados.com"

# Generar certificados autofirmados para www.reprobados.com
generar_certificado_selfsigned() {
    echo -e "\n[INFO] Generando certificado SSL autofirmado para $DOMINIO..."
    mkdir -p /etc/ssl/certs /etc/ssl/private
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -subj "/CN=$DOMINIO/O=Reprobados/C=MX" 2>/dev/null
        
    if [ $? -eq 0 ]; then
        chmod 600 "$KEY_PATH"
        echo -e "\e[32m[OK] Certificado y Llave generados en $CERT_PATH y $KEY_PATH\e[0m"
        return 0
    else
        echo -e "\e[31m[ERROR] Falló la generación del certificado SSL.\e[0m"
        return 1
    fi
}

# Configurar SSL para Apache Linux
configurar_ssl_apache() {
    echo -e "\n[INFO] Configurando SSL/TLS en Apache..."
    
    if [ ! -f "$CERT_PATH" ]; then
        generar_certificado_selfsigned
    fi

    # Habilitar módulos necesarios
    a2enmod ssl rewrite headers 2>/dev/null
    
    # VirtualHost SSL (puerto 443)
    cat <<EOF > /etc/apache2/sites-available/default-ssl.conf
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerAdmin webmaster@localhost
        ServerName $DOMINIO
        DocumentRoot /var/www/html

        SSLEngine on
        SSLCertificateFile $CERT_PATH
        SSLCertificateKeyFile $KEY_PATH

        # Hardening
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-XSS-Protection "1; mode=block"
        Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

        <FilesMatch "\.(cgi|shtml|phtml|php)$">
            SSLOptions +StdEnvVars
        </FilesMatch>
        <Directory /usr/lib/cgi-bin>
            SSLOptions +StdEnvVars
        </Directory>
    </VirtualHost>
</IfModule>
EOF

    # Redirección HTTP -> HTTPS en el puerto 80
    cat <<EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerName $DOMINIO
    DocumentRoot /var/www/html
    
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>
EOF

    # Habilitar sitio SSL y reiniciar
    a2ensite default-ssl.conf 2>/dev/null
    systemctl restart apache2
    echo -e "\e[32m[OK] Apache configurado con SSL y Redirección HTTPS activa.\e[0m"
}

# Configurar SSL para Nginx Linux
configurar_ssl_nginx() {
    echo -e "\n[INFO] Configurando SSL/TLS en Nginx..."
    
    if [ ! -f "$CERT_PATH" ]; then
        generar_certificado_selfsigned
    fi

    # Detectar el puerto HTTP actual de Nginx desde su configuración
    local puerto_http; puerto_http=$(grep -E '^\s*listen\s+' /etc/nginx/sites-available/default 2>/dev/null | grep -oP '[0-9]+' | head -1)
    [[ -z "$puerto_http" ]] && puerto_http="80"

    local puerto_https
    if [ "$puerto_http" = "80" ]; then
        puerto_https="443"
    else
        puerto_https=$((puerto_http + 1))
    fi

    # Evitar conflicto si Apache2 ya está usando el puerto 443
    if [ "$puerto_https" = "443" ] && systemctl is-active --quiet apache2 2>/dev/null; then
        echo -e "\e[33m[WARN] Apache2 está activo y posiblemente usando el puerto 443. Configurando Nginx SSL en el puerto 8443 para evitar conflicto.\e[0m"
        puerto_https="8443"
    fi

    # Configuración de sitio default con SSL y redirección
    cat <<EOF > /etc/nginx/sites-available/default
server {
    listen ${puerto_http} default_server;
    listen [::]:${puerto_http} default_server;
    server_name $DOMINIO;
    return 301 https://\$host:${puerto_https}\$request_uri;
}

server {
    listen ${puerto_https} ssl default_server;
    listen [::]:${puerto_https} ssl default_server;
    server_name $DOMINIO;

    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/html;
    index index.html index.htm;

    # Hardening
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    # Registrar el puerto SSL de Nginx en el firewall si es necesario
    if [ -f "$LIB_DIR/http.sh" ]; then
        configurar_firewall_linux "$puerto_https" "Nginx SSL"
    fi

    systemctl restart nginx
    echo -e "\e[32m[OK] Nginx configurado con SSL en puerto ${puerto_https} y Redirección HTTPS activa.\e[0m"
}

# Configurar SSL para Tomcat Linux
configurar_ssl_tomcat() {
    echo -e "\n[INFO] Configurando SSL/TLS en Tomcat..."
    
    if [ ! -f "$CERT_PATH" ]; then
        generar_certificado_selfsigned
    fi

    local tomcat_dir="/opt/tomcat"
    if [ ! -d "$tomcat_dir" ]; then
        tomcat_dir=$(find /opt -maxdepth 2 -name "tomcat*" -type d | head -n 1)
    fi

    if [ -z "$tomcat_dir" ] || [ ! -d "$tomcat_dir" ]; then
        echo -e "\e[31m[ERROR] No se encontró la instalación de Tomcat en /opt.\e[0m"
        return 1
    fi

    local keystore_file="$tomcat_dir/conf/tomcat.p12"
    
    # Exportar certificado a PKCS12 para Tomcat
    echo "[INFO] Creando almacén PKCS12 para Tomcat..."
    openssl pkcs12 -export -in "$CERT_PATH" -inkey "$KEY_PATH" \
        -out "$keystore_file" -name tomcat -passout pass:changeit 2>/dev/null
        
    chown tomcat:tomcat "$keystore_file" 2>/dev/null
    chmod 600 "$keystore_file" 2>/dev/null

    # Modificar server.xml de Tomcat para añadir conector SSL en puerto 8443
    local server_xml="$tomcat_dir/conf/server.xml"
    
    # Eliminar conector SSL existente en puerto 8443 para evitar duplicados
    sed -i '/<Connector port="8443"/,/<\/Connector>/d' "$server_xml"
    
    # Insertar el nuevo conector SSL justo antes de </Service>
    sed -i '/<\/Service>/i \
    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol" \
               maxThreads="150" SSLEnabled="true" scheme="https" secure="true" \
               clientAuth="false" sslProtocol="TLS"> \
        <SSLHostConfig> \
            <Certificate certificateKeystoreFile="conf/tomcat.p12" \
                         certificateKeystorePassword="changeit" \
                         type="RSA" /> \
        </SSLHostConfig> \
    </Connector>' "$server_xml"

    # Habilitar redirección forzada a nivel de aplicación en web.xml
    local web_xml="$tomcat_dir/conf/web.xml"
    if [ -f "$web_xml" ]; then
        # Remover bloque de redirección previa si existe
        sed -i '/<security-constraint>/,/<\/security-constraint>/d' "$web_xml"
        
        # Insertar redirección antes de </web-app>
        sed -i '/<\/web-app>/i \
    <security-constraint> \
        <web-resource-collection> \
            <web-resource-name>Automatic SSL Forwarding</web-resource-name> \
            <url-pattern>/*</url-pattern> \
        </web-resource-collection> \
        <user-data-constraint> \
            <transport-guarantee>CONFIDENTIAL</transport-guarantee> \
        </user-data-constraint> \
    </security-constraint>' "$web_xml"
    fi

    # Reiniciar Tomcat
    systemctl restart tomcat
    echo -e "\e[32m[OK] Tomcat configurado con SSL en puerto 8443 y forzado HTTPS.\e[0m"
}

# Configurar SSL para vsftpd Linux (FTPS)
configurar_ssl_vsftpd() {
    echo -e "\n[INFO] Configurando cifrado FTPS en vsftpd..."
    
    if [ ! -f "$CERT_PATH" ]; then
        generar_certificado_selfsigned
    fi

    local vs_conf="/etc/vsftpd.conf"
    if [ ! -f "$vs_conf" ]; then
        echo -e "\e[31m[ERROR] No se encontró /etc/vsftpd.conf.\e[0m"
        return 1
    fi

    # Limpiar líneas SSL previas para evitar duplicados
    sed -i '/^ssl_enable/d' "$vs_conf"
    sed -i '/^allow_anon_ssl/d' "$vs_conf"
    sed -i '/^force_local_data_ssl/d' "$vs_conf"
    sed -i '/^force_local_logins_ssl/d' "$vs_conf"
    sed -i '/^ssl_tlsv1/d' "$vs_conf"
    sed -i '/^ssl_sslv2/d' "$vs_conf"
    sed -i '/^ssl_sslv3/d' "$vs_conf"
    sed -i '/^rsa_cert_file/d' "$vs_conf"
    sed -i '/^rsa_private_key_file/d' "$vs_conf"
    sed -i '/^require_ssl_reuse/d' "$vs_conf"

    # Escribir directivas SSL
    cat <<EOF >> "$vs_conf"
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=$CERT_PATH
rsa_private_key_file=$KEY_PATH
require_ssl_reuse=NO
EOF

    systemctl restart vsftpd
    echo -e "\e[32m[OK] vsftpd configurado para requerir FTPS de forma explícita.\e[0m"
}
