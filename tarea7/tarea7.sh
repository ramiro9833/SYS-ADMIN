#!/usr/bin/env bash
# tarea7/tarea7.sh - Orquestador de Despliegue Seguro e Instalación Híbrida Linux

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Buscar directorio de librerías dinámicamente
# Buscar directorio de librerías dinámicamente
if [ -f "$SCRIPT_DIR/../lib/bash/comunes.sh" ] && [ -f "$SCRIPT_DIR/../lib/bash/ftp_client.sh" ]; then
    LIB_DIR="$SCRIPT_DIR/../lib/bash"
elif [ -f "$SCRIPT_DIR/lib/bash/comunes.sh" ] && [ -f "$SCRIPT_DIR/lib/bash/ftp_client.sh" ]; then
    LIB_DIR="$SCRIPT_DIR/lib/bash"
elif [ -f "/mnt/sysadmin/lib/bash/comunes.sh" ] && [ -f "/mnt/sysadmin/lib/bash/ftp_client.sh" ]; then
    LIB_DIR="/mnt/sysadmin/lib/bash"
elif [ -f "$SCRIPT_DIR/comunes.sh" ] && [ -f "$SCRIPT_DIR/ftp_client.sh" ]; then
    LIB_DIR="$SCRIPT_DIR"
else
    LIB_DIR="$SCRIPT_DIR/../lib/bash" # Fallback por defecto
fi

# Cargar y verificar librerías
for lib in comunes.sh http.sh ftp_client.sh ssl.sh; do
    if [ -f "$LIB_DIR/$lib" ]; then
        source "$LIB_DIR/$lib"
    else
        echo -e "\e[31m[ERROR] No se pudo encontrar la librería: $LIB_DIR/$lib\e[0m"
        echo -e "\e[33m[HINT] Asegúrese de ejecutar el script con toda su estructura de carpetas o que las librerías comunes estén en el mismo directorio.\e[0m"
        exit 1
    fi
done

verificar_root

# Mostrar banner inicial
mostrar_banner() {
    clear
    echo "=================================================================="
    echo "  ORQUESTADOR DE INFRAESTRUCTURA DE DESPLIEGUE SEGURO (TAREA 7)  "
    echo "=================================================================="
}

# Verificación automatizada de servicios y certificados
mostrar_resumen_servicios() {
    echo -e "\n=== RESUMEN DE INTEGRIDAD Y SERVICIOS SEGUROS ==="
    
    # 1. vsftpd (FTP/FTPS)
    if systemctl is-active --quiet vsftpd; then
        local ssl_vsf=$(grep -i "ssl_enable=YES" /etc/vsftpd.conf 2>/dev/null)
        if [ -n "$ssl_vsf" ]; then
            echo -e "  [ACTIVO] FTP (vsftpd) -> FTPS Seguro (Require SSL) \e[32m✔\e[0m"
        else
            echo -e "  [ACTIVO] FTP (vsftpd) -> Inseguro (Sin SSL) \e[33m⚠\e[0m"
        fi
    else
        echo -e "  [INACTIVO] FTP (vsftpd) \e[31m✘\e[0m"
    fi

    # 2. Apache
    if systemctl is-active --quiet apache2; then
        if ssl-cert-check -c /etc/ssl/certs/reprobados.crt -n www.reprobados.com >/dev/null 2>&1 || [ -f /etc/ssl/certs/reprobados.crt ]; then
            echo -e "  [ACTIVO] HTTP (Apache) -> HTTPS Seguro (www.reprobados.com) \e[32m✔\e[0m"
        else
            echo -e "  [ACTIVO] HTTP (Apache) -> Inseguro (Sin SSL) \e[33m⚠\e[0m"
        fi
    else
        echo -e "  [INACTIVO] HTTP (Apache) \e[31m✘\e[0m"
    fi

    # 3. Nginx
    if systemctl is-active --quiet nginx; then
        if [ -f /etc/ssl/certs/reprobados.crt ] && grep -q "ssl_certificate" /etc/nginx/sites-enabled/* 2>/dev/null; then
            echo -e "  [ACTIVO] HTTP (Nginx) -> HTTPS Seguro (www.reprobados.com) \e[32m✔\e[0m"
        else
            echo -e "  [ACTIVO] HTTP (Nginx) -> Inseguro (Sin SSL) \e[33m⚠\e[0m"
        fi
    else
        echo -e "  [INACTIVO] HTTP (Nginx) \e[31m✘\e[0m"
    fi

    # 4. Tomcat
    if systemctl is-active --quiet tomcat; then
        local t_port; t_port=$(grep -oP '<Connector[^>]*port="\K[0-9]+' /opt/tomcat/conf/server.xml 2>/dev/null | head -1)
        [[ -z "$t_port" ]] && t_port="8080"
        if ss -tlnp 2>/dev/null | grep -q "8443" || grep -q 'scheme="https"' /opt/tomcat/conf/server.xml 2>/dev/null; then
            echo -e "  [ACTIVO] HTTP (Tomcat) -> HTTPS Seguro (Puerto ${t_port}) \e[32m✔\e[0m"
        else
            echo -e "  [ACTIVO] HTTP (Tomcat) -> Inseguro (Puerto ${t_port}) \e[33m⚠\e[0m"
        fi
    else
        echo -e "  [INACTIVO] HTTP (Tomcat) \e[31m✘\e[0m"
    fi
    echo "================================================="
    read -p "Presione Enter para continuar..." temp
}

# Menu principal
while true; do
    mostrar_banner
    echo "  1) Instalar/Actualizar Servicio HTTP (Híbrido: Web/FTP)"
    echo "  2) Configurar SSL/TLS Seguro en Servicio (HTTP o FTP)"
    echo "  3) Mostrar Estado y Resumen de Seguridad"
    echo "  4) Salir"
    echo "=================================================================="
    read -p "Selecciona una opción (1-4): " opt

    case "$opt" in
        1)
            while true; do
                mostrar_banner
                echo -e "\n=== FUENTE DE INSTALACIÓN HÍBRIDA ==="
                echo "  1) WEB (vía Gestor de Paquetes Oficial)"
                echo "  2) FTP (vía Repositorio Privado Práctica 5)"
                echo "  3) Regresar"
                read -p "Selecciona fuente (1-3): " fuente_opt

                if [ "$fuente_opt" = "1" ]; then
                    mostrar_banner
                    echo -e "\nSeleccione el servicio a instalar:"
                    echo "  1) Apache"
                    echo "  2) Nginx"
                    echo "  3) Tomcat"
                    echo "  4) Regresar"
                    read -p "Opción (1-4): " svc_opt

                    case "$svc_opt" in
                        1)
                            mapfile -t vers < <(consultar_versiones_apache)
                            ver_sel=$(seleccionar_version "Apache2" "${vers[@]}")
                            read -p "Puerto de escucha [80]: " port_sel
                            port=${port_sel:-80}
                            instalar_apache "$ver_sel" "$port"
                            break
                            ;;
                        2)
                            mapfile -t vers < <(consultar_versiones_nginx)
                            ver_sel=$(seleccionar_version "Nginx" "${vers[@]}")
                            read -p "Puerto de escucha [80]: " port_sel
                            port=${port_sel:-80}
                            instalar_nginx "$ver_sel" "$port"
                            break
                            ;;
                        3)
                            mapfile -t vers < <(consultar_versiones_tomcat)
                            ver_sel=$(seleccionar_version "Tomcat" "${vers[@]}")
                            read -p "Puerto de escucha [8080]: " port_sel
                            port=${port_sel:-8080}
                            instalar_tomcat "$ver_sel" "$port"
                            break
                            ;;
                        4)
                            continue
                            ;;
                        *)
                            echo "Opción inválida."
                            sleep 1
                            ;;
                    esac

                elif [ "$fuente_opt" = "2" ]; then
                    # Flujo de descarga FTP no interactiva y validación de hash
                    # descargar_desde_ftp envía logs a stderr; solo devuelve la ruta al stdout
                    binario=$(descargar_desde_ftp "Linux")
                    exit_ftp=$?

                    if [ $exit_ftp -ne 0 ] || [ -z "$binario" ] || [ ! -f "$binario" ]; then
                        echo -e "\e[31m[ERROR] No se pudo obtener el binario desde el servidor FTP.\e[0m"
                        sleep 2
                    else
                        echo -e "\n[INFO] Iniciando instalación del binario: $binario"

                        if [[ "$binario" == *.deb ]]; then
                            dpkg -i "$binario"
                            apt-get install -f -y
                        elif [[ "$binario" == *.tar.gz ]]; then
                            if [[ "$binario" =~ tomcat ]]; then
                                mkdir -p /opt/tomcat
                                tar -xzf "$binario" -C /opt/tomcat --strip-components=1
                                id -u tomcat_svc &>/dev/null || useradd -r -m -U -d /opt/tomcat -s /bin/false tomcat_svc
                                chown -R tomcat_svc:tomcat_svc /opt/tomcat
                                chmod +x /opt/tomcat/bin/*.sh
                                echo -e "\e[32m[OK] Tomcat extraído en /opt/tomcat.\e[0m"
                                echo -e "\e[33m[INFO] Configura el servicio systemd o usa la opción SSL/TLS.\e[0m"
                            else
                                tar -xzf "$binario" -C /tmp/
                                echo -e "\e[32m[OK] Archivo extraído en /tmp.\e[0m"
                            fi
                        elif [[ "$binario" == *.rpm ]]; then
                            rpm -i "$binario"
                        else
                            echo -e "\e[33m[WARN] Extensión no reconocida. Archivo en: $binario\e[0m"
                        fi
                        echo -e "\e[32m[OK] Instalación completada.\e[0m"
                        sleep 2
                    fi
                    break
                elif [ "$fuente_opt" = "3" ]; then
                    break
                else
                    echo -e "\e[31mOpción inválida.\e[0m"
                    sleep 1
                fi
            done
            ;;
            
        2)
            mostrar_banner
            echo -e "\n=== CONFIGURAR SSL/TLS (www.reprobados.com) ==="
            echo "  1) Apache (HTTP -> HTTPS)"
            echo "  2) Nginx (HTTP -> HTTPS)"
            echo "  3) Tomcat (HTTP -> HTTPS Puerto 8443)"
            echo "  4) vsftpd (FTP -> FTPS Seguro)"
            echo "  5) Regresar"
            read -p "Selecciona servicio para asegurar (1-5): " ssl_opt

            case "$ssl_opt" in
                1) configurar_ssl_apache ;;
                2) configurar_ssl_nginx ;;
                3) configurar_ssl_tomcat ;;
                4) configurar_ssl_vsftpd ;;
                *) echo "Regresando..." ;;
            esac
            sleep 2
            ;;

        3)
            mostrar_banner
            mostrar_resumen_servicios
            ;;
            
        4)
            echo "Saliendo del orquestador..."
            exit 0
            ;;
        *)
            echo "Opción no válida."
            sleep 1
            ;;
    esac
done
