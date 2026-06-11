# tarea2/main_win.ps1
# Script principal MODULAR para DHCP en Windows Server.
# Uso: Ejecutar en PowerShell como Administrador.

$OutputEncoding = [System.Text.Encoding]::UTF8
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir    = Join-Path $scriptDir "..\lib\powershell"
if (-not (Test-Path $libDir)) { $libDir = "Z:\lib\powershell" }

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Get-ChildItem "$libDir\*.ps1" | ForEach-Object { Unblock-File $_.FullName -ErrorAction SilentlyContinue }

. "$libDir\Comunes.ps1"
. "$libDir\Red.ps1"
. "$libDir\DHCP.ps1"

Verificar-Admin
Verificar-IPEstatica

while ($true) {
    Banner "GESTOR DHCP - WINDOWS SERVER (POWERSHELL MODULAR)"
    Write-Host "  1) Instalacion Idempotente (Rol DHCP)"
    Write-Host "  2) Configurar Servidor DHCP"
    Write-Host "  3) Modulo de Monitoreo"
    Write-Host "  4) Salir"
    $opt = Read-Host "Seleccione una opcion (1-4)"

    if ($opt -eq "1")     { Instalar-DHCP }
    elseif ($opt -eq "2") { $s = Get-WindowsFeature -Name DHCP; if (-not $s.Installed) { Instalar-DHCP }; Configurar-DHCP }
    elseif ($opt -eq "3") { Monitorear-DHCP }
    elseif ($opt -eq "4") { Write-Host "`nHasta luego!" -ForegroundColor Green; Exit }
    else                  { Write-Host "Opcion invalida." -ForegroundColor Red }
}
