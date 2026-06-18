#!/usr/bin/env bash
# lib/bash/ftp_client.sh - Cliente FTP dinámico y validación de integridad

# Variables de sesión FTP
FTP_IP=""
FTP_USER=""
FTP_PASS=""

# Solicitar credenciales FTP
solicitar_credenciales_ftp() {
    echo -e "\n=== CREDENCIALES DEL SERVIDOR FTP CENTRAL ==="
    read -p "IP del Servidor FTP [192.168.100.10]: " input_ip
    FTP_IP=${input_ip:-"192.168.100.10"}
    
    read -p "Usuario FTP [ftpuser]: " input_user
    FTP_USER=${input_user:-"ftpuser"}
    
    read -s -p "Contraseña FTP: " input_pass
    echo ""
    FTP_PASS=$input_pass
}

# Realizar listado FTP usando curl
listar_directorio_ftp() {
    local ruta="$1"
    # --list-only (-l) devuelve solo los nombres de archivos/directorios uno por línea
    curl -s -l -u "$FTP_USER:$FTP_PASS" "ftp://$FTP_IP/$ruta"
}

# Navegación y descarga dinámica por FTP
descargar_desde_ftp() {
    local os_target="$1" # "Linux" o "Windows"
    
    if [ -z "$FTP_IP" ]; then
        solicitar_credenciales_ftp
    fi

    echo -e "\n[INFO] Conectando a ftp://$FTP_IP/http/$os_target/..."
    
    # 1. Listar servicios disponibles para el SO
    local servicios_raw
    servicios_raw=$(listar_directorio_ftp "http/$os_target/")
    if [ -z "$servicios_raw" ]; then
        echo -e "\e[31m[ERROR] No se pudo conectar al servidor FTP o la carpeta http/$os_target/ está vacía.\e[0m"
        return 1
    fi

    # Convertir a array
    IFS=$'\n' read -rd '' -a servicios <<< "$servicios_raw"
    
    echo -e "\nServicios disponibles en el repositorio FTP:"
    for i in "${!servicios[@]}"; do
        echo "  $((i+1)))- ${servicios[$i]}"
    done
    echo "  $(( ${#servicios[@]} + 1 )))- Cancelar y volver"

    local opcion_svc
    read -p "Selecciona una opción (1-$(( ${#servicios[@]} + 1 ))): " opcion_svc
    
    if [[ "$opcion_svc" -le 0 || "$opcion_svc" -gt "${#servicios[@]}" ]]; then
        echo "Operación cancelada."
        return 1
    fi
    
    local svc_elegido="${servicios[$((opcion_svc-1))]}"
    local ruta_svc="http/$os_target/$svc_elegido"

    # 2. Listar archivos dentro del servicio elegido
    local archivos_raw
    archivos_raw=$(listar_directorio_ftp "$ruta_svc/")
    if [ -z "$archivos_raw" ]; then
        echo -e "\e[31m[ERROR] La carpeta del servicio $svc_elegido está vacía o no existe.\e[0m"
        return 1
    fi

    IFS=$'\n' read -rd '' -a todos_archivos <<< "$archivos_raw"
    
    # Filtrar solo archivos de instalación (ignorar firmas .sha256 o .md5 de la lista visible)
    local instaladores=()
    for archivo in "${todos_archivos[@]}"; do
        if [[ ! "$archivo" =~ \.(sha256|md5)$ ]]; then
            instaladores+=("$archivo")
        fi
    done

    if [ ${#instaladores[@]} -eq 0 ]; then
        echo -e "\e[31m[ERROR] No se encontraron instaladores en $ruta_svc.\e[0m"
        return 1
    fi

    echo -e "\nArchivos de instalación disponibles:"
    for i in "${!instaladores[@]}"; do
        echo "  $((i+1)))- ${instaladores[$i]}"
    done
    echo "  $(( ${#instaladores[@]} + 1 )))- Cancelar"

    local opcion_file
    read -p "Selecciona el archivo a descargar (1-$(( ${#instaladores[@]} + 1 ))): " opcion_file

    if [[ "$opcion_file" -le 0 || "$opcion_file" -gt "${#instaladores[@]}" ]]; then
        echo "Operación cancelada."
        return 1
    fi

    local binario_elegido="${instaladores[$((opcion_file-1))]}"
    local url_binario="ftp://$FTP_IP/$ruta_svc/$binario_elegido"
    local dest_dir="/tmp/ftp_install"
    mkdir -p "$dest_dir"

    local local_binario="$dest_dir/$binario_elegido"

    # Descargar binario
    echo -e "\n[INFO] Descargando $binario_elegido..."
    curl -u "$FTP_USER:$FTP_PASS" "$url_binario" -o "$local_binario"
    if [ $? -ne 0 ]; then
        echo -e "\e[31m[ERROR] Falló la descarga del instalador.\e[0m"
        return 1
    fi

    # 3. Validación de Integridad
    local validado=false
    # Buscar si existe firma SHA256 o MD5 en el listado
    local firma_ext=""
    for archivo in "${todos_archivos[@]}"; do
        if [[ "$archivo" == "$binario_elegido.sha256" ]]; then
            firma_ext="sha256"
            break
        elif [[ "$archivo" == "$binario_elegido.md5" ]]; then
            firma_ext="md5"
            break
        fi
    done

    if [ -n "$firma_ext" ]; then
        local url_firma="ftp://$FTP_IP/$ruta_svc/$binario_elegido.$firma_ext"
        local local_firma="$local_binario.$firma_ext"
        
        echo "[INFO] Descargando firma de integridad .$firma_ext..."
        curl -s -u "$FTP_USER:$FTP_PASS" "$url_firma" -o "$local_firma"
        
        if [ "$firma_ext" = "sha256" ]; then
            # Comparar sha256
            local hash_calculado
            hash_calculado=$(sha256sum "$local_binario" | cut -d' ' -f1)
            # Leer el primer token del archivo de firma
            local hash_servidor
            hash_servidor=$(awk '{print $1}' "$local_firma")
            
            echo "[INFO] Hash SHA256 Local:    $hash_calculado"
            echo "[INFO] Hash SHA256 Servidor: $hash_servidor"
            
            if [ "$hash_calculado" = "$hash_servidor" ]; then
                validado=true
            fi
        else
            # Comparar md5
            local hash_calculado
            hash_calculado=$(md5sum "$local_binario" | cut -d' ' -f1)
            local hash_servidor
            hash_servidor=$(awk '{print $1}' "$local_firma")
            
            echo "[INFO] Hash MD5 Local:    $hash_calculado"
            echo "[INFO] Hash MD5 Servidor: $hash_servidor"
            
            if [ "$hash_calculado" = "$hash_servidor" ]; then
                validado=true
            fi
        fi

        if [ "$validado" = true ]; then
            echo -e "\e[32m[OK] Verificación de integridad exitosa (Hash Coincide).\e[0m"
        else
            echo -e "\e[31m[ERROR] ¡ARCHIVO CORRUPTO! El hash no coincide con el del servidor.\e[0m"
            rm -f "$local_binario" "$local_firma"
            return 1
        fi
    else
        echo -e "\e[33m[WARNING] No se encontró un archivo de firma (.sha256 o .md5) en el servidor FTP.\e[0m"
        read -p "¿Desea continuar la instalación sin verificar la integridad? [s/N]: " continuar_sin_firma
        if [[ ! "$continuar_sin_firma" =~ ^[Ss]$ ]]; then
            rm -f "$local_binario"
            return 1
        fi
    fi

    # Devolver la ruta local del binario descargado
    echo "$local_binario"
    return 0
}
