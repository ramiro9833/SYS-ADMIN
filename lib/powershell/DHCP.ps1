# lib/powershell/DHCP.ps1
# Funciones para instalacion, configuracion y monitoreo de DHCP en Windows Server.
# Uso: . "$libDir\DHCP.ps1"

function Instalar-DHCP {
    Banner "INSTALACION ISC-DHCP-SERVER (Windows)"
    $dhcpFeature = Get-WindowsFeature -Name DHCP
    if ($dhcpFeature.Installed) {
        Write-Host "[INFO] El rol DHCP ya esta instalado." -ForegroundColor Green
        Get-Service -Name DHCPServer -ErrorAction SilentlyContinue | Format-List Name, Status
        return
    }
    Write-Host "[INFO] Instalando rol DHCP..." -ForegroundColor Yellow
    Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop | Out-Null
    netsh dhcp add securitygroups | Out-Null
    Restart-Service -Name DHCPServer -Force
    Write-Host "[OK] Rol DHCP instalado." -ForegroundColor Green
}

function Configurar-DHCP {
    Banner "CONFIGURACION DEL SERVIDOR DHCP"

    $scopeName  = Read-Host "Nombre del Ambito [Red_Sistemas]"
    if ([string]::IsNullOrEmpty($scopeName)) { $scopeName = "Red_Sistemas" }

    $subnet     = Leer-IP "ID de Subred" "192.168.100.0"
    $mask       = Leer-IP "Mascara de Subred" "255.255.255.0"
    $rangeStart = Leer-IP "Rango Inicial" "192.168.100.50"
    $rangeEnd   = Leer-IP "Rango Final" "192.168.100.150"
    $gateway    = Leer-IP "Gateway" "192.168.100.1"
    $dns        = Leer-IP "Servidor DNS" "192.168.100.10"

    $leaseSpan  = New-TimeSpan -Minutes 10

    try {
        $existingScopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
        if ($existingScopes | Where-Object { $_.ScopeId.IPAddressToString -eq $subnet }) {
            Write-Host "[AVISO] Ambito $subnet ya existe. Eliminando para reconfigurar..." -ForegroundColor Yellow
            Remove-DhcpServerv4Scope -ScopeId $subnet -Force
        }

        Add-DhcpServerv4Scope -Name $scopeName -StartRange $rangeStart -EndRange $rangeEnd `
            -SubnetMask $mask -LeaseDuration $leaseSpan -State Active
        Write-Host "[OK] Ambito '$scopeName' creado y activado." -ForegroundColor Green

        Set-DhcpServerv4OptionValue -ScopeId $subnet -Router $gateway
        Write-Host "[OK] Gateway configurado: $gateway" -ForegroundColor Green

        netsh dhcp server scope $subnet set optionvalue 6 IPADDRESS $dns | Out-Null
        Write-Host "[OK] DNS configurado: $dns" -ForegroundColor Green

        Set-Service -Name DHCPServer -StartupType Automatic
        Start-Service -Name DHCPServer -ErrorAction SilentlyContinue
        Write-Host "[OK] Servicio DHCP configurado." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Fallo la configuracion DHCP: $_" -ForegroundColor Red
    }
}

function Monitorear-DHCP {
    $continuar = $true
    while ($continuar) {
        Banner "MONITOREO DHCP - WINDOWS SERVER"
        Write-Host "  1) Estado del servicio DHCP"
        Write-Host "  2) Listar ambitos activos"
        Write-Host "  3) Listar concesiones activas"
        Write-Host "  4) Volver"
        $choice = Read-Host "Opcion (1-4)"

        if ($choice -eq "1") {
            Get-Service -Name DHCPServer | Format-List Name, Status, StartType
        }
        elseif ($choice -eq "2") {
            Get-DhcpServerv4Scope | Format-Table ScopeId, SubnetMask, Name, State
        }
        elseif ($choice -eq "3") {
            $targetScope = Read-Host "ScopeId [192.168.100.0]"
            if ([string]::IsNullOrEmpty($targetScope)) { $targetScope = "192.168.100.0" }
            $leases = Get-DhcpServerv4Lease -ScopeId $targetScope -ErrorAction SilentlyContinue
            if ($leases) {
                $leases | Format-Table IPAddress, ClientId, HostName, AddressState, LeaseExpiryTime
            } else {
                Write-Host "Sin concesiones activas para $targetScope." -ForegroundColor Yellow
            }
        }
        elseif ($choice -eq "4") {
            $continuar = $false
        }
        else {
            Write-Host "Opcion invalida." -ForegroundColor Red
        }
    }
}
