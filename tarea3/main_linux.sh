#!/usr/bin/env bash
# tarea3/main_linux.sh
# Script principal MODULAR para DNS en Linux.
# Uso: chmod +x main_linux.sh && sudo ./main_linux.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib/bash"
[[ ! -d "$LIB_DIR" ]] && LIB_DIR="/mnt/sysadmin/lib/bash"

source "${LIB_DIR}/comunes.sh"
source "${LIB_DIR}/red.sh"
source "${LIB_DIR}/dns.sh"

verificar_root
verificar_ip_estatica

while true; do
  banner "GESTOR DNS - LINUX SERVER (BASH MODULAR)"
  echo -e "  ${BOLD}1)${NC} Instalación Idempotente (BIND9)"
  echo -e "  ${BOLD}2)${NC} Configurar Zona DNS (reprobados.com)"
  echo -e "  ${BOLD}3)${NC} Módulo de Monitoreo y Validación"
  echo -e "  ${BOLD}4)${NC} Salir"
  read -rp "Selecciona una opción (1-4): " opt

  case $opt in
    1) instalar_bind9 ;;
    2) if ! dpkg -l | grep -q "^ii.*bind9 "; then instalar_bind9; fi; configurar_dns ;;
    3) monitorear_dns ;;
    4) echo -e "\n¡Hasta luego!"; exit 0 ;;
    *) echo -e "${RED}Opción inválida.${NC}" ;;
  esac
done
