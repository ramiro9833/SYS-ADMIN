# tarea9/registrar_mfa_usuario.ps1
# Registra un usuario en multiOTP para Google Authenticator (TOTP)
# Uso: .\registrar_mfa_usuario.ps1 -Username Administrador

param(
    [Parameter(Mandatory)][string]$Username
)

$ErrorActionPreference = "Stop"
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

Verificar-Admin
Registrar-Usuario-MFA -Username $Username
