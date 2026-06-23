#!/usr/bin/env bash
# lib/bash/ad.sh
# Funciones para union de clientes Linux a Active Directory (realmd, sssd, adcli).
# Uso: source "${LIB_DIR}/ad.sh"

# ─── Instalar paquetes necesarios para AD ────────────────────────────────────
instalar_paquetes_ad() {
  banner "INSTALACION DE PAQUETES - REALMD, SSSD, ADCLI"
  apt-get update -qq
  instalar_paquete "realmd"
  instalar_paquete "sssd"
  instalar_paquete "sssd-tools"
  instalar_paquete "adcli"
  instalar_paquete "libnss-sss"
  instalar_paquete "libpam-sss"
  instalar_paquete "packagekit"
  instalar_paquete "krb5-user"
  echo -e "${GREEN}[OK] Paquetes de integracion AD instalados.${NC}"
}

# ─── Configurar /etc/sssd/sssd.conf con fallback_homedir ─────────────────────
configurar_sssd() {
  local dominio="${1:-sysadmin.local}"
  local dc_fqdn="${2:-}"

  banner "CONFIGURACION SSSD - HOMEDIR Y DOMINIO"

  if [ -z "$dc_fqdn" ]; then
    dc_fqdn=$(realm discover "$dominio" 2>/dev/null | awk -F': ' '/server-name/ {print $2; exit}')
    [ -z "$dc_fqdn" ] && read -rp "FQDN del Controlador de Dominio: " dc_fqdn
  fi

  local dominio_mayus
  dominio_mayus=$(echo "$dominio" | tr '[:lower:]' '[:upper:]')

  mkdir -p /etc/sssd
  chmod 700 /etc/sssd

  cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = ${dominio}
config_file_version = 2
services = nss, pam

[domain/${dominio}]
ad_domain = ${dominio}
krb5_realm = ${dominio_mayus}
realmd_tags = manages-system joined-with-adcli
id_provider = ad
access_provider = ad
fallback_homedir = /home/%u@%d
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = True
ad_gpo_access_control = permissive
EOF

  chmod 600 /etc/sssd/sssd.conf
  echo -e "${GREEN}[OK] /etc/sssd/sssd.conf configurado (fallback_homedir=/home/%u@%d).${NC}"
}

# ─── Configurar sudo para usuarios/grupos de AD ───────────────────────────────
configurar_sudo_admins() {
  local grupo_sudo="${1:-%domain\ admins@${2:-sysadmin.local}}"

  banner "CONFIGURACION SUDO - USUARIOS AD"

  cat > /etc/sudoers.d/ad-admins <<EOF
# Permisos de sudo para administradores del dominio Active Directory
# Generado automaticamente por tarea8/join_domain_linux.sh

${grupo_sudo} ALL=(ALL:ALL) ALL
EOF

  chmod 440 /etc/sudoers.d/ad-admins
  visudo -cf /etc/sudoers.d/ad-admins
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Sudoers configurado en /etc/sudoers.d/ad-admins.${NC}"
  else
    echo -e "${RED}[ERROR] Sintaxis invalida en sudoers. Revise el archivo.${NC}"
    return 1
  fi
}

# ─── Unir equipo Linux al dominio ────────────────────────────────────────────
unir_dominio_linux() {
  local dominio="${1:-}"
  local usuario_ad="${2:-}"
  local contrasena="${3:-}"

  banner "UNION DE CLIENTE LINUX AL DOMINIO ACTIVE DIRECTORY"

  if [ -z "$dominio" ]; then
    read -rp "Nombre del dominio (ej. sysadmin.local): " dominio
  fi

  # Instalar los paquetes necesarios al inicio (cuando aún tenemos el DNS original con acceso a Internet)
  instalar_paquetes_ad

  # Comprobar si el dominio se puede resolver (directamente vía DNS o por NSS)
  local resolucion_ok=false
  if command -v nslookup >/dev/null 2>&1; then
    if nslookup "$dominio" >/dev/null 2>&1; then
      resolucion_ok=true
    fi
  elif command -v host >/dev/null 2>&1; then
    if host "$dominio" >/dev/null 2>&1; then
      resolucion_ok=true
    fi
  fi
  # Fallback a getent ahosts si no hay herramientas DNS instaladas
  if [ "$resolucion_ok" = false ] && getent ahosts "$dominio" >/dev/null 2>&1; then
    resolucion_ok=true
  fi

  if [ "$resolucion_ok" = false ]; then
    echo -e "${YELLOW}[WARN] No se pudo resolver el dominio '$dominio' por DNS.${NC}"
    echo -e "${YELLOW}[INFO] Para unirse al dominio, el cliente Linux debe usar el DNS del Controlador de Dominio.${NC}"
    read -rp "Ingrese la IP del Controlador de Dominio (DNS) [192.168.100.20]: " dns_ip
    dns_ip=${dns_ip:-192.168.100.20}

    # Verificar conectividad básica con el DNS (puerto 53)
    echo -e "[INFO] Comprobando conectividad con el servidor DNS en $dns_ip:53..."
    if ! timeout 2 bash -c "cat < /dev/null > /dev/tcp/$dns_ip/53" 2>/dev/null; then
      echo -e "${RED}[ERROR] El puerto DNS (53) en la IP $dns_ip no responde.${NC}"
      echo -e "${YELLOW}[HINT] 1. Asegúrese de que el Windows Server esté encendido.${NC}"
      echo -e "${YELLOW}[HINT] 2. Verifique la IP del Windows Server (¿es $dns_ip?).${NC}"
      echo -e "${YELLOW}[HINT] 3. Verifique que ambas VMs estén en la misma red interna de VirtualBox.${NC}"
      return 1
    fi

    # Verificar si el DNS de Windows de verdad conoce el dominio
    echo -e "[INFO] Servidor DNS detectado. Consultando directamente al DNS..."
    local dns_resolve_ok=false
    if command -v nslookup >/dev/null 2>&1; then
      if nslookup "$dominio" "$dns_ip" >/dev/null 2>&1; then
        dns_resolve_ok=true
      fi
    elif command -v dig >/dev/null 2>&1; then
      if dig @"$dns_ip" "$dominio" +short 2>/dev/null | grep -q -E '^[0-9]'; then
        dns_resolve_ok=true
      fi
    elif command -v host >/dev/null 2>&1; then
      if host "$dominio" "$dns_ip" >/dev/null 2>&1; then
        dns_resolve_ok=true
      fi
    else
      # Si no hay herramientas de consulta DNS en este momento, confiamos en la conexión al puerto 53
      dns_resolve_ok=true
    fi

    if [ "$dns_resolve_ok" = false ]; then
      echo -e "${RED}[ERROR] El servidor DNS en $dns_ip no contiene registros para el dominio '$dominio'.${NC}"
      echo -e "${YELLOW}[HINT] Esto suele significar que:${NC}"
      echo -e "${YELLOW}  - Escribió incorrectamente el dominio (el predeterminado es sysadmin.local).${NC}"
      echo -e "${YELLOW}  - No ha completado la promoción de dominio (tarea8.ps1 Opción 10) en Windows Server.${NC}"
      return 1
    fi

    echo -e "[INFO] Configurando temporalmente nameserver $dns_ip y dominio $dominio..."

    # 1. Configurar en systemd-resolved (estándar en Ubuntu Server / Mint)
    local iface; iface=$(ip -o -4 addr show | grep "192.168.100." | awk '{print $2}' | head -n 1)
    [ -z "$iface" ] && iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n 1)

    if [ -n "$iface" ]; then
      if command -v resolvectl >/dev/null 2>&1; then
        echo -e "[INFO] Configurando DNS con resolvectl en interfaz $iface..."
        resolvectl dns "$iface" "$dns_ip"
        resolvectl domain "$iface" "$dominio"
        resolvectl flush-caches
      elif command -v systemd-resolve >/dev/null 2>&1; then
        echo -e "[INFO] Configurando DNS con systemd-resolve en interfaz $iface..."
        systemd-resolve --interface "$iface" --set-dns "$dns_ip" --set-domain "$dominio"
      fi
    fi

    # 2. Configurar en NetworkManager si está disponible
    if command -v nmcli >/dev/null 2>&1; then
      local active_conn; active_conn=$(nmcli -t -f NAME,DEVICE connection show --active | grep -v -E ':lo|:docker|:veth' | head -n 1 | cut -d':' -f1)
      if [ -n "$active_conn" ]; then
        echo -e "[INFO] Configurando DNS en conexión NetworkManager: $active_conn"
        nmcli connection modify "$active_conn" ipv4.dns "$dns_ip"
        nmcli connection up "$active_conn" >/dev/null 2>&1
        sleep 2
      fi
    fi

    # 3. Sobreescribir resolv.conf como fallback directo
    if ! grep -q "nameserver $dns_ip" /etc/resolv.conf 2>/dev/null; then
      [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
      echo -e "nameserver $dns_ip\nnameserver 8.8.8.8" > /etc/resolv.conf
    fi

    # Volver a verificar resolución usando las herramientas directas de DNS
    local resolucion_final=false
    if command -v nslookup >/dev/null 2>&1; then
      if nslookup "$dominio" >/dev/null 2>&1; then
        resolucion_final=true
      fi
    elif command -v host >/dev/null 2>&1; then
      if host "$dominio" >/dev/null 2>&1; then
        resolucion_final=true
      fi
    elif getent ahosts "$dominio" >/dev/null 2>&1; then
      resolucion_final=true
    fi

    if [ "$resolucion_final" = false ]; then
      echo -e "${RED}[ERROR] El sistema aún no puede resolver '$dominio' mediante las herramientas DNS.${NC}"
      echo -e "${YELLOW}[HINT] Reinicie temporalmente el resolvedor o verifique /etc/resolv.conf.${NC}"
      return 1
    else
      echo -e "${GREEN}[OK] Dominio '$dominio' resuelto correctamente (las herramientas de AD podrán conectarse).${NC}"
    fi
  fi

  # Verificar si ya esta unido
  if realm list 2>/dev/null | grep -q "$dominio"; then
    echo -e "${YELLOW}[INFO] Este equipo ya esta unido al dominio '$dominio'.${NC}"
  else
  if [ -z "$usuario_ad" ]; then
      read -rp "Usuario con permisos de dominio (ej. Administrador): " usuario_ad
    fi
    if [ -z "$contrasena" ]; then
      read -rsp "Contrasena del usuario de dominio: " contrasena
      echo ""
    fi

    echo "$contrasena" | realm join --user="$usuario_ad" "$dominio"
    if [ $? -ne 0 ]; then
      echo -e "${RED}[ERROR] Fallo la union al dominio '$dominio'.${NC}"
      return 1
    fi
    echo -e "${GREEN}[OK] Equipo unido al dominio '$dominio'.${NC}"
  fi

  configurar_sssd "$dominio"
  configurar_sudo_admins "%domain\\ admins@${dominio}"

  systemctl enable sssd
  systemctl restart sssd

  echo -e "${GREEN}[OK] SSSD reiniciado. Los usuarios AD pueden iniciar sesion con formato usuario@${dominio}.${NC}"
}

# ─── Mostrar estado de la union al dominio ───────────────────────────────────
mostrar_estado_dominio_linux() {
  banner "ESTADO DE INTEGRACION AD - CLIENTE LINUX"

  echo -e "${CYAN}--- Dominios configurados (realm) ---${NC}"
  realm list 2>/dev/null || echo "  (sin dominios)"

  echo -e "\n${CYAN}--- Servicio SSSD ---${NC}"
  if systemctl is-active --quiet sssd; then
    echo -e "  ${GREEN}[ACTIVO] sssd${NC}"
  else
    echo -e "  ${RED}[INACTIVO] sssd${NC}"
  fi

  echo -e "\n${CYAN}--- fallback_homedir ---${NC}"
  grep -E "fallback_homedir|use_fully_qualified" /etc/sssd/sssd.conf 2>/dev/null || echo "  (sssd.conf no encontrado)"

  echo -e "\n${CYAN}--- Sudoers AD ---${NC}"
  if [ -f /etc/sudoers.d/ad-admins ]; then
    cat /etc/sudoers.d/ad-admins
  else
    echo "  (no configurado)"
  fi
}
