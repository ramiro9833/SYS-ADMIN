# Script:      tarea3_dns_win.ps1
# Descripción: Automatización del Servidor DNS para el dominio reprobados.com en Windows Server.
#              Instalación idempotente, configuración de zona y monitoreo.
# Autor:       Antigravity AI
# Uso:         Ejecutar en PowerShell como Administrador: .\tarea3_dns_win.ps1

$OutputEncoding = [System.Text.Encoding]::UTF8

# ─── Verificar privilegios de Administrador ──────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Ejecutar como Administrador." -ForegroundColor Red; Exit
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

# ─── Leer IP con validación ──────────────────────────────────────────────────
function Leer-IP($prompt, $default) {
    while ($true) {
        $val = Read-Host "$prompt [$default]"
        if ([string]::IsNullOrEmpty($val)) { return $default }
        if (Validar-IP $val) { return $val }
        Write-Host "[ERROR] IP invalida. Formato: X.X.X.X (0-255 por octeto)" -ForegroundColor Red
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# 1. VERIFICACIÓN DE IP ESTÁTICA
# ════════════════════════════════════════════════════════════════════════════════
function Verificar-IPEstatica {
    Write-Host "`n[CHECK] Verificando configuracion de IP estatica en la interfaz interna..." -ForegroundColor Blue

    # Obtener adaptadores activos (excluir loopback)
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notlike "*Loopback*" }

    # Buscar el adaptador de red interna (el que NO tiene una IP 10.0.x.x de NAT)
    $internalAdapter = $adapters | ForEach-Object {
        $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        if ($ip -and $ip -notlike "10.0.*" -and $ip -ne "127.0.0.1") {
            [PSCustomObject]@{ Adapter = $_; IP = $ip }
        }
    } | Select-Object -First 1

    if ($internalAdapter) {
        # Verificar si es estática (no DHCP)
        $ipConfig = Get-NetIPAddress -InterfaceIndex $internalAdapter.Adapter.ifIndex -AddressFamily IPv4
        $dhcpEnabled = (Get-NetIPInterface -InterfaceIndex $internalAdapter.Adapter.ifIndex -AddressFamily IPv4).Dhcp

        if ($dhcpEnabled -eq "Disabled") {
            Write-Host "[OK] IP estatica detectada: $($internalAdapter.IP) en '$($internalAdapter.Adapter.Name)'" -ForegroundColor Green
            $script:SERVER_IP = $internalAdapter.IP
            $script:SERVER_IFACE_INDEX = $internalAdapter.Adapter.ifIndex
        } else {
            Write-Host "[AVISO] El adaptador '$($internalAdapter.Adapter.Name)' usa DHCP. Se configurara IP estatica." -ForegroundColor Yellow
            Configurar-IPEstatica -InterfaceIndex $internalAdapter.Adapter.ifIndex
        }
    } else {
        Write-Host "[AVISO] No se encontro interfaz interna. Listando adaptadores disponibles:" -ForegroundColor Yellow
        Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Format-Table ifIndex, Name, Status
        $idx = Read-Host "Ingresa el ifIndex del adaptador de red interna"
        Configurar-IPEstatica -InterfaceIndex ([int]$idx)
    }
}

function Configurar-IPEstatica($InterfaceIndex) {
    Write-Host "`n[IP] Configurando IP Estatica en el adaptador (index: $InterfaceIndex)..." -ForegroundColor Blue

    $newIP  = Leer-IP "IP estatica para este servidor" "192.168.100.20"
    $prefix = 24
    $gw     = Leer-IP "Puerta de enlace (Gateway)" "192.168.100.1"

    try {
        # Eliminar IPs anteriores del adaptador
        Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        New-NetIPAddress -InterfaceIndex $InterfaceIndex -IPAddress $newIP -PrefixLength $prefix -DefaultGateway $gw -ErrorAction Stop | Out-Null
        Write-Host "[OK] IP estatica $newIP/$prefix configurada." -ForegroundColor Green
        $script:SERVER_IP = $newIP
        $script:SERVER_IFACE_INDEX = $InterfaceIndex
    } catch {
        Write-Host "[ERROR] No se pudo configurar la IP: $_" -ForegroundColor Red
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# 2. INSTALACIÓN IDEMPOTENTE DEL ROL DNS
# ════════════════════════════════════════════════════════════════════════════════
function Instalar-DNSFeature {
    Write-Host "`n[1/4] Verificando rol DNS Server..." -ForegroundColor Blue

    $feature = Get-WindowsFeature -Name DNS
    if ($feature.Installed) {
        Write-Host "[INFO] El rol DNS Server ya esta instalado. No se requiere accion." -ForegroundColor Green
        Get-Service -Name DNS | Format-List Name, Status, StartType
        return
    }

    Write-Host "[INFO] Instalando DNS Server con herramientas de administracion..." -ForegroundColor Yellow
    try {
        Install-WindowsFeature -Name DNS -IncludeManagementTools -ErrorAction Stop | Out-Null
        Start-Service -Name DNS -ErrorAction SilentlyContinue
        Set-Service  -Name DNS -StartupType Automatic
        Write-Host "[OK] Rol DNS Server instalado y servicio iniciado." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Fallo la instalacion del rol DNS: $_" -ForegroundColor Red; Exit
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# 3. CONFIGURACIÓN DE ZONA DNS
# ════════════════════════════════════════════════════════════════════════════════
function Configurar-DNSServer {
    Write-Host "`n[2/4] Configuracion de Zona DNS" -ForegroundColor Blue

    # Parámetros interactivos
    $domain = Read-Host "Dominio a configurar [reprobados.com]"
    if ([string]::IsNullOrEmpty($domain)) { $domain = "reprobados.com" }

    $clientIP = Leer-IP "IP del nodo cliente (registro A apuntara aqui)" "192.168.100.30"
    $nsIP     = if ($script:SERVER_IP) { $script:SERVER_IP } else { "192.168.100.20" }

    Write-Host "`n  Dominio    : $domain" -ForegroundColor Cyan
    Write-Host   "  IP Cliente : $clientIP" -ForegroundColor Cyan
    Write-Host   "  IP Servidor: $nsIP" -ForegroundColor Cyan
    $confirm = Read-Host "Continuar con esta configuracion? [s/N]"
    if ($confirm -notmatch "^[sS]$") { Write-Host "Operacion cancelada."; return }

    Write-Host "`n[3/4] Creando zona y registros DNS en Windows Server..." -ForegroundColor Blue

    try {
        # ── Zona primaria ─────────────────────────────────────────────────────
        $existingZone = Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue
        if ($existingZone) {
            Write-Host "[AVISO] La zona '$domain' ya existe. Eliminando para reconfigurar..." -ForegroundColor Yellow
            Remove-DnsServerZone -Name $domain -Force -ErrorAction Stop
        }

        Add-DnsServerPrimaryZone -Name $domain -ZoneFile "db.$domain.dns" -DynamicUpdate None -ErrorAction Stop
        Write-Host "[OK] Zona primaria '$domain' creada." -ForegroundColor Green

        # ── Registro A para el dominio raíz (@) ──────────────────────────────
        Add-DnsServerResourceRecordA -ZoneName $domain -Name "@" -IPv4Address $clientIP -ErrorAction Stop
        Write-Host "[OK] Registro A: $domain -> $clientIP" -ForegroundColor Green

        # ── Registro A para www ───────────────────────────────────────────────
        Add-DnsServerResourceRecordA -ZoneName $domain -Name "www" -IPv4Address $clientIP -ErrorAction Stop
        Write-Host "[OK] Registro A: www.$domain -> $clientIP" -ForegroundColor Green

        # ── Registro A para ns1 (servidor de nombres) ─────────────────────────
        Add-DnsServerResourceRecordA -ZoneName $domain -Name "ns1" -IPv4Address $nsIP -ErrorAction Stop
        Write-Host "[OK] Registro A: ns1.$domain -> $nsIP" -ForegroundColor Green

        # ── Reiniciar servicio DNS ────────────────────────────────────────────
        Restart-Service -Name DNS -Force
        Write-Host "[OK] Servicio DNS reiniciado. Zona '$domain' activa." -ForegroundColor Green

    } catch {
        Write-Host "[ERROR] Fallo la configuracion DNS: $_" -ForegroundColor Red
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# 4. MÓDULO DE MONITOREO Y PRUEBAS
# ════════════════════════════════════════════════════════════════════════════════
function Monitorear-DNS {
    while ($true) {
        Write-Host "`n=====================================================" -ForegroundColor Blue
        Write-Host "       MODULO DE MONITOREO Y VALIDACION DNS (WS)     " -ForegroundColor Blue
        Write-Host "=====================================================" -ForegroundColor Blue
        Write-Host "  1) Estado actual del servicio DNS"
        Write-Host "  2) Listar zonas configuradas"
        Write-Host "  3) Ver registros de una zona"
        Write-Host "  4) Probar resolucion DNS (Resolve-DnsName)"
        Write-Host "  5) Volver al menu principal"

        $choice = Read-Host "Seleccione una opcion (1-5)"

        switch ($choice) {
            "1" {
                Write-Host "`nEstado del servicio DNS:" -ForegroundColor White
                Get-Service -Name DNS | Format-List Name, Status, StartType
            }
            "2" {
                Write-Host "`nZonas DNS configuradas:" -ForegroundColor White
                Get-DnsServerZone | Format-Table ZoneName, ZoneType, IsAutoCreated, IsDsIntegrated, IsReverseLookupZone
            }
            "3" {
                $zone = Read-Host "Nombre de la zona [reprobados.com]"
                if ([string]::IsNullOrEmpty($zone)) { $zone = "reprobados.com" }
                try {
                    Write-Host "`nRegistros en zona '$zone':" -ForegroundColor Green
                    Get-DnsServerResourceRecord -ZoneName $zone |
                        Format-Table HostName, RecordType, RecordData -AutoSize
                } catch {
                    Write-Host "[ERROR] No se pudo consultar la zona: $_" -ForegroundColor Red
                }
            }
            "4" {
                $dom = Read-Host "Dominio a resolver [reprobados.com]"
                if ([string]::IsNullOrEmpty($dom)) { $dom = "reprobados.com" }
                Write-Host "`n-- Resolviendo $dom --" -ForegroundColor White
                try {
                    Resolve-DnsName -Name $dom         -Server 127.0.0.1 -Type A | Format-Table Name, IPAddress
                    Resolve-DnsName -Name "www.$dom"   -Server 127.0.0.1 -Type A | Format-Table Name, IPAddress
                } catch {
                    Write-Host "[ERROR] Resolucion fallida: $_" -ForegroundColor Red
                }
            }
            "5" { return }
            default { Write-Host "Opcion invalida." -ForegroundColor Red }
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# MENÚ PRINCIPAL
# ════════════════════════════════════════════════════════════════════════════════
function Menu-Principal {
    Verificar-IPEstatica

    while ($true) {
        Write-Host "`n=====================================================" -ForegroundColor Blue
        Write-Host "    GESTOR DE SERVIDOR DNS - WINDOWS SERVER (PS)     " -ForegroundColor Blue
        Write-Host "=====================================================" -ForegroundColor Blue
        Write-Host "  1) Instalacion Idempotente (Rol DNS Server)"
        Write-Host "  2) Configurar Zona DNS (reprobados.com)"
        Write-Host "  3) Modulo de Monitoreo y Validacion"
        Write-Host "  4) Salir"

        $opt = Read-Host "Seleccione una opcion (1-4)"
        switch ($opt) {
            "1" { Instalar-DNSFeature }
            "2" {
                $status = Get-WindowsFeature -Name DNS
                if (-not $status.Installed) { Instalar-DNSFeature }
                Configurar-DNSServer
            }
            "3" { Monitorear-DNS }
            "4" { Write-Host "`nHasta luego!" -ForegroundColor Green; Exit }
            default { Write-Host "Opcion invalida." -ForegroundColor Red }
        }
    }
}

Menu-Principal
