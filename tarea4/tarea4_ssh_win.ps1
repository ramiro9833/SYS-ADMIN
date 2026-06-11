# tarea4/tarea4_ssh_win.ps1
# Script principal modular para SSH en Windows Server.
# Carga las bibliotecas de funciones (dot-sourcing) y presenta el menú.
# Uso: Ejecutar en PowerShell como Administrador: .\tarea4_ssh_win.ps1

$OutputEncoding = [System.Text.Encoding]::UTF8

# ─── Cargar bibliotecas (dot-sourcing) ───────────────────────────────────────
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir    = Join-Path $scriptDir "..\lib\powershell"

# Ruta de respaldo: buscar en la carpeta compartida Z: si no existe relativa
if (-not (Test-Path $libDir)) {
    $libDir = "Z:\lib\powershell"
}

if (-not (Test-Path $libDir)) {
    Write-Host "[ERROR] No se encontro la carpeta de bibliotecas." -ForegroundColor Red
    Write-Host "Ejecuta: .\Desktop\tarea4_ssh_win.ps1 desde Z:\tarea4\" -ForegroundColor Yellow
    Exit 1
}

# Desbloquear archivos de red para permitir su carga (dot-source)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Get-ChildItem "$libDir\*.ps1" | ForEach-Object { Unblock-File $_.FullName -ErrorAction SilentlyContinue }

. "$libDir\Comunes.ps1"
. "$libDir\SSH.ps1"

# ─── Verificar Administrador ─────────────────────────────────────────────────
Verificar-Admin

# ─── Menú Principal ───────────────────────────────────────────────────────────
while ($true) {
    Banner "GESTOR SSH - WINDOWS SERVER (POWERSHELL MODULAR)"
    Write-Host "  1) Instalacion Idempotente (OpenSSH Server)"
    Write-Host "  2) Configurar Seguridad SSH"
    Write-Host "  3) Modulo de Monitoreo y Validacion"
    Write-Host "  4) Salir"

    $opt = Read-Host "Seleccione una opcion (1-4)"
    switch ($opt) {
        "1" { Instalar-SSH }
        "2" { Configurar-SSH }
        "3" { Monitorear-SSH }
        "4" { Write-Host "`nHasta luego!" -ForegroundColor Green; Exit }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
}
