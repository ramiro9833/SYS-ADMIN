#!/usr/bin/env bash

# Script: configurar_red_cliente.sh
# Descripción: Configura la red interna en el cliente Linux Mint (estática o DHCP) usando NetworkManager.
# Autor: Antigravity AI
# Uso: chmod +x configurar_red_cliente.sh && sudo ./configurar_red_cliente.sh

# Colores para la interfaz
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0;37m' # Sin color
BOLD='\033[1m'

# Comprobar privilegios de root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}${BOLD}[ERROR] Este script debe ejecutarse como root (con sudo).${NC}"
  exit 1
fi

# Comprobar que nmcli está disponible
if ! command -v nmcli &> /dev/null; then
  echo -e "${RED}${BOLD}[ERROR] NetworkManager (nmcli) no está instalado o no se encuentra en el sistema.${NC}"
  echo -e "${YELLOW}Este script está diseñado para sistemas con entorno de escritorio como Linux Mint que usan NetworkManager.${NC}"
  exit 1
fi

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}   CONFIGURACIÓN DE RED - CLIENTE LINUX MINT (CLI)   ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}"

# 1. Detectar interfaces de red disponibles
echo -e "\n${BOLD}Detectando interfaces de red...${NC}"
interfaces=($(nmcli -t -f DEVICE device status | grep -v "lo"))

if [ ${#interfaces[@]} -eq 0 ]; then
  echo -e "${RED}[ERROR] No se detectaron interfaces de red físicas.${NC}"
  exit 1
fi

echo -e "Interfaces encontradas:"
index=1
for iface in "${interfaces[@]}"; do
  # Obtener el tipo de dispositivo y el estado
  type=$(nmcli -t -f TYPE device show "$iface" | grep "GENERAL.TYPE" | cut -d':' -f2)
  state=$(nmcli -t -f STATE device show "$iface" | grep "GENERAL.STATE" | cut -d':' -f2)
  ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  
  echo -e "  ${BOLD}$index)${NC} ${GREEN}$iface${NC} | Tipo: $type | Estado: $state | IP actual: ${YELLOW}${ip:-Ninguna}${NC}"
  ((index++))
done

# Seleccionar la interfaz para red_sistemas
while true; do
  read -p "Selecciona el número de la interfaz para la Red Interna (red_sistemas): " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$index" ]; then
    INTERFACE="${interfaces[$((choice-1))]}"
    break
  else
    echo -e "${RED}Opción inválida. Inténtalo de nuevo.${NC}"
  fi
done

echo -e "\nInterfaz seleccionada: ${GREEN}${INTERFACE}${NC}"

# Nombre del perfil de conexión en NetworkManager
CONN_NAME="Red_Sistemas"

# Crear la conexión si no existe
if ! nmcli connection show "$CONN_NAME" &> /dev/null; then
  echo -e "Creando perfil de conexión '${CONN_NAME}' para el dispositivo ${INTERFACE}..."
  nmcli connection add type ethernet con-name "$CONN_NAME" ifname "$INTERFACE" > /dev/null
fi

# 2. Menú de opciones de configuración
echo -e "\n${BOLD}¿Cómo deseas configurar la interfaz ${INTERFACE}?${NC}"
echo -e "  ${BOLD}1)${NC} IP Estática (Para Tarea 1 - Prueba de conectividad)"
echo -e "  ${BOLD}2)${NC} DHCP Cliente (Para Tarea 2 - Obtención dinámica de IP)"
echo -e "  ${BOLD}3)${NC} Cancelar"

while true; do
  read -p "Opción (1-3): " opt
  case $opt in
    1)
      # Configuración Estática
      DEFAULT_IP="192.168.100.30"
      DEFAULT_MASK="24"
      DEFAULT_GW="192.168.100.1"
      DEFAULT_DNS="192.168.100.10" # IP propuesta para el Servidor Linux (DNS)

      echo -e "\n${YELLOW}Configuración de IP Estática (Presione Enter para usar valores por defecto):${NC}"
      
      # Validar IP address
      while true; do
        read -p "Dirección IP [$DEFAULT_IP]: " ip_addr
        ip_addr=${ip_addr:-$DEFAULT_IP}
        if [[ $ip_addr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
          break
        else
          echo -e "${RED}Formato de IP inválido.${NC}"
        fi
      done

      # Validar máscara CIDR
      while true; do
        read -p "Máscara de red en formato CIDR (ej: 24 para 255.255.255.0) [$DEFAULT_MASK]: " cidr
        cidr=${cidr:-$DEFAULT_MASK}
        if [[ $cidr =~ ^[0-9]+$ ]] && [ "$cidr" -ge 0 ] && [ "$cidr" -le 32 ]; then
          break
        else
          echo -e "${RED}Máscara CIDR inválida (debe ser entre 0 y 32).${NC}"
        fi
      done

      # Validar Gateway
      while true; do
        read -p "Puerta de enlace [$DEFAULT_GW] (deja vacío para omitir): " gateway
        gateway=${gateway:-$DEFAULT_GW}
        if [ -z "$gateway" ] || [[ $gateway =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
          break
        else
          echo -e "${RED}Formato de IP de Gateway inválido.${NC}"
        fi
      done

      # Validar DNS
      while true; do
        read -p "Servidor DNS [$DEFAULT_DNS] (deja vacío para omitir): " dns
        dns=${dns:-$DEFAULT_DNS}
        if [ -z "$dns" ] || [[ $dns =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
          break
        else
          echo -e "${RED}Formato de IP de DNS inválido.${NC}"
        fi
      done

      echo -e "\nAplicando configuración estática..."
      
      # Modificar perfil de NetworkManager
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

      # Reactivar conexión
      echo -e "Reiniciando conexión..."
      nmcli connection down "$CONN_NAME" > /dev/null 2>&1
      if nmcli connection up "$CONN_NAME"; then
        echo -e "${GREEN}${BOLD}[OK] Red configurada correctamente con IP ${ip_addr}/${cidr}.${NC}"
      else
        echo -e "${RED}${BOLD}[ERROR] No se pudo activar la interfaz con los valores estáticos.${NC}"
      fi
      break
      ;;

    2)
      # Configuración DHCP
      echo -e "\nAplicando configuración DHCP en ${CONN_NAME}..."
      
      # Modificar perfil para DHCP auto-configuración
      nmcli connection modify "$CONN_NAME" \
        connection.interface-name "$INTERFACE" \
        ipv4.method auto \
        ipv4.addresses "" \
        ipv4.gateway "" \
        ipv4.dns "" \
        ipv6.method ignore

      # Reactivar conexión
      echo -e "Reiniciando conexión para solicitar IP por DHCP..."
      nmcli connection down "$CONN_NAME" > /dev/null 2>&1
      if nmcli connection up "$CONN_NAME"; then
        echo -e "${GREEN}${BOLD}[OK] Red configurada en modo DHCP.${NC}"
        echo -e "Esperando obtención de dirección IP..."
        sleep 3
        ip_obtained=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        if [ -n "$ip_obtained" ]; then
          echo -e "${GREEN}IP asignada por DHCP: ${BOLD}$ip_obtained${NC}"
        else
          echo -e "${YELLOW}[ADVERTENCIA] La interfaz está en DHCP pero no se ha obtenido una IP. Asegúrate de que el servidor DHCP esté activo en la red interna.${NC}"
        fi
      else
        echo -e "${RED}${BOLD}[ERROR] No se pudo activar la conexión DHCP.${NC}"
      fi
      break
      ;;

    3)
      echo -e "\nOperación cancelada."
      exit 0
      ;;
    *)
      echo -e "${RED}Opción inválida. Selecciona 1, 2 o 3.${NC}"
      ;;
  esac
done

echo -e "\n${BLUE}${BOLD}======================================================${NC}"
