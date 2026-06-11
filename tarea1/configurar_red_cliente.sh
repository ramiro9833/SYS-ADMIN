#!/usr/bin/env bash
# tarea1/configurar_red_cliente.sh
# Script principal MODULAR para configuración de red en el cliente Linux Mint.
# Uso: chmod +x configurar_red_cliente.sh && sudo ./configurar_red_cliente.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib/bash"
[[ ! -d "$LIB_DIR" ]] && LIB_DIR="/mnt/sysadmin/lib/bash"

source "${LIB_DIR}/comunes.sh"
source "${LIB_DIR}/red.sh"

verificar_root
configurar_red_cliente_linux
