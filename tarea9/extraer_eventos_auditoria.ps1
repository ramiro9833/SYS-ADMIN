# tarea9/extraer_eventos_auditoria.ps1
# Script de monitoreo para Rol 4: admin_auditoria (Security Auditor)
# Extrae los ultimos 10 eventos de acceso denegado / logon fallido
# Uso: .\extraer_eventos_auditoria.ps1 [-OutputPath "C:\Auditoria\reporte.txt"]

param(
    [string]$OutputPath = "C:\Auditoria\reporte_accesos_denegados.txt",
    [int]$Cantidad = 10
)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir    = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\lib\powershell"))

if (-not (Test-Path "$libDir\SeguridadIdentidad.ps1")) {
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Sort-Object Name)) {
        $c = Join-Path $d.Root "SYS-ADMIN\lib\powershell"
        if (Test-Path "$c\SeguridadIdentidad.ps1") { $libDir = $c; break }
    }
}

. (Join-Path $libDir "Comunes.ps1")
. (Join-Path $libDir "SeguridadIdentidad.ps1")

# admin_auditoria puede ejecutar sin ser Domain Admin si tiene permisos Event Log Readers
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "[WARN] Ejecutar como Administrador o como admin_auditoria con permisos de lectura de Security log." -ForegroundColor Yellow
}

$ruta = Exportar-Eventos-AccesoDenegado -OutputPath $OutputPath -Cantidad $Cantidad
Write-Host "`n--- CONTENIDO DEL REPORTE ---" -ForegroundColor Cyan
Get-Content $ruta
