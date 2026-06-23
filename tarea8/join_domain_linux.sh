#!/usr/bin/env bash
# tarea8/join_domain_linux.sh
# Union automatica de cliente Linux al dominio Active Directory
# Uso: chmod +x join_domain_linux.sh && sudo ./join_domain_linux.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../lib/bash/comunes.sh" ] && [ -f "$SCRIPT_DIR/../lib/bash/ad.sh" ]; then
    LIB_DIR="$SCRIPT_DIR/../lib/bash"
elif [ -f "$SCRIPT_DIR/lib/bash/comunes.sh" ] && [ -f "$SCRIPT_DIR/lib/bash/ad.sh" ]; then
    LIB_DIR="$SCRIPT_DIR/lib/bash"
elif [ -f "/mnt/sysadmin/lib/bash/comunes.sh" ] && [ -f "/mnt/sysadmin/lib/bash/ad.sh" ]; then
    LIB_DIR="/mnt/sysadmin/lib/bash"
elif [ -f "$SCRIPT_DIR/comunes.sh" ] && [ -f "$SCRIPT_DIR/ad.sh" ]; then
    LIB_DIR="$SCRIPT_DIR"
else
    echo -e "\e[31m[ERROR] No se pudo encontrar la librería de AD en lib/bash\e[0m"
    exit 1
fi

source "${LIB_DIR}/comunes.sh"
source "${LIB_DIR}/ad.sh"

verificar_root

banner "UNION DE CLIENTE LINUX - TAREA 8"

read -rp "Nombre del dominio [sysadmin.local]: " dominio
dominio=${dominio:-sysadmin.local}

read -rp "Usuario con permisos de dominio [Administrador]: " usuario_ad
usuario_ad=${usuario_ad:-Administrador}

read -rsp "Contrasena del usuario de dominio: " contrasena
echo ""

unir_dominio_linux "$dominio" "$usuario_ad" "$contrasena"

echo ""
mostrar_estado_dominio_linux
