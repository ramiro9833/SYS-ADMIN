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

# ─── Consultar versiones Tomcat (mirror oficial Apache) ──────────────────────
consultar_versiones_tomcat() {
  echo -e "${YELLOW}[INFO] Consultando versiones disponibles de Tomcat...${NC}" >&2
  if ! command -v curl &>/dev/null; then apt-get install -y -qq curl; fi

  local vers=()

  # 1. Escanear si hay archivos locales descargados en el sistema
  local local_files
  local_files=$(find /tmp /home /mnt/sysadmin "$SCRIPT_DIR" "$(dirname "$SCRIPT_DIR")" -maxdepth 3 -name "apache-tomcat-*.tar.gz" 2>/dev/null)
  while read -r file; do
    if [[ -n "$file" ]]; then
      local filename; filename=$(basename "$file")
      local ver; ver=$(echo "$filename" | grep -oP 'apache-tomcat-\K[0-9.]+(?=\.tar\.gz)')
      if [[ -n "$ver" ]]; then
        vers+=("$ver")
      fi
    fi
  done <<< "$local_files"

  # 2. Intentar obtener versiones reales desde el mirror de Apache
  for major in 10 9; do
    local index_url="https://downloads.apache.org/tomcat/tomcat-${major}/"
    local found
    found=$(curl -s --max-time 10 "$index_url" 2>/dev/null \
      | tr -d '\r' \
      | grep -oP "v${major}\.[0-9]+\.[0-9]+" | sort -Vru | head -3)
    while IFS= read -r v; do
      v=$(echo "$v" | tr -d '[:space:]')
      if [[ -n "$v" ]]; then
        vers+=("${v#v}")
      fi
    done <<< "$found"
  done

  # 3. Eliminar duplicados y ordenar de mayor a menor
  local uniq_vers=()
  if [[ ${#vers[@]} -gt 0 ]]; then
    mapfile -t uniq_vers < <(printf '%s\n' "${vers[@]}" | sort -Vru)
  fi

  if [[ ${#uniq_vers[@]} -eq 0 ]]; then
    uniq_vers=("10.1.34" "10.1.30" "9.0.104" "9.0.100")
    echo -e "${YELLOW}[WARN] Sin acceso al mirror ni archivos locales. Usando fallback.${NC}" >&2
  fi
  printf '%s\n' "${uniq_vers[@]}"
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
  # Asegurar que el puerto SSH (22) siempre esté permitido antes de activar UFW
  ufw allow 22/tcp comment "SSH-Secure" 2>/dev/null
  ufw allow "${puerto}/tcp" comment "HTTP-${servicio}-${puerto}" 2>/dev/null
  
  # Cerrar puerto 80 si el nuevo puerto es diferente
  if (( puerto != 80 )); then
    ufw delete allow 80/tcp 2>/dev/null || true
    echo -e "${YELLOW}[INFO] Puerto 80 cerrado (no se usa).${NC}"
  fi
  ufw --force enable 2>/dev/null
  echo -e "${GREEN}[OK] Firewall: puerto ${puerto}/tcp y puerto SSH (22) habilitados.${NC}"
}

# ─── Verificar si el servicio ya existe y preguntar qué hacer ─────────────────
verifico_previo_y_pregunto() {
  local servicio="$1"   # nombre del systemd unit
  local pkg="$2"        # nombre del paquete apt (puede ser vacío para Tomcat)

  local activo=false
  local instalado=false

  systemctl is-active --quiet "$servicio" 2>/dev/null && activo=true
  if [[ -n "$pkg" ]]; then
    dpkg -l "$pkg" 2>/dev/null | grep -q '^ii' && instalado=true
  elif [[ "$servicio" == "tomcat" ]]; then
    [[ -d "$TOMCAT_BASE/bin" ]] && instalado=true
  fi

  if [[ "$activo" == false && "$instalado" == false ]]; then
    return 0   # no existe → proceder con instalación normal
  fi

  # Ya existe
  echo -e "\n${YELLOW}${BOLD}[!] ${servicio} ya está instalado en este servidor.${NC}"
  $activo && echo -e "    Estado: ${GREEN}ACTIVO${NC}" || echo -e "    Estado: ${RED}INACTIVO${NC}"
  echo -e ""
  echo -e "  ${BOLD}1)${NC} Mantener el actual y solo cambiar configuración (puerto/versión)"
  echo -e "  ${BOLD}2)${NC} Desinstalar completamente y volver a instalar desde cero"
  echo -e "  ${BOLD}3)${NC} Cancelar (volver al menú)"
  echo ""

  local opc
  while true; do
    read -rp "¿Qué deseas hacer? (1/2/3): " opc
    case "$opc" in
      1) return 0    ;; # seguir — la función de instalación sobreescribe la config
      2)               # desinstalar primero
        echo -e "${YELLOW}[INFO] Desinstalando ${servicio}...${NC}"
        case "$servicio" in
          apache2)
            systemctl stop apache2 2>/dev/null
            apt-get purge -y -qq apache2 apache2-bin apache2-data apache2-utils 2>/dev/null
            rm -rf /etc/apache2 /var/log/apache2
            ;;
          nginx)
            systemctl stop nginx 2>/dev/null
            apt-get purge -y -qq nginx nginx-common 2>/dev/null
            rm -rf /etc/nginx
            ;;
          tomcat)
            systemctl stop tomcat 2>/dev/null
            systemctl disable tomcat 2>/dev/null
            rm -f /etc/systemd/system/tomcat.service
            rm -rf "$TOMCAT_BASE"
            systemctl daemon-reload
            ;;
        esac
        echo -e "${GREEN}[OK] ${servicio} desinstalado. Procediendo con instalación limpia.${NC}"
        return 0
        ;;
      3) echo -e "${YELLOW}Cancelado.${NC}"; return 1 ;;
      *) echo -e "${RED}Opción inválida (1, 2 o 3).${NC}" ;;
    esac
  done
}

# ═══════════════════════════════════════════════════════════════════════════════
# APACHE2
# ═══════════════════════════════════════════════════════════════════════════════
instalar_apache() {
  local version="$1"
  local puerto="$2"

  verifico_previo_y_pregunto "apache2" "apache2" || return 0

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
  mostrar_acceso_servicio "Apache2" "$puerto"
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

  verifico_previo_y_pregunto "nginx" "nginx" || return 0

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
  mostrar_acceso_servicio "Nginx" "$puerto"
}

# ═══════════════════════════════════════════════════════════════════════════════
# TOMCAT
# ═══════════════════════════════════════════════════════════════════════════════
instalar_tomcat() {
  local version="$1"
  local puerto="$2"

  verifico_previo_y_pregunto "tomcat" "" || return 0

  banner "INSTALANDO APACHE TOMCAT v${version} EN PUERTO ${puerto}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq openjdk-17-jre-headless curl tar ca-certificates 2>/dev/null

  local major; major=$(echo "$version" | cut -d. -f1)
  local tmp_file="/tmp/tomcat-${version}.tar.gz"
  local descargado=false

  # Intentar mirror principal primero, luego archive, luego CDN
  for base_url in \
    "https://downloads.apache.org/tomcat/tomcat-${major}/v${version}/bin" \
    "https://archive.apache.org/dist/tomcat/tomcat-${major}/v${version}/bin" \
    "https://dlcdn.apache.org/tomcat/tomcat-${major}/v${version}/bin"; do

    local url="${base_url}/apache-tomcat-${version}.tar.gz"
    echo -e "${YELLOW}[INFO] Descargando desde: ${url}${NC}"
    
    # 1. Intento normal
    local err_msg
    err_msg=$(curl -fsSL --max-time 120 -o "$tmp_file" "$url" 2>&1)
    local status=$?
    
    # 2. Intento ignorando certificado (por si ca-certificates está desactualizado)
    if (( status != 0 )); then
      echo -e "${YELLOW}[WARN] Descarga estándar falló (Código: $status). Reintentando con --insecure...${NC}"
      err_msg=$(curl -fsSLk --max-time 120 -o "$tmp_file" "$url" 2>&1)
      status=$?
    fi
    
    # 3. Intento vía HTTP (por si la red bloquea descargas seguras externas)
    if (( status != 0 )); then
      local http_url="${url/https:/http:}"
      echo -e "${YELLOW}[WARN] Reintentando vía HTTP normal: ${http_url}...${NC}"
      err_msg=$(curl -fsSLk --max-time 120 -o "$tmp_file" "$http_url" 2>&1)
      status=$?
    fi

    if (( status == 0 )); then
      # Verificar que el archivo sea un tarball gzip válido
      if tar tzf "$tmp_file" &>/dev/null; then
        descargado=true
        echo -e "${GREEN}[OK] Descarga exitosa.${NC}"
        break
      else
        echo -e "${RED}[ERROR] El archivo descargado está dañado o no es un comprimido válido.${NC}"
        rm -f "$tmp_file"
      fi
    else
      echo -e "${RED}[ERROR] Falló mirror. Curl reportó: ${err_msg}${NC}"
    fi
  done

  if [[ "$descargado" != true ]]; then
    echo -e "${RED}[ERROR] No se pudo descargar Tomcat ${version} desde ningún origen.${NC}"
    echo -e "${YELLOW}[INFO] Si el servidor no tiene conexión a Internet externa, descarga manualmente:${NC}"
    echo -e "${CYAN}  apache-tomcat-${version}.tar.gz${NC}"
    echo -e "${YELLOW}  y colócalo en la carpeta /tmp del servidor antes de ejecutar el script.${NC}"
    
    # Intentar buscar en /tmp, /home, la carpeta compartida /mnt/sysadmin o el directorio de scripts
    local local_tarball; local_tarball=$(find /tmp /home /mnt/sysadmin "$SCRIPT_DIR" "$(dirname "$SCRIPT_DIR")" -maxdepth 3 -name "apache-tomcat-${version}.tar.gz" 2>/dev/null | head -1)
    if [[ -n "$local_tarball" ]]; then
      echo -e "${GREEN}[INFO] Se encontró un instalador local en: $local_tarball. Usando esta copia.${NC}"
      cp "$local_tarball" "$tmp_file"
      descargado=true
    else
      return 1
    fi
  fi

  rm -rf "${TOMCAT_BASE}"
  mkdir -p "${TOMCAT_BASE}"
  tar xzf "$tmp_file" -C "${TOMCAT_BASE}" --strip-components=1
  rm -f "$tmp_file"

  crear_usuario_servicio "$TOMCAT_USER" "$TOMCAT_BASE"
  chown -R "${TOMCAT_USER}:${TOMCAT_USER}" "${TOMCAT_BASE}"
  chmod -R 750 "${TOMCAT_BASE}"
  chmod 755 "${TOMCAT_BASE}/webapps"

  # Detectar JAVA_HOME dinámicamente
  local java_home=""
  if command -v java &>/dev/null; then
    java_home=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
  else
    # Buscar una instalación típica si existe en directorios estándar
    local posibles_paths=(
      "/usr/lib/jvm/java-17-openjdk-amd64"
      "/usr/lib/jvm/java-11-openjdk-amd64"
      "/usr/lib/jvm/default-java"
    )
    for path in "${posibles_paths[@]}"; do
      if [[ -d "$path" ]]; then
        java_home="$path"
        break
      fi
    done
  fi

  if [[ -z "$java_home" ]]; then
    echo -e "${RED}[ERROR] No se detectó Java (JRE/JDK) instalado en el sistema.${NC}"
    echo -e "${YELLOW}[INFO] Para instalar Tomcat de manera offline, primero debes tener Java.${NC}"
    echo -e "       Instala el paquete localmente ejecutando en el servidor con internet o descarga"
    echo -e "       el paquete .deb de Java (openjdk-17-jre-headless) y colócalo en tu carpeta compartida.${NC}"
    return 1
  fi

  # Configurar puerto en server.xml
  sed -i "s/port=\"8080\"/port=\"${puerto}\"/" "${TOMCAT_BASE}/conf/server.xml"

  crear_index_html "${TOMCAT_BASE}/webapps/ROOT" "Tomcat" "$version" "$puerto"

  cat > /etc/systemd/system/tomcat.service <<SVCEOF
[Unit]
Description=Apache Tomcat ${version}
After=network.target

[Service]
Type=forking
User=${TOMCAT_USER}
Group=${TOMCAT_USER}
Environment=JAVA_HOME=${java_home}
Environment=CATALINA_HOME=${TOMCAT_BASE}
ExecStart=${TOMCAT_BASE}/bin/startup.sh
ExecStop=${TOMCAT_BASE}/bin/shutdown.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

  systemctl daemon-reload
  systemctl enable tomcat --quiet
  systemctl restart tomcat
  echo -e "${YELLOW}[INFO] Esperando inicio de Tomcat (10s)...${NC}"
  sleep 10

  configurar_firewall_linux "$puerto" "Tomcat"

  echo -e "\n${GREEN}${BOLD}[✓] Tomcat ${version} desplegado en puerto ${puerto}${NC}"
  mostrar_acceso_servicio "Tomcat" "$puerto"
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

# ─── Mostrar acceso al servicio (URLs) ──────────────────────────────────────
mostrar_acceso_servicio() {
  local servicio="$1"
  local puerto="$2"
  local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}${BOLD}✓ ${servicio} listo${NC}"
  echo -e "  Acceso local:  ${CYAN}http://localhost:${puerto}${NC}"
  echo -e "  Acceso remoto: ${CYAN}http://${ip}:${puerto}${NC}"
  echo -e "  Verificar:     ${YELLOW}curl -I http://localhost:${puerto}${NC}"
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
  echo -e "\n${BOLD}Encabezados HTTP:${NC}"
  curl -s -I --max-time 5 "http://localhost:${puerto}" 2>/dev/null \
    | grep -E 'HTTP/|Server:|X-Frame|X-Content|Content-Type' \
    || echo -e "  ${YELLOW}(Servicio aun iniciando, reintenta en unos segundos)${NC}"
}

estado_servicios_http() {
  banner "ESTADO SERVICIOS HTTP"
  local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')

  # Estado de cada servicio con puerto detectado
  local servicios=( apache2 nginx tomcat )
  for svc in "${servicios[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      # Detectar el puerto real en que escucha
      local pid; pid=$(systemctl show -p MainPID "$svc" 2>/dev/null | cut -d= -f2)
      local puerto_real=""
      if [[ -n "$pid" && "$pid" != "0" ]]; then
        puerto_real=$(ss -tlnp 2>/dev/null | grep "pid=${pid}" | awk '{print $4}' | grep -oP ':\K[0-9]+$' | head -1)
      fi
      # Fallback: buscar en la config
      if [[ -z "$puerto_real" ]]; then
        case "$svc" in
          apache2) puerto_real=$(grep -m1 '^Listen' /etc/apache2/ports.conf 2>/dev/null | awk '{print $2}') ;;
          nginx)   puerto_real=$(grep -m1 'listen' /etc/nginx/sites-enabled/default 2>/dev/null | grep -oP '[0-9]+') ;;
          tomcat)  puerto_real=$(grep -oP 'port="\K[0-9]+' /opt/tomcat/conf/server.xml 2>/dev/null | head -1) ;;
        esac
      fi
      local url=""
      [[ -n "$puerto_real" ]] && url="  → ${CYAN}http://${ip}:${puerto_real}${NC}"
      echo -e "  ${GREEN}[ACTIVO  ]${NC} ${BOLD}${svc}${NC} (puerto: ${puerto_real:-?})${url}"
    else
      echo -e "  ${RED}[INACTIVO]${NC} ${BOLD}${svc}${NC}"
    fi
  done

  echo -e "\n${BOLD}Todos los puertos HTTP activos:${NC}"
  local puertos_activos
  puertos_activos=$(ss -tlnp 2>/dev/null | grep -v 'LISTEN\|Local' | awk '{print $4}' \
    | grep -oP ':\K[0-9]+$' | sort -u | while read -r p; do
      # Solo puertos web comunes (no SSH, DB, etc.)
      if ! echo "${PUERTOS_RESERVADOS[*]}" | grep -qw "$p"; then
        echo -e "    Puerto ${YELLOW}${p}${NC}  →  ${CYAN}http://${ip}:${p}${NC}   $(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://localhost:${p} 2>/dev/null)"
      fi
    done)
  if [[ -z "$puertos_activos" ]]; then
    echo -e "  ${YELLOW}(ningún servicio HTTP detectado)${NC}"
  else
    echo -e "$puertos_activos"
  fi
}
