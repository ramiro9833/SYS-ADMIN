#!/usr/bin/env bash
# tarea10/tarea10.sh
# Orquestador Tarea 10: Virtualizacion, Persistencia y Seguridad en Contenedores
# Uso: chmod +x tarea10.sh && sudo ./tarea10.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA10_DIR="$SCRIPT_DIR"
export TAREA10_DIR

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

verificar_root

mostrar_banner() {
    clear
    echo "=================================================================="
    echo "  TAREA 10 - VIRTUALIZACION, PERSISTENCIA Y SEGURIDAD (DOCKER)   "
    echo "=================================================================="
}

while true; do
    mostrar_banner
    echo "  1) Verificar Docker"
    echo "  2) Desplegar Stack Completo (build + up)"
    echo "  3) Detener Stack"
    echo "  4) Mostrar Estado (red, volumenes, servicios)"
    echo "  5) Respaldo Manual de Base de Datos"
    echo "  6) Ejecutar Protocolo de Pruebas (10.1 - 10.4)"
    echo "  7) Mostrar Limites de Recursos (docker stats)"
    echo "  8) Salir"
    echo "=================================================================="
    read -rp "Selecciona una opcion (1-8): " opt

    case "$opt" in
        1) verificar_docker ;;
        2) desplegar_stack_tarea10 ;;
        3) detener_stack_tarea10 ;;
        4) mostrar_estado_stack ;;
        5) respaldo_manual_bd ;;
        6) ejecutar_pruebas_tarea10 ;;
        7) mostrar_stats_contenedores ;;
        8) echo "Saliendo..."; exit 0 ;;
        *) echo -e "${RED}Opcion invalida.${NC}" ;;
    esac

    if [ "$opt" != "8" ]; then
        read -rp "Presione Enter para continuar..." _
    fi
done
