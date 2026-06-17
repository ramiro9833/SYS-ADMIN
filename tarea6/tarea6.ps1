# tarea6/main_win.ps1
# Script principal MODULAR - Tarea 6: Despliegue Dinamico HTTP (Windows)
# Uso: Ejecutar como Administrador (desde SSH o PowerShell elevado)
# Operacion: Exclusivamente por SSH desde cliente remoto.

$ErrorActionPreference = "Continue"

# Localizar librería en drives montados
$libDir = $null
foreach ($drive in @("7:","D:","Z:","C:")) {
    $candidate = "$drive\SYS-ADMIN\lib\powershell"
    if (Test-Path "$candidate\Comunes.ps1") { $libDir = $candidate; break }
}
if (-not $libDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $libDir    = Join-Path $scriptDir "..\lib\powershell"
}

. "$libDir\Comunes.ps1"
. "$libDir\HTTP.ps1"

Verificar-Admin

while ($true) {
    Menu-HTTP-Win
    $opt = Read-Host "Selecciona una opcion (1-5)"

    switch ($opt) {
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
        "4" { Estado-Servicios-HTTP-Win }
        "5" { Write-Host "`n!Hasta luego!"; exit 0 }
        default { Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red }
    }
}
