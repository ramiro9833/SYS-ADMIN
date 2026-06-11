#!/usr/bin/env bash
# tarea1/configurar_red_linux_server.sh
# Script principal MODULAR para configuración de red en Lubuntu Server.
# Uso: chmod +x configurar_red_linux_server.sh && sudo ./configurar_red_linux_server.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib/bash"
[[ ! -d "$LIB_DIR" ]] && LIB_DIR="/mnt/sysadmin/lib/bash"

source "${LIB_DIR}/comunes.sh"
source "${LIB_DIR}/red.sh"

verificar_root
configurar_red_servidor_linux
