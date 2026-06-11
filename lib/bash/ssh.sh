#!/usr/bin/env bash
# lib/bash/ssh.sh
# Funciones para instalación, configuración y monitoreo de OpenSSH Server en Linux.
# Uso: source ./ssh.sh  (requiere comunes.sh cargado previamente)

# ─── Instalación Idempotente de OpenSSH ──────────────────────────────────────
instalar_ssh() {
  banner "INSTALACIÓN OPENSSH SERVER"
  echo -e "${BLUE}[1/3] Verificando estado de OpenSSH Server...${NC}"

  if systemctl is-active --quiet ssh 2>/dev/null; then
    echo -e "${GREEN}[INFO] OpenSSH Server ya está instalado y activo.${NC}"
    systemctl status ssh --no-pager -l | head -6
    return 0
  fi

  apt-get update -y -qq
  instalar_paquete "openssh-server"

  # Habilitar inicio automático en el boot
  systemctl enable ssh
  systemctl start ssh

  sleep 1
  if verificar_servicio ssh; then
    echo -e "${GREEN}${BOLD}[OK] SSH instalado, habilitado en boot y activo.${NC}"
  else
    echo -e "${RED}[ERROR] SSH no pudo iniciarse. Revisa los logs.${NC}"
    journalctl -u ssh -n 10 --no-pager
  fi
}

# ─── Configuración de Seguridad SSH ──────────────────────────────────────────
configurar_ssh() {
  banner "CONFIGURACIÓN DE SEGURIDAD SSH"
  local SSHD_CONF="/etc/ssh/sshd_config"

  echo -e "${YELLOW}Opciones de seguridad disponibles:${NC}"
  echo -e "  ${BOLD}1)${NC} Cambiar el puerto SSH (por defecto: 22)"
  echo -e "  ${BOLD}2)${NC} Deshabilitar login de root por SSH"
  echo -e "  ${BOLD}3)${NC} Aplicar configuración recomendada (todas las opciones)"
  echo -e "  ${BOLD}4)${NC} Cancelar"
  read -rp "Selecciona una opción (1-4): " sec_opt

  # Respaldo antes de modificar
  cp "$SSHD_CONF" "${SSHD_CONF}.bak.$(date +%s)"
  echo -e "${CYAN}[INFO] Respaldo de sshd_config creado.${NC}"

  case $sec_opt in
    1)
      read -rp "Nuevo puerto SSH [22]: " nuevo_puerto
      [[ -z "$nuevo_puerto" ]] && nuevo_puerto=22
      sed -i "s/^#*Port .*/Port ${nuevo_puerto}/" "$SSHD_CONF"
      echo -e "${GREEN}[OK] Puerto SSH cambiado a: $nuevo_puerto${NC}"
      ;;
    2)
      sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" "$SSHD_CONF"
      echo -e "${GREEN}[OK] Login de root deshabilitado.${NC}"
      ;;
    3)
      sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/"       "$SSHD_CONF"
      sed -i "s/^#*MaxAuthTries .*/MaxAuthTries 3/"              "$SSHD_CONF"
      sed -i "s/^#*LoginGraceTime .*/LoginGraceTime 30/"         "$SSHD_CONF"
      sed -i "s/^#*X11Forwarding .*/X11Forwarding no/"           "$SSHD_CONF"
      sed -i "s/^#*PrintLastLog .*/PrintLastLog yes/"             "$SSHD_CONF"
      echo -e "${GREEN}[OK] Configuración de seguridad recomendada aplicada.${NC}"
      ;;
    4) echo "Operación cancelada."; return ;;
    *) echo -e "${RED}Opción inválida.${NC}"; return ;;
  esac

  # Validar sintaxis y reiniciar
  if sshd -t; then
    echo -e "${GREEN}[OK] Sintaxis de sshd_config: VÁLIDA.${NC}"
    systemctl restart ssh
    echo -e "${GREEN}[OK] Servicio SSH reiniciado con la nueva configuración.${NC}"
  else
    echo -e "${RED}[ERROR] Sintaxis inválida. Restaurando respaldo...${NC}"
    mv "${SSHD_CONF}.bak."* "$SSHD_CONF" 2>/dev/null
    systemctl restart ssh
  fi
}

# ─── Módulo de Monitoreo SSH ──────────────────────────────────────────────────
monitorear_ssh() {
  while true; do
    banner "MÓDULO DE MONITOREO SSH"
    echo -e "  ${BOLD}1)${NC} Estado del servicio SSH"
    echo -e "  ${BOLD}2)${NC} Ver sesiones SSH activas"
    echo -e "  ${BOLD}3)${NC} Ver últimos intentos de conexión (logs)"
    echo -e "  ${BOLD}4)${NC} Mostrar información de conexión para clientes"
    echo -e "  ${BOLD}5)${NC} Volver al menú principal"
    read -rp "Selecciona una opción (1-5): " mon_opt

    case $mon_opt in
      1)
        systemctl status ssh --no-pager -l
        ;;
      2)
        echo -e "\n${BOLD}Sesiones SSH activas (who):${NC}"
        who | grep -v "(:0)" || echo "No hay sesiones SSH activas."
        echo -e "\n${BOLD}Conexiones en puerto 22:${NC}"
        ss -tnp | grep ':22' || echo "Sin conexiones activas en puerto 22."
        ;;
      3)
        echo -e "\n${BOLD}Últimos 20 intentos de conexión SSH:${NC}"
        journalctl -u ssh -n 20 --no-pager
        ;;
      4)
        local server_ip
        server_ip=$(ip -o -4 addr show | grep -v "127.0.0.1" | awk '{print $4}' | cut -d/ -f1 | grep "192.168" | head -1)
        local usuario
        usuario=$(logname 2>/dev/null || echo "$SUDO_USER")
        echo -e "\n${CYAN}${BOLD}════ INFORMACIÓN DE CONEXIÓN SSH ════${NC}"
        echo -e "${CYAN}Servidor:  Lubuntu Server (Srv-Linux-Sistemas)${NC}"
        echo -e "${CYAN}IP:        ${server_ip}${NC}"
        echo -e "${CYAN}Puerto:    22${NC}"
        echo -e "${CYAN}Usuario:   ${usuario}${NC}"
        echo -e "\n${BOLD}Comando desde Linux Mint:${NC}"
        echo -e "  ${GREEN}ssh ${usuario}@${server_ip}${NC}"
        echo -e "\n${BOLD}Configuración en PuTTY/MobaXterm:${NC}"
        echo -e "  Host: ${server_ip}  Puerto: 22  User: ${usuario}"
        ;;
      5) break ;;
      *) echo -e "${RED}Opción inválida.${NC}" ;;
    esac
  done
}
