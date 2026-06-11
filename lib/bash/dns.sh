#!/usr/bin/env bash
# lib/bash/dns.sh
# Funciones de instalación, configuración y monitoreo de BIND9.
# Uso: source ./dns.sh  (requiere comunes.sh y red.sh cargados previamente)

instalar_bind9() {
  banner "INSTALACIÓN BIND9"
  if systemctl is-active --quiet named 2>/dev/null || dpkg -l | grep -q "^ii.*bind9 "; then
    echo -e "${GREEN}[INFO] BIND9 ya está instalado y activo.${NC}"
    systemctl status named --no-pager | head -5
    return 0
  fi
  apt-get update -y -qq
  instalar_paquete "bind9"
  instalar_paquete "bind9utils"
  instalar_paquete "bind9-doc"
  instalar_paquete "dnsutils"
  echo -e "${GREEN}[OK] BIND9 y utilidades instaladas.${NC}"
}

configurar_dns() {
  banner "CONFIGURACIÓN DE ZONA DNS"
  local NS_IP="${SERVER_IP:-192.168.100.10}"

  read -rp "Dominio a configurar [reprobados.com]: " DOMINIO
  [[ -z "$DOMINIO" ]] && DOMINIO="reprobados.com"

  local CLIENT_IP
  CLIENT_IP=$(leer_ip "IP del nodo cliente (registro A)" "192.168.100.30")

  local SERIAL; SERIAL=$(date +%Y%m%d%H)
  local ZONE_FILE="/var/cache/bind/db.${DOMINIO}"
  local NAMED_LOCAL="/etc/bind/named.conf.local"

  echo -e "${CYAN}Dominio: $DOMINIO | IP Cliente: $CLIENT_IP | NS: $NS_IP${NC}"
  read -rp "¿Confirmar? [s/N]: " confirm
  [[ ! "$confirm" =~ ^[sS]$ ]] && echo "Cancelado." && return

  # Respaldo
  cp "$NAMED_LOCAL" "${NAMED_LOCAL}.bak.$(date +%s)" 2>/dev/null || true

  # Eliminar zona anterior si existe
  if grep -q "\"${DOMINIO}\"" "$NAMED_LOCAL" 2>/dev/null; then
    sed -i "/zone \"${DOMINIO}\"/,/^};/d" "$NAMED_LOCAL"
  fi

  # Agregar nueva entrada de zona
  cat >> "$NAMED_LOCAL" <<EOF

zone "${DOMINIO}" {
    type master;
    file "${ZONE_FILE}";
    allow-query { any; };
};
EOF

  # Generar archivo de zona
  cat > "$ZONE_FILE" <<EOF
;
; Zona DNS para: ${DOMINIO}
; Generado: $(date)
;
\$TTL 86400
@   IN  SOA ns1.${DOMINIO}. admin.${DOMINIO}. (
            ${SERIAL} ; Serial
            3600      ; Refresh
            1800      ; Retry
            604800    ; Expire
            86400 )   ; Negative TTL

@   IN  NS  ns1.${DOMINIO}.
ns1 IN  A   ${NS_IP}
@   IN  A   ${CLIENT_IP}
www IN  A   ${CLIENT_IP}
EOF

  chown bind:bind "$ZONE_FILE"
  chmod 644 "$ZONE_FILE"

  named-checkconf  && echo -e "${GREEN}[OK] named.conf: VÁLIDO.${NC}"
  named-checkzone "$DOMINIO" "$ZONE_FILE" && echo -e "${GREEN}[OK] Zona: VÁLIDA.${NC}"

  systemctl restart named
  sleep 2
  verificar_servicio named
}

monitorear_dns() {
  while true; do
    banner "MÓDULO DE MONITOREO DNS"
    echo -e "  ${BOLD}1)${NC} Estado del servicio BIND9"
    echo -e "  ${BOLD}2)${NC} Probar resolución DNS (nslookup)"
    echo -e "  ${BOLD}3)${NC} Ver logs de BIND9"
    echo -e "  ${BOLD}4)${NC} Volver"
    read -rp "Opción (1-4): " opt
    case $opt in
      1) systemctl status named --no-pager ;;
      2)
        read -rp "Dominio [reprobados.com]: " dom
        [[ -z "$dom" ]] && dom="reprobados.com"
        nslookup "$dom" 127.0.0.1
        nslookup "www.$dom" 127.0.0.1
        ;;
      3) journalctl -u named -n 20 --no-pager ;;
      4) break ;;
      *) echo -e "${RED}Opción inválida.${NC}" ;;
    esac
  done
}
