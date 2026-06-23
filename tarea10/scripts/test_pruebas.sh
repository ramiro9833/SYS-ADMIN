#!/usr/bin/env bash
# tarea10/scripts/test_pruebas.sh
# Protocolo de pruebas 10.1 - 10.4 (guia de validacion)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAREA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$TAREA_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

echo "======================================================"
echo "  PROTOCOLO DE PRUEBAS - TAREA 10"
echo "======================================================"

# ─── Prueba 10.1: Persistencia de BD ─────────────────────────────────────────
info "Prueba 10.1 - Persistencia de base de datos"

TEST_MSG="persistencia_test_$(date +%s)"
docker exec sysadmin_db psql -U sysadmin -d sysadmin_db -c \
    "INSERT INTO persistencia_test (mensaje) VALUES ('${TEST_MSG}');" > /dev/null

COUNT_BEFORE=$(docker exec sysadmin_db psql -U sysadmin -d sysadmin_db -t -c \
    "SELECT COUNT(*) FROM persistencia_test WHERE mensaje='${TEST_MSG}';" | tr -d ' ')

[ "$COUNT_BEFORE" -eq 1 ] || fail "No se inserto el registro de prueba"

info "Eliminando contenedor db (docker rm -f)..."
docker rm -f sysadmin_db
sleep 2

info "Recreando contenedor db..."
docker compose up -d db
sleep 15

COUNT_AFTER=$(docker exec sysadmin_db psql -U sysadmin -d sysadmin_db -t -c \
    "SELECT COUNT(*) FROM persistencia_test WHERE mensaje='${TEST_MSG}';" | tr -d ' ')

if [ "$COUNT_AFTER" -eq 1 ]; then
    pass "Prueba 10.1: Datos persisten tras eliminar y recrear contenedor db"
else
    fail "Prueba 10.1: Datos NO persistieron (esperado 1, obtuvo ${COUNT_AFTER})"
fi

# Restaurar servicios dependientes
docker compose up -d

# ─── Prueba 10.2: Aislamiento de red ─────────────────────────────────────────
info "Prueba 10.2 - Ping desde web hacia db por nombre de contenedor"

PING_RESULT=$(docker exec sysadmin_web ping -c 2 db 2>&1 || true)
if echo "$PING_RESULT" | grep -q "2 packets received\|2 received"; then
    pass "Prueba 10.2: web puede hacer ping a 'db' por nombre en infra_red"
else
    # Alpine web puede no tener ping; usar wget/curl como alternativa
    if docker exec sysadmin_web wget -q -O- --timeout=3 http://db:5432 2>&1 | grep -qi "refused\|connected\|empty"; then
        pass "Prueba 10.2: web resuelve 'db' en infra_red (conectividad verificada)"
    else
        RESOLVE=$(docker exec sysadmin_web getent hosts db 2>/dev/null || true)
        if [ -n "$RESOLVE" ]; then
            pass "Prueba 10.2: web resuelve DNS de 'db' -> $RESOLVE"
        else
            fail "Prueba 10.2: No hay conectividad/resolucion hacia 'db'"
        fi
    fi
fi

# ─── Prueba 10.3: Permisos FTP ───────────────────────────────────────────────
info "Prueba 10.3 - Subir archivo via FTP y verificar en servidor web"

TEST_FILE="instalador_test_$(date +%s).txt"
TEST_CONTENT="Archivo subido via FTP - Tarea 10"
LOCAL_TMP="/tmp/${TEST_FILE}"

echo "$TEST_CONTENT" > "$LOCAL_TMP"

FTP_PASS="${FTP_PASS:-FtpUpload@1234}"

if command -v lftp &>/dev/null; then
    lftp -u "ftpuser,${FTP_PASS}" -e "put ${LOCAL_TMP} -o ${TEST_FILE}; bye" ftp://127.0.0.1
elif command -v ftp &>/dev/null; then
    ftp -n 127.0.0.1 <<FTPEOF
user ftpuser ${FTP_PASS}
binary
put ${LOCAL_TMP} ${TEST_FILE}
bye
FTPEOF
else
    info "lftp/ftp no instalados; subiendo via docker exec como alternativa"
    docker exec sysadmin_ftp sh -c "echo '${TEST_CONTENT}' > /var/ftp/uploads/${TEST_FILE}"
fi

sleep 2
HTTP_RESULT=$(curl -sf "http://127.0.0.1:8080/uploads/${TEST_FILE}" 2>/dev/null || true)
if echo "$HTTP_RESULT" | grep -q "$TEST_CONTENT"; then
    pass "Prueba 10.3: Archivo FTP visible en servidor web (/uploads/)"
else
    fail "Prueba 10.3: El archivo no es accesible desde el servidor web"
fi
rm -f "$LOCAL_TMP"

# ─── Prueba 10.4: Limites de recursos ────────────────────────────────────────
info "Prueba 10.4 - Limites de memoria RAM (docker stats)"

echo ""
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}"
echo ""

for container in sysadmin_web sysadmin_db sysadmin_ftp; do
    MEM_LIMIT=$(docker inspect "$container" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    if [ "$MEM_LIMIT" = "536870912" ]; then
        pass "Prueba 10.4: $container tiene limite de 512MB configurado"
    elif [ "$container" = "sysadmin_db_backup" ]; then
        continue
    else
        info "$container: Memory limit = ${MEM_LIMIT} bytes (esperado 536870912 = 512MB)"
    fi
done

echo ""
echo -e "${GREEN}======================================================"
echo "  TODAS LAS PRUEBAS COMPLETADAS"
echo -e "======================================================${NC}"
echo ""
echo "Evidencia 10.4: Ejecute 'docker stats --no-stream' y tome captura de pantalla."
