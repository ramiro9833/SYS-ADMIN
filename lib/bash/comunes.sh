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
