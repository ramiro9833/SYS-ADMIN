#!/usr/bin/env bash
# lib/bash/http.sh
# Biblioteca de funciones para despliegue dinámico de servidores HTTP en Linux.
# Uso: source ./http.sh

# ─── Constantes ──────────────────────────────────────────────────────────────
PUERTOS_RESERVADOS=(21 22 23 25 53 110 143 443 3306 5432 6379 8443)
WWW_ROOT="/var/www/html"
TOMCAT_BASE="/opt/tomcat"
TOMCAT_USER="tomcat_svc"

# ─── Validar puerto ───────────────────────────────────────────────────────────
validar_puerto() {
  local puerto="$1"
  # Solo dígitos
  if [[ ! "$puerto" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}[ERROR] El puerto debe ser un número entero.${NC}" >&2
    return 1
  fi
  # Rango válido para no-root
  if (( puerto < 1024 || puerto > 65535 )); then
    echo -e "${RED}[ERROR] Puerto fuera de rango permitido (1024-65535).${NC}" >&2
    return 1
  fi
  # No reservado
  for res in "${PUERTOS_RESERVADOS[@]}"; do
    if (( puerto == res )); then
      echo -e "${RED}[ERROR] Puerto $puerto reservado por otro servicio.${NC}" >&2
      return 1
    fi
  done
  # No en uso
  if ss -tlnp 2>/dev/null | awk '{print $4}' | grep -qE ":${puerto}$"; then
    echo -e "${RED}[ERROR] Puerto $puerto ya está en uso por otro proceso.${NC}" >&2
    return 1
  fi
  return 0
}

# ─── Leer puerto con validación ───────────────────────────────────────────────
leer_puerto() {
  local default="${1:-8080}"
  local puerto=""
  while true; do
    read -rp "Puerto de escucha [$default]: " puerto
    [[ -z "$puerto" ]] && puerto="$default"
    if validar_puerto "$puerto"; then
      echo "$puerto"
      return 0
    fi
  done
}

# ─── Consultar versiones Apache ───────────────────────────────────────────────
consultar_versiones_apache() {
  echo -e "${YELLOW}[INFO] Consultando versiones disponibles de Apache2...${NC}" >&2
  apt-get update -qq 2>/dev/null
  mapfile -t VERS < <(apt-cache madison apache2 2>/dev/null | awk '{print $3}' | sort -Vr | head -5)
  if [[ ${#VERS[@]} -eq 0 ]]; then
    echo -e "${RED}[ERROR] No se pudieron obtener versiones de Apache2.${NC}" >&2
    return 1
  fi
  printf '%s\n' "${VERS[@]}"
}

# ─── Consultar versiones Nginx ────────────────────────────────────────────────
consultar_versiones_nginx() {
  echo -e "${YELLOW}[INFO] Consultando versiones disponibles de Nginx...${NC}" >&2
  apt-get update -qq 2>/dev/null
  mapfile -t VERS < <(apt-cache madison nginx 2>/dev/null | awk '{print $3}' | sort -Vr | head -5)
  if [[ ${#VERS[@]} -eq 0 ]]; then
    echo -e "${RED}[ERROR] No se pudieron obtener versiones de Nginx.${NC}" >&2
    return 1
  fi
  printf '%s\n' "${VERS[@]}"
}

# ─── Consultar versiones Tomcat (GitHub API) ──────────────────────────────────
consultar_versiones_tomcat() {
  echo -e "${YELLOW}[INFO] Consultando versiones disponibles de Tomcat (GitHub API)...${NC}" >&2
  if ! command -v curl &>/dev/null; then apt-get install -y -qq curl; fi
  # Obtiene releases de Apache Tomcat 10.x y 9.x
  local api_url="https://api.github.com/repos/apache/tomcat/tags"
  mapfile -t VERS < <(
    curl -s --max-time 10 "$api_url" 2>/dev/null \
    | grep '"name"' \
    | grep -oP '(?<="name": ")10\.[0-9]+\.[0-9]+|9\.[0-9]+\.[0-9]+' \
    | sort -Vr | head -6
  )
  if [[ ${#VERS[@]} -eq 0 ]]; then
    # Fallback: versiones estáticas si no hay internet
    VERS=("10.1.34" "10.1.30" "9.0.104" "9.0.100")
    echo -e "${YELLOW}[WARN] Sin acceso a la API. Usando versiones conocidas.${NC}" >&2
  fi
  printf '%s\n' "${VERS[@]}"
}

# ─── Mostrar menú de selección de versión ────────────────────────────────────
seleccionar_version() {
  local servicio="$1"
  shift
  local versiones=("$@")
  echo -e "\n${BOLD}Versiones disponibles para ${CYAN}${servicio}${NC}${BOLD}:${NC}"
  for i in "${!versiones[@]}"; do
    local label=""
    [[ $i -eq 0 ]] && label=" ${GREEN}(Latest)${NC}"
    [[ $i -eq 1 ]] && label=" ${YELLOW}(Stable/LTS)${NC}"
    echo -e "  ${BOLD}$((i+1)))${NC} ${versiones[$i]}${label}"
  done
  local sel=""
  while true; do
    read -rp "Selecciona versión (1-${#versiones[@]}): " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#versiones[@]} )); then
      echo "${versiones[$((sel-1))]}"
      return 0
    fi
    echo -e "${RED}[ERROR] Opción inválida.${NC}" >&2
  done
}

# ─── Crear usuario de servicio dedicado ──────────────────────────────────────
crear_usuario_servicio() {
  local usuario="$1"
  local home_dir="$2"
  if id "$usuario" &>/dev/null; then
    echo -e "${YELLOW}[INFO] Usuario de servicio '$usuario' ya existe.${NC}"
    return 0
  fi
  useradd -r -s /usr/sbin/nologin -d "$home_dir" -M "$usuario"
  echo -e "${GREEN}[OK] Usuario de servicio '$usuario' creado (sin shell, sin login).${NC}"
}

# ─── Crear index.html personalizado ──────────────────────────────────────────
crear_index_html() {
  local root_dir="$1"
  local servicio="$2"
  local version="$3"
  local puerto="$4"
  mkdir -p "$root_dir"
  cat > "${root_dir}/index.html" <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>${servicio} - Tarea 6</title>
  <style>
    body { font-family: Arial, sans-serif; background: #1a1a2e; color: #e0e0e0;
           display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
    .card { background: #16213e; border: 1px solid #0f3460; border-radius: 12px;
            padding: 2rem 3rem; text-align: center; box-shadow: 0 8px 32px rgba(0,0,0,0.5); }
    h1 { color: #e94560; margin-bottom: 0.5rem; }
    .info { margin: 0.8rem 0; font-size: 1.1rem; }
    .badge { display: inline-block; background: #0f3460; border-radius: 6px;
             padding: 0.2rem 0.8rem; margin: 0.2rem; color: #53d8fb; font-weight: bold; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🌐 ${servicio}</h1>
    <div class="info">Servidor: <span class="badge">${servicio}</span></div>
    <div class="info">Versión: <span class="badge">${version}</span></div>
    <div class="info">Puerto: <span class="badge">${puerto}</span></div>
    <div class="info">Host: <span class="badge">$(hostname)</span></div>
    <p style="color:#888;margin-top:1.5rem;font-size:0.85rem;">Tarea 6 – Despliegue Dinámico HTTP</p>
  </div>
</body>
</html>
EOF
  echo -e "${GREEN}[OK] index.html generado en: ${root_dir}${NC}"
}

# ─── Configurar firewall Linux ────────────────────────────────────────────────
configurar_firewall_linux() {
  local puerto="$1"
  local servicio="$2"
  if ! command -v ufw &>/dev/null; then
    apt-get install -y -qq ufw
  fi
  ufw allow "${puerto}/tcp" comment "HTTP-${servicio}-${puerto}" 2>/dev/null
  # Cerrar puerto 80/443 si el nuevo puerto es diferente
  if (( puerto != 80 )); then
    ufw delete allow 80/tcp 2>/dev/null || true
    echo -e "${YELLOW}[INFO] Puerto 80 cerrado (no se usa).${NC}"
  fi
  ufw --force enable 2>/dev/null
  echo -e "${GREEN}[OK] Firewall: puerto ${puerto}/tcp habilitado.${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# APACHE2
# ═══════════════════════════════════════════════════════════════════════════════
instalar_apache() {
  local version="$1"
  local puerto="$2"

  banner "INSTALANDO APACHE2 v${version} EN PUERTO ${puerto}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # Instalar versión específica si está disponible
  if apt-cache show "apache2=${version}" &>/dev/null; then
    apt-get install -y -qq "apache2=${version}" "apache2-bin=${version}" 2>/dev/null \
      || apt-get install -y -qq apache2
  else
    apt-get install -y -qq apache2
  fi

  # Configurar puerto
  sed -i "s/^Listen .*/Listen ${puerto}/" /etc/apache2/ports.conf
  sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:${puerto}>/" \
    /etc/apache2/sites-available/000-default.conf 2>/dev/null || true

  # Usuario dedicado (www-data ya existe en Debian/Ubuntu)
  crear_usuario_servicio "www-data" "/var/www"
  chown -R www-data:www-data /var/www/html
  chmod 750 /var/www/html

  # Hardening
  aplicar_hardening_apache "$puerto"

  # index.html personalizado
  local ver_real; ver_real=$(apache2 -v 2>/dev/null | grep -oP 'Apache/\K[0-9.]+' || echo "$version")
  crear_index_html "$WWW_ROOT" "Apache2" "$ver_real" "$puerto"

  systemctl enable apache2 --quiet
  systemctl restart apache2

  # Firewall
  configurar_firewall_linux "$puerto" "Apache2"

  echo -e "\n${GREEN}${BOLD}[✓] Apache2 desplegado en puerto ${puerto}${NC}"
  echo -e "${CYAN}Verificación: curl -I http://localhost:${puerto}${NC}"
  curl -s -I "http://localhost:${puerto}" 2>/dev/null | head -6 || true
}

aplicar_hardening_apache() {
  local puerto="$1"
  # Ocultar versión
  cat > /etc/apache2/conf-available/security-custom.conf <<'SECEOF'
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
Header unset Server
SECEOF

  a2enmod headers 2>/dev/null || true
  a2enconf security-custom 2>/dev/null || true

  # Deshabilitar métodos peligrosos en vhost principal
  local vhost="/etc/apache2/sites-available/000-default.conf"
  if ! grep -q "LimitExcept" "$vhost" 2>/dev/null; then
    sed -i "/<\/VirtualHost>/i\\
  <Location />\n\
    <LimitExcept GET POST HEAD>\n\
      Require all denied\n\
    </LimitExcept>\n\
  </Location>" "$vhost"
  fi

  echo -e "${GREEN}[OK] Hardening Apache: ServerTokens Prod, headers de seguridad, TRACE desactivado.${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# NGINX
# ═══════════════════════════════════════════════════════════════════════════════
instalar_nginx() {
  local version="$1"
  local puerto="$2"

  banner "INSTALANDO NGINX v${version} EN PUERTO ${puerto}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  if apt-cache show "nginx=${version}" &>/dev/null; then
    apt-get install -y -qq "nginx=${version}" 2>/dev/null || apt-get install -y -qq nginx
  else
    apt-get install -y -qq nginx
  fi

  crear_usuario_servicio "www-data" "/var/www"

  # Configurar puerto y hardening en nginx.conf
  cat > /etc/nginx/sites-available/default <<NGXEOF
server {
    listen ${puerto};
    server_name _;
    root ${WWW_ROOT};
    index index.html;

    # Seguridad: ocultar versión
    server_tokens off;

    # Bloquear métodos peligrosos
    if (\$request_method !~ ^(GET|POST|HEAD)$) {
        return 405;
    }

    # Headers de seguridad
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Server "WebServer" always;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGXEOF

  chown -R www-data:www-data /var/www/html
  chmod 750 /var/www/html

  local ver_real; ver_real=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+' || echo "$version")
  crear_index_html "$WWW_ROOT" "Nginx" "$ver_real" "$puerto"

  nginx -t && systemctl enable nginx --quiet && systemctl restart nginx

  configurar_firewall_linux "$puerto" "Nginx"

  echo -e "\n${GREEN}${BOLD}[✓] Nginx desplegado en puerto ${puerto}${NC}"
  echo -e "${CYAN}Verificación: curl -I http://localhost:${puerto}${NC}"
  curl -s -I "http://localhost:${puerto}" 2>/dev/null | head -6 || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# TOMCAT
# ═══════════════════════════════════════════════════════════════════════════════
instalar_tomcat() {
  local version="$1"
  local puerto="$2"

  banner "INSTALANDO APACHE TOMCAT v${version} EN PUERTO ${puerto}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq openjdk-17-jre-headless curl tar 2>/dev/null

  # Determinar major version para construir la URL
  local major; major=$(echo "$version" | cut -d. -f1)
  local url="https://archive.apache.org/dist/tomcat/tomcat-${major}/v${version}/bin/apache-tomcat-${version}.tar.gz"

  echo -e "${YELLOW}[INFO] Descargando Tomcat desde: ${url}${NC}"
  local tmp_file="/tmp/tomcat-${version}.tar.gz"
  if ! curl -sL --max-time 120 -o "$tmp_file" "$url"; then
    echo -e "${RED}[ERROR] No se pudo descargar Tomcat ${version}.${NC}"
    return 1
  fi

  # Instalar
  rm -rf "${TOMCAT_BASE}"
  mkdir -p "${TOMCAT_BASE}"
  tar xzf "$tmp_file" -C "${TOMCAT_BASE}" --strip-components=1
  rm -f "$tmp_file"

  # Usuario dedicado
  crear_usuario_servicio "$TOMCAT_USER" "$TOMCAT_BASE"
  chown -R "${TOMCAT_USER}:${TOMCAT_USER}" "${TOMCAT_BASE}"
  chmod -R 750 "${TOMCAT_BASE}"
  # Solo acceso a webapps
  chmod 755 "${TOMCAT_BASE}/webapps"

  # Configurar puerto en server.xml
  sed -i "s/port=\"8080\"/port=\"${puerto}\"/" "${TOMCAT_BASE}/conf/server.xml"

  # index.html personalizado en ROOT webapp
  crear_index_html "${TOMCAT_BASE}/webapps/ROOT" "Tomcat" "$version" "$puerto"

  # Systemd service
  cat > /etc/systemd/system/tomcat.service <<SVCEOF
[Unit]
Description=Apache Tomcat ${version}
After=network.target

[Service]
Type=forking
User=${TOMCAT_USER}
Group=${TOMCAT_USER}
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
Environment=CATALINA_HOME=${TOMCAT_BASE}
ExecStart=${TOMCAT_BASE}/bin/startup.sh
ExecStop=${TOMCAT_BASE}/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
SVCEOF

  systemctl daemon-reload
  systemctl enable tomcat --quiet
  systemctl restart tomcat

  configurar_firewall_linux "$puerto" "Tomcat"

  echo -e "\n${GREEN}${BOLD}[✓] Tomcat desplegado en puerto ${puerto}${NC}"
  sleep 3
  echo -e "${CYAN}Verificación: curl -I http://localhost:${puerto}${NC}"
  curl -s -I "http://localhost:${puerto}" 2>/dev/null | head -6 || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# MENÚ PRINCIPAL HTTP LINUX
# ═══════════════════════════════════════════════════════════════════════════════
menu_http_linux() {
  banner "GESTOR HTTP LINUX - TAREA 6"
  echo -e "  ${BOLD}1)${NC} Instalar Apache2"
  echo -e "  ${BOLD}2)${NC} Instalar Nginx"
  echo -e "  ${BOLD}3)${NC} Instalar Apache Tomcat"
  echo -e "  ${BOLD}4)${NC} Estado de servicios HTTP"
  echo -e "  ${BOLD}5)${NC} Salir"
}

estado_servicios_http() {
  banner "ESTADO SERVICIOS HTTP"
  for svc in apache2 nginx tomcat; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      echo -e "  ${GREEN}[ACTIVO]${NC}   $svc"
    else
      echo -e "  ${RED}[INACTIVO]${NC} $svc"
    fi
  done
  echo -e "\n${BOLD}Puertos en escucha (HTTP):${NC}"
  ss -tlnp 2>/dev/null | grep -E ':80|:8080|:8888|:443' | awk '{print "  " $4}' || echo "  (ninguno)"
}
