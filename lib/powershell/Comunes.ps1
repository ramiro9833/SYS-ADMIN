# lib/powershell/Comunes.ps1
# Biblioteca de funciones comunes para todos los scripts PowerShell del proyecto.
# Uso: . "$PSScriptRoot\..\..\lib\powershell\Comunes.ps1"

# ─── Verificar privilegios de Administrador ──────────────────────────────────
function Verificar-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[ERROR] Ejecutar como Administrador." -ForegroundColor Red
        Exit 1
    }
}

# ─── Validar formato IPv4 ────────────────────────────────────────────────────
function Validar-IP($ip) {
    if ($ip -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$") {
        foreach ($oct in $ip.Split('.')) {
            if ([int]$oct -lt 0 -or [int]$oct -gt 255) { return $false }
        }
        return $true
    }
    return $false
}

# ─── Leer IP con validación interactiva ──────────────────────────────────────
function Leer-IP($prompt, $default) {
    while ($true) {
        $val = Read-Host "$prompt [$default]"
        if ([string]::IsNullOrEmpty($val)) { return $default }
        if (Validar-IP $val) { return $val }
        Write-Host "[ERROR] IP invalida. Formato: X.X.X.X (0-255 por octeto)" -ForegroundColor Red
    }
}

# ─── Instalar característica de Windows de forma idempotente ─────────────────
function Instalar-Feature($featureName) {
    $feat = Get-WindowsFeature -Name $featureName
    if ($feat.Installed) {
        Write-Host "[INFO] Caracteristica '$featureName' ya instalada." -ForegroundColor Green
        return
    }
    Write-Host "[INFO] Instalando '$featureName'..." -ForegroundColor Yellow
    Install-WindowsFeature -Name $featureName -IncludeManagementTools -ErrorAction Stop | Out-Null
    Write-Host "[OK] '$featureName' instalada correctamente." -ForegroundColor Green
}

# ─── Banner de sección ────────────────────────────────────────────────────────
function Banner($titulo) {
    Write-Host "`n======================================================" -ForegroundColor Blue
    Write-Host "  $titulo" -ForegroundColor Blue
    Write-Host "======================================================" -ForegroundColor Blue
}
