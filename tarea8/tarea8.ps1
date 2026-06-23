# tarea8/tarea8.ps1
# Orquestador de Gobernanza AD - Tarea 8: Cuotas, Horarios y AppLocker
# Uso: Ejecutar como Administrador en Windows Server (Controlador de Dominio)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Buscar directorio de librerias
$libDir = ""
if ((Test-Path (Join-Path $scriptDir "..\lib\powershell\Comunes.ps1")) -and (Test-Path (Join-Path $scriptDir "..\lib\powershell\Governanza.ps1"))) {
    $libDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\lib\powershell"))
} elseif ((Test-Path (Join-Path $scriptDir "lib\powershell\Comunes.ps1")) -and (Test-Path (Join-Path $scriptDir "lib\powershell\Governanza.ps1"))) {
    $libDir = Join-Path $scriptDir "lib\powershell"
} elseif ((Test-Path (Join-Path $scriptDir "Comunes.ps1")) -and (Test-Path (Join-Path $scriptDir "Governanza.ps1"))) {
    $libDir = $scriptDir
} else {
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Sort-Object Name)) {
        $candidate = Join-Path $d.Root "lib\powershell"
        if ((Test-Path "$candidate\Comunes.ps1") -and (Test-Path "$candidate\Governanza.ps1")) {
            $libDir = $candidate
            break
        }
        $candidateSys = Join-Path $d.Root "SYS-ADMIN\lib\powershell"
        if ((Test-Path "$candidateSys\Comunes.ps1") -and (Test-Path "$candidateSys\Governanza.ps1")) {
            $libDir = $candidateSys
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($libDir)) {
    Write-Host "[ERROR] No se encontraron las librerias en lib/powershell." -ForegroundColor Red
    Exit 1
}

. (Join-Path $libDir "Comunes.ps1")
. (Join-Path $libDir "Governanza.ps1")

Verificar-Admin

$csvDefault = Join-Path $scriptDir "usuarios.csv"

function Mostrar-Banner-T8 {
    Clear-Host
    Write-Host "=================================================================="
    Write-Host "  TAREA 8 - GOBERNANZA, CUOTAS Y CONTROL DE APLICACIONES (AD)   "
    Write-Host "=================================================================="
}

:menuLoop while ($true) {
    Mostrar-Banner-T8
    Write-Host "  1) Instalar Roles (AD DS + FSRM)"
    Write-Host "  2) Configurar Dominio Active Directory"
    Write-Host "  3) Crear Estructura OU (Cuates / No Cuates)"
    Write-Host "  4) Importar Usuarios desde CSV"
    Write-Host "  5) Configurar Share de Carpetas de Usuario"
    Write-Host "  6) Configurar GPO - Cierre de Sesion Forzado"
    Write-Host "  7) Configurar FSRM - Cuotas Estrictas"
    Write-Host "  8) Configurar FSRM - Apantallamiento de Archivos"
    Write-Host "  9) Configurar AppLocker (Notepad)"
    Write-Host " 10) Despliegue Completo (todas las opciones)"
    Write-Host " 11) Mostrar Resumen de Gobernanza"
    Write-Host " 12) Salir"
    Write-Host "=================================================================="
    $opt = Read-Host "Selecciona una opcion (1-12)"

    switch ($opt) {
        "1"  { Instalar-Roles-Gobernanza }
        "2"  { Configurar-Dominio-AD }
        "3"  { Crear-Estructura-OU }
        "4"  {
            $csv = Read-Host "Ruta del CSV [$csvDefault]"
            if ([string]::IsNullOrWhiteSpace($csv)) { $csv = $csvDefault }
            Importar-Usuarios-DesdeCSV -CsvPath $csv
        }
        "5"  { Configurar-Share-Usuarios }
        "6"  { Configurar-GPO-ForceLogoff }
        "7"  { Configurar-Cuotas-FSRM }
        "8"  { Configurar-FileScreen-FSRM }
        "9"  { Configurar-AppLocker-Notepad }
        "10" {
            Instalar-Roles-Gobernanza
            $forest = Get-ADForest -ErrorAction SilentlyContinue
            if (-not $forest) {
                Write-Host "[INFO] Configure el dominio (opcion 2) y reinicie antes de continuar." -ForegroundColor Yellow
                break
            }
            Crear-Estructura-OU
            Importar-Usuarios-DesdeCSV -CsvPath $csvDefault
            Configurar-Share-Usuarios
            Configurar-GPO-ForceLogoff
            Configurar-Cuotas-FSRM
            Configurar-FileScreen-FSRM
            Configurar-AppLocker-Notepad
            Write-Host "`n[OK] Despliegue completo de gobernanza finalizado." -ForegroundColor Green
        }
        "11" { Mostrar-Resumen-Gobernanza }
        "12" {
            Write-Host "`nSaliendo. Hasta luego!" -ForegroundColor Green
            break menuLoop
        }
        default {
            Write-Host "[ERROR] Opcion invalida." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

    if ($opt -ne "12") {
        Write-Host "`nPresione Enter para continuar..."
        Read-Host
    }
}
