# tarea7/tarea7.ps1 - Orquestador de Despliegue Seguro e Instalacion Hibrida Windows

# Obtener directorio del script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Buscar directorio de librerias de forma dinamica
$libDir = ""
if (Test-Path (Join-Path $scriptDir "..\lib\powershell\Comunes.ps1") -and Test-Path (Join-Path $scriptDir "..\lib\powershell\FTPClient.ps1")) {
    $libDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\lib\powershell"))
} elseif (Test-Path (Join-Path $scriptDir "lib\powershell\Comunes.ps1") -and Test-Path (Join-Path $scriptDir "lib\powershell\FTPClient.ps1")) {
    $libDir = Join-Path $scriptDir "lib\powershell"
} elseif (Test-Path (Join-Path $scriptDir "Comunes.ps1") -and Test-Path (Join-Path $scriptDir "FTPClient.ps1")) {
    $libDir = $scriptDir
} else {
    # Buscar en unidades montadas (ej. Z:, 7:, etc.)
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Sort-Object Name)) {
        $candidate = Join-Path $d.Root "lib\powershell"
        if (Test-Path "$candidate\Comunes.ps1" -and Test-Path "$candidate\FTPClient.ps1") {
            $libDir = $candidate
            break
        }
        $candidateSys = Join-Path $d.Root "SYS-ADMIN\lib\powershell"
        if (Test-Path "$candidateSys\Comunes.ps1" -and Test-Path "$candidateSys\FTPClient.ps1") {
            $libDir = $candidateSys
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($libDir)) {
    $libDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\lib\powershell")) # Fallback
}

# Cargar librerias
$libs = @("Comunes.ps1", "HTTP.ps1", "FTPClient.ps1", "SSL.ps1")
foreach ($lib in $libs) {
    $path = Join-Path $libDir $lib
    if (Test-Path $path) {
        . $path
    } else {
        Write-Host "[ERROR] No se pudo encontrar la libreria: $path" -ForegroundColor Red
        Write-Host "[HINT] Asegurese de ejecutar el script con toda su estructura de carpetas o que las librerias comunes esten en el mismo directorio." -ForegroundColor Yellow
        Exit 1
    }
}

Verificar-Admin

# Mostrar banner inicial
function Mostrar-Banner-Win {
    Clear-Host
    Write-Host "=================================================================="
    Write-Host "  ORQUESTADOR DE INFRAESTRUCTURA DE DESPLIEGUE SEGURO "
    Write-Host "=================================================================="
}

# Verificacion automatizada de servicios y certificados en Windows
function Mostrar-Resumen-Servicios-Win {
    Write-Host "`n=== RESUMEN DE INTEGRIDAD Y SERVICIOS SEGUROS (WINDOWS) ===" -ForegroundColor Cyan
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # 1. IIS-FTP (FTPS)
    $ftpSvc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
    if ($null -ne $ftpSvc -and $ftpSvc.Status -eq "Running") {
        # Verificar SSL
        $sslConfig = Get-WebConfiguration '/system.ftpServer/security/ssl'
        if ($null -ne $sslConfig -and $sslConfig.sslControlChannel -eq "Require") {
            Write-Host "  [ACTIVO] IIS-FTP -> FTPS Seguro (Require SSL) [OK]" -ForegroundColor Green
        } else {
            Write-Host "  [ACTIVO] IIS-FTP -> Inseguro (Sin SSL Obligatorio) [WARNING]" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [INACTIVO] IIS-FTP [ERROR]" -ForegroundColor Red
    }

    # 2. IIS (HTTP/HTTPS)
    $iisSvc = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    if ($null -ne $iisSvc -and $iisSvc.Status -eq "Running") {
        # Verificar binding en puerto 443
        $iisBinding = Get-WebBinding -Name "Default Web Site" -Protocol "https" -Port 443
        if ($null -ne $iisBinding) {
            Write-Host "  [ACTIVO] IIS -> HTTPS Seguro (Puerto 443) [OK]" -ForegroundColor Green
        } else {
            Write-Host "  [ACTIVO] IIS -> Inseguro (Sin HTTPS) [WARNING]" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [INACTIVO] IIS [ERROR]" -ForegroundColor Red
    }

    # 3. Apache Windows
    $apacheSvcName = Obtener-Servicio-Real-Win -Patron "Apache" -Fallback "Apache2.4"
    $apacheSvc = Get-Service -Name $apacheSvcName -ErrorAction SilentlyContinue
    if ($null -ne $apacheSvc -and $apacheSvc.Status -eq "Running") {
        # Buscar si escucha en 443 usando netstat
        $escucha443 = netstat -ano | Select-String "0.0.0.0:443"
        if ($null -ne $escucha443) {
            Write-Host "  [ACTIVO] Apache -> HTTPS Seguro (Puerto 443) [OK]" -ForegroundColor Green
        } else {
            Write-Host "  [ACTIVO] Apache -> Inseguro (Sin HTTPS) [WARNING]" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [INACTIVO] Apache [ERROR]" -ForegroundColor Red
    }

    # 4. Nginx Windows
    $nginxProc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($null -ne $nginxProc) {
        # Buscar si escucha en 443 usando netstat
        $escucha443 = netstat -ano | Select-String "0.0.0.0:443"
        if ($null -ne $escucha443) {
            Write-Host "  [ACTIVO] Nginx -> HTTPS Seguro (Puerto 443) [OK]" -ForegroundColor Green
        } else {
            Write-Host "  [ACTIVO] Nginx -> Inseguro (Sin HTTPS) [WARNING]" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [INACTIVO] Nginx [ERROR]" -ForegroundColor Red
    }

    Write-Host "================================================="
    
    # Obtener IP para mostrar comando de prueba
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.*" } | Select-Object -First 1).IPAddress
    if (-not $ip) { $ip = "127.0.0.1" }
    
    Write-Host "`n[INFO] Para probar desde tu maquina Linux (sin editar /etc/hosts), ejecuta:" -ForegroundColor Cyan
    Write-Host "curl -k -H `"Host: www.reprobados.com`" https://$ip/" -ForegroundColor White
    Write-Host "`nPara probar en el navegador, debes anadir esta linea a tu /etc/hosts en Linux:" -ForegroundColor Cyan
    Write-Host "$ip  www.reprobados.com" -ForegroundColor White
    
    Write-Host "`nPresione Enter para continuar..."
    Read-Host
}

# Bucle principal del orquestador
:menuLoop while ($true) {
    Mostrar-Banner-Win
    Write-Host "  1) Instalar/Actualizar Servicio HTTP (Hibrido: Web/FTP)"
    Write-Host "  2) Configurar SSL/TLS Seguro en Servicio (HTTP o FTP)"
    Write-Host "  3) Mostrar Estado y Resumen de Seguridad"
    Write-Host "  4) Salir"
    Write-Host "=================================================================="
    $opt = Read-Host "Selecciona una opcion (1-4)"

    switch ($opt) {
        "1" {
            Mostrar-Banner-Win
            Write-Host "`n=== FUENTE DE INSTALACION HIBRIDA ===" -ForegroundColor Cyan
            Write-Host "  1) WEB (via Gestor de Paquetes Chocolatey)"
            Write-Host "  2) FTP (via Repositorio Privado Practica 5)"
            Write-Host "  3) Regresar"
            $fuente_opt = Read-Host "Selecciona fuente (1-3)"

            if ($fuente_opt -eq "1") {
                # Flujo normal de Tarea 6 (Instalacion por Web/Chocolatey)
                Write-Host "`nSeleccione el servicio a instalar:" -ForegroundColor Cyan
                Write-Host "  1) IIS"
                Write-Host "  2) Apache Windows"
                Write-Host "  3) Nginx Windows"
                $svc_opt = Read-Host "Opcion (1-3)"
                
                switch ($svc_opt) {
                    "1" {
                        $vers = Consultar-Versiones-IIS
                        $ver  = Seleccionar-Version-Win -Servicio "IIS" -Versiones $vers
                        $port = Leer-Puerto-Win -Default 80
                        Instalar-IIS -Version $ver -Puerto $port
                    }
                    "2" {
                        $vers = Consultar-Versiones-Apache-Win
                        $ver  = Seleccionar-Version-Win -Servicio "Apache-Win64" -Versiones $vers
                        $port = Leer-Puerto-Win -Default 8080
                        Instalar-Apache-Win -Version $ver -Puerto $port
                    }
                    "3" {
                        $vers = Consultar-Versiones-Nginx-Win
                        $ver  = Seleccionar-Version-Win -Servicio "Nginx-Win" -Versiones $vers
                        $port = Leer-Puerto-Win -Default 8080
                        Instalar-Nginx-Win -Version $ver -Puerto $port
                    }
                }
            } elseif ($fuente_opt -eq "2") {
                # Flujo de descarga FTP y validacion de hash
                $binario = Descargar-Desde-FTP-Win -OSTarget "Windows"

                if ($null -eq $binario -or -not (Test-Path $binario)) {
                    Write-Host "[ERROR] No se pudo obtener el binario desde el servidor FTP." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                } else {
                    Write-Host "`n[INFO] Iniciando instalacion del binario: $binario" -ForegroundColor Yellow

                    if ($binario.EndsWith(".msi")) {
                        Write-Host "[INFO] Ejecutando instalador MSI silencioso..." -ForegroundColor Yellow
                        $proc = Start-Process msiexec.exe -ArgumentList "/i `"$binario`" /qn /norestart /l*v `"$env:TEMP\msi_install.log`"" -Wait -PassThru
                        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
                            Write-Host "[WARN] MSI termino con codigo: $($proc.ExitCode). Revisa $env:TEMP\msi_install.log" -ForegroundColor Yellow
                        }
                    } elseif ($binario.EndsWith(".exe")) {
                        Write-Host "[INFO] Ejecutando instalador EXE silencioso..." -ForegroundColor Yellow
                        Start-Process $binario -ArgumentList "/S /v/qn" -Wait
                    } elseif ($binario.EndsWith(".zip")) {
                        Write-Host "[INFO] Descomprimiendo archivo ZIP..." -ForegroundColor Yellow
                        # Detectar destino segun el nombre del archivo
                        $dest = "C:\tools"
                        $nombreBin = [System.IO.Path]::GetFileNameWithoutExtension($binario).ToLower()
                        if ($nombreBin -like "*nginx*") { $dest = "C:\nginx" }
                        elseif ($nombreBin -like "*apache*") { $dest = "C:\Apache24" }
                        if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                        Expand-Archive -Path $binario -DestinationPath $dest -Force
                        Write-Host "[INFO] Extraido en: $dest" -ForegroundColor Cyan
                    } elseif ($binario.EndsWith(".7z")) {
                        Write-Host "[INFO] Descomprimiendo archivo 7z (requiere 7-Zip)..." -ForegroundColor Yellow
                        $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
                        if (-not $sevenZip) { choco install 7zip -y --no-progress 2>$null }
                        & 7z x $binario -o"C:\tools" -y
                    } else {
                        Write-Host "[WARN] Extension no reconocida. Archivo descargado en: $binario" -ForegroundColor Yellow
                    }
                    Write-Host "[OK] Instalacion completada." -ForegroundColor Green
                    Start-Sleep -Seconds 2
                }
            }
        }
        "2" {
            Mostrar-Banner-Win
            Write-Host "`n=== CONFIGURAR SSL/TLS (www.reprobados.com) ===" -ForegroundColor Cyan
            Write-Host "  1) IIS (HTTP -> HTTPS)"
            Write-Host "  2) Apache Windows (HTTP -> HTTPS)"
            Write-Host "  3) Nginx Windows (HTTP -> HTTPS)"
            Write-Host "  4) IIS-FTP (FTP -> FTPS Seguro)"
            Write-Host "  5) Regresar"
            $ssl_opt = Read-Host "Selecciona servicio para asegurar (1-5)"

            switch ($ssl_opt) {
                "1" { Configurar-SSL-IIS-Win }
                "2" { Configurar-SSL-Apache-Win }
                "3" { Configurar-SSL-Nginx-Win }
                "4" { Configurar-SSL-IISFTP-Win }
            }
            Start-Sleep -Seconds 2
        }
        "3" {
            Mostrar-Banner-Win
            Mostrar-Resumen-Servicios-Win
        }
        "4" {
            Write-Host "`nSaliendo del orquestador. Hasta luego!" -ForegroundColor Green
            break menuLoop
        }
        default {
            Write-Host "[ERROR] Opcion invalida. Elige entre 1-4." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
