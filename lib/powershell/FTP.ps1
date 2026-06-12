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

    # 3. Configurar el sitio FTP en IIS
    Write-Host "[3/3] Configurando sitio FTP en IIS con aislamiento de usuarios..." -ForegroundColor Blue
    Import-Module WebAdministration

    # Crear sitio FTP si no existe
    $siteName = "FTP_SysAdmin"
    $site = Get-WebSite -Name $siteName -ErrorAction SilentlyContinue
    if ($site) {
        Write-Host "[INFO] Sitio FTP '$siteName' ya existe. Reconfigurando..." -ForegroundColor Yellow
        Remove-WebSite -Name $siteName -Confirm:$false
    }
    
    # Crear el sitio usando el proveedor IIS:\
    New-Item -Path "IIS:\Sites\$siteName" -bindings @{protocol="ftp";bindingInformation="*:21:"} -physicalPath "C:\inetpub\ftproot" | Out-Null

    # Habilitar aislamiento por directorio local (LocalUser\<usuario>)
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.userIsolation.mode -Value "LocalDirectory"

    # Habilitar autenticación básica y anónima
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # Configurar directiva SSL: Permitir sin requerir (SslAllow)
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"

    # Configurar autorización FTP global: Permitir lectura/escritura a todos
    # (Los accesos se limitarán a nivel de NTFS)
    $authPath = "system.ftpServer/security/authorization"
    $filter = "/authorization"
    # Limpiar reglas existentes
    Clear-WebConfiguration -Filter $filter -PSPath "IIS:\Sites\$siteName"
    # Agregar regla para todos los usuarios
    Add-WebConfigurationRule -Filter $filter -PSPath "IIS:\Sites\$siteName" -Value @{accessType="Allow"; users="*"; roles=""; permissions="Read, Write"}

    # Crear directorio virtual 'general' para el usuario Anonymous (Public)
    $publicGeneralPath = "IIS:\Sites\$siteName\LocalUser\Public\general"
    if (-not (Test-Path $publicGeneralPath)) {
        New-WebVirtualDirectory -Site $siteName -Name "general" -PhysicalPath "C:\inetpub\ftproot\general" -ApplicationFolder "LocalUser\Public" | Out-Null
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

    # Crear usuario
    $usr = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
    if ($usr) {
        Write-Host "[AVISO] El usuario '$username' ya existe. Modificando grupo..." -ForegroundColor Yellow
    } else {
        $secPass = ConvertTo-SecureString $password -AsPlainText -Force
        New-LocalUser -Name $username -Password $secPass -FullName $username -Description "Usuario FTP" -PasswordNeverExpires $true | Out-Null
        Write-Host "[OK] Usuario '$username' creado en Windows." -ForegroundColor Green
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

    # Crear la carpeta física del home de aislamiento (chroot)
    $userRootPath = "C:\inetpub\ftproot\LocalUser\$username"
    if (-not (Test-Path $userRootPath)) {
        New-Item -ItemType Directory -Path $userRootPath -Force | Out-Null
    }
    # Solo lectura NTFS para la raíz del home de aislamiento (los directorios virtuales tendrán escritura en sus respectivos destinos)
    icacls $userRootPath /grant:r "${username}:(OI)(CI)R" /grant:r "Administrators:(OI)(CI)F" /inheritance:e | Out-Null

    # Configurar directorios virtuales en IIS
    Import-Module WebAdministration
    $siteName = "FTP_SysAdmin"

    # 1. Virtual 'general'
    $vdirGen = Get-WebVirtualDirectory -Site $siteName -Name "general" -ApplicationFolder "LocalUser\$username" -ErrorAction SilentlyContinue
    if (-not $vdirGen) {
        New-WebVirtualDirectory -Site $siteName -Name "general" -PhysicalPath "C:\inetpub\ftproot\general" -ApplicationFolder "LocalUser\$username" | Out-Null
    }

    # 2. Virtual del Grupo
    # Limpiar directorios virtuales viejos de grupos si los hay
    Remove-WebVirtualDirectory -Site $siteName -Name "reprobados" -ApplicationFolder "LocalUser\$username" -ErrorAction SilentlyContinue
    Remove-WebVirtualDirectory -Site $siteName -Name "recursadores" -ApplicationFolder "LocalUser\$username" -ErrorAction SilentlyContinue
    
    New-WebVirtualDirectory -Site $siteName -Name $group -PhysicalPath "C:\inetpub\ftproot\groups\$group" -ApplicationFolder "LocalUser\$username" | Out-Null

    # 3. Virtual de carpeta personal (con el nombre del usuario)
    $vdirPers = Get-WebVirtualDirectory -Site $siteName -Name $username -ApplicationFolder "LocalUser\$username" -ErrorAction SilentlyContinue
    if (-not $vdirPers) {
        New-WebVirtualDirectory -Site $siteName -Name $username -PhysicalPath "C:\inetpub\ftproot\users\$username" -ApplicationFolder "LocalUser\$username" | Out-Null
    }

    Write-Host "[OK] Aislamiento de directorios virtuales creado para '$username'." -ForegroundColor Green
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

    # Actualizar directorios virtuales en IIS
    Import-Module WebAdministration
    $siteName = "FTP_SysAdmin"
    
    # Remover directorios virtuales de grupo viejos
    Remove-WebVirtualDirectory -Site $siteName -Name "reprobados" -ApplicationFolder "LocalUser\$username" -ErrorAction SilentlyContinue
    Remove-WebVirtualDirectory -Site $siteName -Name "recursadores" -ApplicationFolder "LocalUser\$username" -ErrorAction SilentlyContinue

    # Crear el nuevo directorio virtual
    New-WebVirtualDirectory -Site $siteName -Name $new_group -PhysicalPath "C:\inetpub\ftproot\groups\$new_group" -ApplicationFolder "LocalUser\$username" | Out-Null
    Write-Host "[OK] Directorio virtual de IIS cambiado a '$new_group'." -ForegroundColor Green
}

function Monitorear-FTP-Windows {
    $continuar = $true
    while ($continuar) {
        Banner "MONITOREO FTP - WINDOWS SERVER"
        Write-Host "  1) Estado del servicio FTP (ftpsvc)"
        Write-Host "  2) Ver estado del sitio FTP_SysAdmin"
        Write-Host "  3) Listar usuarios creados en reprobados/recursadores"
        Write-Host "  4) Volver al menú principal"
        $choice = Read-Host "Seleccione una opción (1-4)"

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
            $continuar = $false
        }
        else {
            Write-Host "Opción inválida." -ForegroundColor Red
        }
    }
}
