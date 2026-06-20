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
