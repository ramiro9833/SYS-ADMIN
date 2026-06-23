#!/usr/bin/env bash
# tarea12/tarea12.sh
# Orquestador Tarea 12: Correo privado + Roundcube Webmail
# Uso: chmod +x tarea12.sh && sudo ./tarea12.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA12_DIR="$SCRIPT_DIR"
export TAREA12_DIR

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
source "${LIB_DIR}/correo.sh"

verificar_root

mostrar_banner() {
    clear
    echo "=================================================================="
    echo "  TAREA 12 - CORREO PRIVADO, SEGURIDAD Y WEBMAIL (ROUNDCUBE)      "
    echo "=================================================================="
}

while true; do
    mostrar_banner
    echo "  1) Verificar Docker"
    echo "  2) Generar Certificados TLS"
    echo "  3) Desplegar Stack Completo (mail + webmail)"
    echo "  4) Crear Cuentas de Correo"
    echo "  5) Mostrar Estado del Stack"
    echo "  6) Mostrar Clave DKIM (para DNS)"
    echo "  7) Ver Logs de Auditoria (/var/log/mail)"
    echo "  8) Respaldo Manual de Buzones"
    echo "  9) Restaurar Respaldo"
    echo " 10) Ejecutar Protocolo de Pruebas (12.1 - 12.7)"
    echo " 11) Detener Stack"
    echo " 12) Salir"
    echo "=================================================================="
    read -rp "Selecciona una opcion (1-12): " opt

    case "$opt" in
        1)  verificar_docker ;;
        2)  generar_certificados_tarea12 ;;
        3)  desplegar_stack_tarea12 ;;
        4)  crear_cuentas_tarea12 ;;
        5)  mostrar_estado_tarea12 ;;
        6)  mostrar_dkim_tarea12 ;;
        7)  ver_logs_correo ;;
        8)  respaldo_manual_tarea12 ;;
        9)  restaurar_respaldo_tarea12 ;;
        10) ejecutar_pruebas_tarea12 ;;
        11) detener_stack_tarea12 ;;
        12) echo "Saliendo..."; exit 0 ;;
        *)  echo -e "${RED}Opcion invalida.${NC}" ;;
    esac

    if [ "$opt" != "12" ]; then
        read -rp "Presione Enter para continuar..." _
    fi
done
