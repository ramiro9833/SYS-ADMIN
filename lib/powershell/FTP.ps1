# lib/powershell/FTP.ps1
# Funciones para instalacion, configuracion y gestion de IIS FTP Server en Windows Server.
# Uso: . "$libDir\FTP.ps1"

function Instalar-FTP-Windows {
    Banner "INSTALACION Y CONFIGURACION IIS FTP SERVER"

    # 1. Instalar Rol IIS y servicio FTP
    Write-Host "[1/3] Instalando características de IIS FTP Server..." -ForegroundColor Blue
    try {
        Install-WindowsFeature -Name Web-Server, Web-FTP-Server, Web-FTP-Service, Web-Mgmt-Console -IncludeManagementTools -ErrorAction Stop | Out-Null
        Write-Host "[OK] Características de IIS y FTP instaladas." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Falló la instalación de características: $_" -ForegroundColor Red
        return
    }

    # 2. Crear carpetas físicas
    Write-Host "[2/3] Creando directorios físicos para el FTP..." -ForegroundColor Blue
    $paths = @(
        "C:\inetpub\ftproot\general",
        "C:\inetpub\ftproot\groups\reprobados",
        "C:\inetpub\ftproot\groups\recursadores",
        "C:\inetpub\ftproot\users",
        "C:\inetpub\ftproot\LocalUser\Public"
    )
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
    }

    # Configurar permisos NTFS base
    # - general: IUSR (lectura), Users/Administrators (Full Control)
    # - groups: Administrators (Full Control)
    icacls "C:\inetpub\ftproot\general" /grant:r "IUSR:(OI)(CI)R" /grant:r "Users:(OI)(CI)F" "Administrators:(OI)(CI)F" /inheritance:e | Out-Null
    icacls "C:\inetpub\ftproot\groups\reprobados" /inheritance:r /grant:r "Administrators:(OI)(CI)F" | Out-Null
    icacls "C:\inetpub\ftproot\groups\recursadores" /inheritance:r /grant:r "Administrators:(OI)(CI)F" | Out-Null
    icacls "C:\inetpub\ftproot\users" /inheritance:r /grant:r "Administrators:(OI)(CI)F" | Out-Null

    # CRITICO: Dar permisos de recorrido a NT SERVICE\FTPSVC (el servicio FTP de IIS)
    # Sin esto el servicio no puede leer los directorios home y devuelve error 5 (Access Denied)
    icacls "C:\inetpub\ftproot" /grant "NT SERVICE\FTPSVC:(OI)(CI)RX" | Out-Null
    icacls "C:\inetpub\ftproot" /grant "Users:RX" | Out-Null

    # Asegurar que LocalUser exista antes de establecer permisos
    if (-not (Test-Path "C:\inetpub\ftproot\LocalUser")) {
        New-Item -ItemType Directory -Path "C:\inetpub\ftproot\LocalUser" -Force | Out-Null
    }
    icacls "C:\inetpub\ftproot\LocalUser" /grant "NT SERVICE\FTPSVC:(OI)(CI)RX" | Out-Null
    icacls "C:\inetpub\ftproot\LocalUser" /grant "Users:RX" | Out-Null

    # Asegurar subdirectorio del nombre del equipo con permisos de recorrido
    $localUserComputerPath = "C:\inetpub\ftproot\LocalUser\$env:COMPUTERNAME"
    if (-not (Test-Path $localUserComputerPath)) {
        New-Item -ItemType Directory -Path $localUserComputerPath -Force | Out-Null
    }
    icacls $localUserComputerPath /grant "NT SERVICE\FTPSVC:(OI)(CI)RX" | Out-Null
    icacls $localUserComputerPath /grant "Users:RX" | Out-Null

    # 3. Configurar el sitio FTP en IIS
    Write-Host "[3/3] Configurando sitio FTP en IIS con aislamiento de usuarios..." -ForegroundColor Blue
    Import-Module WebAdministration

    # Desbloquear secciones de IIS FTP a nivel de servidor usando appcmd
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        Start-Process $appcmd -ArgumentList "unlock config -section:system.ftpServer/security/authorization" -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
        Start-Process $appcmd -ArgumentList "unlock config -section:system.ftpServer/security/authentication" -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
    }

    # Crear sitio FTP si no existe
    $siteName = "FTP_SysAdmin"
    $site = Get-WebSite -Name $siteName -ErrorAction SilentlyContinue
    if ($site) {
        Write-Host "[INFO] El sitio FTP '$siteName' ya existe." -ForegroundColor Yellow
        $overwrite = Read-Host "¿Desea reinstalar el servidor de cero, eliminando todos los usuarios alumno* y directorios de aislamiento? (S/N)"
        if ($overwrite -eq "S" -or $overwrite -eq "s") {
            Write-Host "[INFO] Eliminando sitio FTP y limpiando datos..." -ForegroundColor Yellow
            Remove-WebSite -Name $siteName -Confirm:$false
            
            # Limpiar directorios físicos de aislamiento
            if (Test-Path "C:\inetpub\ftproot\LocalUser") {
                Remove-Item -Path "C:\inetpub\ftproot\LocalUser" -Recurse -Force -ErrorAction SilentlyContinue
            }
            # Limpiar usuarios alumno* locales
            Get-LocalUser | Where-Object {$_.Name -like "alumno*"} | Remove-LocalUser -ErrorAction SilentlyContinue
            Write-Host "[OK] Limpieza de usuarios y directorios completada." -ForegroundColor Green
        } else {
            Write-Host "[INFO] Reconfigurando sitio existente sin borrar usuarios ni directorios..." -ForegroundColor Yellow
            Remove-WebSite -Name $siteName -Confirm:$false
        }
    }
    
    # Crear el sitio usando el proveedor IIS:\
    New-Item -Path "IIS:\Sites\$siteName" -bindings @{protocol="ftp";bindingInformation="*:21:"} -physicalPath "C:\inetpub\ftproot" | Out-Null

    # Habilitar aislamiento por directorio local (LocalUser\<usuario>)
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.userIsolation.mode -Value "LocalDirectory"

    # Configurar autenticación básica y anónima usando Set-ItemProperty (sencillo y sin warnings)
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # Configurar directiva SSL: Permitir sin requerir (SslAllow)
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"

    # Configurar autorización FTP global: Permitir lectura/escritura a todos
    # (Los accesos se limitarán a nivel de NTFS)
    $filter = "system.ftpServer/security/authorization"
    # Limpiar reglas existentes
    Clear-WebConfiguration -Filter $filter -PSPath "IIS:\Sites\$siteName" -ErrorAction SilentlyContinue
    # Agregar regla para todos los usuarios
    Add-WebConfiguration -Filter $filter -PSPath "IIS:\Sites\$siteName" -Value @{accessType="Allow"; users="*"; roles=""; permissions="Read, Write"}

    # Crear directorio virtual 'general' para el usuario Anonymous (Public)
    $publicGeneralPath = "IIS:\Sites\$siteName\LocalUser\Public\general"
    if (-not (Test-Path $publicGeneralPath)) {
        New-Item -Path "IIS:\Sites\$siteName\LocalUser\Public\general" -PhysicalPath "C:\inetpub\ftproot\general" -Type VirtualDirectory | Out-Null
    }

    # Iniciar el servicio y el sitio FTP
    Restart-Service ftpsvc -Force
    Start-WebSite -Name $siteName -ErrorAction SilentlyContinue

    Write-Host "[OK] Servidor IIS FTP configurado correctamente." -ForegroundColor Green
}

function Crear-Usuario-FTP-Windows {
    param(
        [string]$username,
        [string]$password,
        [string]$group
    )

    if ([string]::IsNullOrEmpty($username) -or [string]::IsNullOrEmpty($password) -or [string]::IsNullOrEmpty($group)) {
        Write-Host "[ERROR] Parámetros insuficientes." -ForegroundColor Red
        return
    }

    if ($group -ne "reprobados" -and $group -ne "recursadores") {
        Write-Host "[ERROR] El grupo debe ser 'reprobados' o 'recursadores'." -ForegroundColor Red
        return
    }

    # Asegurar que el grupo local de Windows exista
    $grp = Get-LocalGroup -Name $group -ErrorAction SilentlyContinue
    if (-not $grp) {
        New-LocalGroup -Name $group | Out-Null
        Write-Host "[OK] Grupo local '$group' creado." -ForegroundColor Green
    }

    # Crear usuario usando net user (más robusto que New-LocalUser en entornos de servidor)
    $usr = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
    if ($usr) {
        Write-Host "[AVISO] El usuario '$username' ya existe. Restableciendo contraseña..." -ForegroundColor Yellow
        # net user es el método más confiable para resetear contraseña en Windows Server
        net user $username $password | Out-Null
        net user $username /active:yes | Out-Null
    } else {
        net user $username $password /add /passwordreq:yes /expires:never | Out-Null
        net user $username /active:yes | Out-Null
        Write-Host "[OK] Usuario '$username' creado en Windows." -ForegroundColor Green
    }
    # Verificar que la cuenta quedó activa y con contraseña correcta
    $checkUser = net user $username 2>&1
    if ($checkUser -match "Account active.*Yes") {
        Write-Host "[OK] Cuenta '$username' activa y contraseña establecida." -ForegroundColor Green
    } else {
        Write-Host "[WARN] Verificar manualmente el estado de la cuenta '$username'." -ForegroundColor Yellow
        $checkUser | Select-String -Pattern "Account active|Password"
    }

    # Asignar grupo
    # Remover de otros grupos para evitar conflictos
    Remove-LocalGroupMember -Group "reprobados" -Member $username -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "recursadores" -Member $username -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $group -Member $username | Out-Null

    # Dar permisos NTFS a las carpetas del grupo
    icacls "C:\inetpub\ftproot\groups\$group" /grant:r "${group}:(OI)(CI)F" /grant:r "Administrators:(OI)(CI)F" /inheritance:r | Out-Null

    # Crear carpeta física personal del usuario
    $userPersonalPath = "C:\inetpub\ftproot\users\$username"
    if (-not (Test-Path $userPersonalPath)) {
        New-Item -ItemType Directory -Path $userPersonalPath -Force | Out-Null
    }
    # Permisos NTFS restrictivos para carpeta personal
    icacls $userPersonalPath /inheritance:r /grant:r "${username}:(OI)(CI)F" /grant:r "Administrators:(OI)(CI)F" | Out-Null

    # Crear las carpetas físicas de aislamiento (tanto con prefijo de equipo como sin él como fallback)
    $computerDirPath = "C:\inetpub\ftproot\LocalUser\$env:COMPUTERNAME"
    if (-not (Test-Path $computerDirPath)) {
        New-Item -ItemType Directory -Path $computerDirPath -Force | Out-Null
    }
    icacls $computerDirPath /grant "NT SERVICE\FTPSVC:(OI)(CI)RX" | Out-Null
    icacls $computerDirPath /grant "Users:RX" | Out-Null

    # 1. Ruta con prefijo de equipo
    $userRootPathComputer = "C:\inetpub\ftproot\LocalUser\$env:COMPUTERNAME\$username"
    if (-not (Test-Path $userRootPathComputer)) {
        New-Item -ItemType Directory -Path $userRootPathComputer -Force | Out-Null
    }
    icacls $userRootPathComputer /grant:r "${username}:(OI)(CI)RX" /grant:r "Administrators:(OI)(CI)F" /grant:r "NT SERVICE\FTPSVC:(OI)(CI)RX" /inheritance:e | Out-Null

    # 2. Ruta sin prefijo de equipo (fallback)
    $userRootPathPlain = "C:\inetpub\ftproot\LocalUser\$username"
    if (-not (Test-Path $userRootPathPlain)) {
        New-Item -ItemType Directory -Path $userRootPathPlain -Force | Out-Null
    }
    icacls $userRootPathPlain /grant:r "${username}:(OI)(CI)RX" /grant:r "Administrators:(OI)(CI)F" /grant:r "NT SERVICE\FTPSVC:(OI)(CI)RX" /inheritance:e | Out-Null

    # Configurar directorios virtuales en IIS para ambas estructuras (con y sin prefijo de equipo)
    Import-Module WebAdministration
    $siteName = "FTP_SysAdmin"

    $pathsToConfig = @(
        "LocalUser\$env:COMPUTERNAME\$username",
        "LocalUser\$username"
    )

    foreach ($p in $pathsToConfig) {
        # 1. Virtual 'general'
        $vdirGenPath = "IIS:\Sites\$siteName\$p\general"
        if (-not (Test-Path $vdirGenPath)) {
            New-Item -Path $vdirGenPath -PhysicalPath "C:\inetpub\ftproot\general" -Type VirtualDirectory | Out-Null
        }

        # 2. Virtual del Grupo
        Remove-Item -Path "IIS:\Sites\$siteName\$p\reprobados" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "IIS:\Sites\$siteName\$p\recursadores" -Recurse -Force -ErrorAction SilentlyContinue
        
        New-Item -Path "IIS:\Sites\$siteName\$p\$group" -PhysicalPath "C:\inetpub\ftproot\groups\$group" -Type VirtualDirectory | Out-Null

        # 3. Virtual de carpeta personal (con el nombre del usuario)
        $vdirPersPath = "IIS:\Sites\$siteName\$p\$username"
        if (-not (Test-Path $vdirPersPath)) {
            New-Item -Path $vdirPersPath -PhysicalPath "C:\inetpub\ftproot\users\$username" -Type VirtualDirectory | Out-Null
        }
    }

    Write-Host "[OK] Aislamiento de directorios virtuales creado para '$username' (en ambas estructuras de carpetas)." -ForegroundColor Green
}

function Cambiar-Grupo-Usuario-Windows {
    param(
        [string]$username,
        [string]$new_group
    )

    if ([string]::IsNullOrEmpty($username) -or [string]::IsNullOrEmpty($new_group)) {
        Write-Host "[ERROR] Parámetros insuficientes." -ForegroundColor Red
        return
    }

    if ($new_group -ne "reprobados" -and $new_group -ne "recursadores") {
        Write-Host "[ERROR] El grupo debe ser 'reprobados' o 'recursadores'." -ForegroundColor Red
        return
    }

    # Verificar que el usuario exista
    $usr = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
    if (-not $usr) {
        Write-Host "[ERROR] El usuario '$username' no existe." -ForegroundColor Red
        return
    }

    # Cambiar membresía de grupo local
    Remove-LocalGroupMember -Group "reprobados" -Member $username -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "recursadores" -Member $username -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $new_group -Member $username | Out-Null
    Write-Host "[OK] Membresía de Windows actualizada para '$username' -> '$new_group'." -ForegroundColor Green

    # Actualizar directorios virtuales en IIS para ambas estructuras (con y sin prefijo de equipo)
    Import-Module WebAdministration
    $siteName = "FTP_SysAdmin"
    
    $pathsToConfig = @(
        "LocalUser\$env:COMPUTERNAME\$username",
        "LocalUser\$username"
    )

    foreach ($p in $pathsToConfig) {
        # Remover directorios virtuales de grupo viejos
        Remove-Item -Path "IIS:\Sites\$siteName\$p\reprobados" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "IIS:\Sites\$siteName\$p\recursadores" -Recurse -Force -ErrorAction SilentlyContinue

        # Crear el nuevo directorio virtual
        New-Item -Path "IIS:\Sites\$siteName\$p\$new_group" -PhysicalPath "C:\inetpub\ftproot\groups\$new_group" -Type VirtualDirectory | Out-Null
    }
    Write-Host "[OK] Directorio virtual de IIS cambiado a '$new_group' en ambas estructuras." -ForegroundColor Green
}

function Monitorear-FTP-Windows {
    $continuar = $true
    while ($continuar) {
        Banner "MONITOREO FTP - WINDOWS SERVER"
        Write-Host "  1) Estado del servicio FTP (ftpsvc)"
        Write-Host "  2) Ver estado del sitio FTP_SysAdmin"
        Write-Host "  3) Listar usuarios creados en reprobados/recursadores"
        Write-Host "  4) Ver logs de conexiones FTP (u_ex*.log)"
        Write-Host "  5) Volver al menú principal"
        $choice = Read-Host "Seleccione una opción (1-5)"

        if ($choice -eq "1") {
            Get-Service -Name ftpsvc | Format-List Name, Status, StartType
        }
        elseif ($choice -eq "2") {
            Import-Module WebAdministration
            Get-Website -Name "FTP_SysAdmin" | Format-Table Name, State, PhysicalPath, Bindings
        }
        elseif ($choice -eq "3") {
            Write-Host "`nMiembros de 'reprobados':" -ForegroundColor Cyan
            Get-LocalGroupMember -Group "reprobados" -ErrorAction SilentlyContinue | Format-Table Name, PrincipalSource
            Write-Host "`nMiembros de 'recursadores':" -ForegroundColor Cyan
            Get-LocalGroupMember -Group "recursadores" -ErrorAction SilentlyContinue | Format-Table Name, PrincipalSource
        }
        elseif ($choice -eq "4") {
            Write-Host "`nUltimos 15 registros de conexiones FTP en IIS:" -ForegroundColor Cyan
            # Buscar en todos los subdirectorios de LogFiles que empiecen por FTPSVC
            $logDirs = Get-ChildItem -Path "C:\inetpub\logs\LogFiles" -Directory -Filter "FTPSVC*" -ErrorAction SilentlyContinue
            if ($logDirs) {
                $latestLog = Get-ChildItem -Path $logDirs.FullName -Filter *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
                if ($latestLog) {
                    Write-Host "Mostrando: $($latestLog.FullName)`n" -ForegroundColor Yellow
                    Get-Content -Path $latestLog.FullName | Select-Object -Last 15
                } else {
                    Write-Host "No se encontraron archivos de log (.log) en los directorios de FTPSVC." -ForegroundColor Yellow
                }
            } else {
                Write-Host "No se encontro el directorio de logs de FTPSVC en C:\inetpub\logs\LogFiles." -ForegroundColor Yellow
            }
        }
        elseif ($choice -eq "5") {
            $continuar = $false
        }
        else {
            Write-Host "Opción inválida." -ForegroundColor Red
        }
    }
}

function Diagnosticar-Usuario-FTP {
    param([string]$username)

    if ([string]::IsNullOrEmpty($username)) {
        $username = Read-Host "Nombre del usuario a diagnosticar"
    }

    Write-Host "`n====== DIAGNOSTICO CUENTA WINDOWS: $username ======" -ForegroundColor Cyan

    # 1. Estado de la cuenta Windows
    $userInfo = net user $username 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] El usuario '$username' NO existe en Windows." -ForegroundColor Red
        return
    }
    $userInfo | Select-String -Pattern "Account active|Password expires|Password last set|Account expires|User may change|Login hours" | ForEach-Object {
        Write-Host "  $_"
    }

    # 2. Verificar directorios fisicos
    Write-Host "`n-- Directorios fisicos de aislamiento:" -ForegroundColor Cyan
    $paths = @(
        "C:\inetpub\ftproot\LocalUser\$env:COMPUTERNAME\$username",
        "C:\inetpub\ftproot\LocalUser\$username"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Write-Host "  [OK] $p" -ForegroundColor Green
            icacls $p 2>&1 | Select-Object -First 5 | ForEach-Object { Write-Host "       $_" }
        } else {
            Write-Host "  [MISS] $p" -ForegroundColor Red
        }
    }

    # 3. Verificar directorios virtuales IIS
    Write-Host "`n-- Directorios virtuales IIS:" -ForegroundColor Cyan
    Import-Module WebAdministration
    $siteName = "FTP_SysAdmin"
    $iispaths = @(
        "IIS:\Sites\$siteName\LocalUser\$env:COMPUTERNAME\$username",
        "IIS:\Sites\$siteName\LocalUser\$username"
    )
    foreach ($ip in $iispaths) {
        if (Test-Path $ip) {
            Write-Host "  [OK] $ip" -ForegroundColor Green
        } else {
            Write-Host "  [MISS] $ip" -ForegroundColor Red
        }
    }

    # 4. Probar login con Net Logon
    Write-Host "`n-- Test de autenticacion local:" -ForegroundColor Cyan
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $ctx = [System.DirectoryServices.AccountManagement.PrincipalContext]::new([System.DirectoryServices.AccountManagement.ContextType]::Machine)
    $pass = Read-Host "Ingresa la contrasena del usuario para probar autenticacion"
    $loginOk = $ctx.ValidateCredentials($username, $pass)
    if ($loginOk) {
        Write-Host "  [OK] Credenciales validas. Windows acepta el login." -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] Credenciales INVALIDAS. Windows rechaza el login." -ForegroundColor Red
        Write-Host "  -> Esto causa el codigo 1326 en el log de IIS FTP." -ForegroundColor Yellow
    }
}
