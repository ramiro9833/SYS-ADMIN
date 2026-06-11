#!/usr/bin/env bash

# Script: tarea1_diagnostico.sh
# Descripción: Script de diagnóstico de entorno base (Tarea 1).
#               Muestra el nombre del equipo, IPs actuales y espacio en disco.
# Autor: Antigravity AI
# Uso: chmod +x tarea1_diagnostico.sh && ./tarea1_diagnostico.sh

# Colores para salida agradable
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0;37m' # Sin color
BOLD='\033[1m'

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}          DIAGNÓSTICO DE SISTEMA - LINUX             ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}"

# 1. Nombre del equipo (Hostname)
HOSTNAME=$(hostname)
echo -e "\n${BOLD}1. Nombre del Equipo (Hostname):${NC}"
echo -e "  - Hostname: ${GREEN}${HOSTNAME}${NC}"

# 2. Direcciones IP actuales
echo -e "\n${BOLD}2. Direcciones IP IPv4 Activas:${NC}"
# Obtener interfaces e IPs correspondientes excluyendo loopback (lo)
interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"))

if [ ${#interfaces[@]} -eq 0 ]; then
  echo -e "  ${YELLOW}No se detectaron interfaces de red activas.${NC}"
else
  for iface in "${interfaces[@]}"; do
    # Obtener el estado operativo de la interfaz
    state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
    # Obtener IP de la interfaz
    ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    if [ -n "$ip" ]; then
      echo -e "  - Interfaz: ${GREEN}$iface${NC} | Estado: ${CYAN}$state${NC} | IP: ${YELLOW}$ip${NC}"
    else
      echo -e "  - Interfaz: ${GREEN}$iface${NC} | Estado: ${CYAN}$state${NC} | IP: ${YELLOW}Sin asignar${NC}"
    fi
  done
fi

# 3. Espacio en disco
echo -e "\n${BOLD}3. Espacio en Disco (Sistema de Archivos Raíz /):${NC}"
DISK_INFO=($(df -h / | awk 'NR==2 {print $2, $3, $4, $5}'))
if [ ${#DISK_INFO[@]} -eq 4 ]; then
  echo -e "  - Tamaño Total:  ${CYAN}${DISK_INFO[0]}${NC}"
  echo -e "  - Espacio Usado:  ${YELLOW}${DISK_INFO[1]}${NC} (${DISK_INFO[3]})"
  echo -e "  - Disponible:     ${GREEN}${DISK_INFO[2]}${NC}"
else
  df -h /
fi

# 4. Información adicional de diagnóstico
echo -e "\n${BOLD}4. Información de Diagnóstico Adicional:${NC}"
# Versión del Sistema Operativo
if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo -e "  - Sistema Operativo: ${GREEN}$PRETTY_NAME${NC}"
else
  echo -e "  - Sistema Operativo: Linux genérico"
fi

# Versión del kernel
echo -e "  - Versión del Kernel: $(uname -r)"

# Memoria RAM
RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
RAM_USED=$(free -h | awk '/Mem:/ {print $3}')
RAM_FREE=$(free -h | awk '/Mem:/ {print $4}')
echo -e "  - Memoria RAM:       Total: ${CYAN}$RAM_TOTAL${NC} | Usada: ${YELLOW}$RAM_USED${NC} | Libre: ${GREEN}$RAM_FREE${NC}"

# Tiempo de actividad (Uptime)
echo -e "  - Tiempo de Actividad: $(uptime -p)"

echo -e "\n${BLUE}${BOLD}======================================================${NC}"
