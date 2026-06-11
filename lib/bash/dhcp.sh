#!/usr/bin/env bash
# lib/bash/dhcp.sh
# Funciones de instalación, configuración y monitoreo de isc-dhcp-server.
# Uso: source ./dhcp.sh  (requiere comunes.sh y red.sh cargados previamente)

instalar_dhcp() {
  banner "INSTALACIÓN ISC-DHCP-SERVER"
  if systemctl is-active --quiet isc-dhcp-server 2>/dev/null || dpkg -l | grep -q "^ii.*isc-dhcp-server "; then
    echo -e "${GREEN}[INFO] isc-dhcp-server ya está instalado y activo.${NC}"
    systemctl status isc-dhcp-server --no-pager | head -5
    return 0
  fi
  apt-get update -y -qq
  instalar_paquete "isc-dhcp-server"
  echo -e "${GREEN}[OK] isc-dhcp-server instalado.${NC}"
}

configurar_dhcp() {
  banner "CONFIGURACIÓN DEL SERVIDOR DHCP"
  local IFACE="${SERVER_IFACE:-enp0s8}"
  local DHCPD_CONF="/etc/dhcp/dhcpd.conf"
  local IFACE_CONF="/etc/default/isc-dhcp-server"

  read -rp "Subred [192.168.100.0]: " SUBNET;      [[ -z "$SUBNET" ]] && SUBNET="192.168.100.0"
  read -rp "Máscara [255.255.255.0]: " NETMASK;    [[ -z "$NETMASK" ]] && NETMASK="255.255.255.0"
  local RANGE_START; RANGE_START=$(leer_ip "Rango inicial" "192.168.100.50")
  local RANGE_END;   RANGE_END=$(leer_ip "Rango final" "192.168.100.150")
  local GATEWAY;     GATEWAY=$(leer_ip "Gateway" "192.168.100.1")
  local DNS_SERVER;  DNS_SERVER=$(leer_ip "Servidor DNS" "192.168.100.10")
  read -rp "Tiempo de concesión en segundos [600]: " LEASE_TIME
  [[ -z "$LEASE_TIME" ]] && LEASE_TIME=600

  # Configurar interfaz
  sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"${IFACE}\"/" "$IFACE_CONF"

  # Generar dhcpd.conf
  cat > "$DHCPD_CONF" <<EOF
# Generado por tarea2_dhcp_linux.sh
default-lease-time ${LEASE_TIME};
max-lease-time $((LEASE_TIME * 2));

subnet ${SUBNET} netmask ${NETMASK} {
  range ${RANGE_START} ${RANGE_END};
  option routers ${GATEWAY};
  option domain-name-servers ${DNS_SERVER};
  option broadcast-address $(echo $SUBNET | sed 's/\.0$/.255/');
}
EOF

  if dhcpd -t -cf "$DHCPD_CONF" 2>/dev/null; then
    echo -e "${GREEN}[OK] Sintaxis dhcpd.conf válida.${NC}"
  else
    echo -e "${RED}[ERROR] Error de sintaxis en dhcpd.conf.${NC}"; return 1
  fi

  systemctl restart isc-dhcp-server
  verificar_servicio isc-dhcp-server
}

monitorear_dhcp() {
  while true; do
    banner "MÓDULO DE MONITOREO DHCP"
    echo -e "  ${BOLD}1)${NC} Estado del servicio DHCP"
    echo -e "  ${BOLD}2)${NC} Listar concesiones activas"
    echo -e "  ${BOLD}3)${NC} Ver logs del DHCP"
    echo -e "  ${BOLD}4)${NC} Volver"
    read -rp "Opción (1-4): " opt
    case $opt in
      1) systemctl status isc-dhcp-server --no-pager ;;
      2)
        local leases_file="/var/lib/dhcp/dhcpd.leases"
        echo -e "\n${BOLD}Concesiones DHCP Activas:${NC}"
        printf "%-15s | %-17s | %-19s | %-25s\n" "Dirección IP" "MAC" "Vencimiento" "Hostname"
        echo "------------------------------------------------------------------------------------"
        awk '
          /^lease /           { ip=$2; state=""; mac="N/D"; ends="N/D"; host="N/D" }
          /^  binding state / { state=$3; sub(";","",state) }
          /^  hardware /      { mac=$3; sub(";","",mac) }
          /^  ends /          { ends=$3" "$4; sub(";","",ends) }
          /^  client-hostname/{ host=$2; gsub(/[";]/,"",host) }
          /^}/ { if (state == "active") printf "%-15s | %-17s | %-19s | %-25s\n", ip, mac, ends, host }
        ' "$leases_file" 2>/dev/null || echo "Sin concesiones activas."
        ;;
      3) journalctl -u isc-dhcp-server -n 20 --no-pager ;;
      4) break ;;
      *) echo -e "${RED}Opción inválida.${NC}" ;;
    esac
  done
}
