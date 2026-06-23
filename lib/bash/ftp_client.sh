#!/usr/bin/env bash
# lib/bash/ftp_client.sh - Cliente FTP dinámico y validación de integridad
#
# CORRECCIONES APLICADAS:
#   - Todos los mensajes de info/error van a stderr (>&2) para que el
#     llamador pueda capturar únicamente la ruta del binario via $().
#   - Se aplica 'basename' a los nombres devueltos por curl -l para
#     evitar rutas completas que devuelve vsftpd en algunos modos.
#   - Se maneja el caso de credenciales ya capturadas (FTP_IP no vacío).

# Variables de sesión FTP
FTP_IP=""
FTP_USER=""
FTP_PASS=""

# Solicitar credenciales FTP
solicitar_credenciales_ftp() {
    echo -e "\n=== CREDENCIALES DEL SERVIDOR FTP CENTRAL ===" >&2
    read -p "IP del Servidor FTP [192.168.100.10]: " input_ip
    FTP_IP=${input_ip:-"192.168.100.10"}

    read -p "Usuario FTP [ftpuser]: " input_user
    FTP_USER=${input_user:-"ftpuser"}

    read -s -p "Contraseña FTP: " input_pass
    echo "" >&2
    FTP_PASS=$input_pass
}

# ─── listar_directorio_ftp ───────────────────────────────────────────────────
# Devuelve solo el nombre (basename) de cada entrada, uno por línea.
# Filtra líneas vacías.  Todos los errores van a stderr.
listar_directorio_ftp() {
    local ruta="$1"
    local raw
    raw=$(curl -s --connect-timeout 10 --max-time 30 \
         -l -u "${FTP_USER}:${FTP_PASS}" \
         "ftp://${FTP_IP}/${ruta}" 2>/dev/null)

    if [ -z "$raw" ]; then
        echo "[WARN] Listado vacío para ftp://${FTP_IP}/${ruta}" >&2
        return 1
    fi

    # Algunos servidores devuelven paths completos; normalizar a solo nombre
    while IFS= read -r linea; do
        linea="${linea%$'\r'}"   # quitar CR de CRLF
        [[ -z "$linea" ]] && continue
        basename "$linea"
    done <<< "$raw"
}

# ─── descargar_desde_ftp ────────────────────────────────────────────────────
# Navega dinámicamente el repositorio FTP:
#   ftp://IP/http/<OS>/<Servicio>/<Binario>
# Valida integridad con SHA256 o MD5.
# Imprime en stdout ÚNICAMENTE la ruta local del binario descargado.
# Toda la interacción con el usuario va a stderr.
descargar_desde_ftp() {
    local os_target="$1"   # "Linux" o "Windows"

    if [ -z "$FTP_IP" ]; then
        solicitar_credenciales_ftp
    fi

    echo -e "\n[INFO] Conectando a ftp://${FTP_IP}/http/${os_target}/..." >&2

    # ── 1. Listar servicios disponibles para el SO ─────────────────────────
    local servicios_raw
    servicios_raw=$(listar_directorio_ftp "http/${os_target}/")
    if [ $? -ne 0 ] || [ -z "$servicios_raw" ]; then
        echo -e "\e[31m[ERROR] No se pudo listar ftp://${FTP_IP}/http/${os_target}/\e[0m" >&2
        echo -e "\e[33m[HINT] Verifica:\e[0m" >&2
        echo -e "\e[33m  1. IP del servidor FTP correcta\e[0m" >&2
        echo -e "\e[33m  2. Usuario '${FTP_USER}' tiene acceso y la carpeta http/${os_target}/ existe\e[0m" >&2
        echo -e "\e[33m  3. Si usas chroot, la carpeta debe estar DENTRO del home del usuario FTP\e[0m" >&2
        return 1
    fi

    # Convertir a array, ignorando líneas vacías
    local servicios=()
    while IFS= read -r linea; do
        [[ -n "$linea" ]] && servicios+=("$linea")
    done <<< "$servicios_raw"

    if [ ${#servicios[@]} -eq 0 ]; then
        echo -e "\e[31m[ERROR] La carpeta http/${os_target}/ está vacía.\e[0m" >&2
        return 1
    fi

    echo -e "\nServicios disponibles en el repositorio FTP:" >&2
    for i in "${!servicios[@]}"; do
        echo "  $((i+1)))- ${servicios[$i]}" >&2
    done
    echo "  $(( ${#servicios[@]} + 1 )))- Cancelar y volver" >&2

    local opcion_svc
    read -p "Selecciona una opción (1-$(( ${#servicios[@]} + 1 ))): " opcion_svc >&2

    if ! [[ "$opcion_svc" =~ ^[0-9]+$ ]] || \
       [[ "$opcion_svc" -le 0 ]] || \
       [[ "$opcion_svc" -gt "${#servicios[@]}" ]]; then
        echo "Operación cancelada." >&2
        return 1
    fi

    local svc_elegido="${servicios[$((opcion_svc-1))]}"
    local ruta_svc="http/${os_target}/${svc_elegido}"

    # ── 2. Listar archivos dentro del servicio elegido ─────────────────────
    local archivos_raw
    archivos_raw=$(listar_directorio_ftp "${ruta_svc}/")
    if [ $? -ne 0 ] || [ -z "$archivos_raw" ]; then
        echo -e "\e[31m[ERROR] La carpeta '${svc_elegido}' está vacía o no existe.\e[0m" >&2
        return 1
    fi

    local todos_archivos=()
    while IFS= read -r linea; do
        [[ -n "$linea" ]] && todos_archivos+=("$linea")
    done <<< "$archivos_raw"

    # Filtrar: mostrar solo archivos de instalación (sin .sha256 / .md5)
    local instaladores=()
    for archivo in "${todos_archivos[@]}"; do
        if [[ ! "$archivo" =~ \.(sha256|md5)$ ]]; then
            instaladores+=("$archivo")
        fi
    done

    if [ ${#instaladores[@]} -eq 0 ]; then
        echo -e "\e[31m[ERROR] No se encontraron instaladores en ${ruta_svc}.\e[0m" >&2
        return 1
    fi

    echo -e "\nArchivos de instalación disponibles:" >&2
    for i in "${!instaladores[@]}"; do
        echo "  $((i+1)))- ${instaladores[$i]}" >&2
    done
    echo "  $(( ${#instaladores[@]} + 1 )))- Cancelar" >&2

    local opcion_file
    read -p "Selecciona el archivo a descargar (1-$(( ${#instaladores[@]} + 1 ))): " opcion_file >&2

    if ! [[ "$opcion_file" =~ ^[0-9]+$ ]] || \
       [[ "$opcion_file" -le 0 ]] || \
       [[ "$opcion_file" -gt "${#instaladores[@]}" ]]; then
        echo "Operación cancelada." >&2
        return 1
    fi

    local binario_elegido="${instaladores[$((opcion_file-1))]}"
    local url_binario="ftp://${FTP_IP}/${ruta_svc}/${binario_elegido}"
    local dest_dir="/tmp/ftp_install"
    mkdir -p "$dest_dir"

    local local_binario="${dest_dir}/${binario_elegido}"

    # ── 3. Descargar binario ───────────────────────────────────────────────
    echo -e "\n[INFO] Descargando ${binario_elegido}..." >&2
    if ! curl --connect-timeout 10 --max-time 300 \
              -u "${FTP_USER}:${FTP_PASS}" \
              "$url_binario" -o "$local_binario" 2>&1 | \
         grep -E "^[0-9]|curl:|error" >&2; then
        # curl puede salir sin imprimir nada si falla en conexión
        :
    fi

    if [ ! -f "$local_binario" ] || [ ! -s "$local_binario" ]; then
        echo -e "\e[31m[ERROR] Falló la descarga o el archivo está vacío.\e[0m" >&2
        rm -f "$local_binario"
        return 1
    fi
    echo -e "\e[32m[OK] Descarga completada: ${local_binario}\e[0m" >&2

    # ── 4. Validación de Integridad (SHA256 / MD5) ─────────────────────────
    local validado=false
    local firma_ext=""

    for archivo in "${todos_archivos[@]}"; do
        if [[ "$archivo" == "${binario_elegido}.sha256" ]]; then
            firma_ext="sha256"; break
        elif [[ "$archivo" == "${binario_elegido}.md5" ]]; then
            firma_ext="md5"; break
        fi
    done

    if [ -n "$firma_ext" ]; then
        local url_firma="ftp://${FTP_IP}/${ruta_svc}/${binario_elegido}.${firma_ext}"
        local local_firma="${local_binario}.${firma_ext}"

        echo "[INFO] Descargando firma de integridad .${firma_ext}..." >&2
        curl -s --connect-timeout 10 --max-time 30 \
             -u "${FTP_USER}:${FTP_PASS}" \
             "$url_firma" -o "$local_firma" 2>/dev/null

        if [ ! -f "$local_firma" ] || [ ! -s "$local_firma" ]; then
            echo -e "\e[33m[WARNING] No se pudo descargar el archivo de firma.${firma_ext}.\e[0m" >&2
        else
            local hash_calculado hash_servidor
            if [ "$firma_ext" = "sha256" ]; then
                hash_calculado=$(sha256sum "$local_binario" | awk '{print $1}')
            else
                hash_calculado=$(md5sum "$local_binario" | awk '{print $1}')
            fi
            hash_servidor=$(awk '{print $1}' "$local_firma")

            echo "[INFO] Hash ${firma_ext^^} Local:    ${hash_calculado}" >&2
            echo "[INFO] Hash ${firma_ext^^} Servidor: ${hash_servidor}" >&2

            if [ "$hash_calculado" = "$hash_servidor" ]; then
                validado=true
                echo -e "\e[32m[OK] Verificación de integridad exitosa (Hash coincide).\e[0m" >&2
            else
                echo -e "\e[31m[ERROR] ¡ARCHIVO CORRUPTO! El hash no coincide.\e[0m" >&2
                rm -f "$local_binario" "$local_firma"
                return 1
            fi
        fi
    else
        echo -e "\e[33m[WARNING] No se encontró archivo de firma (.sha256 o .md5) en el servidor FTP.\e[0m" >&2
        read -p "¿Continuar la instalación SIN verificar integridad? [s/N]: " continuar_sin_firma >&2
        if [[ ! "$continuar_sin_firma" =~ ^[Ss]$ ]]; then
            rm -f "$local_binario"
            return 1
        fi
    fi

    # Devolver SOLO la ruta al stdout (el llamador la captura con $())
    echo "$local_binario"
    return 0
}
