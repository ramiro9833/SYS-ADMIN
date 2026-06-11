# lib/powershell/Red.ps1
# Funciones de configuracion de red reutilizables.
# Uso: . "$libDir\Red.ps1"

function Verificar-IPEstatica {
    Write-Host "`n[CHECK] Verificando configuracion de IP estatica..." -ForegroundColor Blue

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notlike "*Loopback*" }

    $internalAdapter = $null
    foreach ($a in $adapters) {
        $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        if ($ip -and $ip -notlike "10.0.*" -and $ip -ne "127.0.0.1") {
            $internalAdapter = [PSCustomObject]@{ Adapter = $a; IP = $ip }
            break
        }
    }

    if ($internalAdapter) {
        $dhcpState = (Get-NetIPInterface -InterfaceIndex $internalAdapter.Adapter.ifIndex -AddressFamily IPv4).Dhcp
        if ($dhcpState -eq "Disabled") {
            Write-Host "[OK] IP estatica detectada: $($internalAdapter.IP) en '$($internalAdapter.Adapter.Name)'" -ForegroundColor Green
            $script:SERVER_IP = $internalAdapter.IP
            $script:SERVER_IFACE_INDEX = $internalAdapter.Adapter.ifIndex
        } else {
            Write-Host "[AVISO] Adaptador usa DHCP. Configurando IP estatica..." -ForegroundColor Yellow
            Configurar-IPEstatica -InterfaceIndex $internalAdapter.Adapter.ifIndex
        }
    } else {
        Write-Host "[AVISO] No se encontro interfaz interna. Adaptadores disponibles:" -ForegroundColor Yellow
        Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Format-Table ifIndex, Name, Status
        $idx = Read-Host "ifIndex del adaptador de red interna"
        Configurar-IPEstatica -InterfaceIndex ([int]$idx)
    }
}

function Configurar-IPEstatica($InterfaceIndex) {
    Write-Host "`n[IP] Configurando IP Estatica..." -ForegroundColor Blue

    $newIP  = Leer-IP "IP estatica para este servidor" "192.168.100.20"
    $prefix = 24
    $gw     = Leer-IP "Puerta de enlace (Gateway)" "192.168.100.1"

    try {
        Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        New-NetIPAddress -InterfaceIndex $InterfaceIndex -IPAddress $newIP -PrefixLength $prefix -DefaultGateway $gw | Out-Null
        Write-Host "[OK] IP estatica $newIP/$prefix configurada." -ForegroundColor Green
        $script:SERVER_IP = $newIP
        $script:SERVER_IFACE_INDEX = $InterfaceIndex
    } catch {
        Write-Host "[ERROR] No se pudo configurar la IP: $_" -ForegroundColor Red
    }
}

function Configurar-Red-Servidor-Windows {
    Banner "CONFIGURACION DE RED - WINDOWS SERVER (POWERSHELL)"

    # 1. Obtener adaptadores de red
    Write-Host "`nDetectando adaptadores de red en el sistema..." -ForegroundColor Gray
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -or $_.Status -eq "Disconnected" }

    if ($adapters.Count -eq 0) {
        Write-Host "[ERROR] No se encontraron adaptadores de red en el equipo." -ForegroundColor Red
        return
    }

    Write-Host "`nAdaptadores de red disponibles:" -ForegroundColor Cyan
    $adapters | Format-Table -Property InterfaceIndex, Name, InterfaceDescription, Status, LinkSpeed | Out-String | Write-Host

    # Solicitar seleccion
    $idx = $null
    while ($true) {
        $sel = Read-Host "Seleccione el InterfaceIndex del adaptador para la Red Interna (red_sistemas)"
        if ($sel -match "^\d+$" -and ($adapters.InterfaceIndex -contains [int]$sel)) {
            $idx = [int]$sel
            break
        } else {
            Write-Host "Seleccion invalida. Intentelo de nuevo." -ForegroundColor Red
        }
    }

    $adapter = Get-NetAdapter -InterfaceIndex $idx
    Write-Host "`nAdaptador seleccionado: $($adapter.Name) ($($adapter.InterfaceDescription))" -ForegroundColor Green

    # 2. Configurar direccion IP
    $defaultIP = "192.168.100.20"
    $defaultPrefix = 24

    Write-Host "`nConfiguracion de IP Estatica (Presione Enter para valores por defecto):" -ForegroundColor Yellow
    $ip = Leer-IP "Direccion IP" $defaultIP

    # Solicitar mascara CIDR
    $prefix = $null
    while ($true) {
        $prefixInput = Read-Host "Prefijo de red CIDR (ej: 24) [$defaultPrefix]"
        if ([string]::IsNullOrEmpty($prefixInput)) {
            $prefix = $defaultPrefix
            break
        }
        if ($prefixInput -match "^\d+$" -and [int]$prefixInput -ge 0 -and [int]$prefixInput -le 32) {
            $prefix = [int]$prefixInput
            break
        }
        Write-Host "Prefijo CIDR invalido (debe ser entre 0 y 32)." -ForegroundColor Red
    }

    # 3. Aplicar los cambios
    Write-Host "`nAplicando configuracion..." -ForegroundColor Gray

    # Remover IPs estaticas existentes en la interfaz seleccionada para evitar conflictos
    $existingIPs = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254.*" }

    if ($existingIPs) {
        Write-Host "Eliminando direcciones IP previas en el adaptador..." -ForegroundColor Gray
        foreach ($oldIP in $existingIPs) {
            Remove-NetIPAddress -InterfaceIndex $idx -IPAddress $oldIP.IPAddress -Confirm:$false
        }
    }

    # Configurar nueva direccion IP
    try {
        New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop | Out-Null
        Write-Host "[OK] Direccion IP $ip/$prefix configurada con exito." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] No se pudo configurar la direccion IP: $_" -ForegroundColor Red
        return
    }

    # Mostrar resumen final
    Write-Host "`nResumen de configuracion actual de la interfaz:" -ForegroundColor Cyan
    Get-NetIPConfiguration -InterfaceIndex $idx | Out-String | Write-Host
}
