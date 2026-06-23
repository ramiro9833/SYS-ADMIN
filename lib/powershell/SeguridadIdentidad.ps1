# lib/powershell/SeguridadIdentidad.ps1
# Funciones Tarea 9: RBAC, FGPP, Auditoria y MFA (TOTP)
# Uso: . "$libDir\SeguridadIdentidad.ps1"

# ─── Constantes ───────────────────────────────────────────────────────────────
$script:SEC_DomainName       = "sysadmin.local"
$script:SEC_AdminPassword    = "AdminDelegado123!"
$script:SEC_GrupoAdminsFGPP  = "Cuentas_Administrativas_Delegadas"
$script:SEC_GrupoStdFGPP     = "Usuarios_Estandar"
$script:SEC_MultiOTPPath     = "C:\Program Files\multiOTP"
$script:SEC_MultiOTPExe      = "C:\Program Files\multiOTP\multiotp.exe"
$script:SEC_ReporteAuditoria = "C:\Auditoria\reporte_accesos_denegados.txt"

# GUIDs de permisos extendidos AD
$script:GUID_ResetPassword   = [guid]"ab721a53-1e2f-11d0-9819-00aa0040529b"
$script:GUID_UserObject      = [guid]"bf967aba-0de6-11d0-a285-00aa003049e2"
$script:GUID_GPObject        = [guid]"f30e3bc2-9ff0-11d1-b603-00c04f8f4b62"

# Roles delegados
$script:SEC_Roles = @(
    @{ Sam = "admin_identidad";  Rol = "IAM Operator";      Desc = "Gestion ciclo de vida usuarios OU Cuates/No Cuates" }
    @{ Sam = "admin_storage";    Rol = "Storage Operator";  Desc = "FSRM cuotas y apantallamiento" }
    @{ Sam = "admin_politicas";  Rol = "GPO Compliance";    Desc = "GPO, AppLocker, FGPP, Logon Hours" }
    @{ Sam = "admin_auditoria";  Rol = "Security Auditor";  Desc = "Solo lectura y reportes de auditoria" }
)

# ─── Helper: agregar regla ACL en objeto AD ──────────────────────────────────
function Add-ADAccessRule {
    param(
        [string]$TargetDN,
        [string]$IdentitySam,
        [System.DirectoryServices.ActiveDirectoryRights]$Rights,
        [System.Security.AccessControl.AccessControlType]$Type = "Allow",
        [guid]$ObjectType = [guid]::Empty,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]$Inheritance = "All"
    )
    $sid = (Get-ADPrincipal -Identity $IdentitySam).SID
    $acl  = Get-Acl "AD:$TargetDN"
    if ($ObjectType -eq [guid]::Empty) {
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid, $Rights, $Type, $ObjectType, $null, $Inheritance
        )
    } else {
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid, $Rights, $Type, $ObjectType, $null, $Inheritance
        )
    }
    $acl.AddAccessRule($ace)
    Set-Acl "AD:$TargetDN" $acl
}

# ─── Crear usuarios administrativos delegados ────────────────────────────────
function Crear-Usuarios-Delegados {
    Banner "CREACION DE USUARIOS ADMINISTRATIVOS DELEGADOS (RBAC)"
    Import-Module ActiveDirectory -ErrorAction Stop

    $domainDN  = (Get-ADDomain).DistinguishedName
    $ouAdmin   = "OU=AdminDelegados,OU=Usuarios,$domainDN"

    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'AdminDelegados'" -SearchBase "OU=Usuarios,$domainDN" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "AdminDelegados" -Path "OU=Usuarios,$domainDN" -ProtectedFromAccidentalDeletion $true
        Write-Host "[OK] OU 'AdminDelegados' creada." -ForegroundColor Green
    }

    # Grupo para FGPP de admins (12 caracteres)
    if (-not (Get-ADGroup -Filter "Name -eq '$($script:SEC_GrupoAdminsFGPP)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $script:SEC_GrupoAdminsFGPP -GroupScope Global -GroupCategory Security -Path "OU=Usuarios,$domainDN"
    }

    foreach ($r in $script:SEC_Roles) {
        $sam = $r.Sam
        $params = @{
            Name              = $sam
            SamAccountName    = $sam
            UserPrincipalName = "$sam@$((Get-ADDomain).DNSRoot)"
            DisplayName       = "$($r.Rol) - $sam"
            Description       = $r.Desc
            Path              = $ouAdmin
            AccountPassword   = (ConvertTo-SecureString $script:SEC_AdminPassword -AsPlainText -Force)
            Enabled           = $true
            ChangePasswordAtLogon = $false
        }
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
            New-ADUser @params
            Write-Host "[OK] Usuario delegado '$sam' ($($r.Rol)) creado." -ForegroundColor Green
        } else {
            Set-ADAccountPassword -Identity $sam -NewPassword $params.AccountPassword -Reset
            Write-Host "[INFO] Usuario '$sam' ya existia; contrasena actualizada." -ForegroundColor Yellow
        }
        Add-ADGroupMember -Identity $script:SEC_GrupoAdminsFGPP -Members $sam -ErrorAction SilentlyContinue
    }
}

# ─── Rol 1: admin_identidad - IAM Operator ───────────────────────────────────
function Configurar-Delegacion-IAM {
    Banner "DELEGACION RBAC - ROL 1: admin_identidad (IAM Operator)"
    Import-Module ActiveDirectory -ErrorAction Stop

    $domainDN = (Get-ADDomain).DistinguishedName
    $ouBase   = "OU=Usuarios,$domainDN"
    $ous      = @("OU=Cuates,$ouBase", "OU=No Cuates,$ouBase")
    $user     = "admin_identidad"
    $sid      = (Get-ADUser $user).SID

    foreach ($ouDN in $ous) {
        $acl = Get-Acl "AD:$ouDN"

        # Crear/eliminar usuarios hijos
        $ace1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid,
            [System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor
            [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $script:GUID_UserObject, $null,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        )
        # Reset password
        $ace2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid,
            [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $script:GUID_ResetPassword, $null,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        )
        # Escribir atributos basicos (telefono, oficina, correo)
        $ace3 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid,
            [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $script:GUID_UserObject, $null,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        )
        $acl.AddAccessRule($ace1)
        $acl.AddAccessRule($ace2)
        $acl.AddAccessRule($ace3)
        Set-Acl "AD:$ouDN" $acl
        Write-Host "[OK] Permisos IAM aplicados en $ouDN" -ForegroundColor Green
    }

    # DENEGAR modificacion de GPO
    $gpoContainer = "CN=Policies,CN=System,$domainDN"
    $aclGpo = Get-Acl "AD:$gpoContainer"
    $denyGpo = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite,
        [System.Security.AccessControl.AccessControlType]::Deny,
        [guid]::Empty, $null,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    )
    $aclGpo.AddAccessRule($denyGpo)
    Set-Acl "AD:$gpoContainer" $aclGpo

    # DENEGAR modificar membresia Domain Admins
    $daGroup = (Get-ADGroup "Domain Admins").DistinguishedName
    $aclDa = Get-Acl "AD:$daGroup"
    $denyDa = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty -bor
        [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite,
        [System.Security.AccessControl.AccessControlType]::Deny,
        [guid]::Empty, $null,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None
    )
    $aclDa.AddAccessRule($denyDa)
    Set-Acl "AD:$daGroup" $aclDa

    Write-Host "[OK] Restricciones criticas aplicadas (sin GPO ni Domain Admins)." -ForegroundColor Green
}

# ─── Rol 2: admin_storage - Storage Operator ─────────────────────────────────
function Configurar-Delegacion-Storage {
    Banner "DELEGACION RBAC - ROL 2: admin_storage (Storage Operator)"
    Import-Module ActiveDirectory -ErrorAction Stop

    $domainDN = (Get-ADDomain).DistinguishedName
    $ouBase   = "OU=Usuarios,$domainDN"
    $user     = "admin_storage"
    $sid      = (Get-ADUser $user).SID

    # Permisos FSRM: agregar a grupo local de administracion del servidor de archivos
    $fsrmGroup = "FSRM-Managers"
    if (-not (Get-LocalGroup -Name $fsrmGroup -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $fsrmGroup -Description "Operadores FSRM delegados" | Out-Null
    }
    Add-LocalGroupMember -Group $fsrmGroup -Member "$((Get-ADDomain).NetBIOSName)\$user" -ErrorAction SilentlyContinue
    Write-Host "[OK] '$user' agregado al grupo local '$fsrmGroup' para gestion FSRM." -ForegroundColor Green

    # DENEGAR explicitamente Reset Password en todo OU Usuarios
    $acl = Get-Acl "AD:$ouBase"
    $denyReset = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
        [System.Security.AccessControl.AccessControlType]::Deny,
        $script:GUID_ResetPassword, $null,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    )
    $acl.AddAccessRule($denyReset)
    Set-Acl "AD:$ouBase" $acl

  Write-Host "[OK] DENY Reset Password aplicado a '$user' en OU=Usuarios." -ForegroundColor Green
    Write-Host "[INFO] Test 1B: admin_storage NO puede resetear contrasenas." -ForegroundColor Cyan
}

# ─── Rol 3: admin_politicas - GPO Compliance ─────────────────────────────────
function Configurar-Delegacion-Politicas {
    Banner "DELEGACION RBAC - ROL 3: admin_politicas (GPO Compliance)"
    Import-Module ActiveDirectory -ErrorAction Stop

    $domainDN     = (Get-ADDomain).DistinguishedName
    $gpoContainer = "CN=Policies,CN=System,$domainDN"
    $user         = "admin_politicas"
    $sid          = (Get-ADUser $user).SID

    # Lectura en todo el dominio
    $aclDom = Get-Acl "AD:$domainDN"
    $readDom = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericRead,
        [System.Security.AccessControl.AccessControlType]::Allow,
        [guid]::Empty, $null,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    )
    $aclDom.AddAccessRule($readDom)
    Set-Acl "AD:$domainDN" $aclDom

    # Escritura SOLO sobre contenedor GPO
    $aclGpo = Get-Acl "AD:$gpoContainer"
    $writeGpo = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite -bor
        [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
        [System.Security.AccessControl.AccessControlType]::Allow,
        [guid]::Empty, $null,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    )
    $aclGpo.AddAccessRule($writeGpo)
    Set-Acl "AD:$gpoContainer" $aclGpo

    # DENEGAR escritura sobre objetos usuario
    $ouUsuarios = "OU=Usuarios,$domainDN"
    $aclUsr = Get-Acl "AD:$ouUsuarios"
    $denyUsr = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite -bor
        [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
        [System.Security.AccessControl.AccessControlType]::Deny,
        $script:GUID_UserObject, $null,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    )
    $aclUsr.AddAccessRule($denyUsr)
    Set-Acl "AD:$ouUsuarios" $aclUsr

    # Permiso GPMC: agregar a Group Policy Creator Owners
    Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members $user -ErrorAction SilentlyContinue

    Write-Host "[OK] admin_politicas: Lectura dominio + Escritura GPO; sin escritura en usuarios." -ForegroundColor Green
}

# ─── Rol 4: admin_auditoria - Security Auditor (solo lectura) ────────────────
function Configurar-Delegacion-Auditoria {
    Banner "DELEGACION RBAC - ROL 4: admin_auditoria (Security Auditor)"
    Import-Module ActiveDirectory -ErrorAction Stop

    $domainDN = (Get-ADDomain).DistinguishedName
    $user     = "admin_auditoria"
    $sid      = (Get-ADUser $user).SID

    # Lectura en todo el dominio
    $aclDom = Get-Acl "AD:$domainDN"
    $readDom = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericRead -bor
        [System.DirectoryServices.ActiveDirectoryRights]::ListChildren,
        [System.Security.AccessControl.AccessControlType]::Allow,
        [guid]::Empty, $null,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    )
    $aclDom.AddAccessRule($readDom)
    Set-Acl "AD:$domainDN" $aclDom

    # DENEGAR cualquier escritura en el dominio
    $denyWrite = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite -bor
        [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty -bor
        [System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor
        [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild,
        [System.Security.AccessControl.AccessControlType]::Deny,
        [guid]::Empty, $null,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    )
    $aclDom.AddAccessRule($denyWrite)
    Set-Acl "AD:$domainDN" $aclDom

    # Acceso a registros de seguridad (Event Log Readers)
    Add-LocalGroupMember -Group "Event Log Readers" -Member "$((Get-ADDomain).NetBIOSName)\$user" -ErrorAction SilentlyContinue

    # Permiso para ejecutar script de auditoria
    $auditDir = Split-Path $script:SEC_ReporteAuditoria -Parent
    if (-not (Test-Path $auditDir)) { New-Item -ItemType Directory -Path $auditDir -Force | Out-Null }
    icacls $auditDir /grant "$((Get-ADDomain).NetBIOSName)\$user`:(OI)(CI)M" | Out-Null

    Write-Host "[OK] admin_auditoria: solo lectura AD + Event Log Readers." -ForegroundColor Green
}

# ─── Aplicar toda la delegacion RBAC ─────────────────────────────────────────
function Configurar-Delegacion-RBAC-Completa {
    Crear-Usuarios-Delegados
    Configurar-Delegacion-IAM
    Configurar-Delegacion-Storage
    Configurar-Delegacion-Politicas
    Configurar-Delegacion-Auditoria
    Write-Host "`n[OK] Modelo RBAC completo desplegado (4 roles delegados)." -ForegroundColor Green
}

# ─── FGPP: 12 chars admins, 8 chars estandar ─────────────────────────────────
function Configurar-FGPP {
    Banner "DIRECTIVAS DE CONTRASENA AJUSTADAS (FGPP)"
    Import-Module ActiveDirectory -ErrorAction Stop

    $domainDN = (Get-ADDomain).DistinguishedName
    $ouBase   = "OU=Usuarios,$domainDN"

    # Grupo usuarios estandar (Cuates + No Cuates)
    if (-not (Get-ADGroup -Filter "Name -eq '$($script:SEC_GrupoStdFGPP)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $script:SEC_GrupoStdFGPP -GroupScope Global -GroupCategory Security -Path $ouBase
        $stdUsers = Get-ADUser -Filter * -SearchBase $ouBase -SearchScope OneLevel |
            Where-Object { $_.SamAccountName -notlike "admin_*" }
        foreach ($u in $stdUsers) {
            Add-ADGroupMember -Identity $script:SEC_GrupoStdFGPP -Members $u.SamAccountName -ErrorAction SilentlyContinue
        }
    }

    # FGPP Admins: 12 caracteres minimos
    $fgppAdmin = "FGPP_Admins_12chars"
    if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppAdmin'" -ErrorAction SilentlyContinue)) {
        New-ADFineGrainedPasswordPolicy -Name $fgppAdmin -Precedence 10 `
            -MinPasswordLength 12 -ComplexityEnabled $true `
            -MinPasswordAge "1.00:00:00" -MaxPasswordAge "42.00:00:00" `
            -LockoutThreshold 3 -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00" `
            -PasswordHistoryCount 12 | Out-Null
        Add-ADFineGrainedPasswordPolicySubject -Identity $fgppAdmin -Subjects $script:SEC_GrupoAdminsFGPP
        Write-Host "[OK] FGPP '$fgppAdmin': minimo 12 caracteres (admins delegados)." -ForegroundColor Green
    }

    # FGPP Estandar: 8 caracteres minimos
    $fgppStd = "FGPP_Standard_8chars"
    if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppStd'" -ErrorAction SilentlyContinue)) {
        New-ADFineGrainedPasswordPolicy -Name $fgppStd -Precedence 20 `
            -MinPasswordLength 8 -ComplexityEnabled $true `
            -MinPasswordAge "1.00:00:00" -MaxPasswordAge "90.00:00:00" `
            -LockoutThreshold 5 -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00" `
            -PasswordHistoryCount 5 | Out-Null
        Add-ADFineGrainedPasswordPolicySubject -Identity $fgppStd -Subjects $script:SEC_GrupoStdFGPP
        Write-Host "[OK] FGPP '$fgppStd': minimo 8 caracteres (usuarios estandar)." -ForegroundColor Green
    }

    Write-Host "[INFO] Test 2: admin_identidad rechaza contrasenas de 8 caracteres." -ForegroundColor Cyan
}

# ─── Hardening de auditoria ───────────────────────────────────────────────────
function Configurar-Auditoria-Hardening {
    Banner "HARDENING DE AUDITORIA - LOGON Y ACCESO A OBJETOS"

    # auditpol: inicio de sesion exito/fallo
    auditpol /set /subcategory:"Logon" /success:enable /failure:enable | Out-Null
    auditpol /set /subcategory:"Logoff" /success:enable /failure:enable | Out-Null
    auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable | Out-Null
    auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable | Out-Null
    auditpol /set /subcategory:"Directory Service Changes" /success:enable /failure:enable | Out-Null
    auditpol /set /subcategory:"File System" /success:enable /failure:enable | Out-Null
    auditpol /set /subcategory:"Other Object Access Events" /success:enable /failure:enable | Out-Null

    Write-Host "[OK] Subcategorias de auditoria habilitadas (exito y fallo)." -ForegroundColor Green

    # SACL en OU Usuarios para auditar acceso a objetos AD
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
    $domainDN   = (Get-ADDomain).DistinguishedName
    $ouUsuarios = "OU=Usuarios,$domainDN"

    # Usar dsacls para auditoria SACL (mas compatible en laboratorio)
    $dsacls = "$env:SystemRoot\System32\dsacls.exe"
    if (Test-Path $dsacls) {
        & $dsacls $ouUsuarios /I:S /G "Everyone:GR;;user" 2>$null
        Write-Host "[OK] SACL de auditoria aplicada en OU=Usuarios via dsacls." -ForegroundColor Green
    }

    # GPO de auditoria avanzada (si GPMC disponible)
    Import-Module GroupPolicy -ErrorAction SilentlyContinue
    $gpoAudit = "GPO_Tarea9_Auditoria"
    if (-not (Get-GPO -Name $gpoAudit -ErrorAction SilentlyContinue)) {
        New-GPO -Name $gpoAudit -Comment "Auditoria avanzada Tarea 9" | Out-Null
        Set-GPRegistryValue -Name $gpoAudit -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\Audit" `
            -ValueName "AuditAuthenticationPolicy" -Type DWord -Value 3 | Out-Null
        New-GPLink -Name $gpoAudit -Target $domainDN -LinkEnabled Yes -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Host "[OK] Hardening de auditoria completado." -ForegroundColor Green
}

# ─── Script de extraccion: ultimos 10 accesos denegados ──────────────────────
function Exportar-Eventos-AccesoDenegado {
    param(
        [string]$OutputPath = $script:SEC_ReporteAuditoria,
        [int]$Cantidad = 10
    )
    Banner "EXTRACCION DE EVENTOS - ACCESOS DENEGADOS"

    $auditDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $auditDir)) { New-Item -ItemType Directory -Path $auditDir -Force | Out-Null }

    # IDs: 4625 (logon fallido), 4771 (Kerberos pre-auth fallido), 4740 (cuenta bloqueada)
    $eventIds = @(4625, 4771, 4740, 4656)

    $eventos = @()
    foreach ($id in $eventIds) {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = $id } -MaxEvents $Cantidad -ErrorAction SilentlyContinue
        if ($ev) { $eventos += $ev }
    }
    $eventos = $eventos | Sort-Object TimeCreated -Descending | Select-Object -First $Cantidad

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("======================================================")
    [void]$sb.AppendLine(" REPORTE DE AUDITORIA - ACCESOS DENEGADOS / MFA      ")
    [void]$sb.AppendLine(" Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine(" Servidor: $env:COMPUTERNAME")
    [void]$sb.AppendLine("======================================================")
    [void]$sb.AppendLine("")

    if ($eventos.Count -eq 0) {
        [void]$sb.AppendLine("No se encontraron eventos recientes (4625/4771/4740/4656).")
        [void]$sb.AppendLine("Ejecute intentos de logon fallidos para generar evidencia.")
    } else {
        $i = 1
        foreach ($ev in $eventos) {
            [void]$sb.AppendLine("--- Evento $i ---")
            [void]$sb.AppendLine("ID:        $($ev.Id)")
            [void]$sb.AppendLine("Fecha:     $($ev.TimeCreated)")
            [void]$sb.AppendLine("Nivel:     $($ev.LevelDisplayName)")
            [void]$sb.AppendLine("Origen:    $($ev.ProviderName)")
            [void]$sb.AppendLine("Mensaje:")
            [void]$sb.AppendLine($ev.Message)
            [void]$sb.AppendLine("")
            $i++
        }
    }

    $sb.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "[OK] Reporte exportado: $OutputPath ($($eventos.Count) eventos)" -ForegroundColor Green
    return $OutputPath
}

# ─── Bloqueo de cuenta: 3 intentos MFA fallidos, 30 minutos ──────────────────
function Configurar-Bloqueo-MFA {
    Banner "BLOQUEO DE CUENTA POR MFA FALLIDO (3 intentos / 30 min)"
    Import-Module ActiveDirectory -ErrorAction Stop

    $domain = Get-ADDomain
    Set-ADDefaultDomainPasswordPolicy -Identity $domain.DistinguishedName `
        -LockoutThreshold 3 `
        -LockoutDuration "00:30:00" `
        -LockoutObservationWindow "00:30:00" `
        -ComplexityEnabled $true

    Write-Host "[OK] Politica de bloqueo: 3 intentos fallidos = 30 minutos." -ForegroundColor Green
    Write-Host "[INFO] Test 4: 3 codigos MFA incorrectos bloquean la cuenta." -ForegroundColor Cyan
}

# ─── Instalar multiOTP Credential Provider (MFA TOTP) ─────────────────────────
function Instalar-MFA-MultiOTP {
    param([string]$InstallerPath = "")

    Banner "INSTALACION MFA - multiOTP CREDENTIAL PROVIDER (TOTP)"
    $installDir = "C:\Tools\multiOTP"
    $zipUrl     = "https://download.multiotp.net/credential-provider/multiOTPCredentialProvider-5.10.2.2.zip"

    if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }

    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        $zipFile = Join-Path $installDir "multiOTPCredentialProvider.zip"
        Write-Host "[INFO] Descargando multiOTP Credential Provider..." -ForegroundColor Yellow
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
            Expand-Archive -Path $zipFile -DestinationPath $installDir -Force
            Write-Host "[OK] Paquete descargado y extraido en $installDir" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] No se pudo descargar automaticamente: $_" -ForegroundColor Yellow
            Write-Host "[HINT] Descargue manualmente desde https://download.multiotp.net/credential-provider/" -ForegroundColor Cyan
            Write-Host "[HINT] Extraiga en $installDir y ejecute el instalador .msi" -ForegroundColor Cyan
            return
        }
    }

    # Buscar instalador MSI
    $msi = Get-ChildItem -Path $installDir -Recurse -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($msi) {
        Write-Host "[INFO] Ejecutando instalador: $($msi.FullName)" -ForegroundColor Yellow
        Write-Host "[INFO] Seleccione: 'OTP authentication mandatory for local logon and remote desktop'" -ForegroundColor Cyan
        Start-Process msiexec.exe -ArgumentList "/i `"$($msi.FullName)`" /qb" -Wait
        Write-Host "[OK] multiOTP Credential Provider instalado." -ForegroundColor Green
    } else {
        Write-Host "[WARN] No se encontro .msi. Instale manualmente desde $installDir" -ForegroundColor Yellow
    }

    # Regla de firewall para multiOTP (puerto 8112)
    if (-not (Get-NetFirewallRule -DisplayName "AllowMultiOTP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "AllowMultiOTP" -Direction Inbound -Protocol TCP -LocalPort 8112 -Action Allow | Out-Null
    }

    $script:SEC_MultiOTPExe = "C:\Program Files\multiOTP\multiotp.exe"
    if (-not (Test-Path $script:SEC_MultiOTPExe)) {
        $found = Get-ChildItem "C:\Program Files" -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $script:SEC_MultiOTPExe = $found.FullName }
    }
}

# ─── Registrar usuario en MFA (Google Authenticator / TOTP) ──────────────────
function Registrar-Usuario-MFA {
    param(
        [Parameter(Mandatory)][string]$Username,
        [string]$MultiOTPExe = $script:SEC_MultiOTPExe
    )
    Banner "REGISTRO MFA TOTP - $Username"

    if (-not (Test-Path $MultiOTPExe)) {
        Write-Host "[ERROR] multiotp.exe no encontrado. Ejecute primero Instalar-MFA-MultiOTP." -ForegroundColor Red
        Write-Host "[HINT] Ruta esperada: $MultiOTPExe" -ForegroundColor Yellow
        return
    }

    $otpDir = Split-Path $MultiOTPExe -Parent
    Push-Location $otpDir
    try {
        # Crear usuario en multiOTP con PIN inicial
        & $MultiOTPExe -fastadminnopin $Username 2>&1 | Out-Host

        # Generar token TOTP (muestra QR en consola / archivo HTML)
        $qrFile = Join-Path $otpDir "qr_$Username.html"
        & $MultiOTPExe -qrcode $Username 2>&1 | Out-Host

        Write-Host "`n[OK] Usuario '$Username' registrado en multiOTP." -ForegroundColor Green
        Write-Host "[PASOS MANUALES]:" -ForegroundColor Cyan
        Write-Host "  1. Ejecute: & '$MultiOTPExe' -qrcode $Username" -ForegroundColor White
        Write-Host "  2. Escanee el codigo QR con Google Authenticator" -ForegroundColor White
        Write-Host "  3. Al iniciar sesion, ingrese contrasena + codigo TOTP de 6 digitos" -ForegroundColor White
        Write-Host "`n[INFO] Test 3: El login debe pedir codigo TOTP tras la contrasena." -ForegroundColor Cyan
    } finally {
        Pop-Location
    }
}

# ─── Resumen de seguridad Tarea 9 ────────────────────────────────────────────
function Mostrar-Resumen-Seguridad {
    Banner "RESUMEN DE SEGURIDAD - TAREA 9"
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    Write-Host "`n--- Usuarios Delegados (RBAC) ---" -ForegroundColor Cyan
    foreach ($r in $script:SEC_Roles) {
        $u = Get-ADUser -Filter "SamAccountName -eq '$($r.Sam)'" -ErrorAction SilentlyContinue
        $st = if ($u -and $u.Enabled) { "Activo" } else { "No encontrado" }
        Write-Host "  $($r.Sam) [$($r.Rol)]: $st"
    }

    Write-Host "`n--- FGPP ---" -ForegroundColor Cyan
    Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  $($_.Name): MinLength=$($_.MinPasswordLength)" }

    Write-Host "`n--- Bloqueo de cuenta ---" -ForegroundColor Cyan
    $pol = Get-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue
    if ($pol) {
        Write-Host "  Umbral: $($pol.LockoutThreshold) | Duracion: $($pol.LockoutDuration)"
    }

    Write-Host "`n--- MFA (multiOTP) ---" -ForegroundColor Cyan
    $mfaSvc = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
    if (Test-Path $script:SEC_MultiOTPExe) {
        Write-Host "  multiOTP: Instalado ($script:SEC_MultiOTPExe)" -ForegroundColor Green
    } else {
        Write-Host "  multiOTP: No detectado" -ForegroundColor Yellow
    }

    Write-Host "`n--- Protocolo de Pruebas ---" -ForegroundColor Cyan
    Write-Host "  Test 1: admin_identidad reset OK | admin_storage reset DENEGADO"
    Write-Host "  Test 2: Contrasena 8 chars en admin_identidad -> Rechazada (FGPP 12)"
    Write-Host "  Test 3: Login requiere codigo Google Authenticator"
    Write-Host "  Test 4: 3 MFA fallidos -> Cuenta bloqueada 30 min"
    Write-Host "  Test 5: Exportar-Eventos-AccesoDenegado -> reporte .txt"
}
