#!/usr/bin/env bash
# lib/bash/orquestacion.sh
# Funciones para orquestacion de microservicios - Tarea 11
# Uso: source "${LIB_DIR}/orquestacion.sh"

TAREA11_DIR="${TAREA11_DIR:-}"

resolver_tarea11_dir() {
  if [ -n "$TAREA11_DIR" ] && [ -f "$TAREA11_DIR/docker-compose.yml" ]; then
    echo "$TAREA11_DIR"
    return 0
  fi
  local candidates=(
    "$(pwd)/tarea11"
    "/mnt/sysadmin/tarea11"
  )
  for c in "${candidates[@]}"; do
    if [ -f "$c/docker-compose.yml" ]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

desplegar_stack_tarea11() {
  local dir
  dir=$(resolver_tarea11_dir) || { echo -e "${RED}[ERROR] No se encontro tarea11/docker-compose.yml${NC}"; return 1; }

  banner "DESPLIEGUE STACK - TAREA 11 (Microservicios)"
  cd "$dir"

  if [ ! -f .env ]; then
    echo -e "${YELLOW}[WARN] No existe .env — copiando desde .env.example${NC}"
    cp .env.example .env
  fi

  chmod +x scripts/*.sh 2>/dev/null || true

  echo -e "${BLUE}[INFO] Construyendo imagenes y levantando servicios...${NC}"
  docker compose build
  docker compose up -d

  echo -e "${GREEN}[OK] Stack Tarea 11 desplegado.${NC}"
  docker compose ps
  echo ""
  echo -e "${CYAN}Acceso publico:${NC}  http://localhost:${NGINX_PUBLIC_PORT:-80}"
  echo -e "${CYAN}pgAdmin (tunel):${NC} ssh -L 8080:127.0.0.1:${PGADMIN_HOST_PORT:-5050} user@servidor"
}

detener_stack_tarea11() {
  local dir
  dir=$(resolver_tarea11_dir) || return 1
  cd "$dir"
  docker compose down
  echo -e "${GREEN}[OK] Stack detenido (volumenes conservados).${NC}"
}

mostrar_estado_tarea11() {
  local dir
  dir=$(resolver_tarea11_dir) || return 1
  cd "$dir"

  banner "ESTADO STACK - TAREA 11"
  docker compose ps
  echo ""
  echo -e "${CYAN}--- Redes ---${NC}"
  docker network inspect red_publica --format 'red_publica: {{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "  red_publica: (no creada)"
  docker network inspect red_datos --format 'red_datos: {{range .IPAM.Config}}{{.Subnet}}{{end}} (internal)' 2>/dev/null || echo "  red_datos: (no creada)"
  echo ""
  echo -e "${CYAN}--- Volumen persistente ---${NC}"
  docker volume inspect tarea11_db_data --format '{{.Name}}: {{.Mountpoint}}' 2>/dev/null || echo "  (no creado)"
  echo ""
  echo -e "${CYAN}--- Puertos publicados ---${NC}"
  docker port tarea11_nginx 2>/dev/null || echo "  nginx: (no corriendo)"
  docker port tarea11_pgadmin 2>/dev/null || echo "  pgadmin: solo localhost"
  docker port tarea11_db 2>/dev/null || echo "  db: sin puertos (aislado)"
}

configurar_firewall_tarea11() {
  local dir
  dir=$(resolver_tarea11_dir) || return 1
  chmod +x "$dir/scripts/configurar_firewall.sh"
  bash "$dir/scripts/configurar_firewall.sh"
}

mostrar_tunel_ssh_tarea11() {
  local dir
  dir=$(resolver_tarea11_dir) || return 1
  chmod +x "$dir/scripts/tunel_ssh.sh"
  bash "$dir/scripts/tunel_ssh.sh"
}

ejecutar_pruebas_tarea11() {
  local dir
  dir=$(resolver_tarea11_dir) || return 1
  cd "$dir"
  chmod +x scripts/test_pruebas.sh
  bash scripts/test_pruebas.sh
}
