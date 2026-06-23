# lib/powershell/Governanza.ps1
# Funciones para Gobernanza AD: OU, Logon Hours, GPO, FSRM y AppLocker.
# Uso: . "$libDir\Governanza.ps1"

# ─── Constantes de la practica ────────────────────────────────────────────────
$script:GOV_DomainName      = "sysadmin.local"
$script:GOV_OUBase           = "OU=Usuarios,DC=sysadmin,DC=local"
$script:GOV_OUCuates        = "OU=Cuates,OU=Usuarios,DC=sysadmin,DC=local"
$script:GOV_OUNoCuates       = "OU=No Cuates,OU=Usuarios,DC=sysadmin,DC=local"
$script:GOV_GrupoCuates      = "Cuates"
$script:GOV_GrupoNoCuates    = "No Cuates"
$script:GOV_ShareUsuarios    = "D:\Shares\Usuarios"
if (-not (Test-Path "D:\")) {
    $script:GOV_ShareUsuarios = "C:\Shares\Usuarios"
}
$script:GOV_ShareUNC         = "\\$env:COMPUTERNAME\Usuarios"

# ─── Convertir horas permitidas a arreglo de bytes (Set-ADUser -LogonHours) ───
# Cada bit representa una hora (0=Dom 00:00, bit 23=Dom 23:00, bit 24=Lun 00:00...)
function New-LogonHoursByteArray {
    param([int[]]$AllowedHours)
    $bytes = New-Object byte[] 21
    for ($day = 0; $day -lt 7; $day++) {
        foreach ($hour in $AllowedHours) {
            if ($hour -lt 0 -or $hour -gt 23) { continue }
            $bitIndex  = ($day * 24) + $hour
            $byteIndex = [math]::Floor($bitIndex / 8)
            $bitOffset = $bitIndex % 8
            $bytes[$byteIndex] = $bytes[$byteIndex] -bor [byte](1 -shl $bitOffset)
        }
    }
    return $bytes
}

# Cuates: 08:00 - 15:00 (horas 8..14)
function Get-LogonHours-Cuates   { New-LogonHoursByteArray -AllowedHours @(8..14) }

# No Cuates: 15:00 - 02:00 (horas 15..23 y 0..1)
function Get-LogonHours-NoCuates { New-LogonHoursByteArray -AllowedHours @(15,16,17,18,19,20,21,22,23,0,1) }

# ─── Instalar roles AD DS, FSRM y caracteristicas necesarias ─────────────────
function Instalar-Roles-Gobernanza {
    Banner "INSTALACION DE ROLES - AD DS Y FSRM"
    Import-Module ServerManager -ErrorAction Stop

    $features = @(
        "AD-Domain-Services",
        "RSAT-AD-PowerShell",
        "GPMC",
        "FS-Resource-Manager",
        "FS-FileServer"
    )
    foreach ($feat in $features) {
        Instalar-Feature $feat
    }
    Write-Host "[OK] Roles de gobernanza instalados." -ForegroundColor Green
}

# ─── Promover servidor a Controlador de Dominio ──────────────────────────────
function Configurar-Dominio-AD {
  param(
        [string]$DomainName = $script:GOV_DomainName,
        $SafeModePassword
    )
    Banner "CONFIGURACION DE DOMINIO ACTIVE DIRECTORY"
    Import-Module ADDSDeployment -ErrorAction Stop

    $forest = Get-ADForest -ErrorAction SilentlyContinue
    if ($forest) {
        Write-Host "[INFO] El dominio '$($forest.Name)' ya existe." -ForegroundColor Yellow
        return
    }

    if ($null -eq $SafeModePassword -or [string]::IsNullOrWhiteSpace($SafeModePassword)) {
        $SafeModePassword = Read-Host "Contrasena modo seguro DSRM" -AsSecureString
    } elseif ($SafeModePassword -is [string]) {
        $SafeModePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
    }

    $netbios = ($DomainName -split '\.')[0].ToUpper()
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $netbios `
        -ForestMode WinThreshold `
        -DomainMode WinThreshold `
        -InstallDns `
        -SafeModeAdministratorPassword $SafeModePassword `
        -Force `
        -NoRebootOnCompletion:$false | Out-Null

    Write-Host "[OK] Dominio '$DomainName' creado. Reinicio requerido si no se reinicio automaticamente." -ForegroundColor Green
}

# ─── Crear estructura organizativa (OU Cuates / No Cuates) ───────────────────
function Crear-Estructura-OU {
    Banner "ESTRUCTURA ORGANIZATIVA - CUATES Y NO CUATES"
    Import-Module ActiveDirectory -ErrorAction Stop

    $domainDN = (Get-ADDomain).DistinguishedName
    $ouUsuarios = "OU=Usuarios,$domainDN"

    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Usuarios'" -SearchBase $domainDN -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "Usuarios" -Path $domainDN -ProtectedFromAccidentalDeletion $true
        Write-Host "[OK] OU 'Usuarios' creada." -ForegroundColor Green
    }

    foreach ($ouName in @("Cuates", "No Cuates")) {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'" -SearchBase $ouUsuarios -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $ouName -Path $ouUsuarios -ProtectedFromAccidentalDeletion $true
            Write-Host "[OK] OU '$ouName' creada." -ForegroundColor Green
        } else {
            Write-Host "[INFO] OU '$ouName' ya existe." -ForegroundColor Yellow
        }
    }

    foreach ($grp in @($script:GOV_GrupoCuates, $script:GOV_GrupoNoCuates)) {
        if (-not (Get-ADGroup -Filter "Name -eq '$grp'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $grp -GroupScope Global -GroupCategory Security -Path $ouUsuarios
            Write-Host "[OK] Grupo '$grp' creado." -ForegroundColor Green
        }
    }
}

# ─── Importar usuarios desde CSV y distribuir por Departamento ───────────────
function Importar-Usuarios-DesdeCSV {
    param([string]$CsvPath)

    Banner "IMPORTACION MASIVA DE USUARIOS DESDE CSV"
    Import-Module ActiveDirectory -ErrorAction Stop

    if (-not (Test-Path $CsvPath)) {
        Write-Host "[ERROR] No se encontro el archivo CSV: $CsvPath" -ForegroundColor Red
        return
    }

    $usuarios = Import-Csv -Path $CsvPath -Encoding UTF8
    $domainDN = (Get-ADDomain).DistinguishedName
    $ouUsuarios = "OU=Usuarios,$domainDN"

    foreach ($u in $usuarios) {
        $sam = $u.NombreUsuario
        $depto = $u.Departamento.Trim()

        if ($depto -match "Cuates" -and $depto -notmatch "No") {
            $ouPath  = "OU=Cuates,$ouUsuarios"
            $grupo   = $script:GOV_GrupoCuates
            $logonH  = Get-LogonHours-Cuates
        } else {
            $ouPath  = "OU=No Cuates,$ouUsuarios"
            $grupo   = $script:GOV_GrupoNoCuates
            $logonH  = Get-LogonHours-NoCuates
        }

        $homePath = Join-Path $script:GOV_ShareUsuarios $sam
        if (-not (Test-Path $homePath)) {
            New-Item -ItemType Directory -Path $homePath -Force | Out-Null
        }

        # El directorio personal en AD debe ser una ruta UNC de red para que se monte en clientes
        $homeUNC = "$script:GOV_ShareUNC\$sam"

        $userParams = @{
            Name                 = "$($u.Nombre) $($u.Apellido)"
            SamAccountName       = $sam
            UserPrincipalName    = "$sam@$((Get-ADDomain).DNSRoot)"
            GivenName            = $u.Nombre
            Surname              = $u.Apellido
            DisplayName          = "$($u.Nombre) $($u.Apellido)"
            Path                 = $ouPath
            AccountPassword      = (ConvertTo-SecureString $u.Contrasena -AsPlainText -Force)
            Enabled              = $true
            ChangePasswordAtLogon = $false
            HomeDirectory        = $homeUNC
            HomeDrive            = "H:"
        }

        $existente = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
        if ($existente) {
            Set-ADUser -Identity $sam -Replace @{logonhours = $logonH} -HomeDirectory $homeUNC -HomeDrive "H:"
            Write-Host "[INFO] Usuario '$sam' actualizado (horario y carpeta)." -ForegroundColor Yellow
        } else {
            New-ADUser @userParams
            Set-ADUser -Identity $sam -Replace @{logonhours = $logonH}
            Write-Host "[OK] Usuario '$sam' creado en '$depto'." -ForegroundColor Green
        }

        # Asegurar que el grupo existe antes de agregar miembros
        if (-not (Get-ADGroup -Filter "Name -eq '$grupo'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $grupo -GroupScope Global -GroupCategory Security -Path $ouUsuarios | Out-Null
            Write-Host "[OK] Grupo '$grupo' creado en caliente." -ForegroundColor Green
        }
        Add-ADGroupMember -Identity $grupo -Members $sam -ErrorAction SilentlyContinue

        # Permisos NTFS en carpeta personal
        $acl = Get-Acl $homePath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSADMIN\$sam", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $homePath -AclObject $acl
    }

    Write-Host "[OK] $($usuarios.Count) usuarios procesados desde CSV." -ForegroundColor Green
}

# ─── Compartir carpeta de usuarios en red ────────────────────────────────────
function Configurar-Share-Usuarios {
    Banner "RECURSO COMPARTIDO DE CARPETAS DE USUARIO"
    if (-not (Test-Path $script:GOV_ShareUsuarios)) {
        New-Item -ItemType Directory -Path $script:GOV_ShareUsuarios -Force | Out-Null
    }

    $share = Get-SmbShare -Name "Usuarios" -ErrorAction SilentlyContinue
    if (-not $share) {
        New-SmbShare -Name "Usuarios" -Path $script:GOV_ShareUsuarios -FullAccess "Administrators" -ChangeAccess "Authenticated Users" | Out-Null
        Write-Host "[OK] Share 'Usuarios' creado en $script:GOV_ShareUsuarios" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Share 'Usuarios' ya existe." -ForegroundColor Yellow
    }
}

# ─── GPO: Forzar cierre de sesion al expirar horario de logon ────────────────
function Configurar-GPO-ForceLogoff {
    Banner "GPO - CIERRE DE SESION FORZADO POR HORARIO"
    Import-Module GroupPolicy -ErrorAction Stop

    $gpoName = "GPO_Tarea8_ForceLogoff"
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $gpoName -Comment "Fuerza logoff cuando expiran las horas de inicio de sesion"
        Write-Host "[OK] GPO '$gpoName' creada." -ForegroundColor Green
    }

    # Seguridad de red: cerrar sesion cuando expire el tiempo de inicio de sesion
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -ValueName "EnableForcedLogoff" -Type DWord -Value 1 | Out-Null

    # Politica de seguridad local equivalente (ForceLogoffWhenHourExpire)
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
        -ValueName "EnableForcedLogoff" -Type DWord -Value 1 | Out-Null

    $domainDN = (Get-ADDomain).DistinguishedName
    $ouUsuarios = "OU=Usuarios,$domainDN"
    New-GPLink -Name $gpoName -Target $ouUsuarios -LinkEnabled Yes -Enforced Yes -ErrorAction SilentlyContinue | Out-Null

    Write-Host "[OK] GPO de cierre forzado vinculada a OU Usuarios." -ForegroundColor Green
    Write-Host "[INFO] Ejecute 'gpupdate /force' en clientes para aplicar." -ForegroundColor Cyan
}

# ─── FSRM: Cuotas estrictas por grupo (5 MB / 10 MB) ─────────────────────────
function Configurar-Cuotas-FSRM {
    Banner "FSRM - CUOTAS ESTRICTAS POR GRUPO"
    try {
        Import-Module Fsrm -ErrorAction Stop

        # Plantillas de cuota
        $plantillas = @(
            @{ Name = "Cuota_Cuates_10MB";    Size = 10MB; Desc = "Cuota 10 MB para grupo Cuates" }
            @{ Name = "Cuota_NoCuates_5MB";   Size = 5MB;  Desc = "Cuota 5 MB para grupo No Cuates" }
        )
        foreach ($p in $plantillas) {
            $tpl = Get-FsrmQuotaTemplate -Name $p.Name -ErrorAction SilentlyContinue
            if (-not $tpl) {
                New-FsrmQuotaTemplate -Name $p.Name -Size $p.Size -Description $p.Desc | Out-Null
                Set-FsrmQuotaTemplate -Name $p.Name -SoftLimit:$false | Out-Null
                Write-Host "[OK] Plantilla '$($p.Name)' creada ($([math]::Round($p.Size / 1MB)) MB, estricta)." -ForegroundColor Green
            }
        }

        # Aplicar cuotas por carpeta de usuario segun OU
        $domainDN = (Get-ADDomain).DistinguishedName
        foreach ($ouName in @("Cuates", "No Cuates")) {
            $ouPath = "OU=$ouName,OU=Usuarios,$domainDN"
            $users  = Get-ADUser -Filter * -SearchBase $ouPath -Properties SamAccountName
            $tplName = if ($ouName -eq "Cuates") { "Cuota_Cuates_10MB" } else { "Cuota_NoCuates_5MB" }

            foreach ($user in $users) {
                $userPath = Join-Path $script:GOV_ShareUsuarios $user.SamAccountName
                if (-not (Test-Path $userPath)) { continue }

                $quota = Get-FsrmQuota -Path $userPath -ErrorAction SilentlyContinue
                if ($quota) {
                    Set-FsrmQuota -Path $userPath -Template $tplName | Out-Null
                } else {
                    New-FsrmQuota -Path $userPath -Template $tplName -ErrorAction SilentlyContinue | Out-Null
                }
            }
            Write-Host "[OK] Cuotas '$tplName' aplicadas en OU '$ouName'." -ForegroundColor Green
        }
    } catch {
        Write-Host "[WARNING] No se pudo configurar las cuotas FSRM: $_" -ForegroundColor Yellow
        Write-Host "[HINT] Si acaba de promover el AD, por favor reinicie el servidor y vuelva a ejecutar esta opcion." -ForegroundColor Cyan
    }
}

# ─── FSRM: Apantallamiento dinamico de archivos multimedia y ejecutables ─────
function Configurar-FileScreen-FSRM {
    Banner "FSRM - APANTALLAMIENTO DE ARCHIVOS (ACTIVE SCREENING)"
    try {
        Import-Module Fsrm -ErrorAction Stop

        $groupName = "Bloqueados_Multimedia_Ejecutables"
        $extensions = @("*.mp3", "*.mp4", "*.exe", "*.msi")

        $fg = Get-FsrmFileGroup -Name $groupName -ErrorAction SilentlyContinue
        if (-not $fg) {
            New-FsrmFileGroup -Name $groupName -IncludePattern $extensions `
                -Description "Bloquea multimedia y ejecutables en carpetas personales" | Out-Null
            Write-Host "[OK] Grupo de archivos '$groupName' creado." -ForegroundColor Green
        }

        $screenName = "Screen_Bloqueo_Tarea8"
        $screen = Get-FsrmFileScreenTemplate -Name $screenName -ErrorAction SilentlyContinue
        if (-not $screen) {
            New-FsrmFileScreenTemplate -Name $screenName -IncludeGroup $groupName -Active:$true `
                -Description "Bloqueo activo de extensiones prohibidas" | Out-Null
            Write-Host "[OK] Plantilla de apantallamiento '$screenName' creada." -ForegroundColor Green
        }

        if (-not (Test-Path $script:GOV_ShareUsuarios)) {
            New-Item -ItemType Directory -Path $script:GOV_ShareUsuarios -Force | Out-Null
        }

        $existing = Get-FsrmFileScreen -Path $script:GOV_ShareUsuarios -ErrorAction SilentlyContinue
        if ($existing) {
            Set-FsrmFileScreen -Path $script:GOV_ShareUsuarios -Template $screenName -Active:$true | Out-Null
        } else {
            New-FsrmFileScreen -Path $script:GOV_ShareUsuarios -Template $screenName -Active:$true | Out-Null
        }

        Write-Host "[OK] Apantallamiento activo en $script:GOV_ShareUsuarios" -ForegroundColor Green
        Write-Host "[INFO] Extensiones bloqueadas: $($extensions -join ', ')" -ForegroundColor Cyan
    } catch {
        Write-Host "[WARNING] No se pudo configurar el apantallamiento FSRM: $_" -ForegroundColor Yellow
        Write-Host "[HINT] Si acaba de promover el AD, por favor reinicie el servidor y vuelva a ejecutar esta opcion." -ForegroundColor Cyan
    }
}

# ─── AppLocker: Permitir Notepad en Cuates, bloquear por Hash en No Cuates ───
function Configurar-AppLocker-Notepad {
    Banner "APPLOCKER - CONTROL DE EJECUCION (BLOC DE NOTAS)"
    Import-Module AppLocker -ErrorAction SilentlyContinue

    $notepadPath = "$env:windir\System32\notepad.exe"
    if (-not (Test-Path $notepadPath)) {
        Write-Host "[ERROR] No se encontro notepad.exe en $notepadPath" -ForegroundColor Red
        return
    }

    # Obtener informacion de hash del ejecutable (requerido por la practica)
    $fileInfo = Get-AppLockerFileInformation -Path $notepadPath -FileType exe -ErrorAction Stop
    $hashData = $fileInfo | Select-Object -ExpandProperty FileHash -ErrorAction SilentlyContinue
  if (-not $hashData) {
        $hashData = ($fileInfo | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like "*Hash*" })
    }

    $domainDN = (Get-ADDomain).DistinguishedName
    $ouUsuarios = "OU=Usuarios,$domainDN"

    # --- GPO Cuates: permitir Notepad ---
    $gpoAllow = "GPO_Tarea8_AppLocker_Cuates_AllowNotepad"
    if (-not (Get-GPO -Name $gpoAllow -ErrorAction SilentlyContinue)) {
        New-GPO -Name $gpoAllow -Comment "Permite ejecutar Notepad para grupo Cuates" | Out-Null
    }

    $allowXml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="$(New-Guid)" Name="Permitir Notepad" Description="Cuates pueden usar Bloc de notas" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\System32\notepad.exe" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="$(New-Guid)" Name="Permitir Windows" Description="Permitir sistema" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="$(New-Guid)" Name="Permitir Program Files" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
    Set-AppLockerPolicy -XmlPolicy $allowXml -LDAP "LDAP://OU=Cuates,$ouUsuarios" -ErrorAction SilentlyContinue

    # --- GPO No Cuates: bloquear Notepad por Hash ---
    $gpoDeny = "GPO_Tarea8_AppLocker_NoCuates_DenyNotepad"
    if (-not (Get-GPO -Name $gpoDeny -ErrorAction SilentlyContinue)) {
        New-GPO -Name $gpoDeny -Comment "Bloquea Notepad por hash para grupo No Cuates" | Out-Null
    }

    # Generar regla de hash desde el archivo real (SHA-256)
    $sha256 = (Get-FileHash -Path $notepadPath -Algorithm SHA256).Hash
    $fileLen  = (Get-Item $notepadPath).Length

    $denyXml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FileHashRule Id="$(New-Guid)" Name="Bloquear Notepad por Hash" Description="Impide ejecutar notepad.exe aunque se renombre" UserOrGroupSid="S-1-1-0" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x$sha256" SourceFileName="notepad.exe" SourceFileLength="$fileLen" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
    <FilePathRule Id="$(New-Guid)" Name="Permitir Windows" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="$(New-Guid)" Name="Permitir Program Files" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
    Set-AppLockerPolicy -XmlPolicy $denyXml -LDAP "LDAP://OU=No Cuates,$ouUsuarios" -ErrorAction SilentlyContinue
    Write-Host "[OK] Regla de HASH (SHA-256) para bloquear Notepad aplicada a OU No Cuates." -ForegroundColor Green
    Write-Host "[INFO] Hash: $sha256" -ForegroundColor Cyan

    # Habilitar servicio AppLocker
    Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue

    # GPO para habilitar reglas AppLocker
    $gpoBase = "GPO_Tarea8_AppLocker_Enforcement"
    if (-not (Get-GPO -Name $gpoBase -ErrorAction SilentlyContinue)) {
        $gpoObj = New-GPO -Name $gpoBase
        Set-GPRegistryValue -Name $gpoBase -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\SrpV2\Exe" `
            -ValueName "EnforcementMode" -Type DWord -Value 1 | Out-Null
        New-GPLink -Name $gpoBase -Target $ouUsuarios -LinkEnabled Yes | Out-Null
    }

    Write-Host "[OK] Politicas AppLocker configuradas." -ForegroundColor Green
    Write-Host "[INFO] Cuates: Notepad permitido | No Cuates: bloqueado por HASH" -ForegroundColor Cyan
}

# ─── Union de cliente Windows al dominio ─────────────────────────────────────
function Unir-Cliente-Windows-Dominio {
    param(
        [string]$DomainName = $script:GOV_DomainName,
        [string]$DomainUser,
        [string]$DomainPassword,
        [string]$OuPath = ""
    )
    Banner "UNION DE CLIENTE WINDOWS AL DOMINIO"

    $domainInfo = Get-WmiObject Win32_ComputerSystem
    if ($domainInfo.PartOfDomain -and $domainInfo.Domain -eq $DomainName) {
        Write-Host "[INFO] Este equipo ya pertenece al dominio '$DomainName'." -ForegroundColor Yellow
        return
    }

    if ([string]::IsNullOrWhiteSpace($DomainUser)) {
        $DomainUser = Read-Host "Usuario con permisos de dominio (ej. Administrador)"
    }
    if ([string]::IsNullOrWhiteSpace($DomainPassword)) {
        $secPass = Read-Host "Contrasena" -AsSecureString
    } else {
        $secPass = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
    }

    $cred = New-Object System.Management.Automation.PSCredential("$DomainName\$DomainUser", $secPass)

    $params = @{
        DomainName = $DomainName
        Credential = $cred
        Force      = $true
        Restart    = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($OuPath)) {
        $params["OUPath"] = $OuPath
    }

    Add-Computer @params
    Write-Host "[OK] Cliente unido al dominio. Reiniciando..." -ForegroundColor Green
}

# ─── Resumen de estado de gobernanza ───────────────────────────────────────────
function Mostrar-Resumen-Gobernanza {
    Banner "RESUMEN DE GOBERNANZA - TAREA 8"
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    Write-Host "`n--- Estructura Organizativa ---" -ForegroundColor Cyan
    foreach ($ou in @("Cuates", "No Cuates")) {
        $domainDN = (Get-ADDomain).DistinguishedName
        $count = (Get-ADUser -Filter * -SearchBase "OU=$ou,OU=Usuarios,$domainDN" -ErrorAction SilentlyContinue).Count
        Write-Host "  OU '$ou': $count usuarios"
    }

    Write-Host "`n--- Horarios de Logon ---" -ForegroundColor Cyan
    Write-Host "  Cuates:     08:00 - 15:00"
    Write-Host "  No Cuates:  15:00 - 02:00"

    Write-Host "`n--- FSRM ---" -ForegroundColor Cyan
    Import-Module Fsrm -ErrorAction SilentlyContinue
    $tpls = Get-FsrmQuotaTemplate -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    if ($tpls) { Write-Host "  Plantillas de cuota: $($tpls -join ', ')" }
    $screens = Get-FsrmFileGroup -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    if ($screens) { Write-Host "  Grupos de archivos: $($screens -join ', ')" }

    Write-Host "`n--- AppLocker ---" -ForegroundColor Cyan
    $svc = Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq "Running") { "Green" } else { "Yellow" }
        Write-Host "  Servicio AppIDSvc: $($svc.Status)" -ForegroundColor $color
    }

    Write-Host "`n--- Protocolo de Pruebas ---" -ForegroundColor Cyan
    Write-Host "  Test 1: Login Cuates a las 16:00 -> Restriccion de cuenta"
    Write-Host "  Test 2: Login No Cuates 01:55, esperar 02:00 -> Logoff forzado"
    Write-Host "  Test 3: Copiar 15 MB en carpeta de Cuates (10 MB) -> Espacio insuficiente"
    Write-Host "  Test 4: Guardar .mp3/.exe en carpeta -> Bloqueo FSRM"
    Write-Host "  Test 5: Abrir Notepad como No Cuates (y renombrado) -> Bloqueo AppLocker"
}
