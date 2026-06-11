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
