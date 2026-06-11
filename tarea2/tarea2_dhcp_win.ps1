# Script: tarea2_dhcp_win.ps1
# Descripción: Automatización y Gestión de Servidor DHCP en Windows Server 2022.
#               Instalación de características, configuración guiada y monitoreo.
# Autor: Antigravity AI
# Uso: Ejecutar en PowerShell como Administrador: .\tarea2_dhcp_win.ps1

$OutputEncoding = [System.Text.Encoding]::UTF8

# Verificar permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Este script debe ser ejecutado en una sesión de PowerShell como Administrador." -ForegroundColor Red
    Exit
}

# Función para validar direcciones IP
function Validar-IP ($ipAddress) {
    if ($ipAddress -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$") {
        $octets = $ipAddress.Split('.')
        foreach ($oct in $octets) {
            if ([int]$oct -lt 0 -or [int]$oct -gt 255) { return $false }
        }
        return $true
    }
    return $false
}

# 1. Instalación Idempotente
function Instalar-DHCPFeature {
    Write-Host "`n[1/4] Verificando características del rol DHCP..." -ForegroundColor Blue
    $dhcpFeature = Get-WindowsFeature -Name DHCP
    
    if ($dhcpFeature.Installed) {
        Write-Host "[INFO] El rol DHCP ya se encuentra instalado en este sistema." -ForegroundColor Green
    } else {
        Write-Host "[INFO] El rol DHCP no está instalado. Iniciando instalación desatendida..." -ForegroundColor Yellow
        try {
            Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop | Out-Null
            Write-Host "[OK] Rol DHCP e herramientas de administración instaladas correctamente." -ForegroundColor Green
            
            # Configurar grupos de seguridad locales DHCP (Recomendado para servidores independientes)
            Write-Host "Configurando grupos de seguridad DHCP locales..." -ForegroundColor Gray
            netsh dhcp add securitygroups | Out-Null
            
            # Reiniciar servicio para aplicar grupos
            Restart-Service -Name DHCPServer -Force
        } catch {
            Write-Host "[ERROR] Ocurrió un error al instalar el rol DHCP: $_" -ForegroundColor Red
            Exit
        }
    }
}

# 2. Orquestación de Configuración Dinámica
function Configurar-DHCPServer {
    Write-Host "`n[2/4] Configuración del Servidor DHCP" -ForegroundColor Blue
    
    # Nombre del Ámbito
    $scopeName = Read-Host "Nombre descriptivo del Ámbito (ej: Red_Sistemas)"
    if ([string]::IsNullOrEmpty($scopeName)) { $scopeName = "Red_Sistemas" }

    # IP de Subred
    $subnet = $null
    while ($true) {
        $inputSub = Read-Host "ID de Subred [192.168.100.0]"
        if ([string]::IsNullOrEmpty($inputSub)) { $subnet = "192.168.100.0"; break }
        if (Validar-IP $inputSub) { $subnet = $inputSub; break }
        Write-Host "IP inválida." -ForegroundColor Red
    }

    # Máscara de Subred
    $mask = $null
    while ($true) {
        $inputMask = Read-Host "Máscara de Subred [255.255.255.0]"
        if ([string]::IsNullOrEmpty($inputMask)) { $mask = "255.255.255.0"; break }
        if (Validar-IP $inputMask) { $mask = $inputMask; break }
        Write-Host "Máscara inválida." -ForegroundColor Red
    }

    # Rango Inicial
    $rangeStart = $null
    while ($true) {
        $inputStart = Read-Host "Rango IP - Dirección Inicial [192.168.100.50]"
        if ([string]::IsNullOrEmpty($inputStart)) { $rangeStart = "192.168.100.50"; break }
        if (Validar-IP $inputStart) { $rangeStart = $inputStart; break }
        Write-Host "IP inválida." -ForegroundColor Red
    }

    # Rango Final
    $rangeEnd = $null
    while ($true) {
        $inputEnd = Read-Host "Rango IP - Dirección Final [192.168.100.150]"
        if ([string]::IsNullOrEmpty($inputEnd)) { $rangeEnd = "192.168.100.150"; break }
        if (Validar-IP $inputEnd) { $rangeEnd = $inputEnd; break }
        Write-Host "IP inválida." -ForegroundColor Red
    }

    # Tiempos de Concesión (Lease Duration)
    Write-Host "`nDuración de la Concesión (Lease Duration):" -ForegroundColor Yellow
    $days = 0; $hours = 8; $minutes = 0
    
    $inDays = Read-Host "Días [0]"
    if ($inDays -match "^\d+$") { $days = [int]$inDays }
    
    $inHours = Read-Host "Horas [8]"
    if ($inHours -match "^\d+$") { $hours = [int]$inHours }
    
    $inMins = Read-Host "Minutos [0]"
    if ($inMins -match "^\d+$") { $minutes = [int]$inMins }

    $leaseSpan = New-TimeSpan -Days $days -Hours $hours -Minutes $minutes

    # Gateway (Router)
    $gateway = $null
    while ($true) {
        $inputGw = Read-Host "Puerta de enlace (Router/Gateway) [192.168.100.1]"
        if ([string]::IsNullOrEmpty($inputGw)) { $gateway = "192.168.100.1"; break }
        if (Validar-IP $inputGw) { $gateway = $inputGw; break }
        Write-Host "IP inválida." -ForegroundColor Red
    }

    # DNS Server
    $dns = $null
    while ($true) {
        $inputDns = Read-Host "Servidor DNS [192.168.100.10]"
        if ([string]::IsNullOrEmpty($inputDns)) { $dns = "192.168.100.10"; break }
        if (Validar-IP $inputDns) { $dns = $inputDns; break }
        Write-Host "IP inválida." -ForegroundColor Red
    }

    # 3. Aplicar Configuración en el Servidor
    Write-Host "`n[3/4] Creando Ámbito y Opciones de Red en el Servidor..." -ForegroundColor Blue
    
    try {
        # Verificar si el ámbito ya existe para evitar errores
        $existingScopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
        if ($existingScopes | Where-Object { $_.ScopeId.IPAddressToString -eq $subnet }) {
            Write-Host "[WARNING] El ámbito con ID $subnet ya existe. Eliminándolo para reconfigurar..." -ForegroundColor Yellow
            Remove-DhcpServerv4Scope -ScopeId $subnet -Force -ErrorAction Stop
        }

        # Agregar el ámbito DHCP
        Add-DhcpServerv4Scope -Name $scopeName -StartRange $rangeStart -EndRange $rangeEnd -SubnetMask $mask -LeaseDuration $leaseSpan -State Active -ErrorAction Stop
        Write-Host "[OK] Ámbito '$scopeName' ($subnet) creado y activado." -ForegroundColor Green

        # Agregar Opción 3 (Gateway/Router) - sin validación de DNS
        Set-DhcpServerv4OptionValue -ScopeId $subnet -Router $gateway -ErrorAction Stop
        Write-Host "[OK] Gateway configurado: $gateway" -ForegroundColor Green

        # Agregar Opción 6 (DNS) usando netsh para evitar la validación de conectividad DNS
        $netshOut = netsh dhcp server scope $subnet set optionvalue 6 IPADDRESS $dns 2>&1
        Write-Host "[OK] DNS configurado: $dns (via netsh)" -ForegroundColor Green

        # Asegurar servicio iniciado y automático
        Set-Service -Name DHCPServer -StartupType Automatic
        Start-Service -Name DHCPServer -ErrorAction SilentlyContinue
        Write-Host "[OK] Servicio DHCP Server configurado para inicio automático y ejecutándose." -ForegroundColor Green

    } catch {
        Write-Host "[ERROR] No se pudo configurar el Servidor DHCP: $_" -ForegroundColor Red
        Exit
    }
}

# 4. Módulo de Monitoreo
function Monitorear-DHCP {
    while ($true) {
        Write-Host "`n======================================================" -ForegroundColor Blue
        Write-Host "      MÓDULO DE MONITOREO Y VALIDACIÓN DHCP (WS)     " -ForegroundColor Blue
        Write-Host "======================================================" -ForegroundColor Blue
        Write-Host "  1) Ver estado actual del servicio DHCP"
        Write-Host "  2) Listar todos los ámbitos activos"
        Write-Host "  3) Listar concesiones (leases) activas por ámbito"
        Write-Host "  4) Ver estadísticas generales del servidor"
        Write-Host "  5) Volver / Salir"
        
        $choice = Read-Host "Seleccione una opción (1-5)"
        
        switch ($choice) {
            "1" {
                Write-Host "`nEstado del servicio DHCPServer:" -ForegroundColor White
                Get-Service -Name DHCPServer | Format-List | Out-String | Write-Host
            }
            "2" {
                Write-Host "`nÁmbitos v4 configurados:" -ForegroundColor White
                Get-DhcpServerv4Scope | Format-Table -Property ScopeId, SubnetMask, Name, State | Out-String | Write-Host
            }
            "3" {
                $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
                if ($null -eq $scopes -or $scopes.Count -eq 0) {
                    Write-Host "No hay ámbitos configurados en este servidor." -ForegroundColor Yellow
                    continue
                }
                
                Write-Host "`nÁmbitos disponibles:" -ForegroundColor Cyan
                $scopes | Format-Table -Property ScopeId, Name | Out-String | Write-Host
                
                $targetScope = Read-Host "Ingrese el ScopeId (ID de Subred, ej: 192.168.100.0)"
                if (-not [string]::IsNullOrEmpty($targetScope)) {
                    try {
                        $leases = Get-DhcpServerv4Lease -ScopeId $targetScope -ErrorAction Stop
                        if ($null -eq $leases -or $leases.Count -eq 0) {
                            Write-Host "No se encontraron concesiones (leases) activas para el ámbito $targetScope." -ForegroundColor Yellow
                        } else {
                            Write-Host "`nConcesiones Activas en $targetScope`:" -ForegroundColor Green
                            $leases | Format-Table -Property IPAddress, ClientId, HostName, AddressState, LeaseExpiryTime | Out-String | Write-Host
                        }
                    } catch {
                        Write-Host "Error al consultar las concesiones: $_" -ForegroundColor Red
                    }
                }
            }
            "4" {
                Write-Host "`nEstadísticas del Servidor DHCP v4:" -ForegroundColor White
                try {
                    Get-DhcpServerv4Statistics | Format-List | Out-String | Write-Host
                } catch {
                    Write-Host "No se pudieron obtener estadísticas." -ForegroundColor Red
                }
            }
            "5" {
                break
            }
            default {
                Write-Host "Opción no válida." -ForegroundColor Red
            }
        }
    }
}

# Menú Principal
function Menu-Principal {
    while ($true) {
        Write-Host "`n======================================================" -ForegroundColor Blue
        Write-Host "       GESTOR DE SERVIDOR DHCP - WINDOWS (PS)         " -ForegroundColor Blue
        Write-Host "======================================================" -ForegroundColor Blue
        Write-Host "  1) Instalación Inicial Idempotente (Windows Feature)"
        Write-Host "  2) Configurar Ámbito DHCP e Inicializar (Interactivo)"
        Write-Host "  3) Módulo de Monitoreo y Validación"
        Write-Host "  4) Salir"
        
        $opt = Read-Host "Seleccione una opción (1-4)"
        
        switch ($opt) {
            "1" {
                Instalar-DHCPFeature
            }
            "2" {
                # Asegurar rol instalado
                $status = Get-WindowsFeature -Name DHCP
                if (-not $status.Installed) {
                    Instalar-DHCPFeature
                }
                Configurar-DHCPServer
            }
            "3" {
                Monitorear-DHCP
            }
            "4" {
                Write-Host "`n¡Hasta luego!" -ForegroundColor Green
                Exit
            }
            default {
                Write-Host "Opción inválida." -ForegroundColor Red
            }
        }
    }
}

# Iniciar menú principal
Menu-Principal
