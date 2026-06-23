#!/usr/bin/env bash
# tarea11/tarea11.sh
# Orquestador Tarea 11: Microservicios, HA y Tuneles SSH
# Uso: chmod +x tarea11.sh && sudo ./tarea11.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA11_DIR="$SCRIPT_DIR"
export TAREA11_DIR

if [ -d "$SCRIPT_DIR/../lib/bash" ]; then
    LIB_DIR="$SCRIPT_DIR/../lib/bash"
elif [ -d "/mnt/sysadmin/lib/bash" ]; then
    LIB_DIR="/mnt/sysadmin/lib/bash"
else
    echo "[ERROR] No se encontro lib/bash"
    exit 1
fi

source "${LIB_DIR}/comunes.sh"
source "${LIB_DIR}/docker.sh"
source "${LIB_DIR}/orquestacion.sh"

verificar_root

mostrar_banner() {
    clear
    echo "=================================================================="
    echo "  TAREA 11 - ORQUESTACION MICROSERVICIOS, HA Y TUNELES SSH        "
    echo "=================================================================="
}

while true; do
    mostrar_banner
    echo "  1) Verificar Docker"
    echo "  2) Desplegar Stack Completo (build + up)"
    echo "  3) Detener Stack (conserva volumenes)"
    echo "  4) Mostrar Estado (redes, volumenes, puertos)"
    echo "  5) Configurar Firewall Host (bloquear BD/pgAdmin)"
    echo "  6) Guia / Tunel SSH hacia pgAdmin"
    echo "  7) Ejecutar Protocolo de Pruebas (11.1 - 11.4)"
    echo "  8) Salir"
    echo "=================================================================="
    read -rp "Selecciona una opcion (1-8): " opt

    case "$opt" in
        1) verificar_docker ;;
        2) desplegar_stack_tarea11 ;;
        3) detener_stack_tarea11 ;;
        4) mostrar_estado_tarea11 ;;
        5) configurar_firewall_tarea11 ;;
        6) mostrar_tunel_ssh_tarea11 ;;
        7) ejecutar_pruebas_tarea11 ;;
        8) echo "Saliendo..."; exit 0 ;;
        *) echo -e "${RED}Opcion invalida.${NC}" ;;
    esac

    if [ "$opt" != "8" ]; then
        read -rp "Presione Enter para continuar..." _
    fi
done
