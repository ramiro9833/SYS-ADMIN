#!/usr/bin/env bash

# Script: configurar_red_linux_server.sh
# Descripción: Configura la red interna en Lubuntu Server (Estática) usando Netplan.
# Autor: Antigravity AI
# Uso: chmod +x configurar_red_linux_server.sh && sudo ./configurar_red_linux_server.sh

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

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}  CONFIGURACIÓN DE RED - LUBUNTU SERVER (NETPLAN)    ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}"

# 1. Detectar interfaces de red físicas
echo -e "\n${BOLD}Detectando interfaces de red...${NC}"
interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"))

if [ ${#interfaces[@]} -eq 0 ]; then
  echo -e "${RED}[ERROR] No se encontraron interfaces de red.${NC}"
  exit 1
fi

# Intentar clasificar interfaces
echo -e "Interfaces encontradas:"
index=1
for iface in "${interfaces[@]}"; do
  ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -v "127.0.0.1" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
  echo -e "  ${BOLD}$index)${NC} ${GREEN}$iface${NC} | Estado: $state | IP actual: ${YELLOW}${ip:-Ninguna}${NC}"
  ((index++))
done

# Seleccionar la interfaz de red interna
while true; do
  read -p "Selecciona el número de la interfaz para la Red Interna (red_sistemas) [habitualmente la segunda]: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$index" ]; then
    INT_IFACE="${interfaces[$((choice-1))]}"
    break
  else
    echo -e "${RED}Opción inválida. Inténtalo de nuevo.${NC}"
  fi
done

# Seleccionar la interfaz de NAT (Internet)
while true; do
  read -p "Selecciona el número de la interfaz para NAT (Internet) [habitualmente la primera]: " nat_choice
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

# 2. Configurar valores de IP estática para la red interna
DEFAULT_IP="192.168.100.10"
DEFAULT_MASK="24"

echo -e "\n${YELLOW}Configuración de IP Estática para la red interna:${NC}"
while true; do
  read -p "Dirección IP [$DEFAULT_IP]: " ip_addr
  ip_addr=${ip_addr:-$DEFAULT_IP}
  if [[ $ip_addr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    break
  else
    echo -e "${RED}Formato de IP inválido.${NC}"
  fi
done

while true; do
  read -p "Máscara en formato CIDR (ej: 24 para 255.255.255.0) [$DEFAULT_MASK]: " cidr
  cidr=${cidr:-$DEFAULT_MASK}
  if [[ $cidr =~ ^[0-9]+$ ]] && [ "$cidr" -ge 0 ] && [ "$cidr" -le 32 ]; then
    break
  else
    echo -e "${RED}Máscara CIDR inválida (debe ser entre 0 y 32).${NC}"
  fi
done

read -p "¿Confirmas escribir estos datos en la configuración de Netplan? (s/n): " confirm
if [[ ! "$confirm" =~ ^[sS]$ && ! "$confirm" =~ ^[yY]$ ]]; then
  echo -e "${RED}Operación cancelada.${NC}"
  exit 0
fi

# 3. Copia de seguridad de la configuración actual de Netplan
NETPLAN_DIR="/etc/netplan"
BACKUP_DIR="/etc/netplan/backup_$(date +%F_%T)"

echo -e "\nCreando copia de seguridad de la configuración de Netplan en ${BACKUP_DIR}..."
mkdir -p "$BACKUP_DIR"
cp "$NETPLAN_DIR"/*.yaml "$BACKUP_DIR/" 2>/dev/null || true

# Eliminar archivos yaml existentes para evitar conflictos de nombres
echo -e "Generando nuevo archivo de configuración en /etc/netplan/99-sysadmin-config.yaml..."
rm -f "$NETPLAN_DIR"/*.yaml

# Escribir la nueva configuración de Netplan
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

# Ajustar permisos del archivo yaml
chmod 600 "$NETPLAN_DIR/99-sysadmin-config.yaml"

# Aplicar la configuración
echo -e "Aplicando configuración con 'netplan apply'..."
if netplan apply; then
  echo -e "${GREEN}${BOLD}[OK] Configuración aplicada exitosamente.${NC}"
  echo -e "Estado de la interfaz interna:"
  ip addr show "$INT_IFACE"
else
  echo -e "${RED}${BOLD}[ERROR] Hubo un error al aplicar la configuración de Netplan.${NC}"
  echo -e "Restaurando copia de seguridad..."
  cp "$BACKUP_DIR"/*.yaml "$NETPLAN_DIR/"
  netplan apply
  exit 1
fi

echo -e "\n${BLUE}${BOLD}======================================================${NC}"
