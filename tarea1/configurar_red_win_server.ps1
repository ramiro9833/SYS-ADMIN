# tarea1/configurar_red_win_server.ps1
# Script principal MODULAR para configuración de red en Windows Server 2022.
# Uso: Ejecutar en PowerShell como Administrador.

$OutputEncoding = [System.Text.Encoding]::UTF8
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir    = Join-Path $scriptDir "..\lib\powershell"
if (-not (Test-Path $libDir)) { $libDir = "Z:\lib\powershell" }

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Get-ChildItem "$libDir\*.ps1" | ForEach-Object { Unblock-File $_.FullName -ErrorAction SilentlyContinue }

. "$libDir\Comunes.ps1"
. "$libDir\Red.ps1"

Verificar-Admin
Configurar-Red-Servidor-Windows
