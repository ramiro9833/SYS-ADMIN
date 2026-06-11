#!/usr/bin/env bash
# tarea4/tarea4_ssh_linux.sh
# Script principal modular para SSH en Linux.
# Carga las bibliotecas de funciones y presenta el menú.
# Uso: chmod +x tarea4_ssh_linux.sh && sudo ./tarea4_ssh_linux.sh

# ─── Cargar bibliotecas (source) ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib/bash"

# Ruta de respaldo: si no existe relativa, buscar en la carpeta compartida montada
if [[ ! -d "$LIB_DIR" ]]; then
  LIB_DIR="/mnt/sysadmin/lib/bash"
fi

if [[ ! -d "$LIB_DIR" ]]; then
  echo "[ERROR] No se encontró la carpeta de bibliotecas."
  echo "Ejecuta: sudo bash /mnt/sysadmin/tarea4/tarea4_ssh_linux.sh"
  exit 1
fi

source "${LIB_DIR}/comunes.sh"
source "${LIB_DIR}/ssh.sh"

# ─── Verificar root ───────────────────────────────────────────────────────────
verificar_root

# ─── Menú Principal ───────────────────────────────────────────────────────────
while true; do
  banner "GESTOR SSH - LINUX SERVER (BASH MODULAR)"
  echo -e "  ${BOLD}1)${NC} Instalación Idempotente (OpenSSH Server)"
  echo -e "  ${BOLD}2)${NC} Configurar Seguridad SSH"
  echo -e "  ${BOLD}3)${NC} Módulo de Monitoreo y Validación"
  echo -e "  ${BOLD}4)${NC} Salir"
  read -rp "Selecciona una opción (1-4): " opt

  case $opt in
    1) instalar_ssh ;;
    2) configurar_ssh ;;
    3) monitorear_ssh ;;
    4) echo -e "\n¡Hasta luego!"; exit 0 ;;
    *) echo -e "${RED}Opción inválida.${NC}" ;;
  esac
done
