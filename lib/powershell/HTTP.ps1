# lib/powershell/HTTP.ps1
# Biblioteca de funciones para despliegue dinámico de servidores HTTP en Windows.
# Uso: . "$PSScriptRoot\..\..\lib\powershell\HTTP.ps1"

# ─── Constantes ───────────────────────────────────────────────────────────────
$PUERTOS_RESERVADOS = @(21,22,23,25,53,110,143,443,3306,5432,6379,8443)
$IIS_WWWROOT        = "C:\inetpub\wwwroot"
$CHOCO_APACHE_ID    = "apache-httpd"
$CHOCO_NGINX_ID     = "nginx"

# ─── Asegurar Chocolatey instalado ────────────────────────────────────────────
function Asegurar-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "[INFO] Chocolatey ya instalado." -ForegroundColor Green
        return
    }
    Write-Host "[INFO] Instalando Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
    Write-Host "[OK] Chocolatey instalado." -ForegroundColor Green
}

# ─── Validar puerto ───────────────────────────────────────────────────────────
function Validar-Puerto-Win {
    param([int]$Puerto)
    if ($Puerto -lt 1024 -or $Puerto -gt 65535) {
        Write-Host "[ERROR] Puerto fuera de rango (1024-65535)." -ForegroundColor Red
        return $false
    }
    if ($PUERTOS_RESERVADOS -contains $Puerto) {
        Write-Host "[ERROR] Puerto $Puerto reservado por otro servicio." -ForegroundColor Red
        return $false
    }
    $enUso = Test-NetConnection -ComputerName localhost -Port $Puerto -InformationLevel Quiet -WarningAction SilentlyContinue 2>$null
    if ($enUso) {
        Write-Host "[ERROR] Puerto $Puerto ya está en uso." -ForegroundColor Red
        return $false
    }
    return $true
}

function Leer-Puerto-Win {
    param([int]$Default = 8080)
    while ($true) {
        $input = Read-Host "Puerto de escucha [$Default]"
        if ([string]::IsNullOrWhiteSpace($input)) { $input = $Default }
        $p = 0
        if (-not [int]::TryParse($input, [ref]$p)) {
            Write-Host "[ERROR] Debe ser un número entero." -ForegroundColor Red
            continue
        }
        if (Validar-Puerto-Win -Puerto $p) { return $p }
    }
}

# ─── Consultar versiones IIS ──────────────────────────────────────────────────
function Consultar-Versiones-IIS {
    $key = "HKLM:\SOFTWARE\Microsoft\InetStp"
    try {
        $ver = (Get-ItemProperty $key -ErrorAction Stop).VersionString
        Write-Host "[INFO] IIS detectado: $ver" -ForegroundColor Yellow
        return @($ver, "10.0 (Instalacion desde Windows Features)")
    } catch {
        return @("10.0", "8.5")
    }
}

# ─── Consultar versiones Apache Windows (Chocolatey) ─────────────────────────
function Consultar-Versiones-Apache-Win {
    Asegurar-Chocolatey
    Write-Host "[INFO] Consultando versiones de Apache para Windows..." -ForegroundColor Yellow
    try {
        $raw = choco list $CHOCO_APACHE_ID --all-versions 2>$null | Select-String -Pattern "$CHOCO_APACHE_ID\s+\d"
        $vers = $raw | ForEach-Object { ($_ -split '\s+')[1] } | Select-Object -Unique | Select-Object -First 5
        if (-not $vers) { return @("2.4.63","2.4.62","2.4.58") }
        return $vers
    } catch { return @("2.4.63","2.4.62","2.4.58") }
}

# ─── Consultar versiones Nginx Windows (Chocolatey) ──────────────────────────
function Consultar-Versiones-Nginx-Win {
    Asegurar-Chocolatey
    Write-Host "[INFO] Consultando versiones de Nginx para Windows..." -ForegroundColor Yellow
    try {
        $raw = choco list $CHOCO_NGINX_ID --all-versions 2>$null | Select-String -Pattern "nginx\s+\d"
        $vers = $raw | ForEach-Object { ($_ -split '\s+')[1] } | Select-Object -Unique | Select-Object -First 5
        if (-not $vers) { return @("1.27.4","1.26.3","1.24.0") }
        return $vers
    } catch { return @("1.27.4","1.26.3","1.24.0") }
}

# ─── Seleccionar versión ──────────────────────────────────────────────────────
function Seleccionar-Version-Win {
    param([string]$Servicio, [string[]]$Versiones)
    Write-Host "`nVersiones disponibles para $Servicio :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Versiones.Count; $i++) {
        $label = ""
        if ($i -eq 0) { $label = " (Latest)" }
        if ($i -eq 1) { $label = " (Stable/LTS)" }
        Write-Host "  $($i+1)) $($Versiones[$i])$label"
    }
    while ($true) {
        $sel = Read-Host "Selecciona version (1-$($Versiones.Count))"
        $n = 0
        if ([int]::TryParse($sel, [ref]$n) -and $n -ge 1 -and $n -le $Versiones.Count) {
            return $Versiones[$n-1]
        }
        Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red
    }
}

# ─── Crear index.html Windows ─────────────────────────────────────────────────
function Crear-Index-Html-Win {
    param([string]$RootDir, [string]$Servicio, [string]$Version, [int]$Puerto)
    if (-not (Test-Path $RootDir)) { New-Item -ItemType Directory -Path $RootDir -Force | Out-Null }
    $hostname = $env:COMPUTERNAME
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>$Servicio - Tarea 6</title>
  <style>
    body { font-family: Arial, sans-serif; background: #1a1a2e; color: #e0e0e0;
           display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
    .card { background: #16213e; border: 1px solid #0f3460; border-radius: 12px;
            padding: 2rem 3rem; text-align: center; box-shadow: 0 8px 32px rgba(0,0,0,0.5); }
    h1 { color: #e94560; margin-bottom: 0.5rem; }
    .badge { display: inline-block; background: #0f3460; border-radius: 6px;
             padding: 0.2rem 0.8rem; margin: 0.2rem; color: #53d8fb; font-weight: bold; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🌐 $Servicio</h1>
    <div>Servidor: <span class="badge">$Servicio</span></div>
    <div>Version: <span class="badge">$Version</span></div>
    <div>Puerto: <span class="badge">$Puerto</span></div>
    <div>Host: <span class="badge">$hostname</span></div>
    <p style="color:#888;margin-top:1.5rem;font-size:0.85rem;">Tarea 6 - Despliegue Dinamico HTTP</p>
  </div>
</body>
</html>
"@
    Set-Content -Path "$RootDir\index.html" -Value $html -Encoding UTF8
    Write-Host "[OK] index.html generado en: $RootDir" -ForegroundColor Green
}

# ─── Crear usuario de servicio Windows ───────────────────────────────────────
function Crear-Usuario-Servicio-Win {
    param([string]$Usuario, [string]$DirectorioLimitado)
    $existente = Get-LocalUser -Name $Usuario -ErrorAction SilentlyContinue
    if (-not $existente) {
        $pwd = ConvertTo-SecureString "Svc$(Get-Random -Max 9999)!Http" -AsPlainText -Force
        New-LocalUser -Name $Usuario -Password $pwd -Description "Cuenta de servicio HTTP" `
            -PasswordNeverExpires $true -UserMayNotChangePassword $true -AccountNeverExpires | Out-Null
        # Quitar del grupo Users para minimizar permisos
        Remove-LocalGroupMember -Group "Users" -Member $Usuario -ErrorAction SilentlyContinue
        Write-Host "[OK] Usuario de servicio '$Usuario' creado con permisos limitados." -ForegroundColor Green
    } else {
        Write-Host "[INFO] Usuario '$Usuario' ya existe." -ForegroundColor Yellow
    }
    # Restringir NTFS: solo acceso al directorio del servicio
    $acl = Get-Acl $DirectorioLimitado
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Usuario, "ReadAndExecute,Write", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $DirectorioLimitado -AclObject $acl
    Write-Host "[OK] Permisos NTFS restringidos para '$Usuario' en $DirectorioLimitado." -ForegroundColor Green
}

# ─── Configurar firewall Windows ──────────────────────────────────────────────
function Configurar-Firewall-Win {
    param([int]$Puerto, [string]$Servicio)
    # Asegurar que el puerto de administración de red (RDP / WinRM / SSH) no se toque.
    # Eliminar regla si ya existe con ese nombre
    Remove-NetFirewallRule -DisplayName "HTTP-$Servicio-Custom" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTP-$Servicio-Custom" `
        -Direction Inbound -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    # Cerrar puerto 80 si el elegido es diferente
    if ($Puerto -ne 80) {
        $regla80 = Get-NetFirewallRule -DisplayName "HTTP-80" -ErrorAction SilentlyContinue
        if ($regla80) {
            Remove-NetFirewallRule -DisplayName "HTTP-80" -ErrorAction SilentlyContinue
            Write-Host "[INFO] Regla de puerto 80 eliminada." -ForegroundColor Yellow
        }
    }
    Write-Host "[OK] Firewall: regla creada para puerto $Puerto TCP (Inbound)." -ForegroundColor Green
}

# ─── Verificar si el servicio ya existe y preguntar qué hacer (Windows) ─────────
function Verifico-Previo-Y-Pregunto-Win {
    param(
        [string]$Servicio,  # "W3SVC", "Apache2.4", o "nginx" (proceso)
        [string]$ChocoPkg   # "apache-httpd", "nginx", o ""
    )

    $activo = $false
    $instalado = $false

    if ($Servicio -eq "nginx") {
        $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
        if ($proc) { $activo = $true; $instalado = $true }
        elseif (Test-Path "C:\nginx" -or (Get-Command nginx -ErrorAction SilentlyContinue)) { $instalado = $true }
    } else {
        $svc = Get-Service -Name $Servicio -ErrorAction SilentlyContinue
        if ($svc) {
            $instalado = $true
            if ($svc.Status -eq "Running") { $activo = $true }
        }
    }

    if (-not $activo -and -not $instalado) {
        return $true # proceder con instalación normal
    }

    Write-Host "`n[!] $Servicio ya esta instalado en este servidor." -ForegroundColor Yellow
    if ($activo) {
        Write-Host "    Estado: ACTIVO" -ForegroundColor Green
    } else {
        Write-Host "    Estado: INACTIVO" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  1) Mantener el actual y solo cambiar configuracion (puerto/version)"
    Write-Host "  2) Desinstalar completamente y volver a instalar desde cero"
    Write-Host "  3) Cancelar (volver al menu)"
    Write-Host ""

    while ($true) {
        $opc = Read-Host "¿Que deseas hacer? (1/2/3)"
        switch ($opc) {
            "1" { return $true }
            "2" {
                Write-Host "[INFO] Desinstalando $Servicio..." -ForegroundColor Yellow
                if ($Servicio -eq "W3SVC") {
                    # Desinstalar IIS
                    $features = @("Web-Server","Web-Common-Http","Web-Default-Doc","Web-Static-Content","Web-Mgmt-Console")
                    foreach ($f in $features) {
                        if ((Get-WindowsFeature -Name $f).Installed) {
                            Uninstall-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null
                        }
                    }
                    if (Test-Path $IIS_WWWROOT) {
                        Remove-Item -Path $IIS_WWWROOT -Recurse -Force -ErrorAction SilentlyContinue
                    }
                } elseif ($Servicio -eq "Apache2.4") {
                    Stop-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
                    $apacheBase = @("C:\Apache24","C:\tools\Apache24","$env:PROGRAMFILES\Apache24") | Where-Object { Test-Path "$_\bin\httpd.exe" } | Select-Object -First 1
                    if ($apacheBase) {
                        & "$apacheBase\bin\httpd.exe" -k uninstall 2>$null | Out-Null
                    }
                    choco uninstall apache-httpd -y -f --no-progress 2>$null
                    foreach ($dir in @("C:\Apache24","C:\tools\Apache24")) {
                        if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue }
                    }
                } elseif ($Servicio -eq "nginx") {
                    Stop-Process -Name "nginx" -Force -ErrorAction SilentlyContinue
                    choco uninstall nginx -y -f --no-progress 2>$null
                    foreach ($dir in @("C:\nginx","C:\tools\nginx")) {
                        if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue }
                    }
                }
                Write-Host "[OK] $Servicio desinstalado. Procediendo con instalacion limpia." -ForegroundColor Green
                return $true
            }
            "3" {
                Write-Host "Cancelado." -ForegroundColor Yellow
                return $false
            }
            default {
                Write-Host "[ERROR] Opcion invalida (1, 2 o 3)." -ForegroundColor Red
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# IIS
# ═══════════════════════════════════════════════════════════════════════════════
function Instalar-IIS {
    param([string]$Version, [int]$Puerto)
    if (-not (Verifico-Previo-Y-Pregunto-Win -Servicio "W3SVC" -ChocoPkg "")) { return }
    
    Write-Host "`n[INFO] Instalando IIS en puerto $Puerto..." -ForegroundColor Yellow

    # Instalar características IIS
    $features = @(
        "Web-Server","Web-Common-Http","Web-Default-Doc","Web-Static-Content",
        "Web-Http-Errors","Web-Http-Logging","Web-Request-Monitor",
        "Web-Filtering","Web-Stat-Compression","Web-Mgmt-Console",
        "Web-Scripting-Tools"
    )
    foreach ($f in $features) {
        if (-not (Get-WindowsFeature -Name $f).Installed) {
            Install-WindowsFeature -Name $f -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Cambiar puerto del sitio Default Web Site
    $site = "Default Web Site"
    if (Get-Website -Name $site -ErrorAction SilentlyContinue) {
        Remove-WebBinding -Name $site -ErrorAction SilentlyContinue
    }
    New-WebBinding -Name $site -Protocol http -Port $Puerto -IPAddress "*" -ErrorAction SilentlyContinue

    # Hardening IIS
    Aplicar-Hardening-IIS

    # Usuario de servicio (IUSR ya existe, crear uno adicional limitado)
    Crear-Usuario-Servicio-Win -Usuario "iis_http_svc" -DirectorioLimitado $IIS_WWWROOT

    # index.html
    $verReal = ""
    try { $verReal = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp").VersionString } catch { $verReal = $Version }
    Crear-Index-Html-Win -RootDir $IIS_WWWROOT -Servicio "IIS" -Version $verReal -Puerto $Puerto

    Start-Website -Name $site -ErrorAction SilentlyContinue
    Configurar-Firewall-Win -Puerto $Puerto -Servicio "IIS"

    Write-Host "[OK] IIS desplegado en puerto $Puerto" -ForegroundColor Green
    Write-Host "Verificacion: Invoke-WebRequest http://localhost:$Puerto -Method Head" -ForegroundColor Cyan
    try { (Invoke-WebRequest -Uri "http://localhost:$Puerto" -Method Head -TimeoutSec 5).Headers | Format-Table } catch { }
}

function Aplicar-Hardening-IIS {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $site = "Default Web Site"

    # Eliminar encabezado X-Powered-By
    try {
        Remove-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -AtElement @{name="X-Powered-By"} -ErrorAction SilentlyContinue
    } catch { }

    # Agregar security headers
    $headers = @(
        @{name="X-Frame-Options";     value="SAMEORIGIN"},
        @{name="X-Content-Type-Options"; value="nosniff"},
        @{name="X-XSS-Protection";    value="1; mode=block"}
    )
    foreach ($h in $headers) {
        try {
            Add-WebConfigurationProperty -PSPath "IIS:\Sites\$site" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." -Value $h -ErrorAction SilentlyContinue
        } catch { }
    }

    # Request Filtering: denegar métodos peligrosos
    $badVerbs = @("TRACE","TRACK","OPTIONS","DELETE","PUT")
    foreach ($verb in $badVerbs) {
        try {
            Add-WebConfigurationProperty -PSPath "IIS:\Sites\$site" `
                -Filter "system.webServer/security/requestFiltering/verbs" `
                -Name "." -Value @{verb=$verb; allowed="false"} -ErrorAction SilentlyContinue
        } catch { }
    }

    # Ocultar token de versión del servidor
    Set-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.webServer/security/requestFiltering" `
        -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue

    Write-Host "[OK] Hardening IIS: headers de seguridad, X-Powered-By eliminado, verbos bloqueados." -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
# APACHE WINDOWS (Chocolatey)
# ═══════════════════════════════════════════════════════════════════════════════
function Instalar-Apache-Win {
    param([string]$Version, [int]$Puerto)
    if (-not (Verifico-Previo-Y-Pregunto-Win -Servicio "Apache2.4" -ChocoPkg "apache-httpd")) { return }
    
    Asegurar-Chocolatey
    Write-Host "`n[INFO] Instalando Apache $Version en puerto $Puerto (Chocolatey)..." -ForegroundColor Yellow
    choco install $CHOCO_APACHE_ID --version=$Version -y --no-progress 2>$null
    if ($LASTEXITCODE -ne 0) {
        choco install $CHOCO_APACHE_ID -y --no-progress 2>$null
    }

    # Localizar httpd.conf
    $apacheBase = @("C:\Apache24","C:\tools\Apache24","$env:PROGRAMFILES\Apache24") | Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
    if (-not $apacheBase) {
        Write-Host "[ERROR] No se encontro httpd.conf de Apache." -ForegroundColor Red; return
    }

    # Cambiar puerto
    (Get-Content "$apacheBase\conf\httpd.conf") -replace "Listen \d+", "Listen $Puerto" |
        Set-Content "$apacheBase\conf\httpd.conf"
    (Get-Content "$apacheBase\conf\httpd.conf") -replace "ServerTokens Full","ServerTokens Prod" |
        Set-Content "$apacheBase\conf\httpd.conf"

    # Hardening
    $secConf = "$apacheBase\conf\extra\httpd-security.conf"
    @"
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
"@ | Set-Content $secConf

    if (-not (Select-String -Path "$apacheBase\conf\httpd.conf" -Pattern "httpd-security")) {
        Add-Content "$apacheBase\conf\httpd.conf" "`nInclude conf/extra/httpd-security.conf"
    }

    # Index.html
    $verReal = (choco list $CHOCO_APACHE_ID --local-only 2>$null | Select-String "$CHOCO_APACHE_ID\s+\d" | ForEach-Object { ($_ -split '\s+')[1] } | Select-Object -First 1)
    if (-not $verReal) { $verReal = $Version }
    Crear-Index-Html-Win -RootDir "$apacheBase\htdocs" -Servicio "Apache-Win64" -Version $verReal -Puerto $Puerto

    # Instalar como servicio Windows
    & "$apacheBase\bin\httpd.exe" -k install 2>$null | Out-Null
    Start-Service Apache2.4 -ErrorAction SilentlyContinue

    Configurar-Firewall-Win -Puerto $Puerto -Servicio "Apache-Win"
    Write-Host "[OK] Apache Windows desplegado en puerto $Puerto" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
# NGINX WINDOWS (Chocolatey)
# ═══════════════════════════════════════════════════════════════════════════════
function Instalar-Nginx-Win {
    param([string]$Version, [int]$Puerto)
    if (-not (Verifico-Previo-Y-Pregunto-Win -Servicio "nginx" -ChocoPkg "nginx")) { return }

    Asegurar-Chocolatey
    Write-Host "`n[INFO] Instalando Nginx $Version en puerto $Puerto (Chocolatey)..." -ForegroundColor Yellow
    choco install $CHOCO_NGINX_ID --version=$Version -y --no-progress 2>$null
    if ($LASTEXITCODE -ne 0) {
        choco install $CHOCO_NGINX_ID -y --no-progress 2>$null
    }

    $nginxBase = @("C:\nginx","C:\tools\nginx","$env:PROGRAMFILES\nginx") | Where-Object { Test-Path "$_\conf\nginx.conf" } | Select-Object -First 1
    if (-not $nginxBase) {
        Write-Host "[ERROR] No se encontro nginx.conf." -ForegroundColor Red; return
    }

    # Reescribir nginx.conf con hardening y puerto correcto
    @"
worker_processes auto;
events { worker_connections 1024; }
http {
    include mime.types;
    default_type application/octet-stream;
    server_tokens off;
    sendfile on;

    server {
        listen $Puerto;
        server_name _;
        root html;
        index index.html;

        if (`$request_method !~ ^(GET|POST|HEAD)`$) { return 405; }

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Server "WebServer" always;

        location / { try_files `$uri `$uri/ =404; }
    }
}
"@ | Set-Content "$nginxBase\conf\nginx.conf"

    $verReal = (choco list $CHOCO_NGINX_ID --local-only 2>$null | Select-String "nginx\s+\d" | ForEach-Object { ($_ -split '\s+')[1] } | Select-Object -First 1)
    if (-not $verReal) { $verReal = $Version }
    Crear-Index-Html-Win -RootDir "$nginxBase\html" -Servicio "Nginx-Win" -Version $verReal -Puerto $Puerto

    # Iniciar Nginx
    Push-Location $nginxBase
    Start-Process -FilePath ".\nginx.exe" -WindowStyle Hidden
    Pop-Location

    Configurar-Firewall-Win -Puerto $Puerto -Servicio "Nginx-Win"
    Write-Host "[OK] Nginx Windows desplegado en puerto $Puerto" -ForegroundColor Green
}

# ─── Estado de servicios Windows ─────────────────────────────────────────────
function Estado-Servicios-HTTP-Win {
    Write-Host "`n=============================" -ForegroundColor Blue
    Write-Host "  ESTADO SERVICIOS HTTP WIN  " -ForegroundColor Blue
    Write-Host "=============================" -ForegroundColor Blue

    # Priorizar IP del adaptador Host-Only (192.168.x.x) para red interna
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.*" } | Select-Object -First 1).IPAddress
    if (-not $ip) {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
    }
    if (-not $ip) { $ip = "127.0.0.1" }

    $serviciosInfo = @(
        @{ SvcName = "W3SVC"; DispName = "IIS"; ProcessName = "w3wp" }
        @{ SvcName = "Apache2.4"; DispName = "Apache"; ProcessName = "httpd" }
        @{ SvcName = "nginx"; DispName = "Nginx"; ProcessName = "nginx" }
    )

    foreach ($item in $serviciosInfo) {
        $status = "INACTIVO"
        $puertoReal = "?"
        $url = ""

        if ($item.SvcName -eq "nginx") {
            $procs = Get-Process -Name $item.ProcessName -ErrorAction SilentlyContinue
            if ($procs) {
                $status = "ACTIVO"
                $pids = $procs.Id
                $conn = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $pids -contains $_.OwningProcess } | Select-Object -First 1
                if ($conn) { $puertoReal = $conn.LocalPort }
            }
        } else {
            $svc = Get-Service -Name $item.SvcName -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.Status -eq "Running") {
                    $status = "ACTIVO"
                    if ($item.SvcName -eq "W3SVC") {
                        Import-Module WebAdministration -ErrorAction SilentlyContinue
                        $binding = Get-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue
                        if ($binding) { $puertoReal = $binding.bindingInformation.Split(':')[-2] }
                    } else {
                        $procs = Get-Process -Name $item.ProcessName -ErrorAction SilentlyContinue
                        if ($procs) {
                            $pids = $procs.Id
                            $conn = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $pids -contains $_.OwningProcess } | Select-Object -First 1
                            if ($conn) { $puertoReal = $conn.LocalPort }
                        }
                    }
                }
            } else {
                $status = "NO INSTALADO"
            }
        }

        $col = if ($status -eq "ACTIVO") { "Green" } elseif ($status -eq "INACTIVO") { "Red" } else { "Yellow" }
        if ($status -eq "ACTIVO" -and $puertoReal -ne "?") {
            $url = "  → http://${ip}:$puertoReal"
            Write-Host "  [$status] $($item.DispName) (puerto: $puertoReal)$url" -ForegroundColor $col
        } else {
            Write-Host "  [$status] $($item.DispName)" -ForegroundColor $col
        }
    }

    Write-Host "`nTodos los puertos HTTP activos:"
    $puertosActivos = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object {
        $p = $_.LocalPort
        $PUERTOS_RESERVADOS -notcontains $p -and $p -ne 0 -and $p -ne 3389 -and $p -ne 5985 -and $p -ne 5986
    }
    if (-not $puertosActivos) {
        Write-Host "  (ningun servicio HTTP detectado)" -ForegroundColor Yellow
    } else {
        $printedPorts = @()
        foreach ($conn in $puertosActivos) {
            $p = $conn.LocalPort
            if ($printedPorts -notcontains $p) {
                $printedPorts += $p
                $code = "?"
                try {
                    $res = Invoke-WebRequest -Uri "http://localhost:$p" -Method Head -TimeoutSec 1 -ErrorAction Stop
                    $code = [int]$res.StatusCode
                } catch {
                    if ($_.Exception.Response) {
                        $code = [int]$_.Exception.Response.StatusCode
                    }
                }
                Write-Host "    Puerto $p  →  http://${ip}:$p   ($code)" -ForegroundColor Cyan
            }
        }
    }
}

# ─── Menú principal Windows ───────────────────────────────────────────────────
function Menu-HTTP-Win {
    Write-Host "`n======================================================" -ForegroundColor Blue
    Write-Host "  GESTOR HTTP WINDOWS - TAREA 6" -ForegroundColor Blue
    Write-Host "======================================================" -ForegroundColor Blue
    Write-Host "  1) Instalar IIS"
    Write-Host "  2) Instalar Apache para Windows (Chocolatey)"
    Write-Host "  3) Instalar Nginx para Windows (Chocolatey)"
    Write-Host "  4) Estado de servicios HTTP"
    Write-Host "  5) Salir"
}
