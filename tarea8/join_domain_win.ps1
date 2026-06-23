# tarea8/join_domain_win.ps1
# Union automatica de cliente Windows al dominio Active Directory
# Uso: Ejecutar como Administrador en el cliente Windows

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$libDir = ""
if (Test-Path (Join-Path $scriptDir "..\lib\powershell\Comunes.ps1") -and Test-Path (Join-Path $scriptDir "..\lib\powershell\Governanza.ps1")) {
    $libDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\lib\powershell"))
} elseif (Test-Path (Join-Path $scriptDir "lib\powershell\Comunes.ps1") -and Test-Path (Join-Path $scriptDir "lib\powershell\Governanza.ps1")) {
    $libDir = Join-Path $scriptDir "lib\powershell"
} elseif (Test-Path (Join-Path $scriptDir "Comunes.ps1") -and Test-Path (Join-Path $scriptDir "Governanza.ps1")) {
    $libDir = $scriptDir
} else {
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Sort-Object Name)) {
        $candidate = Join-Path $d.Root "lib\powershell"
        if (Test-Path "$candidate\Comunes.ps1" -and Test-Path "$candidate\Governanza.ps1") {
            $libDir = $candidate
            break
        }
        $candidateSys = Join-Path $d.Root "SYS-ADMIN\lib\powershell"
        if (Test-Path "$candidateSys\Comunes.ps1" -and Test-Path "$candidateSys\Governanza.ps1") {
            $libDir = $candidateSys
            break
        }
    }
}

. (Join-Path $libDir "Comunes.ps1")
. (Join-Path $libDir "Governanza.ps1")

Verificar-Admin

Banner "UNION DE CLIENTE WINDOWS - TAREA 8"

$domain   = Read-Host "Nombre del dominio [sysadmin.local]"
if ([string]::IsNullOrWhiteSpace($domain)) { $domain = "sysadmin.local" }

$user     = Read-Host "Usuario con permisos de dominio [Administrador]"
if ([string]::IsNullOrWhiteSpace($user)) { $user = "Administrador" }

$secPass  = Read-Host "Contrasena" -AsSecureString
$ou       = Read-Host "OU de destino (opcional, Enter para predeterminada)"

$cred = New-Object System.Management.Automation.PSCredential("$domain\$user", $secPass)

$domainInfo = Get-WmiObject Win32_ComputerSystem
if ($domainInfo.PartOfDomain -and $domainInfo.Domain -eq $domain) {
    Write-Host "[INFO] Este equipo ya pertenece al dominio '$domain'." -ForegroundColor Yellow
    exit 0
}

$params = @{ DomainName = $domain; Credential = $cred; Force = $true; Restart = $true }
if (-not [string]::IsNullOrWhiteSpace($ou)) { $params["OUPath"] = $ou }

Add-Computer @params
