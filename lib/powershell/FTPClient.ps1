# lib/powershell/FTPClient.ps1 - Cliente FTP dinamico y validacion de integridad para Windows

$global:FTP_IP = ""
$global:FTP_USER = ""
$global:FTP_PASS = ""

# Solicitar credenciales FTP
function Solicitar-Credenciales-FTP-Win {
    Write-Host "`n=== CREDENCIALES DEL SERVIDOR FTP CENTRAL ===" -ForegroundColor Cyan
    $input_ip = Read-Host "IP del Servidor FTP [192.168.100.10]"
    $global:FTP_IP = if ([string]::IsNullOrWhiteSpace($input_ip)) { "192.168.100.10" } else { $input_ip }

    $input_user = Read-Host "Usuario FTP [ftpuser]"
    $global:FTP_USER = if ([string]::IsNullOrWhiteSpace($input_user)) { "ftpuser" } else { $input_user }

    $global:FTP_PASS = Read-Host "Contrasena FTP" -AsSecureString
}

# Obtener contrasena en texto plano desde SecureString
function Obtener-Plano-Pass-Win {
    if ($global:FTP_PASS -is [System.Security.SecureString]) {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($global:FTP_PASS)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
    return $global:FTP_PASS
}

# Listar directorio FTP - devuelve array de nombres (solo el basename de cada entrada)
function Listar-Directorio-FTP-Win {
    param([string]$Ruta, [bool]$UsePassive = $true)
    $planoPass = Obtener-Plano-Pass-Win
    $uri = "ftp://$global:FTP_IP/$Ruta"
    try {
        $request = [System.Net.FtpWebRequest]::Create($uri)
        $request.Credentials = New-Object System.Net.NetworkCredential($global:FTP_USER, $planoPass)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.UsePassive = $UsePassive     # PASV para clientes Windows/.NET
        $request.UseBinary  = $true
        $request.KeepAlive  = $false
        $request.Timeout = 10000
        $request.ReadWriteTimeout = 15000
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $output = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()

        # Parsear: filtrar lineas vacias y extraer solo el nombre (basename)
        $items = @()
        foreach ($line in ($output -split "`r?`n")) {
            $line = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            # Si viene en formato largo tipo ls -l (empieza con d o -), tomar la ultima columna
            if ($line -match '^[d\-][rwx\-]{9}') {
                $parts = $line -split '\s+'
                if ($parts.Count -ge 9) {
                    $line = ($parts[8..($parts.Count-1)] -join ' ').Trim()
                }
            }
            # Tomar solo el basename (por si viene ruta completa)
            $line = [System.IO.Path]::GetFileName($line.TrimEnd('/'))
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $items += $line
            }
        }
        return $items
    } catch {
        # Si PASV falló, reintentar en modo ACTIVO (PORT)
        if ($UsePassive) {
            Write-Host "[INFO] Modo PASV falló, reintentando en modo ACTIVO (PORT)..." -ForegroundColor Yellow
            return Listar-Directorio-FTP-Win -Ruta $Ruta -UsePassive $false
        }
        Write-Host "[ERROR] Error al listar FTP ($uri): $_" -ForegroundColor Red
        return @()
    }
}

# Descargar archivo FTP
function Descargar-Archivo-FTP-Win {
    param([string]$Url, [string]$Destino)
    $planoPass = Obtener-Plano-Pass-Win
    try {
        $request = [System.Net.FtpWebRequest]::Create($Url)
        $request.Credentials = New-Object System.Net.NetworkCredential($global:FTP_USER, $planoPass)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $request.UsePassive = $true   # PASV - requerido para Windows
        $request.UseBinary  = $true
        $request.KeepAlive  = $false
        $request.Timeout = 30000
        $request.ReadWriteTimeout = 120000  # 2 min para archivos grandes

        $response = $request.GetResponse()
        $stream   = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($Destino)
        $stream.CopyTo($fileStream)
        $fileStream.Close()
        $stream.Close()
        $response.Close()
        return $true
    } catch {
        Write-Host "[ERROR] Error al descargar de FTP ($Url): $_" -ForegroundColor Red
        return $false
    }
}

# Navegacion y descarga dinamica por FTP en Windows
function Descargar-Desde-FTP-Win {
    param([string]$OSTarget) # "Windows" o "Linux"

    if ([string]::IsNullOrWhiteSpace($global:FTP_IP)) {
        Solicitar-Credenciales-FTP-Win
    }

    Write-Host "`n[INFO] Conectando a ftp://$global:FTP_IP/http/$OSTarget/..." -ForegroundColor Yellow

    # 1. Listar servicios
    $servicios = @(Listar-Directorio-FTP-Win -Ruta "http/$OSTarget/")
    if ($servicios.Count -eq 0) {
        Write-Host "[ERROR] No se pudo conectar al servidor FTP o la carpeta http/$OSTarget/ esta vacia." -ForegroundColor Red
        Write-Host "[HINT] Verifica:" -ForegroundColor Yellow
        Write-Host "  1. IP del servidor FTP: $global:FTP_IP" -ForegroundColor Yellow
        Write-Host "  2. Usuario '$global:FTP_USER' tiene acceso a la carpeta http/$OSTarget/" -ForegroundColor Yellow
        Write-Host "  3. El repositorio FTP fue preparado con setup_ftp_repo.sh" -ForegroundColor Yellow
        return $null
    }

    Write-Host "`nServicios disponibles en el repositorio FTP:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $servicios.Count; $i++) {
        Write-Host "  $($i+1))- $($servicios[$i])"
    }
    Write-Host "  $($servicios.Count + 1))- Cancelar y volver"

    $opcion_svc = Read-Host "Selecciona una opcion (1-$($servicios.Count + 1))"
    $idx_svc = 0
    if (-not [int]::TryParse($opcion_svc, [ref]$idx_svc) -or $idx_svc -le 0 -or $idx_svc -gt $servicios.Count) {
        Write-Host "Operacion cancelada." -ForegroundColor Yellow
        return $null
    }

    $svc_elegido = $servicios[$idx_svc - 1]
    $ruta_svc = "http/$OSTarget/$svc_elegido"

    # 2. Listar archivos
    $todos_archivos = @(Listar-Directorio-FTP-Win -Ruta "$ruta_svc/")
    if ($todos_archivos.Count -eq 0) {
        Write-Host "[ERROR] La carpeta del servicio $svc_elegido esta vacia o no existe." -ForegroundColor Red
        return $null
    }

    # Filtrar solo archivos instaladores (no archivos de firma)
    $instaladores = @($todos_archivos | Where-Object { $_ -notmatch '\.(sha256|md5)$' })
    if ($instaladores.Count -eq 0) {
        Write-Host "[ERROR] No se encontraron instaladores en $ruta_svc." -ForegroundColor Red
        return $null
    }

    Write-Host "`nArchivos de instalacion disponibles:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $instaladores.Count; $i++) {
        Write-Host "  $($i+1))- $($instaladores[$i])"
    }
    Write-Host "  $($instaladores.Count + 1))- Cancelar"

    $opcion_file = Read-Host "Selecciona el archivo a descargar (1-$($instaladores.Count + 1))"
    $idx_file = 0
    if (-not [int]::TryParse($opcion_file, [ref]$idx_file) -or $idx_file -le 0 -or $idx_file -gt $instaladores.Count) {
        Write-Host "Operacion cancelada." -ForegroundColor Yellow
        return $null
    }

    $binario_elegido = $instaladores[$idx_file - 1]
    $url_binario = "ftp://$global:FTP_IP/$ruta_svc/$binario_elegido"
    
    $dest_dir = "$env:TEMP\ftp_install"
    if (-not (Test-Path $dest_dir)) { New-Item -ItemType Directory -Path $dest_dir -Force | Out-Null }

    $local_binario = Join-Path $dest_dir $binario_elegido

    # Descargar binario
    Write-Host "`n[INFO] Descargando $binario_elegido..." -ForegroundColor Yellow
    $ok = Descargar-Archivo-FTP-Win -Url $url_binario -Destino $local_binario
    if (-not $ok) {
        Write-Host "[ERROR] Fallo la descarga del instalador." -ForegroundColor Red
        return $null
    }

    # 3. Validacion de Integridad
    $validado = $false
    $firma_ext = ""
    foreach ($archivo in $todos_archivos) {
        if ($archivo -eq "$binario_elegido.sha256") {
            $firma_ext = "sha256"
            break
        } elseif ($archivo -eq "$binario_elegido.md5") {
            $firma_ext = "md5"
            break
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($firma_ext)) {
        $url_firma = "ftp://$global:FTP_IP/$ruta_svc/$binario_elegido.$firma_ext"
        $local_firma = "$local_binario.$firma_ext"
        
        Write-Host "[INFO] Descargando firma de integridad .$firma_ext..." -ForegroundColor Yellow
        $okFirma = Descargar-Archivo-FTP-Win -Url $url_firma -Destino $local_firma
        
        if ($okFirma) {
            $hash_servidor = (Get-Content $local_firma -Raw).Trim().Split(" ")[0].ToLower()
            
            $algo = if ($firma_ext -eq "sha256") { "SHA256" } else { "MD5" }
            $hash_calculado = (Get-FileHash -Path $local_binario -Algorithm $algo).Hash.ToLower()
            
            Write-Host "[INFO] Hash $algo Local:    $hash_calculado" -ForegroundColor Cyan
            Write-Host "[INFO] Hash $algo Servidor: $hash_servidor" -ForegroundColor Cyan
            
            if ($hash_calculado -eq $hash_servidor) {
                $validado = $true
            }
        }

        if ($validado) {
            Write-Host "[OK] Verificacion de integridad exitosa (Hash Coincide)." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] ¡ARCHIVO CORRUPTO! El hash no coincide con el del servidor." -ForegroundColor Red
            Remove-Item $local_binario -Force -ErrorAction SilentlyContinue
            Remove-Item $local_firma -Force -ErrorAction SilentlyContinue
            return $null
        }
    } else {
        Write-Host "[WARNING] No se encontro un archivo de firma (.sha256 o .md5) en el servidor FTP." -ForegroundColor Yellow
        $continuar = Read-Host "¿Desea continuar la instalacion sin verificar la integridad? [s/N]"
        if ($continuar -notmatch '^[sS]$') {
            Remove-Item $local_binario -Force -ErrorAction SilentlyContinue
            return $null
        }
    }

    return $local_binario
}
