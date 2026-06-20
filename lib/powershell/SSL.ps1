# lib/powershell/SSL.ps1 - Generacion de certificados y configuracion SSL/TLS en Windows

$global:DOMINIO = "www.reprobados.com"

# Generar certificado autofirmado en Windows
function Generar-Certificado-SelfSigned-Win {
    Write-Host "`n[INFO] Generando certificado SSL autofirmado para $global:DOMINIO..." -ForegroundColor Yellow
    
    # Buscar si ya existe
    $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*CN=$global:DOMINIO*" } | Select-Object -First 1
    if ($null -ne $cert) {
        Write-Host "[OK] Certificado ya existe en el almacen de Windows: $($cert.Thumbprint)" -ForegroundColor Green
        return $cert
    }

    $cert = New-SelfSignedCertificate -DnsName $global:DOMINIO -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName "SSL Reprobados.com"
    if ($null -ne $cert) {
        Write-Host "[OK] Certificado generado exitosamente: $($cert.Thumbprint)" -ForegroundColor Green
        return $cert
    } else {
        Write-Host "[ERROR] Fallo la generacion del certificado SSL." -ForegroundColor Red
        return $null
    }
}

# Exportar Certificado a archivos PEM (.crt y .key) usando openssl de Apache
function Exportar-Certificado-PEM-Win {
    param([string]$ApacheBase, [string]$DestDir)

    $cert = Generar-Certificado-SelfSigned-Win
    if ($null -eq $cert) { return $false }

    $pfxPath = Join-Path $env:TEMP "reprobados.pfx"
    $mypwd = ConvertTo-SecureString -String "changeit" -Force -AsPlainText
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $mypwd | Out-Null

    $openssl = Join-Path $ApacheBase "bin\openssl.exe"
    if (-not (Test-Path $openssl)) {
        # Si no hay apache, buscar openssl.exe en el sistema o git
        $found = Get-ChildItem -Path "C:\", "C:\Program Files" -Filter "openssl.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $openssl = $found.FullName }
    }

    if (-not (Test-Path $openssl)) {
        Write-Host "[ERROR] No se pudo localizar openssl.exe en el sistema para exportar el certificado." -ForegroundColor Red
        return $false
    }

    $crtPath = Join-Path $DestDir "reprobados.crt"
    $keyPath = Join-Path $DestDir "reprobados.key"

    # Convertir PFX a CRT y KEY usando openssl
    & $openssl pkcs12 -in $pfxPath -nocerts -out $keyPath -nodes -passin pass:changeit 2>$null | Out-Null
    & $openssl pkcs12 -in $pfxPath -clcerts -nokeys -out $crtPath -passin pass:changeit 2>$null | Out-Null

    Remove-Item $pfxPath -Force -ErrorAction SilentlyContinue
    
    if ((Test-Path $crtPath) -and (Test-Path $keyPath)) {
        return $true
    }
    return $false
}

# Configurar SSL para IIS Windows
function Configurar-SSL-IIS-Win {
    Write-Host "`n[INFO] Configurando SSL/TLS en IIS..." -ForegroundColor Yellow
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $cert = Generar-Certificado-SelfSigned-Win
    if ($null -eq $cert) { return }

    # 1. Asegurar binding HTTPS (puerto 443)
    $hasBinding = Get-WebBinding -Name "Default Web Site" -Protocol "https" -Port 443
    if ($null -eq $hasBinding) {
        New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port 443 -Protocol "https" | Out-Null
    }

    # 2. Asociar el certificado al puerto 443 usando netsh
    netsh http delete sslcert ipport=0.0.0.0:443 2>$null | Out-Null
    netsh http add sslcert ipport=0.0.0.0:443 certhash=$($cert.Thumbprint) appid="{4dc3e181-e14b-4a21-b022-59fc669b0914}" 2>$null | Out-Null

    # 3. Habilitar redireccion HTTP -> HTTPS usando URL Rewrite si esta disponible
    # Asegurar modulo URL Rewrite
    if (-not (Test-Path "$env:SystemRoot\System32\inetsrv\rewrite.dll")) {
        Write-Host "[INFO] Modulo URL Rewrite no detectado. Instalando..." -ForegroundColor Yellow
        choco install urlrewrite -y --no-progress | Out-Null
    }

    # Crear/Sobrescribir el web.config en wwwroot para HSTS y Redireccion
    $webConfigPath = "C:\inetpub\wwwroot\web.config"
    $configContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="Redirect to HTTPS" stopProcessing="true">
                    <match url="(.*)" />
                    <conditions>
                        <add input="{HTTPS}" pattern="^OFF$" />
                    </conditions>
                    <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
                </rule>
            </rules>
            <outboundRules>
                <rule name="Add HSTS Header">
                    <match serverVariable="RESPONSE_Strict_Transport_Security" pattern=".*" />
                    <conditions>
                        <add input="{HTTPS}" pattern="on" />
                    </conditions>
                    <action type="Rewrite" value="max-age=31536000; includeSubDomains" />
                </rule>
            </outboundRules>
        </rewrite>
    </system.webServer>
</configuration>
"@
    Set-Content -Path $webConfigPath -Value $configContent

    iisreset
    Write-Host "[OK] IIS configurado con SSL y Redireccion HTTPS activa." -ForegroundColor Green
}

# Configurar SSL para Apache Windows
function Configurar-SSL-Apache-Win {
    Write-Host "`n[INFO] Configurando SSL/TLS en Apache Windows..." -ForegroundColor Yellow

    # Buscar ApacheBase
    $apacheBase = @("C:\Apache24","C:\tools\Apache24","$env:PROGRAMFILES\Apache24","$env:APPDATA\Apache24") | Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
    if (-not $apacheBase) {
        $found = Get-ChildItem -Path "C:\tools", "C:\", $env:USERPROFILE -Filter "httpd.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $apacheBase = $found.Directory.Parent.FullName }
    }

    if (-not $apacheBase) {
        Write-Host "[ERROR] No se pudo encontrar la ruta de instalacion de Apache." -ForegroundColor Red
        return
    }

    # Exportar certificados
    $ok = Exportar-Certificado-PEM-Win -ApacheBase $apacheBase -DestDir "$apacheBase\conf"
    if (-not $ok) {
        Write-Host "[ERROR] Fallo la exportacion del certificado PEM para Apache." -ForegroundColor Red
        return
    }

    # Habilitar mod_ssl en httpd.conf
    $httpdConf = "$apacheBase\conf\httpd.conf"
    $confText = Get-Content $httpdConf
    $confText = $confText -replace '#\s*LoadModule ssl_module', 'LoadModule ssl_module'
    $confText = $confText -replace '#\s*LoadModule socache_shmcb_module', 'LoadModule socache_shmcb_module'
    $confText = $confText -replace '#\s*Include conf/extra/httpd-ssl.conf', 'Include conf/extra/httpd-ssl.conf'
    $confText | Set-Content $httpdConf

    # Configurar conf/extra/httpd-ssl.conf
    $sslConfPath = "$apacheBase\conf\extra\httpd-ssl.conf"
    $sslConfContent = @"
Listen 443
SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLProxyCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLHonorCipherOrder on
SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
SSLSessionCache "shmcb:logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost *:443>
    DocumentRoot "$apacheBase/htdocs"
    ServerName $global:DOMINIO:443
    ServerAdmin admin@reprobados.com
    ErrorLog "logs/ssl_error.log"
    TransferLog "logs/ssl_access.log"

    SSLEngine on
    SSLCertificateFile "$apacheBase/conf/reprobados.crt"
    SSLCertificateKeyFile "$apacheBase/conf/reprobados.key"

    # Hardening Headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

    <FilesMatch "\.(cgi|shtml|phtml|php)$">
        SSLOptions +StdEnvVars
    </FilesMatch>
    <Directory "$apacheBase/cgi-bin">
        SSLOptions +StdEnvVars
    </Directory>
</VirtualHost>
"@
    Set-Content -Path $sslConfPath -Value $sslConfContent

    # Forzar redireccion HTTP -> HTTPS en el puerto 8080 (o el puerto configurado de apache)
    # Detectar el puerto configurado actual de Apache
    $puerto = 8080
    $confText = Get-Content $httpdConf
    if ($confText -match '^\s*Listen\s+(\d+)') {
        $puerto = $Matches[1]
    }

    # Modificar el puerto de escucha para redireccion
    $redirectVhost = @"
<VirtualHost *:$puerto>
    ServerName $global:DOMINIO
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>
"@
    # Asegurar que rewrite_module este activo
    $confText = $confText -replace '#\s*LoadModule rewrite_module', 'LoadModule rewrite_module'
    $confText | Set-Content $httpdConf
    
    if (-not (Select-String -Path $httpdConf -Pattern "RewriteEngine On")) {
        Add-Content $httpdConf "`nInclude conf/extra/httpd-redirect.conf"
        Set-Content -Path "$apacheBase\conf\extra\httpd-redirect.conf" -Value $redirectVhost
    }

    # Reiniciar Apache
    $nombreSvcReal = Obtener-Servicio-Real-Win -Patron "Apache" -Fallback "Apache2.4"
    Restart-Service -Name $nombreSvcReal -Force -ErrorAction SilentlyContinue

    Write-Host "[OK] Apache Windows configurado con SSL (443) y Redireccion HTTPS." -ForegroundColor Green
}

# Configurar SSL para Nginx Windows
function Configurar-SSL-Nginx-Win {
    Write-Host "`n[INFO] Configurando SSL/TLS en Nginx Windows..." -ForegroundColor Yellow

    # Buscar Nginx Base
    $nginxBase = @("C:\nginx","C:\tools\nginx","$env:PROGRAMFILES\nginx") | Where-Object { Test-Path "$_\conf\nginx.conf" } | Select-Object -First 1
    if (-not $nginxBase) {
        $found = Get-ChildItem -Path "C:\tools", "C:\", $env:USERPROFILE -Filter "nginx.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $nginxBase = $found.Directory.Parent.FullName }
    }

    if (-not $nginxBase) {
        Write-Host "[ERROR] No se pudo encontrar la ruta de instalacion de Nginx." -ForegroundColor Red
        return
    }

    # Buscar Apache o Git openssl para exportar el PEM
    # Si no hay Apache, intentamos buscar openssl en C:\
    $ok = Exportar-Certificado-PEM-Win -ApacheBase "C:\Apache24" -DestDir "$nginxBase\conf"
    if (-not $ok) {
        Write-Host "[ERROR] Fallo la exportacion del certificado PEM para Nginx." -ForegroundColor Red
        return
    }

    # Detectar el puerto HTTP actual
    $nginxConf = "$nginxBase\conf\nginx.conf"
    $puertoHttp = 80
    # Escribir un nginx.conf limpio con SSL y Redireccion
    $nginxContent = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80 default_server;
        server_name  $global:DOMINIO;
        return 301 https://`$$host`$$request_uri;
    }

    server {
        listen       443 ssl default_server;
        server_name  $global:DOMINIO;

        ssl_certificate      reprobados.crt;
        ssl_certificate_key  reprobados.key;

        ssl_session_cache    shared:SSL:1m;
        ssl_session_timeout  5m;

        ssl_ciphers  HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers  on;

        # Hardening Headers
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
        add_header X-XSS-Protection "1; mode=block";
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }
}
"@
    Set-Content -Path $nginxConf -Value $nginxContent

    # Reiniciar Nginx
    Stop-Process -Name "nginx" -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden

    Write-Host "[OK] Nginx Windows configurado con SSL y Redireccion HTTPS." -ForegroundColor Green
}

# Configurar SSL para IIS-FTP (FTPS)
function Configurar-SSL-IISFTP-Win {
    Write-Host "`n[INFO] Configurando FTPS en IIS-FTP..." -ForegroundColor Yellow
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $cert = Generar-Certificado-SelfSigned-Win
    if ($null -eq $cert) { return }

    # Establecer la configuracion SSL en el servidor FTP a nivel global/sitio
    try {
        # Configurar hash de certificado y requerir canal SSL para control y datos
        Set-WebConfiguration '/system.ftpServer/security/ssl' -Value @{
            serverCertHash = $cert.Thumbprint
            sslControlChannel = "Require"
            sslDataChannel = "Require"
        }
        
        # Reiniciar servicio FTP
        Restart-Service -Name "FTPSVC" -Force
        Write-Host "[OK] IIS-FTP configurado con FTPS (Require SSL)." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Error al configurar FTPS en IIS: $_" -ForegroundColor Red
    }
}
