# lib/powershell/Comunes.ps1
# Biblioteca de funciones comunes para todos los scripts PowerShell del proyecto.
# Uso: . "$PSScriptRoot\..\..\lib\powershell\Comunes.ps1"

# ─── Verificar privilegios de Administrador ──────────────────────────────────
function Verificar-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[ERROR] Ejecutar como Administrador." -ForegroundColor Red
        Exit 1
    }
}

# ─── Validar formato IPv4 ────────────────────────────────────────────────────
function Validar-IP($ip) {
    if ($ip -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$") {
        foreach ($oct in $ip.Split('.')) {
            if ([int]$oct -lt 0 -or [int]$oct -gt 255) { return $false }
        }
        return $true
    }
    return $false
}

# ─── Leer IP con validación interactiva ──────────────────────────────────────
function Leer-IP($prompt, $default) {
    while ($true) {
        $val = Read-Host "$prompt [$default]"
        if ([string]::IsNullOrEmpty($val)) { return $default }
        if (Validar-IP $val) { return $val }
        Write-Host "[ERROR] IP invalida. Formato: X.X.X.X (0-255 por octeto)" -ForegroundColor Red
    }
}

# ─── Instalar característica de Windows de forma idempotente ─────────────────
function Instalar-Feature($featureName) {
    $feat = Get-WindowsFeature -Name $featureName
    if ($feat.Installed) {
        Write-Host "[INFO] Caracteristica '$featureName' ya instalada." -ForegroundColor Green
        return
    }
    Write-Host "[INFO] Instalando '$featureName'..." -ForegroundColor Yellow
    Install-WindowsFeature -Name $featureName -IncludeManagementTools -ErrorAction Stop | Out-Null
    Write-Host "[OK] '$featureName' instalada correctamente." -ForegroundColor Green
}

# ─── Banner de sección ────────────────────────────────────────────────────────
function Banner($titulo) {
    Write-Host "`n======================================================" -ForegroundColor Blue
    Write-Host "  $titulo" -ForegroundColor Blue
    Write-Host "======================================================" -ForegroundColor Blue
}

# ─── Diagnóstico de sistema (Windows) ────────────────────────────────────────
function Mostrar-Diagnostico {
    Banner "DIAGNOSTICO DE SISTEMA - WINDOWS"

    # 1. Hostname
    $hostname = $env:COMPUTERNAME
    Write-Host "`n1. Nombre del Equipo (Hostname):" -ForegroundColor White
    Write-Host "  - Hostname: $hostname" -ForegroundColor Green

    # 2. Direcciones IP
    Write-Host "`n2. Direcciones IP IPv4 Activas:" -ForegroundColor White
    $ipConfigs = Get-NetIPConfiguration -ErrorAction SilentlyContinue
    if ($null -eq $ipConfigs -or $ipConfigs.Count -eq 0) {
        Write-Host "  - No se detectaron interfaces de red configuradas." -ForegroundColor Yellow
    } else {
        foreach ($cfg in $ipConfigs) {
            if ($cfg.IPv4Address) {
                $interface = $cfg.InterfaceAlias
                $ip = $cfg.IPv4Address.IPAddress
                $gateway = if ($cfg.IPv4DefaultGateway) { $cfg.IPv4DefaultGateway.NextHop } else { "Ninguno" }
                
                Write-Host "  - Interfaz: " -NoNewline -ForegroundColor Green
                Write-Host "$interface " -NoNewline -ForegroundColor White
                Write-Host "| IP: " -NoNewline -ForegroundColor Green
                Write-Host "$ip " -NoNewline -ForegroundColor Yellow
                Write-Host "| Puerta de Enlace: " -NoNewline -ForegroundColor Green
                Write-Host "$gateway" -ForegroundColor Cyan
            }
        }
    }

    # 3. Espacio en disco
    Write-Host "`n3. Espacio en Disco (Volúmenes con letra asignada):" -ForegroundColor White
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 }
    if ($null -eq $volumes -or $volumes.Count -eq 0) {
        Write-Host "  - No se encontraron volumenes validos." -ForegroundColor Yellow
    } else {
        foreach ($vol in $volumes) {
            $letter = $vol.DriveLetter
            $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "Sin Etiqueta" }
            $totalGB = [Math]::Round($vol.Size / 1GB, 2)
            $freeGB = [Math]::Round($vol.SizeRemaining / 1GB, 2)
            $usedGB = [Math]::Round($totalGB - $freeGB, 2)
            $pctUsed = if ($totalGB -gt 0) { [Math]::Round(($usedGB / $totalGB) * 100, 2) } else { 0 }
            
            Write-Host "  - Unidad ${letter}: ($label) | Total: " -NoNewline -ForegroundColor Green
            Write-Host "$totalGB GB " -NoNewline -ForegroundColor Cyan
            Write-Host "| Usado: " -NoNewline -ForegroundColor Green
            Write-Host "$usedGB GB ($pctUsed%) " -NoNewline -ForegroundColor Yellow
            Write-Host "| Libre: " -NoNewline -ForegroundColor Green
            Write-Host "$freeGB GB" -ForegroundColor Green
        }
    }

    # 4. Información adicional
    Write-Host "`n4. Informacion de Diagnostico Adicional:" -ForegroundColor White
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        Write-Host "  - Sistema Operativo: " -NoNewline -ForegroundColor Green
        Write-Host "$($os.Caption) ($($os.OSArchitecture) / $($os.Version))" -ForegroundColor White
    } catch {
        Write-Host "  - Sistema Operativo: Windows Server" -ForegroundColor White
    }

    try {
        $physicalMem = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum
        $totalRamGB = if ($physicalMem.Sum -gt 0) { [Math]::Round($physicalMem.Sum / 1GB, 2) } else { 
            [Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1MB, 2)
        }
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $freeRamGB = [Math]::Round($osInfo.FreePhysicalMemory / 1MB, 2)
        $usedRamGB = [Math]::Round($totalRamGB - $freeRamGB, 2)
        
        Write-Host "  - Memoria RAM:       " -NoNewline -ForegroundColor Green
        Write-Host "Total: " -NoNewline -ForegroundColor Green
        Write-Host "$totalRamGB GB " -NoNewline -ForegroundColor Cyan
        Write-Host "| Usada: " -NoNewline -ForegroundColor Green
        Write-Host "$usedRamGB GB " -NoNewline -ForegroundColor Yellow
        Write-Host "| Libre: " -NoNewline -ForegroundColor Green
        Write-Host "$freeRamGB GB" -ForegroundColor Green
    } catch {
        Write-Host "  - Memoria RAM: Informacion no disponible" -ForegroundColor Yellow
    }

    try {
        $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        $uptime = (Get-Date) - $bootTime
        $uptimeStr = "$($uptime.Days) dias, $($uptime.Hours) horas, $($uptime.Minutes) minutos"
        Write-Host "  - Uptime:            " -NoNewline -ForegroundColor Green
        Write-Host "$uptimeStr" -ForegroundColor White
    } catch {
        Write-Host "  - Uptime: Informacion no disponible" -ForegroundColor Yellow
    }

    Write-Host "`n======================================================" -ForegroundColor Blue
}
