#!/usr/bin/env bash
# lib/bash/docker.sh
# Funciones para despliegue de contenedores Docker - Tarea 10
# Uso: source "${LIB_DIR}/docker.sh"

TAREA10_DIR="${TAREA10_DIR:-}"

# ─── Verificar que Docker y Compose estan disponibles ────────────────────────
verificar_docker() {
  if ! command -v docker &>/dev/null; then
    echo -e "${RED}[ERROR] Docker no esta instalado.${NC}"
    echo -e "${YELLOW}Instale con: sudo apt-get install -y docker.io docker-compose-v2${NC}"
    return 1
  fi
  if ! docker info &>/dev/null; then
    echo -e "${RED}[ERROR] Docker no esta en ejecucion o requiere permisos sudo.${NC}"
    return 1
  fi
  echo -e "${GREEN}[OK] Docker disponible: $(docker --version)${NC}"
  docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
  return 0
}

# ─── Resolver directorio de Tarea 10 ─────────────────────────────────────────
resolver_tarea10_dir() {
  if [ -n "$TAREA10_DIR" ] && [ -f "$TAREA10_DIR/docker-compose.yml" ]; then
    echo "$TAREA10_DIR"
    return 0
  fi
  local candidates=(
    "$(cd "$(dirname "${BASH_SOURCE[1]}")/../tarea10" 2>/dev/null && pwd)"
    "$(pwd)/tarea10"
    "/mnt/sysadmin/tarea10"
  )
  for c in "${candidates[@]}"; do
    if [ -f "$c/docker-compose.yml" ]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

# ─── Desplegar stack completo ─────────────────────────────────────────────────
desplegar_stack_tarea10() {
  local dir
  dir=$(resolver_tarea10_dir) || { echo -e "${RED}[ERROR] No se encontro tarea10/docker-compose.yml${NC}"; return 1; }

  banner "DESPLIEGUE STACK DOCKER - TAREA 10"
  cd "$dir"

  mkdir -p backups
  chmod +x scripts/*.sh 2>/dev/null || true

  echo -e "${BLUE}[INFO] Construyendo imagenes y levantando servicios...${NC}"
  docker compose build --no-cache
  docker compose up -d

  echo -e "${GREEN}[OK] Stack desplegado.${NC}"
  echo ""
  docker compose ps
  echo ""
  echo -e "${CYAN}Servicios:${NC}"
  echo "  Web:  http://localhost:8080"
  echo "  FTP:  ftp://localhost:21 (usuario: ftpuser)"
  echo "  DB:   sysadmin_db (red interna infra_red)"
}

# ─── Detener stack ────────────────────────────────────────────────────────────
detener_stack_tarea10() {
  local dir
  dir=$(resolver_tarea10_dir) || return 1
  cd "$dir"
  docker compose down
  echo -e "${GREEN}[OK] Stack detenido.${NC}"
}

# ─── Mostrar estado del stack ─────────────────────────────────────────────────
mostrar_estado_stack() {
  local dir
  dir=$(resolver_tarea10_dir) || return 1
  cd "$dir"

  banner "ESTADO DEL STACK - TAREA 10"
  docker compose ps
  echo ""
  echo -e "${CYAN}--- Red infra_red ---${NC}"
  docker network inspect infra_red --format '{{range .IPAM.Config}}Subnet: {{.Subnet}}{{end}}' 2>/dev/null || echo "  (red no creada)"
  echo ""
  echo -e "${CYAN}--- Volumenes ---${NC}"
  docker volume ls --filter name=db_data --filter name=web_content
  echo ""
  echo -e "${CYAN}--- Ultimos respaldos ---${NC}"
  ls -lh backups/*.sql.gz 2>/dev/null | tail -5 || echo "  (sin respaldos aun)"
}

# ─── Limites de recursos (Prueba 10.4) ───────────────────────────────────────
mostrar_stats_contenedores() {
  banner "LIMITES DE RECURSOS - docker stats (Prueba 10.4)"
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
  echo ""
  echo -e "${CYAN}--- Limites configurados (inspect) ---${NC}"
  for c in sysadmin_web sysadmin_db sysadmin_ftp; do
    if docker inspect "$c" &>/dev/null; then
      local mem cpu
      mem=$(docker inspect "$c" --format '{{.HostConfig.Memory}}')
      cpu=$(docker inspect "$c" --format '{{.HostConfig.NanoCpus}}')
      local mem_mb=$((mem / 1024 / 1024))
      local cpu_cores
      cpu_cores=$(echo "scale=2; $cpu / 1000000000" | bc 2>/dev/null || echo "N/A")
      echo "  $c: RAM=${mem_mb}MB | CPU=${cpu_cores} cores"
    fi
  done
}

# ─── Ejecutar protocolo de pruebas ───────────────────────────────────────────
ejecutar_pruebas_tarea10() {
  local dir
  dir=$(resolver_tarea10_dir) || return 1
  cd "$dir"
  chmod +x scripts/test_pruebas.sh
  bash scripts/test_pruebas.sh
}

# ─── Respaldo manual de BD ─────────────────────────────────────────────────────
respaldo_manual_bd() {
  local dir
  dir=$(resolver_tarea10_dir) || return 1
  chmod +x "$dir/scripts/backup_db.sh"
  bash "$dir/scripts/backup_db.sh"
}
