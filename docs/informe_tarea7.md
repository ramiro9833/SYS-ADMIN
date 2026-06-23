# Informe Técnico: Tarea 7 - Infraestructura de Despliegue Seguro e Instalación Híbrida (FTP/Web)

Este informe detalla el diseño, la implementación y la validación de un sistema de despliegue seguro que integra una PKI local autofirmada (SSL/TLS) para 8 servicios de red y un orquestador híbrido de instalación con navegación FTP dinámica y firma de integridad por hashes (SHA256/MD5).

---

## 1. Mapa de la Arquitectura de Software

La arquitectura modular se extiende integrando bibliotecas específicas para el cliente FTP y el motor criptográfico SSL:

```
SYS-ADMIN/
├── lib/
│   ├── bash/
│   │   ├── comunes.sh         # Utilidades globales Linux
│   │   ├── http.sh            # Aprovisionamiento HTTP Linux (Web)
│   │   ├── ftp_client.sh      # [NUEVO] Cliente FTP interactivo, descargas y hashes Linux
│   │   └── ssl.sh             # [NUEVO] PKI y configuraciones SSL para 4 servidores Linux
│   └── powershell/
│       ├── Comunes.ps1        # Utilidades globales Windows
│       ├── HTTP.ps1           # Aprovisionamiento HTTP Windows (Web)
│       ├── FTPClient.ps1      # [NUEVO] Cliente FTP FtpWebRequest y hashes Windows
│       └── SSL.ps1            # [NUEVO] PKI y configuraciones SSL para 4 servidores Windows
├── tarea7/
│   ├── tarea7.sh              # [NUEVO] Orquestador de instalación e infraestructura segura Linux
│   └── tarea7.ps1             # [NUEVO] Orquestador de instalación e infraestructura segura Windows
└── docs/
    └── informe_tarea7.md      # Este reporte técnico
```

---

## 2. Orquestación e Instalación Híbrida (Web/FTP)

El operador puede decidir instalar paquetes a través de repositorios públicos (Web) o mediante un repositorio local FTP de almacenamiento privado (Práctica 5).

### Navegación y Descarga no Interactiva:
* **Linux (Bash):** Uso de `curl -s -l` para conectarse y listar únicamente los nombres de archivos/directorios. Se parsea el listado para presentar al usuario menús navegables y dinámicos según el sistema operativo actual.
* **Windows (PowerShell):** Uso de `[System.Net.FtpWebRequest]` con el método `ListDirectory` para obtener de forma limpia los nombres en el servidor sin necesidad de utilidades de terceros.

---

## 3. Validación de Integridad (SHA256/MD5)

Antes de ejecutar cualquier instalador descargado del repositorio FTP, el script realiza una comprobación matemática de hash para garantizar que el binario no está corrupto o alterado:
1. El script descarga el binario (ej. `tomcat.tar.gz`) y busca en la misma ruta su firma complementaria (`tomcat.tar.gz.sha256` o `.md5`).
2. Calcula localmente la firma del archivo utilizando:
   * **Linux:** `sha256sum` o `md5sum`.
   * **Windows:** `Get-FileHash -Algorithm SHA256` o `MD5`.
3. Compara ambas cadenas hexadecimales. Si los hashes coinciden, se inicia la instalación silenciosa. En caso contrario, el archivo se elimina del disco duro de inmediato y se aborta el despliegue con un error crítico.

---

## 4. PKI y Canal SSL/TLS en 8 Servidores (`www.reprobados.com`)

Se genera dinámicamente un certificado autofirmado para el dominio `www.reprobados.com` y se distribuye e implanta en los 8 servicios de red:

### Servidores en Linux (Lubuntu)
1. **Apache:** Habilitación de `mod_ssl`/`mod_rewrite`. Configuración de redirección 301 en puerto 80 hacia `https://www.reprobados.com` y cifrado en puerto 443.
2. **Nginx:** Bloques `server` independientes para puerto 80 (redirección permanente) y puerto 443 con directivas `ssl_certificate`.
3. **Tomcat:** Conversión del certificado y llave a almacén PKCS12 (`.p12`). Configuración del conector HTTPS en puerto 8443 en `server.xml` y redirección automática mediante restricciones de seguridad en `web.xml`.
4. **vsftpd (FTPS):** Configuración de `ssl_enable=YES` con transferencia y login TLS obligatorio (`force_local_data_ssl=YES`).

### Servidores en Windows (Windows Server 2022)
1. **IIS:** Creación e importación del certificado en el almacén local de Windows (`Cert:\LocalMachine\My`). Asignación del enlace SSL al puerto 443 mediante `netsh http` e inyección de reglas de redirección nativas HSTS en `web.config` usando el módulo URL Rewrite.
2. **Apache Windows:** Conversión de certificados a PEM utilizando el binario `openssl.exe` incluido en Apache. Modificación del archivo `httpd-ssl.conf` y redirección en `httpd.conf` en base al puerto activo.
3. **Nginx Windows:** Modificación de `nginx.conf` habilitando `listen 443 ssl` y configurando las cabeceras de hardening y rutas relativas a los certificados PEM.
4. **IIS-FTP (FTPS):** Mapeo de la huella del certificado (`Thumbprint`) al servidor FTP y activación de la regla SSL obligatoria para canales de control y de datos en IIS.

---

## 5. Guía de Ejecución y Pruebas

### Ejecución de los Orquestadores (vía SSH)

* **En Linux Server (Lubuntu):**
  ```bash
  sudo ./tarea7/tarea7.sh
  ```
* **En Windows Server 2022:**
  ```powershell
  powershell -ExecutionPolicy Bypass -File Z:\tarea7\tarea7.ps1
  ```

### Pruebas de Validación desde el Cliente:
1. **Prueba de Redirección HSTS y HTTPS:**
   ```bash
   curl -k -Iv https://www.reprobados.com
   ```
2. **Prueba de FTP Seguro (FTPS):**
   ```bash
   curl --ftp-ssl -k -u ftpuser:contraseña ftp://192.168.100.10/
   ```
   *(La terminal debe reportar el saludo y la transferencia encriptada TLSv1.2/TLSv1.3)*
3. **Prueba de Integridad de Hashes:** Al descargar paquetes vía FTP, el menú muestra visualmente la descarga del `.sha256` y la coincidencia de hashes con estado `[OK]`.

---

## 6. Correcciones Aplicadas (Bugs Identificados y Solucionados)

### Bug 1 — `ftp_client.sh`: Stdout contaminado (Crítico)

**Síntoma:** `binario=$(descargar_desde_ftp "Linux")` capturaba todos los `echo` de la función junto con la ruta final del binario, resultando en un string multi-línea en lugar de una ruta válida.

**Corrección:** Todos los mensajes de log redirigidos a `stderr` (`>&2`). Solo la ruta del archivo va al `stdout`.

```bash
echo -e "\n[INFO] Conectando..." >&2   # mensajes → stderr
echo "$local_binario"                  # único valor → stdout (capturado por $())
```

### Bug 2 — `ftp.sh`: Usuarios de vsftpd no podían hacer login (Error 500)

**Síntoma:** vsftpd respondía `500 OOPS: refusing to run with writable root inside chroot()`.

**Causa:** Con `chroot_local_user=YES`, vsftpd exige que el directorio raíz del chroot sea `root:root 755`. El script tenía `allow_writeable_chroot=YES` que solo funciona en vsftpd < 3.0.

**Corrección:**
```bash
# Raíz del chroot: siempre root:root 755
chown root:root "/srv/ftp/usuarios/$username"
chmod 755 "/srv/ftp/usuarios/$username"
# Subdirectorio de escritura del usuario
chmod 700 "/srv/ftp/usuarios/$username/privado"
```

### Bug 3 — `ftp_client.sh`: `curl -l` puede devolver paths completos

**Síntoma:** Algunos modos de vsftpd devuelven `/http/Linux/Apache` en lugar de solo `Apache`. Las rutas de descarga se duplicaban.

**Corrección:** Se aplica `basename` a cada línea del listado antes de usarla.

### Bug 4 — `FTPClient.ps1`: `.Length` falla en array de un elemento

**Síntoma (Windows):** Con 1 solo elemento, PowerShell devuelve `[string]` en vez de `[string[]]`. `.Length` retorna la longitud del texto (caracteres), no 1.

**Corrección:** Forzar tipo array con `@()` y usar `.Count`:
```powershell
$servicios = @(Listar-Directorio-FTP-Win -Ruta "http/$OSTarget/")
if ($servicios.Count -eq 0) { ... }
```

### Bug 5 — `FTPClient.ps1`: `-ForegroundColor Warning` inválido

**Corrección:** Cambiado a `-ForegroundColor Yellow`.

### Nuevo: `tarea7/setup_ftp_repo.sh`

Script de preparación del servidor FTP que crea la estructura correcta del repositorio y configura los permisos de chroot. Ejecutar en el servidor FTP antes de usar el orquestador:

```bash
sudo ./tarea7/setup_ftp_repo.sh ftprepo MiPass123
```
