#!/usr/bin/env bash
# tarea6/main_linux.sh
# Script principal MODULAR - Tarea 6: Despliegue Dinámico HTTP (Linux)
# Uso: chmod +x main_linux.sh && sudo ./main_linux.sh
# Operación: Exclusivamente por SSH desde cliente remoto.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib/bash"
[[ ! -d "$LIB_DIR" ]] && LIB_DIR="/mnt/sysadmin/lib/bash"

source "${LIB_DIR}/comunes.sh" || { echo "[ERROR] comunes.sh no encontrado."; exit 1; }
source "${LIB_DIR}/http.sh"    || { echo "[ERROR] http.sh no encontrado."; exit 1; }

verificar_root

while true; do
  menu_http_linux
  read -rp "Selecciona una opción (1-5): " opt

  case $opt in
    1)
      mapfile -t VERSIONES < <(consultar_versiones_apache)
      [[ ${#VERSIONES[@]} -eq 0 ]] && continue
      VERSION=$(seleccionar_version "Apache2" "${VERSIONES[@]}")
      PUERTO=$(leer_puerto 80)
      instalar_apache "$VERSION" "$PUERTO"
      ;;
    2)
      mapfile -t VERSIONES < <(consultar_versiones_nginx)
      [[ ${#VERSIONES[@]} -eq 0 ]] && continue
      VERSION=$(seleccionar_version "Nginx" "${VERSIONES[@]}")
      PUERTO=$(leer_puerto 80)
      instalar_nginx "$VERSION" "$PUERTO"
      ;;
    3)
      mapfile -t VERSIONES < <(consultar_versiones_tomcat)
      [[ ${#VERSIONES[@]} -eq 0 ]] && continue
      VERSION=$(seleccionar_version "Tomcat" "${VERSIONES[@]}")
      PUERTO=$(leer_puerto 8080)
      instalar_tomcat "$VERSION" "$PUERTO"
      ;;
    4)
      estado_servicios_http
      ;;
    5)
      echo -e "\n¡Hasta luego!"
      exit 0
      ;;
    *)
      echo -e "${RED}Opción inválida.${NC}"
      ;;
  esac
done
