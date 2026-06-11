#!/usr/bin/env bash
# lib/bash/red.sh
# Funciones de configuración de red reutilizables.
# Uso: source ./red.sh  (requiere comunes.sh cargado previamente)

# ─── Verificar IP estática en la interfaz interna ────────────────────────────
verificar_ip_estatica() {
  echo -e "\n${BLUE}[CHECK] Verificando IP estática en la interfaz interna...${NC}"

  local iface
  iface=$(ip -o -4 addr show | awk '{print $2}' | grep -v lo | tail -1)

  local ip_actual
  ip_actual=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

  local es_estatica=false
  if grep -rq "dhcp4: no" /etc/netplan/ 2>/dev/null; then
    es_estatica=true
  fi

  if $es_estatica && [[ -n "$ip_actual" ]]; then
    echo -e "${GREEN}[OK] IP estática detectada: ${BOLD}$ip_actual${NC} en ${BOLD}$iface${NC}"
    SERVER_IP="$ip_actual"
    SERVER_IFACE="$iface"
  else
    echo -e "${YELLOW}[AVISO] No se detectó IP estática. Configurando...${NC}"
    configurar_ip_estatica "$iface"
  fi
}

# ─── Configurar IP estática en Netplan ───────────────────────────────────────
configurar_ip_estatica() {
  local iface="${1:-enp0s8}"
  banner "CONFIGURACIÓN DE IP ESTÁTICA"

  local ip_nueva
  ip_nueva=$(leer_ip "IP estática para este servidor" "192.168.100.10")
  local gateway
  gateway=$(leer_ip "Puerta de enlace (Gateway)" "192.168.100.1")

  local iface_nat
  iface_nat=$(ip route | awk '/default/ {print $5}' | head -1)
  [[ -z "$iface_nat" ]] && iface_nat="enp0s3"

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
