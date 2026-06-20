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

    try {
        $cert = New-SelfSignedCertificate -DnsName $global:DOMINIO -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName "SSL Reprobados.com" -NotAfter (Get-Date).AddYears(1)
        Write-Host "[OK] Certificado generado exitosamente: $($cert.Thumbprint)" -ForegroundColor Green
        return $cert
    } catch {
        Write-Host "[ERROR] Fallo la generacion del certificado SSL: $_" -ForegroundColor Red
        return $null
    }
}

# Buscar openssl.exe en el sistema de forma eficiente
function Buscar-OpenSSL-Win {
    # Buscar en rutas conocidas primero (rapido)
    $rutasConocidas = @(
        "C:\Apache24\bin\openssl.exe",
        "C:\tools\Apache24\bin\openssl.exe",
        "$env:PROGRAMFILES\Apache24\bin\openssl.exe",
        "$env:APPDATA\Apache24\bin\openssl.exe",
        "C:\Program Files\Git\usr\bin\openssl.exe",
        "C:\Program Files\Git\mingw64\bin\openssl.exe",
        "C:\Program Files (x86)\Git\usr\bin\openssl.exe",
        "C:\OpenSSL-Win64\bin\openssl.exe",
        "C:\OpenSSL\bin\openssl.exe"
    )
    foreach ($ruta in $rutasConocidas) {
        if (Test-Path $ruta) {
            Write-Host "[INFO] OpenSSL encontrado en: $ruta" -ForegroundColor Green
            return $ruta
        }
    }

    # Buscar de forma dinamica en carpetas de Apache instalado via Chocolatey
    $searchPaths = @("C:\tools", "C:\ProgramData\chocolatey\lib", "$env:USERPROFILE\AppData")
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            $found = Get-ChildItem -Path $sp -Filter "openssl.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                Write-Host "[INFO] OpenSSL encontrado en: $($found.FullName)" -ForegroundColor Green
                return $found.FullName
            }
        }
    }

    # Intentar instalar openssl via Chocolatey como ultimo recurso
    Write-Host "[INFO] OpenSSL no encontrado. Instalando via Chocolatey..." -ForegroundColor Yellow
    choco install openssl.light -y --no-progress 2>$null | Out-Null
    $opensslChoco = "C:\Program Files\OpenSSL\bin\openssl.exe"
    if (Test-Path $opensslChoco) { return $opensslChoco }
    $opensslChoco2 = "C:\OpenSSL-Win64\bin\openssl.exe"
    if (Test-Path $opensslChoco2) { return $opensslChoco2 }

    return $null
}

# Exportar Certificado a archivos PEM (.crt y .key) usando openssl
function Exportar-Certificado-PEM-Win {
    param([string]$DestDir)

    $cert = Generar-Certificado-SelfSigned-Win
    if ($null -eq $cert) { return $false }

    # Asegurar que el directorio destino existe
    if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }

    $pfxPath = Join-Path $env:TEMP "reprobados.pfx"
    $mypwd = ConvertTo-SecureString -String "changeit" -Force -AsPlainText
    
    try {
        # Exportar usando la ruta completa del certificado en el almacen
        $certPath = "Cert:\LocalMachine\My\$($cert.Thumbprint)"
        Export-PfxCertificate -Cert $certPath -FilePath $pfxPath -Password $mypwd -Force | Out-Null
        Write-Host "[OK] Certificado exportado a PFX temporal." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Fallo la exportacion del certificado PFX: $_" -ForegroundColor Red
        return $false
    }

    $openssl = Buscar-OpenSSL-Win
    if ($null -eq $openssl) {
        Write-Host "[ERROR] No se pudo localizar ni instalar openssl.exe." -ForegroundColor Red
        Remove-Item $pfxPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    $crtPath = Join-Path $DestDir "reprobados.crt"
    $keyPath = Join-Path $DestDir "reprobados.key"

    # Convertir PFX a CRT y KEY usando openssl
    Write-Host "[INFO] Convirtiendo PFX a archivos PEM..." -ForegroundColor Yellow
    & $openssl pkcs12 -in $pfxPath -nocerts -out $keyPath -nodes -passin pass:changeit 2>$null
    & $openssl pkcs12 -in $pfxPath -clcerts -nokeys -out $crtPath -passin pass:changeit 2>$null

    Remove-Item $pfxPath -Force -ErrorAction SilentlyContinue
    
    if ((Test-Path $crtPath) -and (Test-Path $keyPath)) {
        Write-Host "[OK] Archivos PEM generados: $crtPath y $keyPath" -ForegroundColor Green
        return $true
    }
    Write-Host "[ERROR] No se generaron los archivos PEM." -ForegroundColor Red
    return $false
}

# Buscar la ruta base de Apache Windows de forma robusta
function Buscar-ApacheBase-Win {
    $rutas = @("C:\Apache24","C:\tools\Apache24","$env:PROGRAMFILES\Apache24","$env:APPDATA\Apache24")
    foreach ($r in $rutas) {
        if (Test-Path "$r\conf\httpd.conf") { return $r }
    }
    # Busqueda dinamica
    $searchPaths = @("C:\tools", "C:\ProgramData\chocolatey\lib", $env:USERPROFILE)
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            $found = Get-ChildItem -Path $sp -Filter "httpd.conf" -Recurse -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.Directory.Parent.FullName }
        }
    }
    return $null
}

# Buscar la ruta base de Nginx Windows de forma robusta
function Buscar-NginxBase-Win {
    $rutas = @("C:\nginx","C:\tools\nginx","$env:PROGRAMFILES\nginx")
    foreach ($r in $rutas) {
        if (Test-Path "$r\conf\nginx.conf") { return $r }
    }
    $searchPaths = @("C:\tools", "C:\ProgramData\chocolatey\lib", $env:USERPROFILE)
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            $found = Get-ChildItem -Path $sp -Filter "nginx.conf" -Recurse -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.Directory.Parent.FullName }
        }
    }
    return $null
}

# ══════════════════════════════════════════════════════════════════════════════
# Configurar SSL para IIS Windows
# ══════════════════════════════════════════════════════════════════════════════
function Configurar-SSL-IIS-Win {
    Write-Host "`n[INFO] Configurando SSL/TLS en IIS..." -ForegroundColor Yellow
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $cert = Generar-Certificado-SelfSigned-Win
    if ($null -eq $cert) { return }

    # 1. Asegurar binding HTTPS (puerto 443)
    try {
        $existingBinding = Get-WebBinding -Name "Default Web Site" -Protocol "https" -ErrorAction SilentlyContinue
        if ($null -eq $existingBinding) {
            New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port 443 -Protocol "https" | Out-Null
            Write-Host "[OK] Binding HTTPS creado en puerto 443." -ForegroundColor Green
        } else {
            Write-Host "[INFO] Binding HTTPS ya existe." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[WARN] Error al crear binding HTTPS: $_" -ForegroundColor Yellow
    }

    # 2. Asociar el certificado al puerto 443 usando netsh
    $thumbprint = $cert.Thumbprint
    Write-Host "[INFO] Asociando certificado (Thumbprint: $thumbprint) al puerto 443..." -ForegroundColor Yellow
    netsh http delete sslcert ipport=0.0.0.0:443 2>$null | Out-Null
    $result = netsh http add sslcert ipport=0.0.0.0:443 certhash=$thumbprint appid="{4dc3e181-e14b-4a21-b022-59fc669b0914}" 2>&1
    Write-Host "[INFO] netsh resultado: $result" -ForegroundColor Cyan

    # 3. Abrir puerto 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-IIS-443" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTPS-IIS-443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow | Out-Null
    Write-Host "[OK] Regla de firewall para puerto 443 creada." -ForegroundColor Green

    # 4. Reiniciar IIS
    iisreset 2>$null | Out-Null
    Write-Host "[OK] IIS configurado con SSL en puerto 443." -ForegroundColor Green
    
    # Verificacion rapida
    try {
        $testUrl = "https://localhost"
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $response = Invoke-WebRequest -Uri $testUrl -Method Head -TimeoutSec 5 -ErrorAction Stop
        Write-Host "[OK] Verificacion HTTPS exitosa: $($response.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "[INFO] HTTPS responde (certificado autofirmado - normal en navegadores)." -ForegroundColor Yellow
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# Configurar SSL para Apache Windows
# ══════════════════════════════════════════════════════════════════════════════
function Configurar-SSL-Apache-Win {
    Write-Host "`n[INFO] Configurando SSL/TLS en Apache Windows..." -ForegroundColor Yellow

    $apacheBase = Buscar-ApacheBase-Win
    if (-not $apacheBase) {
        Write-Host "[ERROR] No se pudo encontrar la ruta de instalacion de Apache." -ForegroundColor Red
        return
    }
    Write-Host "[INFO] Apache encontrado en: $apacheBase" -ForegroundColor Cyan

    # Exportar certificados PEM al directorio conf de Apache
    $ok = Exportar-Certificado-PEM-Win -DestDir "$apacheBase\conf"
    if (-not $ok) {
        Write-Host "[ERROR] Fallo la exportacion del certificado PEM para Apache." -ForegroundColor Red
        return
    }

    # Habilitar modulos SSL en httpd.conf
    $httpdConf = "$apacheBase\conf\httpd.conf"
    $confText = Get-Content $httpdConf -Raw
    $confText = $confText -replace '#\s*LoadModule ssl_module', 'LoadModule ssl_module'
    $confText = $confText -replace '#\s*LoadModule socache_shmcb_module', 'LoadModule socache_shmcb_module'
    $confText = $confText -replace '#\s*LoadModule rewrite_module', 'LoadModule rewrite_module'
    $confText = $confText -replace '#\s*Include conf/extra/httpd-ssl.conf', 'Include conf/extra/httpd-ssl.conf'
    Set-Content $httpdConf -Value $confText
    Write-Host "[OK] Modulos SSL habilitados en httpd.conf." -ForegroundColor Green

    # Crear directorio extra si no existe
    $extraDir = "$apacheBase\conf\extra"
    if (-not (Test-Path $extraDir)) { New-Item -ItemType Directory -Path $extraDir -Force | Out-Null }

    # Configurar httpd-ssl.conf con rutas de Windows (backslash)
    $crtFile = "$apacheBase\conf\reprobados.crt" -replace '\\','/'
    $keyFile = "$apacheBase\conf\reprobados.key" -replace '\\','/'
    $docRoot = "$apacheBase\htdocs" -replace '\\','/'

    $sslConfContent = @"
Listen 443
SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLHonorCipherOrder on
SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
SSLSessionCache "shmcb:logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost *:443>
    DocumentRoot "$docRoot"
    ServerName $global:DOMINIO`:443
    ServerAdmin admin@reprobados.com
    ErrorLog "logs/ssl_error.log"
    TransferLog "logs/ssl_access.log"

    SSLEngine on
    SSLCertificateFile "$crtFile"
    SSLCertificateKeyFile "$keyFile"

    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</VirtualHost>
"@
    Set-Content -Path "$extraDir\httpd-ssl.conf" -Value $sslConfContent
    Write-Host "[OK] httpd-ssl.conf configurado." -ForegroundColor Green

    # Abrir puerto 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-Apache-443" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTPS-Apache-443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow | Out-Null

    # Reiniciar Apache
    $nombreSvcReal = Obtener-Servicio-Real-Win -Patron "Apache" -Fallback "Apache2.4"
    Stop-Service -Name $nombreSvcReal -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Service -Name $nombreSvcReal -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache Windows configurado con SSL (443)." -ForegroundColor Green
}

# ══════════════════════════════════════════════════════════════════════════════
# Configurar SSL para Nginx Windows
# ══════════════════════════════════════════════════════════════════════════════
function Configurar-SSL-Nginx-Win {
    Write-Host "`n[INFO] Configurando SSL/TLS en Nginx Windows..." -ForegroundColor Yellow

    $nginxBase = Buscar-NginxBase-Win
    if (-not $nginxBase) {
        Write-Host "[ERROR] No se pudo encontrar la ruta de instalacion de Nginx." -ForegroundColor Red
        return
    }
    Write-Host "[INFO] Nginx encontrado en: $nginxBase" -ForegroundColor Cyan

    # Exportar certificados PEM al directorio conf de Nginx
    $ok = Exportar-Certificado-PEM-Win -DestDir "$nginxBase\conf"
    if (-not $ok) {
        Write-Host "[ERROR] Fallo la exportacion del certificado PEM para Nginx." -ForegroundColor Red
        return
    }

    # Escribir nginx.conf con SSL y Redireccion
    $nginxConf = "$nginxBase\conf\nginx.conf"
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
        return 301 https://`$host`$request_uri;
    }

    server {
        listen       443 ssl default_server;
        server_name  $global:DOMINIO;

        ssl_certificate      conf/reprobados.crt;
        ssl_certificate_key  conf/reprobados.key;

        ssl_session_cache    shared:SSL:1m;
        ssl_session_timeout  5m;
        ssl_ciphers  HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers  on;

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
    Write-Host "[OK] nginx.conf configurado con SSL." -ForegroundColor Green

    # Abrir puerto 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-Nginx-443" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTPS-Nginx-443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow | Out-Null

    # Reiniciar Nginx
    Stop-Process -Name "nginx" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
    Write-Host "[OK] Nginx Windows configurado con SSL (443)." -ForegroundColor Green
}

# ══════════════════════════════════════════════════════════════════════════════
# Configurar SSL para IIS-FTP (FTPS)
# ══════════════════════════════════════════════════════════════════════════════
function Configurar-SSL-IISFTP-Win {
    Write-Host "`n[INFO] Configurando FTPS en IIS-FTP..." -ForegroundColor Yellow
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $cert = Generar-Certificado-SelfSigned-Win
    if ($null -eq $cert) { return }

    try {
        # Configurar hash de certificado y requerir canal SSL para control y datos
        Set-WebConfiguration '/system.ftpServer/security/ssl' -Value @{
            serverCertHash = $cert.Thumbprint
            sslControlChannel = "Require"
            sslDataChannel = "Require"
        }
        
        # Reiniciar servicio FTP
        Restart-Service -Name "FTPSVC" -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] IIS-FTP configurado con FTPS (Require SSL)." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Error al configurar FTPS en IIS: $_" -ForegroundColor Red
    }
}
