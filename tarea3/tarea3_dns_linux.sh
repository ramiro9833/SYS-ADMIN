#!/usr/bin/env bash

# Script:      tarea3_dns_linux.sh
# Descripción: Automatización del Servidor DNS (BIND9) para el dominio reprobados.com
#              Instalación idempotente, configuración de zona y monitoreo.
# Autor:       Antigravity AI
# Uso:         chmod +x tarea3_dns_linux.sh && sudo ./tarea3_dns_linux.sh

# ─── Colores ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
RED='\033[0;31m';   CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# ─── Verificar privilegios root ──────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}${BOLD}[ERROR] Ejecutar como root: sudo ./tarea3_dns_linux.sh${NC}"
  exit 1
fi

# ─── Validar formato IPv4 ────────────────────────────────────────────────────
validar_ip() {
  local ip=$1
  if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS='.' read -r -a octetos <<< "$ip"
    for oct in "${octetos[@]}"; do
      [[ $oct -gt 255 ]] && return 1
    done
    return 0
  fi
  return 1
}

# ─── Leer IP con validación ──────────────────────────────────────────────────
leer_ip() {
  local prompt="$1"
  local default="$2"
  local ip=""
  while true; do
    read -rp "$prompt [$default]: " ip
    [[ -z "$ip" ]] && ip="$default"
    if validar_ip "$ip"; then echo "$ip"; return; fi
    echo -e "${RED}[ERROR] IP inválida. Formato requerido: X.X.X.X (0-255 cada octeto)${NC}"
  done
}

# ════════════════════════════════════════════════════════════════════════════════
# 1. VERIFICACIÓN DE IP ESTÁTICA
# ════════════════════════════════════════════════════════════════════════════════
verificar_ip_estatica() {
  echo -e "\n${BLUE}${BOLD}[CHECK] Verificando IP estática en la interfaz interna...${NC}"

  # Detectar la interfaz de red interna (la que NO es loopback ni NAT)
  local iface
  iface=$(ip -o -4 addr show | awk '{print $2}' | grep -v lo | tail -1)

  local ip_actual
  ip_actual=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

  # Verificar si está configurada como estática en Netplan
  local es_estatica=false
  if grep -rq "dhcp4: no" /etc/netplan/ 2>/dev/null; then
    es_estatica=true
  fi

  if $es_estatica && [[ -n "$ip_actual" ]]; then
    echo -e "${GREEN}[OK] IP estática detectada: ${BOLD}$ip_actual${NC} en interfaz ${BOLD}$iface${NC}"
    SERVER_IP="$ip_actual"
    SERVER_IFACE="$iface"
  else
    echo -e "${YELLOW}[AVISO] No se detectó IP estática en $iface.${NC}"
    echo -e "${YELLOW}Se procederá a configurar una IP estática antes de continuar.${NC}"
    configurar_ip_estatica "$iface"
  fi
}

configurar_ip_estatica() {
  local iface="${1:-enp0s8}"
  echo -e "\n${BLUE}${BOLD}[IP] Configuración de IP Estática en $iface${NC}"

  local ip_nueva
  ip_nueva=$(leer_ip "Ingresa la IP estática para este servidor" "192.168.100.10")

  local gateway
  gateway=$(leer_ip "Ingresa la puerta de enlace (Gateway)" "192.168.100.1")

  # Detectar la interfaz NAT (la que tiene ruta por defecto)
  local iface_nat
  iface_nat=$(ip route | awk '/default/ {print $5}' | head -1)
  [[ -z "$iface_nat" ]] && iface_nat="enp0s3"

  echo -e "${YELLOW}Generando configuración Netplan...${NC}"
  cat > /etc/netplan/99-sysadmin-config.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${iface_nat}:
      dhcp4: true
    ${iface}:
      dhcp4: no
      addresses:
        - ${ip_nueva}/24
EOF

  chmod 600 /etc/netplan/99-sysadmin-config.yaml
  netplan apply
  echo -e "${GREEN}[OK] IP estática $ip_nueva aplicada en $iface.${NC}"
  SERVER_IP="$ip_nueva"
  SERVER_IFACE="$iface"
}

# ════════════════════════════════════════════════════════════════════════════════
# 2. INSTALACIÓN IDEMPOTENTE DE BIND9
# ════════════════════════════════════════════════════════════════════════════════
instalar_bind9() {
  echo -e "\n${BLUE}${BOLD}[1/4] Verificando instalación de BIND9...${NC}"

  if systemctl is-active --quiet named 2>/dev/null || dpkg -l | grep -q "^ii.*bind9 "; then
    echo -e "${GREEN}[INFO] BIND9 ya está instalado y activo. No se requiere reinstalación.${NC}"
    systemctl status named --no-pager -l | head -5
    return 0
  fi

  echo -e "${YELLOW}[INFO] BIND9 no está instalado. Iniciando instalación desatendida...${NC}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y -qq
  apt-get install -y -qq bind9 bind9utils bind9-doc dnsutils

  if dpkg -l | grep -q "^ii.*bind9 "; then
    echo -e "${GREEN}[OK] BIND9, bind9utils y bind9-doc instalados correctamente.${NC}"
  else
    echo -e "${RED}[ERROR] Falló la instalación de BIND9.${NC}"; exit 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════════
# 3. CONFIGURACIÓN DE ZONA DNS
# ════════════════════════════════════════════════════════════════════════════════
configurar_dns() {
  echo -e "\n${BLUE}${BOLD}[2/4] Configuración de Zona DNS para reprobados.com${NC}"

  # Solicitar parámetros interactivos
  read -rp "Dominio a configurar [reprobados.com]: " DOMINIO
  [[ -z "$DOMINIO" ]] && DOMINIO="reprobados.com"

  local CLIENT_IP
  CLIENT_IP=$(leer_ip "IP del nodo cliente (registro A apuntará aquí)" "192.168.100.30")

  local NS_IP="${SERVER_IP:-192.168.100.10}"
  local SERIAL
  SERIAL=$(date +%Y%m%d%H)

  local ZONE_FILE="/var/cache/bind/db.${DOMINIO}"
  local NAMED_LOCAL="/etc/bind/named.conf.local"

  echo -e "\n${CYAN}  Dominio    : $DOMINIO${NC}"
  echo -e "${CYAN}  IP Cliente : $CLIENT_IP${NC}"
  echo -e "${CYAN}  IP Servidor: $NS_IP${NC}"
  echo -e "${CYAN}  Archivo    : $ZONE_FILE${NC}"
  read -rp "¿Continuar con esta configuración? [s/N]: " confirm
  [[ ! "$confirm" =~ ^[sS]$ ]] && echo "Operación cancelada." && return

  # ── Respaldo ──────────────────────────────────────────────────────────────
  echo -e "${YELLOW}Creando respaldos de configuraciones anteriores...${NC}"
  cp "$NAMED_LOCAL" "${NAMED_LOCAL}.bak.$(date +%s)" 2>/dev/null || true
  cp "$ZONE_FILE"   "${ZONE_FILE}.bak.$(date +%s)"   2>/dev/null || true

  # ── Generar named.conf.local ──────────────────────────────────────────────
  echo -e "${YELLOW}[3/4] Escribiendo zona en $NAMED_LOCAL...${NC}"

  # Eliminar bloque anterior del mismo dominio si existe
  if grep -q "\"${DOMINIO}\"" "$NAMED_LOCAL" 2>/dev/null; then
    echo -e "${YELLOW}[AVISO] Zona $DOMINIO ya existe en named.conf.local. Se reemplazará.${NC}"
    # Eliminar bloque existente
    sed -i "/zone \"${DOMINIO}\"/,/^};/d" "$NAMED_LOCAL"
  fi

  cat >> "$NAMED_LOCAL" <<EOF

zone "${DOMINIO}" {
    type master;
    file "${ZONE_FILE}";
    allow-query { any; };
};
EOF
  echo -e "${GREEN}[OK] Zona ${DOMINIO} registrada en named.conf.local.${NC}"

  # ── Generar archivo de zona ───────────────────────────────────────────────
  echo -e "${YELLOW}Generando archivo de zona: $ZONE_FILE ...${NC}"
  cat > "$ZONE_FILE" <<EOF
;
; Archivo de Zona DNS para: ${DOMINIO}
; Generado por: tarea3_dns_linux.sh
; Fecha: $(date)
;
\$TTL 86400
@   IN  SOA ns1.${DOMINIO}. admin.${DOMINIO}. (
            ${SERIAL} ; Serial (AñoMesDíaHora)
            3600      ; Refresh
            1800      ; Retry
            604800    ; Expire
            86400 )   ; Negative Cache TTL

; Servidor de nombres autoritativo
@   IN  NS  ns1.${DOMINIO}.

; Registro A para el servidor de nombres
ns1 IN  A   ${NS_IP}

; Registro A para el dominio raíz → IP del cliente
@   IN  A   ${CLIENT_IP}

; Registro A para www → IP del cliente
www IN  A   ${CLIENT_IP}
EOF
  echo -e "${GREEN}[OK] Archivo de zona generado correctamente.${NC}"

  # ── Ajustar permisos ──────────────────────────────────────────────────────
  chown bind:bind "$ZONE_FILE"
  chmod 644 "$ZONE_FILE"

  # ── Validación de sintaxis ────────────────────────────────────────────────
  echo -e "\n${BLUE}Validando sintaxis con named-checkconf...${NC}"
  if named-checkconf; then
    echo -e "${GREEN}[OK] Sintaxis de named.conf: VÁLIDA.${NC}"
  else
    echo -e "${RED}[ERROR] Error de sintaxis en named.conf. Revisa la configuración.${NC}"
    return 1
  fi

  echo -e "${BLUE}Validando archivo de zona con named-checkzone...${NC}"
  if named-checkzone "$DOMINIO" "$ZONE_FILE"; then
    echo -e "${GREEN}[OK] Archivo de zona: VÁLIDO.${NC}"
  else
    echo -e "${RED}[ERROR] Error en el archivo de zona. Revisa $ZONE_FILE.${NC}"
    return 1
  fi

  # ── Reiniciar BIND9 ───────────────────────────────────────────────────────
  echo -e "${BLUE}Reiniciando servicio BIND9...${NC}"
  systemctl restart named

  sleep 2
  if systemctl is-active --quiet named; then
    echo -e "${GREEN}${BOLD}[OK] Servidor DNS BIND9 activo y resolviendo ${DOMINIO}.${NC}"
  else
    echo -e "${RED}[ERROR] El servicio named no inició. Revisando logs...${NC}"
    journalctl -u named -n 15 --no-pager
  fi
}

# ════════════════════════════════════════════════════════════════════════════════
# 4. MÓDULO DE MONITOREO Y PRUEBAS
# ════════════════════════════════════════════════════════════════════════════════
monitorear_dns() {
  while true; do
    echo -e "\n${BLUE}${BOLD}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}       MÓDULO DE MONITOREO Y VALIDACIÓN DNS          ${NC}"
    echo -e "${BLUE}${BOLD}=====================================================${NC}"
    echo -e "  ${BOLD}1)${NC} Estado del servicio BIND9 en tiempo real"
    echo -e "  ${BOLD}2)${NC} Probar resolución DNS (nslookup)"
    echo -e "  ${BOLD}3)${NC} Probar conectividad (ping al dominio)"
    echo -e "  ${BOLD}4)${NC} Ver últimos logs de BIND9"
    echo -e "  ${BOLD}5)${NC} Volver al menú principal"
    read -rp "Selecciona una opción (1-5): " mon_opt

    case $mon_opt in
      1)
        echo -e "\n${BOLD}Estado del servicio named (BIND9):${NC}"
        systemctl status named --no-pager -l
        ;;
      2)
        read -rp "Dominio a resolver [reprobados.com]: " dom
        [[ -z "$dom" ]] && dom="reprobados.com"
        echo -e "\n${BOLD}── nslookup $dom 127.0.0.1 ──${NC}"
        nslookup "$dom" 127.0.0.1
        echo -e "\n${BOLD}── nslookup www.$dom 127.0.0.1 ──${NC}"
        nslookup "www.$dom" 127.0.0.1
        ;;
      3)
        read -rp "Dominio para ping [www.reprobados.com]: " dom
        [[ -z "$dom" ]] && dom="www.reprobados.com"
        echo -e "\n${BOLD}── ping -c 4 $dom (usando DNS local) ──${NC}"
        ping -c 4 "$dom" 2>/dev/null || \
          echo -e "${YELLOW}[INFO] El ping al nombre puede fallar si el cliente no está activo. La resolución DNS es lo relevante.${NC}"
        ;;
      4)
        echo -e "\n${BOLD}Últimas líneas de log de BIND9:${NC}"
        journalctl -u named -n 25 --no-pager
        ;;
      5) break ;;
      *) echo -e "${RED}Opción inválida.${NC}" ;;
    esac
  done
}

# ════════════════════════════════════════════════════════════════════════════════
# MENÚ PRINCIPAL
# ════════════════════════════════════════════════════════════════════════════════
main_menu() {
  # Verificar IP estática al inicio
  verificar_ip_estatica

  while true; do
    echo -e "\n${BLUE}${BOLD}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}     GESTOR DE SERVIDOR DNS - LINUX BASH (BIND9)     ${NC}"
    echo -e "${BLUE}${BOLD}=====================================================${NC}"
    echo -e "  ${BOLD}1)${NC} Instalación Idempotente (BIND9)"
    echo -e "  ${BOLD}2)${NC} Configurar Zona DNS (reprobados.com)"
    echo -e "  ${BOLD}3)${NC} Módulo de Monitoreo y Validación"
    echo -e "  ${BOLD}4)${NC} Salir"
    read -rp "Selecciona una opción (1-4): " opt

    case $opt in
      1) instalar_bind9 ;;
      2)
        if ! dpkg -l | grep -q "^ii.*bind9 "; then
          instalar_bind9
        fi
        configurar_dns
        ;;
      3) monitorear_dns ;;
      4) echo -e "\n¡Hasta luego!"; exit 0 ;;
      *) echo -e "${RED}Opción inválida.${NC}" ;;
    esac
  done
}

main_menu
