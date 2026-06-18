#!/usr/bin/env bash
# tarea7/tarea7.sh - Orquestador de Despliegue Seguro e Instalación Híbrida Linux

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib/bash"

# Cargar librerías
source "$LIB_DIR/comunes.sh"
source "$LIB_DIR/http.sh"
source "$LIB_DIR/ftp_client.sh"
source "$LIB_DIR/ssl.sh"

verificar_root

# Mostrar banner inicial
mostrar_banner() {
    clear
    echo "=================================================================="
    echo "  ORQUESTADOR DE INFRAESTRUCTURA DE DESPLIEGUE SEGURO (TAREA 7)  "
    echo "=================================================================="
    echo "  Estudiante: Herman Geovany Ayala Zuñiga                        "
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
        # Verificar puerto 8443
        if ss -tlnp | grep -q "8443"; then
            echo -e "  [ACTIVO] HTTP (Tomcat) -> HTTPS Seguro (Puerto 8443) \e[32m✔\e[0m"
        else
            echo -e "  [ACTIVO] HTTP (Tomcat) -> Inseguro (Puerto 8080) \e[33m⚠\e[0m"
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
            mostrar_banner
            echo -e "\n=== FUENTE DE INSTALACIÓN HÍBRIDA ==="
            echo "  1) WEB (vía Gestor de Paquetes Oficial)"
            echo "  2) FTP (vía Repositorio Privado Práctica 5)"
            echo "  3) Regresar"
            read -p "Selecciona fuente (1-3): " fuente_opt

            if [ "$fuente_opt" -eq 1 ]; then
                # Flujo normal de Tarea 6 (Instalación por Web)
                echo -e "\nSeleccione el servicio a instalar:"
                echo "  1) Apache"
                echo "  2) Nginx"
                echo "  3) Tomcat"
                read -p "Opción (1-3): " svc_opt
                
                case "$svc_opt" in
                    1)
                        # Consultar versiones e instalar Apache
                        versiones=$(consultar_versiones_apache)
                        echo "$versiones"
                        read -p "Selecciona versión: " ver_sel
                        read -p "Puerto de escucha [80]: " port_sel
                        port=${port_sel:-80}
                        instalar_apache "$ver_sel" "$port"
                        ;;
                    2)
                        versiones=$(consultar_versiones_nginx)
                        echo "$versiones"
                        read -p "Selecciona versión: " ver_sel
                        read -p "Puerto de escucha [80]: " port_sel
                        port=${port_sel:-80}
                        instalar_nginx "$ver_sel" "$port"
                        ;;
                    3)
                        versiones=$(consultar_versiones_tomcat)
                        echo "$versiones"
                        read -p "Selecciona versión: " ver_sel
                        read -p "Puerto de escucha [8080]: " port_sel
                        port=${port_sel:-8080}
                        instalar_tomcat "$ver_sel" "$port"
                        ;;
                    *)
                        echo "Opción inválida."
                        ;;
                esac

            elif [ "$fuente_opt" -eq 2 ]; then
                # Flujo de descarga FTP no interactiva y hash
                binario=$(descargar_desde_ftp "Linux")
                if [ -n "$binario" ] && [ -f "$binario" ]; then
                    echo -e "\n[INFO] Iniciando instalación manual del binario descargado: $binario"
                    
                    # Decidir instalación por extensión
                    if [[ "$binario" == *.deb ]]; then
                        dpkg -i "$binario"
                        apt-get install -f -y
                    elif [[ "$binario" == *.tar.gz ]]; then
                        # Si es tomcat o java, descomprimir en el destino sugerido
                        if [[ "$binario" =~ tomcat ]]; then
                            mkdir -p /opt/tomcat
                            tar -xzf "$binario" -C /opt/tomcat --strip-components=1
                            # Configurar usuario y permisos
                            id -u tomcat &>/dev/null || useradd -r -m -U -d /opt/tomcat -s /bin/false tomcat
                            chown -R tomcat:tomcat /opt/tomcat
                            chmod +x /opt/tomcat/bin/*.sh
                        else
                            echo "[INFO] Archivo .tar.gz extraído a /tmp."
                            tar -xzf "$binario" -C /tmp/
                        fi
                    fi
                    echo -e "\e[32m[OK] Instalación manual completada exitosamente.\e[0m"
                    sleep 2
                fi
            fi
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
