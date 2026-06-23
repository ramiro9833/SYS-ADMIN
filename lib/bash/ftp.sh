#!/usr/bin/env bash
# lib/bash/ftp.sh
# Funciones para instalación, configuración y gestión del servidor FTP (vsftpd) en Linux.
# Uso: source ./ftp.sh  (requiere comunes.sh cargado previamente)

# ─── Instalar e Inicializar vsftpd ───────────────────────────────────────────
instalar_ftp_linux() {
  banner "INSTALACIÓN Y CONFIGURACIÓN VSFTPD"

  # Instalar vsftpd si no está instalado
  instalar_paquete "vsftpd"

  # Crear directorios base
  echo -e "${BLUE}[INFO] Creando directorios base de FTP...${NC}"
  mkdir -p /srv/ftp/general
  mkdir -p /srv/ftp/grupos/reprobados
  mkdir -p /srv/ftp/grupos/recursadores
  mkdir -p /srv/ftp/usuarios
  mkdir -p /srv/ftp/anon/general

  # Permisos bases
  chmod 777 /srv/ftp/general
  chmod 777 /srv/ftp/grupos/reprobados
  chmod 777 /srv/ftp/grupos/recursadores
  chmod 755 /srv/ftp/usuarios
  
  # Aislamiento anónimo (anon root debe ser de solo lectura para vsftpd)
  chown root:root /srv/ftp/anon
  chmod 555 /srv/ftp/anon
  
  # Realizar montaje de general dentro de anon
  umount /srv/ftp/anon/general 2>/dev/null || true
  mount --bind /srv/ftp/general /srv/ftp/anon/general

  # Agregar persistencia del montaje anon al fstab si no existe
  if ! grep -q "/srv/ftp/anon/general" /etc/fstab; then
    echo "/srv/ftp/general /srv/ftp/anon/general none bind 0 0" >> /etc/fstab
  fi

  # Asegurar que nologin esté en /etc/shells para permitir autenticación PAM
  if ! grep -q "/usr/sbin/nologin" /etc/shells; then
    echo "/usr/sbin/nologin" >> /etc/shells
    echo -e "${GREEN}[OK] /usr/sbin/nologin agregado a /etc/shells.${NC}"
  fi

  # Copiar configuración de vsftpd original
  if [ ! -f /etc/vsftpd.conf.bak ]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.bak
    echo -e "${GREEN}[OK] Respaldo de /etc/vsftpd.conf creado.${NC}"
  fi

  # Detectar IP del servidor para PASV
  local SERVER_IP
  SERVER_IP=$(ip -o -4 addr show | grep -v "127.0.0.1" | awk '{print $4}' | cut -d/ -f1 | grep "192.168" | head -1)
  [ -z "$SERVER_IP" ] && SERVER_IP=$(hostname -I | awk '{print $1}')

  # Escribir la nueva configuración de vsftpd
  echo -e "${BLUE}[INFO] Escribiendo configuración /etc/vsftpd.conf (IP PASV: ${SERVER_IP})...${NC}"
  cat > /etc/vsftpd.conf <<VSFTPDEOF
# Configuración del servidor FTP - vsftpd
listen=NO
listen_ipv6=YES

# Permitir acceso anónimo (Solo Lectura)
anonymous_enable=YES
no_anon_password=YES
anon_root=/srv/ftp/anon
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# Permitir usuarios locales (Escritura)
local_enable=YES
write_enable=YES
local_umask=022

# Aislamiento chroot para usuarios locales
# IMPORTANTE: el directorio raíz del chroot (local_root) DEBE ser propiedad de
# root y NO tener permisos de escritura para el usuario (chmod 755).
chroot_local_user=YES
local_root=/srv/ftp/usuarios/\$USER
user_sub_token=\$USER

# ── MODO PASIVO (PASV) ──────────────────────────────────────────────────────
# Requerido para clientes Windows (.NET FtpWebRequest) e interfaces gráficas.
# Se fija un rango de puertos para que el firewall pueda abrirlos.
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=${SERVER_IP}
# pasv_promiscuous=YES  <- solo si hay NAT doble o el cliente no puede alcanzar pasv_address

# Logs y misceláneos
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
utf8_filesystem=YES
VSFTPDEOF

  # Asegurar el inicio en el arranque
  systemctl enable vsftpd
  systemctl restart vsftpd

  # Abrir puertos en UFW (FTP control + rango PASV para clientes Windows/.NET)
  if command -v ufw &>/dev/null; then
    ufw allow 21/tcp  comment "FTP-Control"          2>/dev/null
    ufw allow 40000:40100/tcp comment "FTP-PASV-Data" 2>/dev/null
    echo -e "${GREEN}[OK] Firewall: puertos 21 y 40000-40100/tcp abiertos.${NC}"
  fi

  # Verificar servicio
  sleep 1
  verificar_servicio vsftpd
}

# ─── Crear Usuario de FTP en Linux ───────────────────────────────────────────
crear_usuario_ftp_linux() {
  local username="$1"
  local password="$2"
  local group="$3"

  if [[ -z "$username" || -z "$password" || -z "$group" ]]; then
    echo -e "${RED}[ERROR] Faltan parámetros para crear el usuario.${NC}"
    return 1
  fi

  # Validar que el grupo sea correcto
  if [[ "$group" != "reprobados" && "$group" != "recursadores" ]]; then
    echo -e "${RED}[ERROR] Grupo inválido. Debe ser 'reprobados' o 'recursadores'.${NC}"
    return 1
  fi

  # Asegurar que el grupo del sistema exista
  if ! getent group "$group" >/dev/null; then
    groupadd "$group"
    echo -e "${GREEN}[OK] Grupo del sistema '$group' creado.${NC}"
  fi

  # Verificar si el usuario ya existe
  if id "$username" &>/dev/null; then
    echo -e "${YELLOW}[AVISO] El usuario '$username' ya existe. Reconfigurando permisos...${NC}"
    # Cambiar de grupo por si acaso
    usermod -g "$group" "$username"
  else
    # Crear usuario sin shell de login y con home en su chroot directory
    useradd -m -d "/srv/ftp/usuarios/$username" -s /usr/sbin/nologin -g "$group" "$username"
    echo "$username:$password" | chpasswd
    echo -e "${GREEN}[OK] Usuario '$username' creado en el sistema.${NC}"
  fi

  # Estructura del chroot:
  #   /srv/ftp/usuarios/<user>/          <- raíz chroot: root:root 755 (vsftpd lo exige)
  #   /srv/ftp/usuarios/<user>/privado/  <- dir privado con escritura para el usuario
  #   /srv/ftp/usuarios/<user>/general/  <- bind mount de /srv/ftp/general
  #   /srv/ftp/usuarios/<user>/<group>/  <- bind mount del grupo
  local user_home="/srv/ftp/usuarios/$username"
  mkdir -p "$user_home/general"
  mkdir -p "$user_home/$group"
  mkdir -p "$user_home/privado"  # carpeta de escritura personal dentro del chroot

  # El directorio raíz del chroot DEBE ser de root:root y NO writable por el usuario
  # (de lo contrario vsftpd rechaza el login con error 500)
  chown root:root "$user_home"
  chmod 755 "$user_home"

  # La subcarpeta privada sí puede ser 700 del usuario
  chown -R "$username:$group" "$user_home/privado"
  chmod 700 "$user_home/privado"

  # Realizar los montajes bind
  # 1. Montaje de general
  umount "$user_home/general" 2>/dev/null || true
  mount --bind /srv/ftp/general "$user_home/general"
  
  # 2. Montaje del grupo
  umount "$user_home/$group" 2>/dev/null || true
  mount --bind "/srv/ftp/grupos/$group" "$user_home/$group"

  # Agregar montajes al fstab para persistencia si no existen
  if ! grep -q "$user_home/general" /etc/fstab; then
    echo "/srv/ftp/general $user_home/general none bind 0 0" >> /etc/fstab
  fi
  if ! grep -q "$user_home/$group" /etc/fstab; then
    echo "/srv/ftp/grupos/$group $user_home/$group none bind 0 0" >> /etc/fstab
  fi

  echo -e "${GREEN}[OK] Estructura de directorios y montajes configurados para '$username'.${NC}"
}

# ─── Cambiar Grupo de Usuario FTP ────────────────────────────────────────────
cambiar_grupo_usuario_linux() {
  local username="$1"
  local new_group="$2"

  if [[ -z "$username" || -z "$new_group" ]]; then
    echo -e "${RED}[ERROR] Faltan parámetros.${NC}"
    return 1
  fi

  if [[ "$new_group" != "reprobados" && "$new_group" != "recursadores" ]]; then
    echo -e "${RED}[ERROR] Grupo destino inválido. Debe ser 'reprobados' o 'recursadores'.${NC}"
    return 1
  fi

  # Verificar que el usuario exista
  if ! id "$username" &>/dev/null; then
    echo -e "${RED}[ERROR] El usuario '$username' no existe.${NC}"
    return 1
  fi

  # Determinar el grupo viejo
  local old_group; old_group=$(id -gn "$username")

  if [[ "$old_group" == "$new_group" ]]; then
    echo -e "${YELLOW}[INFO] El usuario '$username' ya pertenece al grupo '$new_group'.${NC}"
    return 0
  fi

  # Cambiar grupo principal en el sistema
  usermod -g "$new_group" "$username"
  echo -e "${GREEN}[OK] Grupo principal del usuario cambiado a '$new_group'.${NC}"

  local user_home="/srv/ftp/usuarios/$username"

  # 1. Desmontar grupo viejo
  umount "$user_home/$old_group" 2>/dev/null || true
  rm -rf "$user_home/$old_group"
  
  # Eliminar del fstab la línea del grupo viejo
  sed -i "\|/srv/ftp/grupos/$old_group $user_home/$old_group|d" /etc/fstab

  # 2. Crear y montar grupo nuevo
  mkdir -p "$user_home/$new_group"
  mount --bind "/srv/ftp/grupos/$new_group" "$user_home/$new_group"

  # Agregar al fstab
  if ! grep -q "$user_home/$new_group" /etc/fstab; then
    echo "/srv/ftp/grupos/$new_group $user_home/$new_group none bind 0 0" >> /etc/fstab
  fi

  # Ajustar permisos de la carpeta personal (para que pertenezca al nuevo grupo)
  chown -R "$username:$new_group" "$user_home/privado"

  echo -e "${GREEN}[OK] Montaje cambiado exitosamente de '$old_group' a '$new_group'.${NC}"
}

# ─── Monitoreo FTP ───────────────────────────────────────────────────────────
monitorear_ftp_linux() {
  while true; do
    banner "MONITOREO FTP - LINUX SERVER"
    echo -e "  ${BOLD}1)${NC} Estado del servicio vsftpd"
    echo -e "  ${BOLD}2)${NC} Ver usuarios conectados"
    echo -e "  ${BOLD}3)${NC} Ver logs de transferencias FTP"
    echo -e "  ${BOLD}4)${NC} Listar montajes bind activos"
    echo -e "  ${BOLD}5)${NC} Volver"
    read -rp "Seleccione una opción (1-5): " opt

    case $opt in
      1) systemctl status vsftpd --no-pager ;;
      2) 
        echo -e "\n${BOLD}Sesiones activas de vsftpd:${NC}"
        ps aux | grep vsftpd | grep -v grep || echo "No hay sesiones FTP activas."
        ;;
      3) 
        echo -e "\n${BOLD}Últimos eventos en vsftpd.log:${NC}"
        tail -n 20 /var/log/vsftpd.log 2>/dev/null || echo "No se pudo leer /var/log/vsftpd.log o no hay registros."
        ;;
      4)
        echo -e "\n${BOLD}Montajes enlazados (bind) de FTP:${NC}"
        mount | grep "/srv/ftp" || echo "No hay montajes enlazados activos."
        ;;
      5) break ;;
      *) echo -e "${RED}Opción inválida.${NC}" ;;
    esac
  done
}
