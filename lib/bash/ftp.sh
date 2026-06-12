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

  # Permisos bases
  chmod 777 /srv/ftp/general
  chmod 777 /srv/ftp/grupos/reprobados
  chmod 777 /srv/ftp/grupos/recursadores
  chmod 755 /srv/ftp/usuarios

  # Copiar configuración de vsftpd original
  if [ ! -f /etc/vsftpd.conf.bak ]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.bak
    echo -e "${GREEN}[OK] Respaldo de /etc/vsftpd.conf creado.${NC}"
  fi

  # Escribir la nueva configuración de vsftpd
  echo -e "${BLUE}[INFO] Escribiendo configuración /etc/vsftpd.conf...${NC}"
  cat <<EOF > /etc/vsftpd.conf
# Configuración del servidor FTP - vsftpd
listen=NO
listen_ipv6=YES

# Permitir acceso anónimo (Solo Lectura)
anonymous_enable=YES
no_anon_password=YES
anon_root=/srv/ftp/general
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# Permitir usuarios locales (Escritura)
local_enable=YES
write_enable=YES
local_umask=022

# Aislamiento chroot para usuarios locales
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=/srv/ftp/usuarios/\$USER
user_sub_token=\$USER

# Logs y misceláneos
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
utf8_filesystem=YES
EOF

  # Asegurar el inicio en el arranque
  systemctl enable vsftpd
  systemctl restart vsftpd

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

  # Crear carpetas dentro de la raíz chroot del usuario
  local user_home="/srv/ftp/usuarios/$username"
  mkdir -p "$user_home/general"
  mkdir -p "$user_home/$group"
  mkdir -p "$user_home/$username"

  # Asignar permisos a la carpeta personal real
  chown -R "$username:$group" "$user_home/$username"
  chmod 700 "$user_home/$username"

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
  chown -R "$username:$new_group" "$user_home/$username"

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
