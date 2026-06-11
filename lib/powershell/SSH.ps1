# lib/powershell/SSH.ps1
# Funciones para instalacion, configuracion y monitoreo de OpenSSH Server en Windows.
# Uso: . "$libDir\SSH.ps1"

function Instalar-SSH {
    Banner "INSTALACION OPENSSH SERVER"
    Write-Host "[1/3] Verificando estado de OpenSSH Server..." -ForegroundColor Blue

    $sshCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }

    if ($sshCapability -and $sshCapability.State -eq "Installed") {
        Write-Host "[INFO] OpenSSH Server ya esta instalado." -ForegroundColor Green
    } else {
        Write-Host "[INFO] Instalando OpenSSH Server..." -ForegroundColor Yellow
        try {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
            Write-Host "[OK] OpenSSH Server instalado." -ForegroundColor Green
        } catch {
            Write-Host "[AVISO] Instalacion via capacidad opcional fallo. Intentando alternativa..." -ForegroundColor Yellow
        }
    }

    # Iniciar servicio y configurar arranque automatico
    try {
        Start-Service  -Name sshd -ErrorAction SilentlyContinue
        Set-Service    -Name sshd -StartupType Automatic
        Write-Host "[OK] Servicio sshd configurado para inicio automatico." -ForegroundColor Green
    } catch {
        Write-Host "[AVISO] No se pudo configurar el servicio: $_" -ForegroundColor Yellow
    }

    # Regla de firewall para puerto 22
    $fwRule = Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue
    if (-not $fwRule) {
        New-NetFirewallRule -Name "sshd" -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        Write-Host "[OK] Regla firewall creada para puerto 22." -ForegroundColor Green
    } else {
        Write-Host "[INFO] Regla firewall para puerto 22 ya existe." -ForegroundColor Green
    }

    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "[OK] sshd activo, en boot automatico y firewall configurado." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El servicio sshd no pudo iniciarse." -ForegroundColor Red
    }
}

function Configurar-SSH {
    Banner "CONFIGURACION DE SEGURIDAD SSH"
    $sshdConfig = "$env:ProgramData\ssh\sshd_config"

    if (-not (Test-Path $sshdConfig)) {
        Write-Host "[ERROR] No se encontro sshd_config en: $sshdConfig" -ForegroundColor Red
        return
    }

    Copy-Item $sshdConfig "$sshdConfig.bak_$(Get-Date -Format 'yyyyMMddHHmm')" -Force
    Write-Host "[INFO] Respaldo de sshd_config creado." -ForegroundColor Cyan

    $content = Get-Content $sshdConfig
    $content = $content -replace "#?PermitRootLogin.*",  "PermitRootLogin no"
    $content = $content -replace "#?MaxAuthTries.*",     "MaxAuthTries 3"
    $content = $content -replace "#?LoginGraceTime.*",   "LoginGraceTime 30"
    $content = $content -replace "#?PrintLastLog.*",     "PrintLastLog yes"
    Set-Content $sshdConfig $content

    Restart-Service sshd -Force
    Write-Host "[OK] Configuracion de seguridad aplicada y servicio reiniciado." -ForegroundColor Green
}

function Monitorear-SSH {
    $continuar = $true
    while ($continuar) {
        Banner "MONITOREO SSH - WINDOWS SERVER"
        Write-Host "  1) Estado del servicio sshd"
        Write-Host "  2) Ver reglas de firewall para SSH"
        Write-Host "  3) Ver conexiones activas en puerto 22"
        Write-Host "  4) Informacion de conexion para clientes"
        Write-Host "  5) Volver al menu principal"

        $choice = Read-Host "Seleccione una opcion (1-5)"

        if ($choice -eq "1") {
            Get-Service -Name sshd -ErrorAction SilentlyContinue | Format-List Name, Status, StartType
        }
        elseif ($choice -eq "2") {
            Write-Host "`nReglas de Firewall para SSH:" -ForegroundColor White
            Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*SSH*" -or $_.DisplayName -like "*sshd*" } |
                Format-Table DisplayName, Enabled, Direction, Action
        }
        elseif ($choice -eq "3") {
            Write-Host "`nConexiones en puerto 22:" -ForegroundColor White
            netstat -ano | findstr ":22"
        }
        elseif ($choice -eq "4") {
            $serverIP = (Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object { $_.IPAddress -like "192.168.*" }).IPAddress |
                Select-Object -First 1
            Write-Host "`n===== INFORMACION DE CONEXION SSH =====" -ForegroundColor Cyan
            Write-Host "Servidor : Windows Server 2022" -ForegroundColor Cyan
            Write-Host "IP       : $serverIP"           -ForegroundColor Cyan
            Write-Host "Puerto   : 22"                  -ForegroundColor Cyan
            Write-Host "Usuario  : Administrator"       -ForegroundColor Cyan
            Write-Host "`nComando desde Linux Mint:"    -ForegroundColor White
            Write-Host "  ssh Administrator@$serverIP"  -ForegroundColor Green
            Write-Host "`nPuTTY: Host=$serverIP  Puerto=22  User=Administrator"
        }
        elseif ($choice -eq "5") {
            $continuar = $false
        }
        else {
            Write-Host "Opcion invalida." -ForegroundColor Red
        }
    }
}
