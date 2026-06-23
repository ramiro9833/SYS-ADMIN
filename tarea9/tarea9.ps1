# tarea9/tarea9.ps1
# Orquestador Tarea 9: Seguridad de Identidad, Delegacion RBAC y MFA
# Uso: Ejecutar como Administrador en Windows Server (Controlador de Dominio)
# Requisito previo: Tarea 8 desplegada (dominio sysadmin.local, OUs Cuates/No Cuates)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Buscar librerias
$libDir = ""
$candidates = @(
    (Join-Path $scriptDir "..\lib\powershell"),
    (Join-Path $scriptDir "lib\powershell"),
    $scriptDir
)
foreach ($c in $candidates) {
    if ((Test-Path "$c\Comunes.ps1") -and (Test-Path "$c\SeguridadIdentidad.ps1")) {
        $libDir = [System.IO.Path]::GetFullPath($c)
        break
    }
}
if ([string]::IsNullOrWhiteSpace($libDir)) {
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Sort-Object Name)) {
        foreach ($sub in @("lib\powershell", "SYS-ADMIN\lib\powershell")) {
            $candidate = Join-Path $d.Root $sub
            if ((Test-Path "$candidate\Comunes.ps1") -and (Test-Path "$candidate\SeguridadIdentidad.ps1")) {
                $libDir = $candidate
                break
            }
        }
        if ($libDir) { break }
    }
}

if ([string]::IsNullOrWhiteSpace($libDir)) {
    Write-Host "[ERROR] No se encontraron Comunes.ps1 y SeguridadIdentidad.ps1 en lib/powershell." -ForegroundColor Red
    Exit 1
}

. (Join-Path $libDir "Comunes.ps1")
. (Join-Path $libDir "SeguridadIdentidad.ps1")

Verificar-Admin

function Mostrar-Banner-T9 {
    Clear-Host
    Write-Host "=================================================================="
    Write-Host "  TAREA 9 - SEGURIDAD DE IDENTIDAD, DELEGACION RBAC Y MFA        "
    Write-Host "=================================================================="
}

:menuLoop while ($true) {
    Mostrar-Banner-T9
    Write-Host "  1) Crear Usuarios Administrativos Delegados (4 roles)"
    Write-Host "  2) Configurar Delegacion RBAC Completa (ACLs por rol)"
    Write-Host "  3) Configurar FGPP (12 chars admins / 8 chars estandar)"
    Write-Host "  4) Hardening de Auditoria (auditpol + SACL)"
    Write-Host "  5) Configurar Bloqueo por MFA Fallido (3 / 30 min)"
    Write-Host "  6) Instalar MFA multiOTP (Credential Provider TOTP)"
    Write-Host "  7) Registrar Usuario en MFA (Google Authenticator)"
    Write-Host "  8) Exportar Reporte de Accesos Denegados (Test 5)"
    Write-Host "  9) Despliegue Completo (opciones 1-6)"
    Write-Host " 10) Mostrar Resumen de Seguridad"
    Write-Host " 11) Salir"
    Write-Host "=================================================================="
    $opt = Read-Host "Selecciona una opcion (1-11)"

    switch ($opt) {
        "1"  { Crear-Usuarios-Delegados }
        "2"  { Configurar-Delegacion-RBAC-Completa }
        "3"  { Configurar-FGPP }
        "4"  { Configurar-Auditoria-Hardening }
        "5"  { Configurar-Bloqueo-MFA }
        "6"  { Instalar-MFA-MultiOTP }
        "7"  {
            $user = Read-Host "Usuario a registrar en MFA [Administrador]"
            if ([string]::IsNullOrWhiteSpace($user)) { $user = "Administrador" }
            Registrar-Usuario-MFA -Username $user
        }
        "8"  {
            $out = Read-Host "Ruta del reporte [C:\Auditoria\reporte_accesos_denegados.txt]"
            if ([string]::IsNullOrWhiteSpace($out)) { $out = "C:\Auditoria\reporte_accesos_denegados.txt" }
            Exportar-Eventos-AccesoDenegado -OutputPath $out
            Get-Content $out
        }
        "9"  {
            Configurar-Delegacion-RBAC-Completa
            Configurar-FGPP
            Configurar-Auditoria-Hardening
            Configurar-Bloqueo-MFA
            Instalar-MFA-MultiOTP
            Write-Host "`n[OK] Despliegue completo Tarea 9 finalizado." -ForegroundColor Green
            Write-Host "[SIGUIENTE] Opcion 7: registrar usuarios en MFA y escanear QR con Google Authenticator." -ForegroundColor Cyan
        }
        "10" { Mostrar-Resumen-Seguridad }
        "11" {
            Write-Host "`nSaliendo. Hasta luego!" -ForegroundColor Green
            break menuLoop
        }
        default {
            Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

    if ($opt -ne "11") {
        Write-Host "`nPresione Enter para continuar..."
        Read-Host
    }
}
