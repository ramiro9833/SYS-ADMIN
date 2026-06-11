# Script: configurar_red_win_server.ps1
# Descripción: Configura la red interna en Windows Server 2022 (Estática) usando PowerShell.
# Autor: Antigravity AI
# Uso: Ejecutar en PowerShell como Administrador: .\configurar_red_win_server.ps1

# Configuración de salida UTF-8 y codificación de consola
$OutputEncoding = [System.Text.Encoding]::UTF8

# Verificar permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Este script debe ser ejecutado en una sesión de PowerShell como Administrador." -ForegroundColor Red
    Write-Host "Por favor, abra PowerShell como Administrador y vuelva a intentarlo." -ForegroundColor Yellow
    Exit
}

Write-Host "======================================================" -ForegroundColor Blue
Write-Host "  CONFIGURACIÓN DE RED - WINDOWS SERVER 2022 (PS)    " -ForegroundColor Blue
Write-Host "======================================================" -ForegroundColor Blue

# 1. Obtener adaptadores de red
Write-Host "`nDetectando adaptadores de red en el sistema..." -ForegroundColor Gray
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -or $_.Status -eq "Disconnected" }

if ($adapters.Count -eq 0) {
    Write-Host "[ERROR] No se encontraron adaptadores de red en el equipo." -ForegroundColor Red
    Exit
}

Write-Host "`nAdaptadores de red disponibles:" -ForegroundColor Cyan
$adapters | Format-Table -Property InterfaceIndex, Name, InterfaceDescription, Status, LinkSpeed | Out-String | Write-Host

# Solicitar selección
$idx = $null
while ($true) {
    $sel = Read-Host "Seleccione el InterfaceIndex del adaptador para la Red Interna (red_sistemas)"
    if ($sel -match "^\d+$" -and ($adapters.InterfaceIndex -contains [int]$sel)) {
        $idx = [int]$sel
        break
    } else {
        Write-Host "Selección inválida. Inténtelo de nuevo." -ForegroundColor Red
    }
}

$adapter = Get-NetAdapter -InterfaceIndex $idx
Write-Host "`nAdaptador seleccionado: $($adapter.Name) ($($adapter.InterfaceDescription))" -ForegroundColor Green

# 2. Configurar dirección IP
$defaultIP = "192.168.100.20"
$defaultPrefix = 24

Write-Host "`nConfiguración de IP Estática (Presione Enter para valores por defecto):" -ForegroundColor Yellow

# Solicitar IP
$ip = $null
while ($true) {
    $ipInput = Read-Host "Dirección IP [$defaultIP]"
    if ([string]::IsNullOrEmpty($ipInput)) {
        $ip = $defaultIP
        break
    }
    if ($ipInput -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$") {
        # Validar octetos
        $valid = $true
        $octets = $ipInput.Split('.')
        foreach ($oct in $octets) {
            if ([int]$oct -lt 0 -or [int]$oct -gt 255) { $valid = $false }
        }
        if ($valid) {
            $ip = $ipInput
            break
        }
    }
    Write-Host "Formato de dirección IP inválido." -ForegroundColor Red
}

# Solicitar máscara CIDR
$prefix = $null
while ($true) {
    $prefixInput = Read-Host "Prefijo de red CIDR (ej: 24 para 255.255.255.0) [$defaultPrefix]"
    if ([string]::IsNullOrEmpty($prefixInput)) {
        $prefix = $defaultPrefix
        break
    }
    if ($prefixInput -match "^\d+$" -and [int]$prefixInput -ge 0 -and [int]$prefixInput -le 32) {
        $prefix = [int]$prefixInput
        break
    }
    Write-Host "Prefijo CIDR inválido (debe ser entre 0 y 32)." -ForegroundColor Red
}

# 3. Aplicar los cambios
Write-Host "`nAplicando configuración..." -ForegroundColor Gray

# Remover IPs estáticas existentes en la interfaz seleccionada para evitar conflictos
$existingIPs = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254.*" }

if ($existingIPs) {
    Write-Host "Eliminando direcciones IP previas en el adaptador..." -ForegroundColor Gray
    foreach ($oldIP in $existingIPs) {
        Remove-NetIPAddress -InterfaceIndex $idx -IPAddress $oldIP.IPAddress -Confirm:$false
    }
}

# Configurar nueva dirección IP
try {
    New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop | Out-Null
    Write-Host "[OK] Dirección IP $ip/$prefix configurada con éxito." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] No se pudo configurar la dirección IP: $_" -ForegroundColor Red
    Exit
}

# Mostrar resumen final
Write-Host "`nResumen de configuración actual de la interfaz:" -ForegroundColor Cyan
Get-NetIPConfiguration -InterfaceIndex $idx | Out-String | Write-Host

Write-Host "======================================================" -ForegroundColor Blue
