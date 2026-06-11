#!/usr/bin/env bash
# tarea1/tarea1_diagnostico.sh
# Script principal MODULAR para diagnóstico del entorno en Linux.
# Uso: chmod +x tarea1_diagnostico.sh && ./tarea1_diagnostico.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib/bash"
[[ ! -d "$LIB_DIR" ]] && LIB_DIR="/mnt/sysadmin/lib/bash"

source "${LIB_DIR}/comunes.sh"

mostrar_diagnostico
