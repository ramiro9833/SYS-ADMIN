# tarea1/tarea1_diagnostico.ps1
# Script principal MODULAR para diagnóstico del entorno en Windows.
# Uso: .\tarea1_diagnostico.ps1

$OutputEncoding = [System.Text.Encoding]::UTF8
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libDir    = Join-Path $scriptDir "..\lib\powershell"
if (-not (Test-Path $libDir)) { $libDir = "Z:\lib\powershell" }

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Get-ChildItem "$libDir\*.ps1" | ForEach-Object { Unblock-File $_.FullName -ErrorAction SilentlyContinue }

. "$libDir\Comunes.ps1"

Mostrar-Diagnostico
