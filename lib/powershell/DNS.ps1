# lib/powershell/DNS.ps1
# Funciones para instalacion, configuracion y monitoreo de DNS en Windows Server.
# Uso: . "$libDir\DNS.ps1"

function Instalar-DNS {
    Banner "INSTALACION ROL DNS SERVER"
    $feature = Get-WindowsFeature -Name DNS
    if ($feature.Installed) {
        Write-Host "[INFO] El rol DNS Server ya esta instalado." -ForegroundColor Green
        Get-Service -Name DNS | Format-List Name, Status, StartType
        return
    }
    Write-Host "[INFO] Instalando DNS Server..." -ForegroundColor Yellow
    Install-WindowsFeature -Name DNS -IncludeManagementTools -ErrorAction Stop | Out-Null
    Start-Service -Name DNS -ErrorAction SilentlyContinue
    Set-Service   -Name DNS -StartupType Automatic
    Write-Host "[OK] Rol DNS Server instalado y activo." -ForegroundColor Green
}

function Configurar-DNS {
    Banner "CONFIGURACION DE ZONA DNS"

    $domain = Read-Host "Dominio a configurar [reprobados.com]"
    if ([string]::IsNullOrEmpty($domain)) { $domain = "reprobados.com" }

    $clientIP = Leer-IP "IP del nodo cliente (registro A)" "192.168.100.30"
    $nsIP     = if ($script:SERVER_IP) { $script:SERVER_IP } else { "192.168.100.20" }

    Write-Host "`n  Dominio   : $domain"    -ForegroundColor Cyan
    Write-Host   "  IP Cliente: $clientIP"  -ForegroundColor Cyan
    Write-Host   "  IP NS     : $nsIP"      -ForegroundColor Cyan
    $confirm = Read-Host "Confirmar? [s/N]"
    if ($confirm -notmatch "^[sS]$") { Write-Host "Cancelado."; return }

    try {
        $existingZone = Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue
        if ($existingZone) {
            Write-Host "[AVISO] Zona '$domain' ya existe. Eliminando..." -ForegroundColor Yellow
            Remove-DnsServerZone -Name $domain -Force
        }

        Add-DnsServerPrimaryZone -Name $domain -ZoneFile "db.$domain.dns" -DynamicUpdate None
        Write-Host "[OK] Zona primaria '$domain' creada." -ForegroundColor Green

        Add-DnsServerResourceRecordA -ZoneName $domain -Name "@"   -IPv4Address $clientIP
        Add-DnsServerResourceRecordA -ZoneName $domain -Name "www" -IPv4Address $clientIP
        Add-DnsServerResourceRecordA -ZoneName $domain -Name "ns1" -IPv4Address $nsIP
        Write-Host "[OK] Registros A creados: reprobados.com y www.reprobados.com -> $clientIP" -ForegroundColor Green

        Restart-Service -Name DNS -Force
        Write-Host "[OK] Servicio DNS reiniciado. Zona activa." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Fallo la configuracion DNS: $_" -ForegroundColor Red
    }
}

function Monitorear-DNS {
    $continuar = $true
    while ($continuar) {
        Banner "MONITOREO DNS - WINDOWS SERVER"
        Write-Host "  1) Estado del servicio DNS"
        Write-Host "  2) Listar zonas configuradas"
        Write-Host "  3) Ver registros de una zona"
        Write-Host "  4) Probar resolucion DNS"
        Write-Host "  5) Volver"
        $choice = Read-Host "Opcion (1-5)"

        if ($choice -eq "1") {
            Get-Service -Name DNS | Format-List Name, Status, StartType
        }
        elseif ($choice -eq "2") {
            Get-DnsServerZone | Format-Table ZoneName, ZoneType, IsReverseLookupZone
        }
        elseif ($choice -eq "3") {
            $zone = Read-Host "Zona [reprobados.com]"
            if ([string]::IsNullOrEmpty($zone)) { $zone = "reprobados.com" }
            Get-DnsServerResourceRecord -ZoneName $zone | Format-Table HostName, RecordType, RecordData -AutoSize
        }
        elseif ($choice -eq "4") {
            $dom = Read-Host "Dominio [reprobados.com]"
            if ([string]::IsNullOrEmpty($dom)) { $dom = "reprobados.com" }
            Resolve-DnsName -Name $dom       -Server 127.0.0.1 -Type A -ErrorAction SilentlyContinue | Format-Table Name, IPAddress
            Resolve-DnsName -Name "www.$dom" -Server 127.0.0.1 -Type A -ErrorAction SilentlyContinue | Format-Table Name, IPAddress
        }
        elseif ($choice -eq "5") {
            $continuar = $false
        }
        else {
            Write-Host "Opcion invalida." -ForegroundColor Red
        }
    }
}
