# Script: tarea1_diagnostico.ps1
# Descripción: Script de diagnóstico de entorno base para Windows (Tarea 1).
#               Muestra el nombre del equipo, IPs actuales y espacio en disco.
# Autor: Antigravity AI
# Uso: .\tarea1_diagnostico.ps1

$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "======================================================" -ForegroundColor Blue
Write-Host "          DIAGNÓSTICO DE SISTEMA - WINDOWS           " -ForegroundColor Blue
Write-Host "======================================================" -ForegroundColor Blue

# 1. Nombre del equipo (Hostname)
$hostname = $env:COMPUTERNAME
Write-Host "`n1. Nombre del Equipo (Hostname):" -ForegroundColor White
Write-Host "  - Hostname: $hostname" -ForegroundColor Green

# 2. Direcciones IP actuales
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
    Write-Host "  - No se encontraron volúmenes válidos." -ForegroundColor Yellow
} else {
    foreach ($vol in $volumes) {
        $letter = $vol.DriveLetter
        $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "Sin Etiqueta" }
        $totalGB = [Math]::Round($vol.Size / 1GB, 2)
        $freeGB = [Math]::Round($vol.SizeRemaining / 1GB, 2)
        $usedGB = [Math]::Round($totalGB - $freeGB, 2)
        $pctUsed = if ($totalGB -gt 0) { [Math]::Round(($usedGB / $totalGB) * 100, 2) } else { 0 }
        
        Write-Host "  - Unidad $letter: ($label) | Total: " -NoNewline -ForegroundColor Green
        Write-Host "$totalGB GB " -NoNewline -ForegroundColor Cyan
        Write-Host "| Usado: " -NoNewline -ForegroundColor Green
        Write-Host "$usedGB GB ($pctUsed%) " -NoNewline -ForegroundColor Yellow
        Write-Host "| Libre: " -NoNewline -ForegroundColor Green
        Write-Host "$freeGB GB" -ForegroundColor Green
    }
}

# 4. Información adicional de diagnóstico
Write-Host "`n4. Información de Diagnóstico Adicional:" -ForegroundColor White

# OS Version
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Write-Host "  - Sistema Operativo: " -NoNewline -ForegroundColor Green
    Write-Host "$($os.Caption) ($($os.OSArchitecture) / $($os.Version))" -ForegroundColor White
} catch {
    Write-Host "  - Sistema Operativo: Windows Server / Windows Client" -ForegroundColor White
}

# RAM Memory
try {
    $physicalMem = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum
    $totalRamGB = if ($physicalMem.Sum -gt 0) { [Math]::Round($physicalMem.Sum / 1GB, 2) } else { 
        # Fallback if CimInstance fails
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
    Write-Host "  - Memoria RAM: Información no disponible" -ForegroundColor Yellow
}

# Uptime
try {
    $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    $uptimeStr = "$($uptime.Days) días, $($uptime.Hours) horas, $($uptime.Minutes) minutos"
    Write-Host "  - Uptime:            " -NoNewline -ForegroundColor Green
    Write-Host "$uptimeStr" -ForegroundColor White
} catch {
    Write-Host "  - Uptime: Información no disponible" -ForegroundColor Yellow
}

Write-Host "`n======================================================" -ForegroundColor Blue
