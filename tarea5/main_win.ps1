# tarea5/main_win.ps1
# Script principal MODULAR para Tarea 5 (FTP) en Windows Server.
# Uso: Ejecutar en PowerShell como Administrador.

$OutputEncoding = [System.Text.Encoding]::UTF8
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir    = Join-Path $scriptDir "..\lib\powershell"
if (-not (Test-Path $libDir)) {
    # Buscar dinámicamente la carpeta de librerías en todas las unidades del sistema (VirtualBox monta carpetas compartidas en letras aleatorias/secuenciales como Z:, 7:, etc.)
    $found = $false
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Sort-Object Name)) {
        $candidate = Join-Path $d.Root "lib\powershell"
        if (Test-Path "$candidate\FTP.ps1") {
            $libDir = $candidate
            $found = $true
            break
        }
        $candidateSys = Join-Path $d.Root "SYS-ADMIN\lib\powershell"
        if (Test-Path "$candidateSys\FTP.ps1") {
            $libDir = $candidateSys
            $found = $true
            break
        }
    }
    if (-not $found) {
        $libDir = "Z:\lib\powershell" # Fallback por defecto
    }
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Get-ChildItem "$libDir\*.ps1" | ForEach-Object { Unblock-File $_.FullName -ErrorAction SilentlyContinue }

. "$libDir\Comunes.ps1"
. "$libDir\FTP.ps1"

Verificar-Admin

while ($true) {
    Banner "GESTOR FTP - WINDOWS SERVER (POWERSHELL MODULAR)"
    Write-Host "  1) Instalacion Idempotente (Rol IIS FTP)"
    Write-Host "  2) Alta Masiva de Usuarios FTP"
    Write-Host "  3) Cambiar Grupo de un Usuario"
    Write-Host "  4) Modulo de Monitoreo"
    Write-Host "  5) Diagnosticar Usuario FTP" -ForegroundColor Cyan
    Write-Host "  6) Salir"
    $opt = Read-Host "Seleccione una opcion (1-6)"

    if ($opt -eq "1") {
        Instalar-FTP-Windows
    }
    elseif ($opt -eq "2") {
        $nInput = Read-Host "Numero de usuarios a crear"
        if ($nInput -match "^\d+$" -and [int]$nInput -gt 0) {
            $n = [int]$nInput
            for ($i = 1; $i -le $n; $i++) {
                Write-Host "`n--- Configuracion del Usuario $i de $n ---" -ForegroundColor Blue
                $username = Read-Host "Nombre de usuario"
                $password = Read-Host "Contrasena"
                
                $group = ""
                while ($group -ne "reprobados" -and $group -ne "recursadores") {
                    $group = Read-Host "Grupo (reprobados/recursadores)"
                }
                
                Crear-Usuario-FTP-Windows -username $username -password $password -group $group
            }
        } else {
            Write-Host "[ERROR] Debe ingresar un numero entero positivo." -ForegroundColor Red
        }
    }
    elseif ($opt -eq "3") {
        $username = Read-Host "Nombre de usuario a modificar"
        $new_group = ""
        while ($new_group -ne "reprobados" -and $new_group -ne "recursadores") {
            $new_group = Read-Host "Nuevo grupo (reprobados/recursadores)"
        }
        Cambiar-Grupo-Usuario-Windows -username $username -new_group $new_group
    }
    elseif ($opt -eq "4") {
        Monitorear-FTP-Windows
    }
    elseif ($opt -eq "5") {
        Diagnosticar-Usuario-FTP
    }
    elseif ($opt -eq "6") {
        Write-Host "`nHasta luego!" -ForegroundColor Green
        break
    }
    else {
        Write-Host "Opcion invalida." -ForegroundColor Red
    }
}
