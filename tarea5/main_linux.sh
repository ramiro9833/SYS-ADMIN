#!/usr/bin/env bash
# tarea5/main_linux.sh
# Script principal MODULAR para Tarea 5 (FTP) en Linux.
# Uso: chmod +x main_linux.sh && sudo ./main_linux.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib/bash"
[[ ! -d "$LIB_DIR" ]] && LIB_DIR="/mnt/sysadmin/lib/bash"

source "${LIB_DIR}/comunes.sh"
source "${LIB_DIR}/ftp.sh"

verificar_root

while true; do
  banner "GESTOR FTP - LINUX SERVER (BASH MODULAR)"
  echo -e "  ${BOLD}1)${NC} Instalación Idempotente (vsftpd)"
  echo -e "  ${BOLD}2)${NC} Alta Masiva de Usuarios FTP"
  echo -e "  ${BOLD}3)${NC} Cambiar Grupo de un Usuario"
  echo -e "  ${BOLD}4)${NC} Módulo de Monitoreo y Validación"
  echo -e "  ${BOLD}5)${NC} Salir"
  read -rp "Selecciona una opción (1-5): " opt

  case $opt in
    1) instalar_ftp_linux ;;
    2)
      read -rp "Número de usuarios a crear: " n
      if [[ ! "$n" =~ ^[0-9]+$ ]] || [ "$n" -le 0 ]; then
        echo -e "${RED}[ERROR] Debe ingresar un número entero positivo.${NC}"
        continue
      fi
      
      for ((i=1; i<=n; i++)); do
        echo -e "\n${BLUE}--- Configuración del Usuario $i de $n ---${NC}"
        read -rp "Nombre de usuario: " username
        read -rsp "Contraseña: " password; echo ""
        
        while true; do
          read -rp "Grupo (reprobados/recursadores): " group
          if [[ "$group" == "reprobados" || "$group" == "recursadores" ]]; then
            break
          else
            echo -e "${RED}[ERROR] Grupo inválido. Intente de nuevo.${NC}"
          fi
        done
        
        crear_usuario_ftp_linux "$username" "$password" "$group"
      done
      ;;
    3)
      read -rp "Nombre de usuario a modificar: " username
      while true; do
        read -rp "Nuevo grupo (reprobados/recursadores): " new_group
        if [[ "$new_group" == "reprobados" || "$new_group" == "recursadores" ]]; then
          break
        else
          echo -e "${RED}[ERROR] Grupo inválido. Intente de nuevo.${NC}"
        fi
      done
      cambiar_grupo_usuario_linux "$username" "$new_group"
      ;;
    4)
      monitorear_ftp_linux
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
