#!/usr/bin/env bash
# lib/bash/correo.sh
# Funciones para infraestructura de correo - Tarea 12
# Uso: source "${LIB_DIR}/correo.sh"

TAREA12_DIR="${TAREA12_DIR:-}"

resolver_tarea12_dir() {
  if [ -n "$TAREA12_DIR" ] && [ -f "$TAREA12_DIR/docker-compose.yml" ]; then
    echo "$TAREA12_DIR"
    return 0
  fi
  local candidates=(
    "$(pwd)/tarea12"
    "/mnt/sysadmin/tarea12"
  )
  for c in "${candidates[@]}"; do
    if [ -f "$c/docker-compose.yml" ]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

desplegar_stack_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || { echo -e "${RED}[ERROR] No se encontro tarea12/docker-compose.yml${NC}"; return 1; }

  banner "DESPLIEGUE STACK - TAREA 12 (Correo + Webmail)"
  cd "$dir"

  if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${YELLOW}[WARN] Creado .env desde plantilla — revise credenciales.${NC}"
  fi

  chmod +x scripts/*.sh 2>/dev/null || true
  mkdir -p certs backups docker-data/dms/config

  if [ ! -f certs/cert.pem ]; then
    bash scripts/generar_certificados.sh
  fi

  echo -e "${BLUE}[INFO] Construyendo y levantando servicios...${NC}"
  docker compose build
  docker compose up -d

  echo -e "${BLUE}[INFO] Esperando mailserver (60s)...${NC}"
  sleep 60

  bash scripts/crear_cuentas.sh

  echo -e "${GREEN}[OK] Stack Tarea 12 desplegado.${NC}"
  docker compose ps
  echo ""
  echo -e "${CYAN}Webmail HTTPS:${NC} https://localhost:${WEBMAIL_HTTPS_PORT:-443}"
  echo -e "${CYAN}IMAP:${NC}         ${MAIL_HOSTNAME:-mail.reprobados.com}:${IMAPS_PORT:-993}"
  echo -e "${CYAN}SMTP:${NC}         ${MAIL_HOSTNAME:-mail.reprobados.com}:${SUBMISSION_PORT:-587}"
}

detener_stack_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  cd "$dir"
  docker compose down
  echo -e "${GREEN}[OK] Stack detenido (volumenes conservados).${NC}"
}

mostrar_estado_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  cd "$dir"

  banner "ESTADO STACK - TAREA 12"
  docker compose ps
  echo ""
  echo -e "${CYAN}--- Volumenes ---${NC}"
  docker volume ls --filter name=mail_data --filter name=mail_logs --filter name=roundcube_db_data
  echo ""
  echo -e "${CYAN}--- Cuentas de correo ---${NC}"
  docker exec tarea12_mailserver setup email list 2>/dev/null || echo "  (mailserver no activo)"
  echo ""
  echo -e "${CYAN}--- Ultimos respaldos ---${NC}"
  ls -lh backups/mail_data_*.tar.gz 2>/dev/null | tail -3 || echo "  (sin respaldos)"
}

generar_certificados_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  bash "$dir/scripts/generar_certificados.sh"
}

crear_cuentas_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  bash "$dir/scripts/crear_cuentas.sh"
}

mostrar_dkim_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  bash "$dir/scripts/mostrar_dkim.sh"
}

respaldo_manual_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  bash "$dir/scripts/backup_mail.sh"
}

restaurar_respaldo_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  read -rp "Archivo de respaldo: " archivo
  bash "$dir/scripts/restore_mail.sh" "$archivo"
}

ejecutar_pruebas_tarea12() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  bash "$dir/scripts/test_pruebas.sh"
}

ver_logs_correo() {
  local dir
  dir=$(resolver_tarea12_dir) || return 1
  banner "LOGS DE AUDITORIA - /var/log/mail"
  docker exec tarea12_mailserver tail -50 /var/log/mail/mail.log 2>/dev/null || \
  docker exec tarea12_mailserver tail -50 /var/log/mail.log 2>/dev/null || \
  echo "[INFO] Busque logs en volumen mail_logs"
}
