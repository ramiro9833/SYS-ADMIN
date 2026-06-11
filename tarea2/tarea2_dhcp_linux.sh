#!/usr/bin/env bash

# Script: tarea2_dhcp_linux.sh
# Descripción: Automatización y Gestión de Servidor DHCP en Lubuntu Server (isc-dhcp-server).
#               Instalación idempotente, configuración guiada y monitoreo.
# Autor: Antigravity AI
# Uso: chmod +x tarea2_dhcp_linux.sh && sudo ./tarea2_dhcp_linux.sh

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0;37m'
BOLD='\033[1m'

# Comprobar privilegios de root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}${BOLD}[ERROR] Este script debe ejecutarse como root (con sudo).${NC}"
  exit 1
fi

# Función para validar direcciones IP
validar_ip() {
  local ip=$1
  local stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    # Comprobar que cada octeto está entre 0 y 255
    if [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]; then
      stat=0
    fi
  fi
  return $stat
}

# 1. Instalación Idempotente
instalar_dhcp() {
  echo -e "\n${BLUE}${BOLD}[1/4] Verificando estado del servicio DHCP...${NC}"
  if dpkg -l | grep -q isc-dhcp-server; then
    echo -e "${GREEN}[INFO] El paquete 'isc-dhcp-server' ya está instalado.${NC}"
  else
    echo -e "${YELLOW}[INFO] 'isc-dhcp-server' no está instalado. Iniciando instalación desatendida...${NC}"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}${BOLD}[OK] Instalación completada con éxito.${NC}"
    else
      echo -e "${RED}${BOLD}[ERROR] Falló la instalación de isc-dhcp-server.${NC}"
      exit 1
    fi
  fi
}

# 2. Orquestación de Configuración Dinámica
configurar_dhcp() {
  echo -e "\n${BLUE}${BOLD}[2/4] Configuración del Servidor DHCP${NC}"
  
  # Detectar interfaces disponibles para sugerencia
  interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"))
  echo -e "Interfaces de red detectadas:"
  for iface in "${interfaces[@]}"; do
    ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo -e "  - ${GREEN}$iface${NC} (${ip:-Sin IP})"
  done
  
  # Solicitar Interfaz DHCP
  while true; do
    read -p "Ingresa el nombre de la interfaz para escuchar peticiones DHCP (ej: enp0s8): " dhcp_iface
    if [[ " ${interfaces[*]} " =~ " ${dhcp_iface} " ]]; then
      break
    else
      echo -e "${RED}La interfaz '$dhcp_iface' no existe. Selecciona una de la lista.${NC}"
    fi
  done

  # Solicitar Nombre del Ámbito (Scope)
  read -p "Nombre descriptivo del Ámbito/Red [Red_Interna]: " scope_name
  scope_name=${scope_name:-"Red_Interna"}

  # Solicitar Subred
  while true; do
    read -p "Dirección de Subred [192.168.100.0]: " subnet
    subnet=${subnet:-"192.168.100.0"}
    if validar_ip "$subnet"; then break; else echo -e "${RED}IP no válida.${NC}"; fi
  done

  # Solicitar Máscara
  while true; do
    read -p "Máscara de Subred [255.255.255.0]: " netmask
    netmask=${netmask:-"255.255.255.0"}
    if validar_ip "$netmask"; then break; else echo -e "${RED}IP no válida.${NC}"; fi
  done

  # Rango de IPs
  while true; do
    read -p "Rango de IP - Inicial [192.168.100.50]: " range_start
    range_start=${range_start:-"192.168.100.50"}
    if validar_ip "$range_start"; then break; else echo -e "${RED}IP no válida.${NC}"; fi
  done

  while true; do
    read -p "Rango de IP - Final [192.168.100.150]: " range_end
    range_end=${range_end:-"192.168.100.150"}
    if validar_ip "$range_end"; then 
      # Comprobar que no es menor que el inicial
      break
    else 
      echo -e "${RED}IP no válida.${NC}"
    fi
  done

  # Tiempo de Concesión (Lease Time)
  while true; do
    read -p "Tiempo de concesión por defecto (en segundos) [600]: " lease_default
    lease_default=${lease_default:-600}
    if [[ $lease_default =~ ^[0-9]+$ ]]; then break; else echo -e "${RED}Debe ser un número entero.${NC}"; fi
  done

  while true; do
    read -p "Tiempo de concesión máximo (en segundos) [7200]: " lease_max
    lease_max=${lease_max:-7200}
    if [[ $lease_max =~ ^[0-9]+$ ]] && [ "$lease_max" -ge "$lease_default" ]; then break; else echo -e "${RED}Debe ser un número mayor o igual al valor por defecto.${NC}"; fi
  done

  # Gateway (Router)
  while true; do
    read -p "Puerta de enlace (Router) [192.168.100.1]: " gateway
    gateway=${gateway:-"192.168.100.1"}
    if validar_ip "$gateway"; then break; else echo -e "${RED}IP no válida.${NC}"; fi
  done

  # DNS
  while true; do
    read -p "Servidor DNS (IP de este u otro servidor) [192.168.100.10]: " dns_server
    dns_server=${dns_server:-"192.168.100.10"}
    if validar_ip "$dns_server"; then break; else echo -e "${RED}IP no válida.${NC}"; fi
  done

  # 3. Aplicar y Validar Configuración
  echo -e "\n${BLUE}${BOLD}[3/4] Escribiendo archivos de configuración...${NC}"
  
  # Respaldo de archivos
  cp /etc/default/isc-dhcp-server /etc/default/isc-dhcp-server.bak 2>/dev/null || true
  cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak 2>/dev/null || true

  # Configurar interfaz de escucha
  # Reemplazar la línea de INTERFACESv4
  sed -i "s/INTERFACESv4=\"[^\"]*\"/INTERFACESv4=\"$dhcp_iface\"/g" /etc/default/isc-dhcp-server
  if ! grep -q "INTERFACESv4=" /etc/default/isc-dhcp-server; then
    echo "INTERFACESv4=\"$dhcp_iface\"" >> /etc/default/isc-dhcp-server
  fi

  # Escribir dhcpd.conf
  cat <<EOF > /etc/dhcp/dhcpd.conf
# dhcpd.conf generado automáticamente por script de automatización
# Ámbito: $scope_name

option domain-name "sistemas.local";
option domain-name-servers $dns_server;

default-lease-time $lease_default;
max-lease-time $lease_max;

# Indicar que este servidor es el oficial para la red local
authoritative;

# Definición de la subred
subnet $subnet netmask $netmask {
  range $range_start $range_end;
  option routers $gateway;
  option subnet-mask $netmask;
  option broadcast-address ${subnet%.*}.255;
}
EOF

  # Validación sintáctica con dhcpd -t
  echo -e "Validando sintaxis de configuración con 'dhcpd -t'..."
  dhcpd -t -cf /etc/dhcp/dhcpd.conf > /tmp/dhcp_check.log 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}${BOLD}[OK] Sintaxis de configuración válida.${NC}"
    
    # Reiniciar y habilitar servicio
    echo -e "Reiniciando el servicio DHCP..."
    systemctl restart isc-dhcp-server
    systemctl enable isc-dhcp-server > /dev/null 2>&1
    
    if systemctl is-active --quiet isc-dhcp-server; then
      echo -e "${GREEN}${BOLD}[OK] El servidor DHCP se ha iniciado correctamente y está en ejecución.${NC}"
    else
      echo -e "${RED}${BOLD}[ERROR] El servicio no pudo iniciar. Revisa los logs.${NC}"
      tail -n 10 /tmp/dhcp_check.log
      systemctl status isc-dhcp-server --no-pager
    fi
  else
    echo -e "${RED}${BOLD}[ERROR] Error en la sintaxis de dhcpd.conf. Restaurando archivos de respaldo...${NC}"
    cat /tmp/dhcp_check.log
    mv /etc/dhcp/dhcpd.conf.bak /etc/dhcp/dhcpd.conf 2>/dev/null
    mv /etc/default/isc-dhcp-server.bak /etc/default/isc-dhcp-server 2>/dev/null
    exit 1
  fi
}

# 4. Módulo de Monitoreo y Validación
monitorear_dhcp() {
  while true; do
    echo -e "\n${BLUE}${BOLD}======================================================${NC}"
    echo -e "${BLUE}${BOLD}      MÓDULO DE MONITOREO Y VALIDACIÓN DHCP          ${NC}"
    echo -e "${BLUE}${BOLD}======================================================${NC}"
    echo -e "  ${BOLD}1)${NC} Ver estado actual del servicio en tiempo real"
    echo -e "  ${BOLD}2)${NC} Listar concesiones (leases) activas"
    echo -e "  ${BOLD}3)${NC} Ver logs del DHCP en tiempo real (últimas 20 líneas)"
    echo -e "  ${BOLD}4)${NC} Volver al menú principal / Salir"
    read -p "Selecciona una opción (1-4): " mon_opt
    
    case $mon_opt in
      1)
        echo -e "\n${BOLD}Estado del servicio isc-dhcp-server:${NC}"
        systemctl status isc-dhcp-server --no-pager
        ;;
      2)
        local leases_file="/var/lib/dhcp/dhcpd.leases"
        if [ ! -f "$leases_file" ] || [ ! -s "$leases_file" ]; then
          echo -e "\n${YELLOW}No se encontraron concesiones (leases) DHCP en el archivo o está vacío.${NC}"
          continue
        fi
        
        echo -e "\n${BOLD}Concesiones DHCP Activas en el Servidor:${NC}"
        echo -e "--------------------------------------------------------------------------------------------------"
        printf "${BOLD}%-15s | %-17s | %-19s | %-25s${NC}\n" "Dirección IP" "Dirección MAC" "Vencimiento (UTC)" "Hostname Cliente"
        echo -e "--------------------------------------------------------------------------------------------------"
        
        awk '
          /^lease /           { ip=$2; state=""; mac="N/D"; ends="N/D"; host="N/D" }
          /^  binding state / { state=$3; sub(";","",state) }
          /^  hardware /      { mac=$3; sub(";","",mac) }
          /^  ends /          { ends=$3" "$4; sub(";","",ends) }
          /^  client-hostname/{ host=$2; gsub(/[";]/,"",host) }
          /^}/ {
            if (state == "active")
              printf "%-15s | %-17s | %-19s | %-25s\n", ip, mac, ends, host
          }
        ' "$leases_file"
        echo -e "--------------------------------------------------------------------------------------------------"
        ;;
      3)
        echo -e "\n${BOLD}Últimos registros en logs (journalctl):${NC}"
        journalctl -u isc-dhcp-server -n 20 --no-pager
        ;;
      4)
        break
        ;;
      *)
        echo -e "${RED}Opción inválida.${NC}"
        ;;
    esac
  done
}

# Menú Principal
main_menu() {
  while true; do
    echo -e "\n${BLUE}${BOLD}======================================================${NC}"
    echo -e "${BLUE}${BOLD}       GESTOR DE SERVIDOR DHCP - LINUX (BASH)         ${NC}"
    echo -e "${BLUE}${BOLD}======================================================${NC}"
    echo -e "  ${BOLD}1)${NC} Instalación Inicial Idempotente (apt-get)"
    echo -e "  ${BOLD}2)${NC} Configurar Servidor e Inicializar (Interactivo)"
    echo -e "  ${BOLD}3)${NC} Módulo de Monitoreo y Validación"
    echo -e "  ${BOLD}4)${NC} Salir"
    read -p "Selecciona una opción (1-4): " main_opt
    
    case $main_opt in
      1)
        instalar_dhcp
        ;;
      2)
        # Asegurar que esté instalado
        if ! dpkg -l | grep -q isc-dhcp-server; then
          instalar_dhcp
        fi
        configurar_dhcp
        ;;
      3)
        monitorear_dhcp
        ;;
      4)
        echo -e "\n¡Hasta luego!"
        exit 0
        ;;
      *)
        echo -e "${RED}Opción inválida.${NC}"
        ;;
    esac
  done
}

# Ejecutar el menú principal
main_menu
