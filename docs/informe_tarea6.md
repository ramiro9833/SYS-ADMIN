# Informe Técnico: Tarea 6 - Automatización de Despliegue de Servicios HTTP Multi-Versión

Este informe detalla la implementación modular y la automatización para el aprovisionamiento, hardening y despliegue dinámico de servidores HTTP en entornos Linux (Lubuntu) y Windows Server 2022. La solución permite la selección dinámica de versiones, asignación de puertos personalizados, seguridad mediante cabeceras restrictivas y aislamiento de cuentas de ejecución.

---

## 1. Mapa de la Arquitectura de Software

La estructura modular del repositorio separa la interfaz de control (orquestadores) de los motores funcionales de instalación (bibliotecas):

```
SYS-ADMIN/
├── lib/
│   ├── bash/
│   │   ├── comunes.sh         # Funciones comunes compartidas
│   │   └── http.sh            # [NUEVO] Lógica HTTP Linux (Apache, Nginx, Tomcat, hardening, firewall)
│   └── powershell/
│       ├── Comunes.ps1        # Funciones comunes de red y administrador Windows
│       └── HTTP.ps1           # [NUEVO] Lógica HTTP Windows (IIS, Apache, Nginx, hardening, firewall)
├── tarea6/
│   ├── tarea6.sh              # [NUEVO] Orquestador / Menú interactivo Linux
│   └── tarea6.ps1             # [NUEVO] Orquestador / Menú interactivo Windows
└── docs/
    └── informe_tarea6.md      # Este reporte técnico
```

---

## 2. Lógica de Despliegue y Multi-Versión

El orquestador realiza consultas a repositorios de software e instala de forma silenciosa la versión y puerto solicitados por el operador.

### Implementación en Linux (Lubuntu)
1. **Detección Dinámica de Versiones:**
   * **Apache & Nginx:** Se usa `apt-cache madison <paquete>` para obtener las versiones LTS y Latest del sistema.
   * **Tomcat:** Se consulta la API de GitHub de Apache Tomcat para localizar de forma dinámica las últimas dos releases estables sin hardcodear URLs.
2. **Despliegue Portable (Tomcat):**
   * Descarga de tarball oficial, descompresión automatizada en `/opt/tomcat` y configuración dinámica de puertos en `server.xml` mediante expresiones regulares.

### Implementación en Windows (Windows Server 2022)
1. **Detección Dinámica de Versiones:**
   * **IIS:** Determina la versión del sistema operativo leyendo el registro `HKLM:\SOFTWARE\Microsoft\InetStp`.
   * **Apache & Nginx:** Usa el proveedor de Chocolatey (`choco search <paquete> --limit-output`) para obtener las versiones disponibles en línea de manera dinámica.
2. **Despliegue y Resolución de Rutas:**
   * Uso de Chocolatey para instalaciones desatendidas con VC++ Redistributable como pre-requisito.
   * Resolución dinámica de directorios de configuración (`httpd.conf`, `nginx.conf`) utilizando búsqueda recursiva (`Get-ChildItem`) para soportar diferentes perfiles de instalación.

---

## 3. Hardening y Seguridad Aplicada

Para mitigar vulnerabilidades y asegurar la infraestructura, se implementaron de forma automática las siguientes políticas:

### Políticas de Aislamiento y Red
* **Usuarios de Ejecución Dedicados:**
  * **Linux:** Creación del usuario del sistema `http_svc` sin shell (`/usr/sbin/nologin`) y directorio principal restringido.
  * **Windows:** Creación del usuario local `http_svc` con contraseñas seguras y restricción estricta de permisos NTFS para la raíz web.
* **Firewall Idempotente:**
  * Configuración de reglas en `ufw` (Linux) y `New-NetFirewallRule` (Windows) cerrando puertos por defecto y habilitando únicamente el puerto personalizado asignado.

### Hardening de Servidores Web
* **Ocultación de Versiones:**
  * **Apache:** Directivas `ServerTokens Prod` y `ServerSignature Off`.
  * **Nginx:** Directiva `server_tokens off`.
  * **IIS:** Deshabilitar `X-Powered-By` y remover versión del servidor mediante Request Filtering.
* **Bloqueo de Métodos de Rastreo:**
  * Bloqueo explícito de verbos `TRACE` y `TRACK` en las configuraciones principales.
* **Cabeceras de Seguridad Inyectadas:**
  * `X-Frame-Options: SAMEORIGIN` (Protección contra Clickjacking).
  * `X-Content-Type-Options: nosniff` (Previene ataques de sniffing de MIME).
  * `X-XSS-Protection: 1; mode=block` (Protege contra Cross-Site Scripting).

---

## 4. Guía de Ejecución y Pruebas

### En Linux (Lubuntu)
1. Ejecuta el script principal como root:
   ```bash
   sudo ./tarea6/tarea6.sh
   ```
2. Selecciona el servicio HTTP (1. Apache, 2. Nginx, 3. Tomcat).
3. Selecciona la versión (LTS / Latest) e ingresa un puerto válido (ej. 8080).
4. Verifica con:
   ```bash
   curl -I http://localhost:PORT
   ```

### En Windows Server 2022
1. Ejecuta PowerShell como Administrador:
   ```powershell
   powershell -ExecutionPolicy Bypass -File Z:\tarea6\tarea6.ps1
   ```
2. Selecciona el servicio HTTP (1. IIS, 2. Apache, 3. Nginx).
3. Selecciona la versión de la lista interactiva e introduce el puerto personalizado.
4. Verifica con:
   ```powershell
   Invoke-WebRequest -Uri "http://localhost:PORT" -Method Head
   ```
