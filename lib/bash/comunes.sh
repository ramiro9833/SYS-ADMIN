#!/usr/bin/env bash
# lib/bash/comunes.sh
# Biblioteca de funciones comunes reutilizables para todos los scripts del proyecto.
# Uso: source ./comunes.sh

# ─── Colores ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
RED='\033[0;31m';   CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# ─── Verificar privilegios root ──────────────────────────────────────────────
verificar_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[ERROR] Este script debe ejecutarse como root (sudo).${NC}"
    exit 1
  fi
}

# ─── Validar formato IPv4 ────────────────────────────────────────────────────
validar_ip() {
  local ip=$1
  if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS='.' read -r -a octetos <<< "$ip"
    for oct in "${octetos[@]}"; do
      [[ $oct -gt 255 ]] && return 1
    done
    return 0
  fi
  return 1
}

# ─── Leer IP con validación interactiva ──────────────────────────────────────
leer_ip() {
  local prompt="$1"
  local default="$2"
  local ip=""
  while true; do
    read -rp "${prompt} [${default}]: " ip
    [[ -z "$ip" ]] && ip="$default"
    if validar_ip "$ip"; then echo "$ip"; return 0; fi
    echo -e "${RED}[ERROR] IP inválida. Formato: X.X.X.X (0-255 por octeto)${NC}" >&2
  done
}

# ─── Instalar paquete de forma idempotente ───────────────────────────────────
instalar_paquete() {
  local paquete="$1"
  if dpkg -l | grep -q "^ii.*${paquete} "; then
    echo -e "${GREEN}[INFO] Paquete '${paquete}' ya instalado.${NC}"
    return 0
  fi
  echo -e "${YELLOW}[INFO] Instalando '${paquete}'...${NC}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq "$paquete"
  if dpkg -l | grep -q "^ii.*${paquete} "; then
    echo -e "${GREEN}[OK] '${paquete}' instalado correctamente.${NC}"
  else
    echo -e "${RED}[ERROR] Falló la instalación de '${paquete}'.${NC}"
    return 1
  fi
}

# ─── Verificar si un servicio está activo ────────────────────────────────────
verificar_servicio() {
  local servicio="$1"
  if systemctl is-active --quiet "$servicio"; then
    echo -e "${GREEN}[OK] Servicio '${servicio}' está activo.${NC}"
    return 0
  else
    echo -e "${RED}[WARN] Servicio '${servicio}' NO está activo.${NC}"
    return 1
  fi
}

# ─── Banner de sección ────────────────────────────────────────────────────────
banner() {
  local titulo="$1"
  echo -e "\n${BLUE}${BOLD}======================================================${NC}"
  echo -e "${BLUE}${BOLD}  ${titulo}${NC}"
  echo -e "${BLUE}${BOLD}======================================================${NC}"
}

# ─── Diagnóstico de sistema (Linux) ──────────────────────────────────────────
mostrar_diagnostico() {
  banner "DIAGNÓSTICO DE SISTEMA - LINUX"

  # 1. Hostname
  local host; host=$(hostname)
  echo -e "\n${BOLD}1. Nombre del Equipo (Hostname):${NC}"
  echo -e "  - Hostname: ${GREEN}${host}${NC}"

  # 2. Direcciones IP
  echo -e "\n${BOLD}2. Direcciones IP IPv4 Activas:${NC}"
  local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"))

  if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}No se detectaron interfaces de red activas.${NC}"
  else
    for iface in "${interfaces[@]}"; do
      local state; state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
      local ip; ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
      if [ -n "$ip" ]; then
        echo -e "  - Interfaz: ${GREEN}$iface${NC} | Estado: ${CYAN}$state${NC} | IP: ${YELLOW}$ip${NC}"
      else
        echo -e "  - Interfaz: ${GREEN}$iface${NC} | Estado: ${CYAN}$state${NC} | IP: ${YELLOW}Sin asignar${NC}"
      fi
    done
  fi

  # 3. Espacio en disco
  echo -e "\n${BOLD}3. Espacio en Disco (Sistema de Archivos Raíz /):${NC}"
  local disk_info=($(df -h / | awk 'NR==2 {print $2, $3, $4, $5}'))
  if [ ${#disk_info[@]} -eq 4 ]; then
    echo -e "  - Tamaño Total:  ${CYAN}${disk_info[0]}${NC}"
    echo -e "  - Espacio Usado:  ${YELLOW}${disk_info[1]}${NC} (${disk_info[3]})"
    echo -e "  - Disponible:     ${GREEN}${disk_info[2]}${NC}"
  else
    df -h /
  fi

  # 4. Diagnóstico Adicional
  echo -e "\n${BOLD}4. Información de Diagnóstico Adicional:${NC}"
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "  - Sistema Operativo: ${GREEN}$PRETTY_NAME${NC}"
  else
    echo -e "  - Sistema Operativo: Linux genérico"
  fi
  echo -e "  - Versión del Kernel: $(uname -r)"

  local ram_total; ram_total=$(free -h | awk '/Mem:/ {print $2}')
  local ram_used;  ram_used=$(free -h | awk '/Mem:/ {print $3}')
  local ram_free;  ram_free=$(free -h | awk '/Mem:/ {print $4}')
  echo -e "  - Memoria RAM:       Total: ${CYAN}$ram_total${NC} | Usada: ${YELLOW}$ram_used${NC} | Libre: ${GREEN}$ram_free${NC}"
  echo -e "  - Tiempo de Actividad: $(uptime -p)"
  echo -e "\n${BLUE}${BOLD}======================================================${NC}"
}
