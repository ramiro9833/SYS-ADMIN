#!/usr/bin/env bash
# lib/bash/red.sh
# Funciones de configuración de red reutilizables.
# Uso: source ./red.sh  (requiere comunes.sh cargado previamente)

# ─── Verificar IP estática en la interfaz interna (Lubuntu) ──────────────────
verificar_ip_estatica() {
  echo -e "\n${BLUE}[CHECK] Verificando IP estática en la interfaz interna...${NC}"

  local iface
  iface=$(ip -o -4 addr show | awk '{print $2}' | grep -v lo | tail -1)

  local ip_actual
  ip_actual=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

  local es_estatica=false
  if grep -rq "dhcp4: no" /etc/netplan/ 2>/dev/null; then
    es_estatica=true
  fi

  if $es_estatica && [[ -n "$ip_actual" ]]; then
    echo -e "${GREEN}[OK] IP estática detectada: ${BOLD}$ip_actual${NC} en ${BOLD}$iface${NC}"
    SERVER_IP="$ip_actual"
    SERVER_IFACE="$iface"
  else
    echo -e "${YELLOW}[AVISO] No se detectó IP estática. Configurando...${NC}"
    configurar_ip_estatica "$iface"
  fi
}

# ─── Configurar IP estática en Netplan ───────────────────────────────────────
configurar_ip_estatica() {
  local iface="${1:-enp0s8}"
  banner "CONFIGURACIÓN DE IP ESTÁTICA"

  local ip_nueva
  ip_nueva=$(leer_ip "IP estática para este servidor" "192.168.100.10")
  local gateway
  gateway=$(leer_ip "Puerta de enlace (Gateway)" "192.168.100.1")

  local iface_nat
  iface_nat=$(ip route | awk '/default/ {print $5}' | head -1)
  [[ -z "$iface_nat" ]] && iface_nat="enp0s3"

  cat > /etc/netplan/99-sysadmin-config.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${iface_nat}:
      dhcp4: true
    ${iface}:
      dhcp4: no
      addresses:
        - ${ip_nueva}/24
EOF

  chmod 600 /etc/netplan/99-sysadmin-config.yaml
  netplan apply
  echo -e "${GREEN}[OK] IP estática $ip_nueva aplicada en $iface.${NC}"
  SERVER_IP="$ip_nueva"
  SERVER_IFACE="$iface"
}

# ─── Configurar Red Servidor Linux (Tarea 1) ──────────────────────────────────
configurar_red_servidor_linux() {
  banner "CONFIGURACIÓN DE RED - LUBUNTU SERVER (NETPLAN)"

  # 1. Detectar interfaces de red físicas
  echo -e "\n${BOLD}Detectando interfaces de red...${NC}"
  local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"))

  if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${RED}[ERROR] No se encontraron interfaces de red.${NC}"
    return 1
  fi

  # Mostrar interfaces
  echo -e "Interfaces encontradas:"
  local index=1
  for iface in "${interfaces[@]}"; do
    local ip; ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -v "127.0.0.1" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    local state; state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
    echo -e "  ${BOLD}$index)${NC} ${GREEN}$iface${NC} | Estado: $state | IP actual: ${YELLOW}${ip:-Ninguna}${NC}"
    ((index++))
  done

  # Seleccionar la interfaz de red interna
  local INT_IFACE
  while true; do
    read -rp "Selecciona el número de la interfaz para la Red Interna (red_sistemas) [habitualmente la segunda]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$index" ]; then
      INT_IFACE="${interfaces[$((choice-1))]}"
      break
    else
      echo -e "${RED}Opción inválida. Inténtalo de nuevo.${NC}"
    fi
  done

  # Seleccionar la interfaz de NAT (Internet)
  local NAT_IFACE
  while true; do
    read -rp "Selecciona el número de la interfaz para NAT (Internet) [habitualmente la primera]: " nat_choice
    if [[ "$nat_choice" =~ ^[0-9]+$ ]] && [ "$nat_choice" -ge 1 ] && [ "$nat_choice" -lt "$index" ]; then
      NAT_IFACE="${interfaces[$((nat_choice-1))]}"
      if [ "$NAT_IFACE" == "$INT_IFACE" ]; then
        echo -e "${RED}La interfaz de NAT no puede ser la misma que la interfaz de Red Interna.${NC}"
      else
        break
      fi
    else
      echo -e "${RED}Opción inválida. Inténtalo de nuevo.${NC}"
    fi
  done

  echo -e "\nConfiguración propuesta:"
  echo -e "  - Interfaz NAT (Internet - DHCP): ${GREEN}${NAT_IFACE}${NC}"
  echo -e "  - Interfaz Interna (Estática):     ${GREEN}${INT_IFACE}${NC}"

  # Configurar valores de IP estática para la red interna
  local DEFAULT_IP="192.168.100.10"
  local DEFAULT_MASK="24"

  echo -e "\n${YELLOW}Configuración de IP Estática para la red interna:${NC}"
  local ip_addr; ip_addr=$(leer_ip "Dirección IP" "$DEFAULT_IP")

  local cidr
  while true; do
    read -rp "Máscara en formato CIDR (ej: 24 para 255.255.255.0) [$DEFAULT_MASK]: " cidr
    cidr=${cidr:-$DEFAULT_MASK}
    if [[ $cidr =~ ^[0-9]+$ ]] && [ "$cidr" -ge 0 ] && [ "$cidr" -le 32 ]; then
      break
    else
      echo -e "${RED}Máscara CIDR inválida (debe ser entre 0 y 32).${NC}"
    fi
  done

  read -rp "¿Confirmas escribir estos datos en la configuración de Netplan? (s/n): " confirm
  if [[ ! "$confirm" =~ ^[sS]$ && ! "$confirm" =~ ^[yY]$ ]]; then
    echo -e "${RED}Operación cancelada.${NC}"
    return 0
  fi

  # Copia de seguridad
  local NETPLAN_DIR="/etc/netplan"
  local BACKUP_DIR="/etc/netplan/backup_$(date +%F_%T)"
  echo -e "\nCreando copia de seguridad de la configuración de Netplan en ${BACKUP_DIR}..."
  mkdir -p "$BACKUP_DIR"
  cp "$NETPLAN_DIR"/*.yaml "$BACKUP_DIR/" 2>/dev/null || true

  # Eliminar anteriores y escribir el nuevo archivo
  rm -f "$NETPLAN_DIR"/*.yaml
  cat <<EOF > "$NETPLAN_DIR/99-sysadmin-config.yaml"
# Archivo de configuración generado automáticamente por el script de configuración de red
network:
  version: 2
  renderer: networkd
  ethernets:
    $NAT_IFACE:
      dhcp4: true
    $INT_IFACE:
      dhcp4: no
      addresses:
        - $ip_addr/$cidr
EOF

  chmod 600 "$NETPLAN_DIR/99-sysadmin-config.yaml"

  echo -e "Aplicando configuración con 'netplan apply'..."
  if netplan apply; then
    echo -e "${GREEN}${BOLD}[OK] Configuración aplicada exitosamente.${NC}"
    ip addr show "$INT_IFACE"
  else
    echo -e "${RED}${BOLD}[ERROR] Hubo un error al aplicar la configuración de Netplan.${NC}"
    echo -e "Restaurando copia de seguridad..."
    cp "$BACKUP_DIR"/*.yaml "$NETPLAN_DIR/"
    netplan apply
    return 1
  fi
}

# ─── Configurar Red Cliente Linux Mint (Tarea 1) ─────────────────────────────
configurar_red_cliente_linux() {
  # Comprobar que nmcli está disponible
  if ! command -v nmcli &> /dev/null; then
    echo -e "${RED}${BOLD}[ERROR] NetworkManager (nmcli) no está instalado o no se encuentra en el sistema.${NC}"
    return 1
  fi

  banner "CONFIGURACIÓN DE RED - CLIENTE LINUX MINT (CLI)"

  # 1. Detectar interfaces
  echo -e "\n${BOLD}Detectando interfaces de red...${NC}"
  local interfaces=($(nmcli -t -f DEVICE device status | grep -v "lo"))

  if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${RED}[ERROR] No se detectaron interfaces de red físicas.${NC}"
    return 1
  fi

  echo -e "Interfaces encontradas:"
  local index=1
  for iface in "${interfaces[@]}"; do
    local type; type=$(nmcli -t -f TYPE device show "$iface" | grep "GENERAL.TYPE" | cut -d':' -f2)
    local state; state=$(nmcli -t -f STATE device show "$iface" | grep "GENERAL.STATE" | cut -d':' -f2)
    local ip; ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo -e "  ${BOLD}$index)${NC} ${GREEN}$iface${NC} | Tipo: $type | Estado: $state | IP actual: ${YELLOW}${ip:-Ninguna}${NC}"
    ((index++))
  done

  # Seleccionar interfaz
  local INTERFACE
  while true; do
    read -rp "Selecciona el número de la interfaz para la Red Interna (red_sistemas): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$index" ]; then
      INTERFACE="${interfaces[$((choice-1))]}"
      break
    else
      echo -e "${RED}Opción inválida. Inténtalo de nuevo.${NC}"
    fi
  done

  echo -e "\nInterfaz seleccionada: ${GREEN}${INTERFACE}${NC}"
  local CONN_NAME="Red_Sistemas"

  if ! nmcli connection show "$CONN_NAME" &> /dev/null; then
    echo -e "Creando perfil de conexión '${CONN_NAME}' para el dispositivo ${INTERFACE}..."
    nmcli connection add type ethernet con-name "$CONN_NAME" ifname "$INTERFACE" > /dev/null
  fi

  # Menú de opciones
  echo -e "\n${BOLD}¿Cómo deseas configurar la interfaz ${INTERFACE}?${NC}"
  echo -e "  ${BOLD}1)${NC} IP Estática"
  echo -e "  ${BOLD}2)${NC} DHCP Cliente"
  echo -e "  ${BOLD}3)${NC} Cancelar"

  while true; do
    read -rp "Opción (1-3): " opt
    case $opt in
      1)
        local DEFAULT_IP="192.168.100.30"
        local DEFAULT_MASK="24"
        local DEFAULT_GW="192.168.100.1"
        local DEFAULT_DNS="192.168.100.10"

        echo -e "\n${YELLOW}Configuración de IP Estática (Presione Enter para usar valores por defecto):${NC}"
        local ip_addr; ip_addr=$(leer_ip "Dirección IP" "$DEFAULT_IP")

        local cidr
        while true; do
          read -rp "Máscara CIDR (ej: 24) [$DEFAULT_MASK]: " cidr
          cidr=${cidr:-$DEFAULT_MASK}
          if [[ $cidr =~ ^[0-9]+$ ]] && [ "$cidr" -ge 0 ] && [ "$cidr" -le 32 ]; then
            break
          else
            echo -e "${RED}Máscara CIDR inválida.${NC}"
          fi
        done

        local gateway; gateway=$(leer_ip "Puerta de enlace" "$DEFAULT_GW")
        local dns; dns=$(leer_ip "Servidor DNS" "$DEFAULT_DNS")

        echo -e "\nAplicando configuración estática..."
        nmcli connection modify "$CONN_NAME" \
          connection.interface-name "$INTERFACE" \
          ipv4.method manual \
          ipv4.addresses "${ip_addr}/${cidr}" \
          ipv6.method ignore

        if [ -n "$gateway" ]; then
          nmcli connection modify "$CONN_NAME" ipv4.gateway "$gateway"
        else
          nmcli connection modify "$CONN_NAME" ipv4.gateway ""
        fi

        if [ -n "$dns" ]; then
          nmcli connection modify "$CONN_NAME" ipv4.dns "$dns"
        else
          nmcli connection modify "$CONN_NAME" ipv4.dns ""
        fi

        echo -e "Reiniciando conexión..."
        nmcli connection down "$CONN_NAME" > /dev/null 2>&1
        if nmcli connection up "$CONN_NAME"; then
          echo -e "${GREEN}${BOLD}[OK] Red configurada correctamente con IP ${ip_addr}/${cidr}.${NC}"
        else
          echo -e "${RED}${BOLD}[ERROR] No se pudo activar la interfaz.${NC}"
        fi
        break
        ;;
      2)
        echo -e "\nAplicando configuración DHCP en ${CONN_NAME}..."
        nmcli connection modify "$CONN_NAME" \
          connection.interface-name "$INTERFACE" \
          ipv4.method auto \
          ipv4.addresses "" \
          ipv4.gateway "" \
          ipv4.dns "" \
          ipv6.method ignore

        echo -e "Reiniciando conexión para solicitar IP por DHCP..."
        nmcli connection down "$CONN_NAME" > /dev/null 2>&1
        if nmcli connection up "$CONN_NAME"; then
          echo -e "${GREEN}${BOLD}[OK] Red configurada en modo DHCP.${NC}"
          sleep 2
          local ip_obtained; ip_obtained=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
          if [ -n "$ip_obtained" ]; then
            echo -e "${GREEN}IP asignada por DHCP: ${BOLD}$ip_obtained${NC}"
          else
            echo -e "${YELLOW}[ADVERTENCIA] No se ha obtenido una IP aún. Revisa el servidor DHCP.${NC}"
          fi
        else
          echo -e "${RED}${BOLD}[ERROR] No se pudo activar la conexión DHCP.${NC}"
        fi
        break
        ;;
      3)
        echo -e "\nOperación cancelada."
        return 0
        ;;
      *)
        echo -e "${RED}Opción inválida. Selecciona 1, 2 o 3.${NC}"
        ;;
    esac
  done
}
