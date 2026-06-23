#!/usr/bin/env bash
# tarea7/setup_ftp_repo.sh
# Prepara el repositorio FTP privado en el servidor con la estructura requerida por Tarea 7.
# Debe ejecutarse en el servidor FTP ANTES de usar el orquestador de instalación.
#
# Estructura resultante (dentro del home del usuario FTP):
#
#  /srv/ftp/usuarios/<FTP_USER>/
#    http/
#      Linux/
#        Apache/
#          apache2_<ver>.deb          (copiado automáticamente si existe)
#          apache2_<ver>.deb.sha256
#        Nginx/
#          nginx_<ver>.deb
#          nginx_<ver>.deb.sha256
#        Tomcat/
#          apache-tomcat-<ver>.tar.gz (copiado automáticamente si existe)
#          apache-tomcat-<ver>.tar.gz.sha256
#      Windows/
#        Apache/
#          apache_<ver>.zip
#          apache_<ver>.zip.sha256
#        Nginx/
#          nginx_<ver>.zip
#          nginx_<ver>.zip.sha256
#        IIS/
#          (placeholder .msi + sha256)
#
# NOTA CRÍTICA DE VSFTPD CHROOT:
#   El directorio raíz del usuario (/srv/ftp/usuarios/<user>) debe ser:
#     - Propiedad de root:root
#     - Permisos 755 (NO writable por el usuario)
#   La carpeta http/ dentro de él puede ser 755 root:root o 755 ftprepo:ftprepo.
#   El usuario de acceso FTP debe tener permiso de LECTURA en http/ (lectura, no escritura).
#   Si necesitas que pueda subir archivos, usa la subcarpeta 'privado/' (700 del usuario).

set -euo pipefail

# ─── Configuración ────────────────────────────────────────────────────────────
FTP_REPO_USER="${1:-ftprepo}"      # usuario FTP del repositorio (no interactivo)
FTP_REPO_PASS="${2:-Repo@1234}"    # contraseña (solo para crear el usuario)
FTP_BASE="/srv/ftp/usuarios"

# ─── Verificar root ───────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Ejecutar como root (sudo)."
    exit 1
fi

echo "======================================================="
echo "  CONFIGURADOR DE REPOSITORIO FTP - TAREA 7"
echo "======================================================="
echo "Usuario FTP de repositorio: ${FTP_REPO_USER}"
echo "Directorio base: ${FTP_BASE}/${FTP_REPO_USER}"
echo ""

# ─── Crear usuario FTP de repositorio (solo lectura del repo, sin shell) ─────
if ! id "$FTP_REPO_USER" &>/dev/null; then
    useradd -m -d "${FTP_BASE}/${FTP_REPO_USER}" -s /usr/sbin/nologin "$FTP_REPO_USER"
    echo "${FTP_REPO_USER}:${FTP_REPO_PASS}" | chpasswd
    echo "[OK] Usuario '${FTP_REPO_USER}' creado."
else
    echo "[INFO] Usuario '${FTP_REPO_USER}' ya existe."
fi

# Asegurar que /usr/sbin/nologin esté en /etc/shells (PAM lo requiere)
grep -q "/usr/sbin/nologin" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

# ─── Crear estructura de directorios ─────────────────────────────────────────
REPO_HOME="${FTP_BASE}/${FTP_REPO_USER}"

declare -a DIRS=(
    "${REPO_HOME}/http/Linux/Apache"
    "${REPO_HOME}/http/Linux/Nginx"
    "${REPO_HOME}/http/Linux/Tomcat"
    "${REPO_HOME}/http/Windows/Apache"
    "${REPO_HOME}/http/Windows/Nginx"
    "${REPO_HOME}/http/Windows/IIS"
    "${REPO_HOME}/privado"   # carpeta writable para el usuario
)

for d in "${DIRS[@]}"; do
    mkdir -p "$d"
done
echo "[OK] Estructura de carpetas creada."

# ─── Permisos correctos para vsftpd chroot ───────────────────────────────────
# La raíz del chroot DEBE ser root:root 755 (vsftpd exige que NO sea writable)
chown root:root "${REPO_HOME}"
chmod 755 "${REPO_HOME}"

# Las carpetas del repositorio son de root, legibles por todos
chown -R root:root "${REPO_HOME}/http"
chmod -R 755 "${REPO_HOME}/http"

# La carpeta privada sí es del usuario (puede subir archivos aquí)
chown -R "${FTP_REPO_USER}:${FTP_REPO_USER}" "${REPO_HOME}/privado"
chmod 700 "${REPO_HOME}/privado"

echo "[OK] Permisos de chroot configurados (raíz: root:root 755)."

# ─── Generar archivos de firma para binarios existentes ──────────────────────
generar_firma() {
    local archivo="$1"
    if [ -f "$archivo" ]; then
        sha256sum "$archivo" | awk '{print $1}' > "${archivo}.sha256"
        echo "[OK] Firma SHA256 generada: ${archivo}.sha256"
    fi
}

# Buscar binarios ya descargados en el sistema y copiarlos al repo
echo ""
echo "[INFO] Buscando binarios Tomcat existentes en el sistema..."
for tarball in $(find /tmp /root /home "${REPO_HOME}" -maxdepth 3 -name "apache-tomcat-*.tar.gz" 2>/dev/null | grep -v "${REPO_HOME}/http"); do
    ver=$(basename "$tarball" | grep -oP 'apache-tomcat-\K[0-9.]+(?=\.tar\.gz)')
    dest="${REPO_HOME}/http/Linux/Tomcat/apache-tomcat-${ver}.tar.gz"
    if [ ! -f "$dest" ]; then
        cp "$tarball" "$dest"
        chown root:root "$dest"
        chmod 644 "$dest"
        generar_firma "$dest"
        echo "[OK] Tomcat ${ver} añadido al repositorio FTP."
    fi
done

echo "[INFO] Buscando paquetes Apache2 existentes (deb)..."
for deb in $(find /var/cache/apt/archives /tmp -maxdepth 2 -name "apache2_*.deb" 2>/dev/null); do
    dest="${REPO_HOME}/http/Linux/Apache/$(basename "$deb")"
    if [ ! -f "$dest" ]; then
        cp "$deb" "$dest"
        chown root:root "$dest"
        chmod 644 "$dest"
        generar_firma "$dest"
        echo "[OK] Apache2 deb añadido al repositorio FTP."
    fi
done

echo "[INFO] Buscando paquetes Nginx existentes (deb)..."
for deb in $(find /var/cache/apt/archives /tmp -maxdepth 2 -name "nginx_*.deb" 2>/dev/null); do
    dest="${REPO_HOME}/http/Linux/Nginx/$(basename "$deb")"
    if [ ! -f "$dest" ]; then
        cp "$deb" "$dest"
        chown root:root "$dest"
        chmod 644 "$dest"
        generar_firma "$dest"
        echo "[OK] Nginx deb añadido al repositorio FTP."
    fi
done

# ─── Crear placeholder de ejemplo si las carpetas están vacías ───────────────
for dir in "${REPO_HOME}/http/Linux/Apache" \
           "${REPO_HOME}/http/Linux/Nginx" \
           "${REPO_HOME}/http/Linux/Tomcat" \
           "${REPO_HOME}/http/Windows/Apache" \
           "${REPO_HOME}/http/Windows/Nginx" \
           "${REPO_HOME}/http/Windows/IIS"; do

    svc=$(basename "$dir")
    os=$(basename "$(dirname "$dir")")

    # Solo crear placeholder si la carpeta está vacía
    if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        PLACEHOLDER="${dir}/COLOCA_AQUI_EL_INSTALADOR_${svc}_${os}.txt"
        cat > "$PLACEHOLDER" <<EOF
Coloca en este directorio el instalador de ${svc} para ${os}.
Ejemplo de nombres esperados:
  - ${svc,,}_2.4.deb        (Linux .deb)
  - ${svc,,}-*.tar.gz       (Linux tarball)
  - ${svc,,}_*.msi          (Windows MSI)
  - ${svc,,}-*.zip          (Windows ZIP)

Luego genera su firma SHA256:
  sha256sum <archivo> | awk '{print \$1}' > <archivo>.sha256
EOF
        chown root:root "$PLACEHOLDER"
        chmod 644 "$PLACEHOLDER"
        echo "[INFO] Placeholder creado en: ${dir}"
    fi
done

# ─── Verificar que vsftpd está configurado correctamente ─────────────────────
echo ""
echo "======================================================="
echo "  VERIFICANDO VSFTPD"
echo "======================================================="

if ! systemctl is-active --quiet vsftpd; then
    echo "[WARN] vsftpd no está corriendo. Iniciando..."
    systemctl enable vsftpd
    systemctl start vsftpd
fi

if systemctl is-active --quiet vsftpd; then
    echo "[OK] vsftpd está activo."
    # Probar conexión local
    if command -v curl &>/dev/null; then
        local_test=$(curl -s --connect-timeout 5 -l \
            -u "${FTP_REPO_USER}:${FTP_REPO_PASS}" \
            "ftp://127.0.0.1/" 2>&1)
        if [ $? -eq 0 ]; then
            echo "[OK] Login FTP de '${FTP_REPO_USER}' exitoso. Contenido del home:"
            echo "$local_test" | sed 's/^/  /'
        else
            echo "[WARN] Prueba de login FTP falló. Revisa /var/log/vsftpd.log"
            echo "       Detalle: $local_test"
        fi
    fi
fi

echo ""
echo "======================================================="
echo "  RESUMEN"
echo "======================================================="
echo "  Usuario FTP repositorio : ${FTP_REPO_USER}"
echo "  Contraseña              : ${FTP_REPO_PASS}"
echo "  Ruta del repositorio    : ${REPO_HOME}/http/"
echo ""
echo "  Para usar en el orquestador:"
echo "    IP del servidor FTP  : $(hostname -I | awk '{print $1}')"
echo "    Usuario FTP          : ${FTP_REPO_USER}"
echo "    Contraseña FTP       : ${FTP_REPO_PASS}"
echo ""
echo "  Estructura del repositorio:"
find "${REPO_HOME}/http" -type d | sort | sed "s|${REPO_HOME}/http|  /http|"
echo "======================================================="
