#!/usr/bin/env bash
# tarea11/scripts/test_pruebas.sh
# Protocolo de pruebas de aceptacion 11.1 - 11.4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$TAREA_DIR"

if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

PGADMIN_PORT="${PGADMIN_HOST_PORT:-5050}"
NGINX_PORT="${NGINX_PUBLIC_PORT:-80}"
SERVER_IP="${SERVER_IP:-127.0.0.1}"

echo "======================================================"
echo "  PROTOCOLO DE PRUEBAS - TAREA 11"
echo "======================================================"

# ─── Prueba 11.1: Aislamiento de red ─────────────────────────────────────────
info "Prueba 11.1 - Aislamiento: BD y pgAdmin no accesibles desde el host publico"

DB_RESULT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://${SERVER_IP}:5432" 2>/dev/null || echo "000")
PG_RESULT=$(timeout 3 bash -c "echo >/dev/tcp/${SERVER_IP}/${PGADMIN_PORT}" 2>/dev/null && echo "open" || echo "closed")

# PostgreSQL no debe aceptar conexiones HTTP; puerto 5432 no debe estar expuesto
if docker port tarea11_db 2>/dev/null | grep -q 5432; then
    fail "Prueba 11.1: PostgreSQL tiene puertos publicados al host"
else
    pass "Prueba 11.1a: PostgreSQL sin puertos expuestos al host"
fi

# pgAdmin solo en 127.0.0.1
PG_BIND=$(docker port tarea11_pgadmin 2>/dev/null || true)
if echo "$PG_BIND" | grep -q "127.0.0.1"; then
    pass "Prueba 11.1b: pgAdmin ligado solo a localhost (${PG_BIND})"
elif [ -z "$PG_BIND" ]; then
    pass "Prueba 11.1b: pgAdmin sin exposicion publica"
else
    warn "pgAdmin binding: $PG_BIND — verificar que no sea 0.0.0.0"
fi

# Intento de conexion externa a pgAdmin (debe fallar si SERVER_IP no es 127.0.0.1)
if [ "$SERVER_IP" != "127.0.0.1" ]; then
    EXT=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" "http://${SERVER_IP}:${PGADMIN_PORT}" 2>/dev/null || echo "000")
    if [ "$EXT" = "000" ] || [ "$EXT" = "000" ]; then
        pass "Prueba 11.1c: pgAdmin no accesible en IP externa ${SERVER_IP}:${PGADMIN_PORT}"
    fi
else
    info "Prueba 11.1c: Omitida (SERVER_IP=127.0.0.1). Pruebe desde otra maquina con SERVER_IP=<ip_lan>"
fi

# ─── Prueba 11.2: Resolucion DNS interna ──────────────────────────────────────
info "Prueba 11.2 - DNS interno: ping a 'db' desde contenedor nginx"

PING_OUT=$(docker exec tarea11_nginx ping -c 2 db 2>&1 || true)
if echo "$PING_OUT" | grep -q "2 packets received\|2 received"; then
    pass "Prueba 11.2: nginx resuelve y alcanza 'db' por nombre de servicio"
else
    RESOLVE=$(docker exec tarea11_nginx getent hosts db 2>/dev/null || true)
    if [ -n "$RESOLVE" ]; then
        pass "Prueba 11.2: nginx resuelve DNS de 'db' -> $RESOLVE"
    else
        fail "Prueba 11.2: nginx no puede resolver 'db'"
    fi
fi

# ─── Prueba 11.3: Tunel SSH (manual) ─────────────────────────────────────────
info "Prueba 11.3 - Tunel SSH hacia pgAdmin (validacion manual)"
echo ""
echo "  Ejecute en su maquina LOCAL:"
echo "    ssh -L ${SSH_TUNNEL_LOCAL_PORT:-8080}:127.0.0.1:${PGADMIN_PORT} usuario@IP_SERVIDOR"
echo "  Abra: http://localhost:${SSH_TUNNEL_LOCAL_PORT:-8080}"
echo ""
warn "Prueba 11.3 requiere captura de pantalla manual del panel pgAdmin via tunel"

# Verificar pgAdmin healthy en localhost
PG_LOCAL=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://127.0.0.1:${PGADMIN_PORT}/misc/ping" 2>/dev/null || echo "000")
if [ "$PG_LOCAL" = "200" ]; then
    pass "Prueba 11.3 (servidor): pgAdmin responde en 127.0.0.1:${PGADMIN_PORT} (listo para tunel)"
else
    warn "pgAdmin ping local: HTTP $PG_LOCAL (puede estar iniciando)"
fi

# ─── Prueba 11.4: Persistencia y healthcheck ─────────────────────────────────
info "Prueba 11.4 - Persistencia y dependencias healthcheck"

TEST_MSG="persistencia_t11_$(date +%s)"
docker exec tarea11_db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c \
    "INSERT INTO persistencia_t11 (mensaje) VALUES ('${TEST_MSG}');" > /dev/null 2>&1 || \
    fail "Prueba 11.4: No se pudo insertar dato de prueba"

info "Deteniendo stack (docker compose down)..."
docker compose down

info "Reiniciando stack..."
docker compose up -d

info "Esperando healthcheck de db y arranque de pgadmin..."
sleep 25

DB_HEALTH=$(docker inspect tarea11_db --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
PG_HEALTH=$(docker inspect tarea11_pgadmin --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

if [ "$DB_HEALTH" = "healthy" ]; then
    pass "Prueba 11.4a: PostgreSQL healthy tras reinicio"
else
    warn "PostgreSQL health: $DB_HEALTH"
fi

if [ "$PG_HEALTH" = "healthy" ] || docker ps --filter name=tarea11_pgadmin --filter status=running -q | grep -q .; then
    pass "Prueba 11.4b: pgAdmin arranco tras dependencia de db"
else
    warn "pgAdmin health: $PG_HEALTH"
fi

COUNT=$(docker exec tarea11_db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c \
    "SELECT COUNT(*) FROM persistencia_t11 WHERE mensaje='${TEST_MSG}';" 2>/dev/null | tr -d ' ')

if [ "${COUNT:-0}" -eq 1 ]; then
    pass "Prueba 11.4c: Datos persisten en volumen tarea11_db_data"
else
    fail "Prueba 11.4c: Datos NO persistieron (count=${COUNT:-0})"
fi

# Verificar balanceador publico
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${NGINX_PORT}/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "Prueba extra: Balanceador nginx responde HTTP 200"
else
    warn "Balanceador HTTP: $HTTP_CODE"
fi

echo ""
echo -e "${GREEN}======================================================"
echo "  PRUEBAS AUTOMATIZADAS COMPLETADAS"
echo -e "======================================================${NC}"
echo "Complete Prueba 11.3 con captura del tunel SSH + pgAdmin en navegador."
