#Requires -RunAsAdministrator
# ===========================================================================
#
#   ███╗   ██╗██╗   ██╗██╗     ██╗  ██╗   ██╗██████╗ ██╗     ██╗███████╗███████╗███████╗██╗   ██╗██╗
#   ████╗  ██║██║   ██║██║     ██║  ╚██╗ ██╔╝██╔══██╗██║     ██║██╔════╝██╔════╝██╔════╝██║   ██║██║
#   ██╔██╗ ██║██║   ██║██║     ██║   ╚████╔╝ ██████╔╝██║     ██║███████╗███████╗█████╗  ██║   ██║██║
#   ██║╚██╗██║██║   ██║██║     ██║    ╚██╔╝  ██╔══██╗██║     ██║╚════██║╚════██║██╔══╝  ██║   ██║██║
#   ██║ ╚████║╚██████╔╝███████╗███████╗██║   ██████╔╝███████╗██║███████║███████║██║     ╚██████╔╝███████╗
#   ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚══════╝╚═╝   ╚═════╝ ╚══════╝╚═╝╚══════╝╚══════╝╚═╝      ╚═════╝ ╚══════╝
#
# ---------------------------------------------------------------------------
#  AUTHOR  : NullyBlissful | MAYAN_SUTHAR
#  GITHUB  : github.com/MayanSuthar
#  MEDIUM  : medium.com/@mayan230848
#  VERSION : 3.0
#  REPO    : github.com/MayanSuthar/Corp-AD-Lab
# ---------------------------------------------------------------------------
#
#  Corp Active Directory Penetration Testing Lab
#  Automated setup script for all Windows VMs
#
#  USAGE:
#    .\Setup-CorpLab.ps1 -Role DC01          # Phase 1 - install AD, reboots
#    .\Setup-CorpLab.ps1 -Role DC01Phase2    # Phase 2 - users, SPNs, shares
#    .\Setup-CorpLab.ps1 -Role WEBSRV1
#    .\Setup-CorpLab.ps1 -Role MAILSRV1
#    .\Setup-CorpLab.ps1 -Role CLIENT01
#    .\Setup-CorpLab.ps1 -Role CLIENT02
#
#  NETWORK:
#    VMnet1 (External) : 192.168.56.0/24
#    VMnet2 (Internal) : 10.10.10.0/24
#    Kali Attacker     : 192.168.56.5
#    DC01              : 10.10.10.10   (corp.local)
#    WEBSRV1           : 192.168.56.11 / 10.10.10.12
#    MAILSRV1          : 192.168.56.10 / 10.10.10.11
#    CLIENT01          : 10.10.10.20
#    CLIENT02          : 10.10.10.30
#
#  -------------------------------------------------------------------------
#  This script is part of the Corp AD Lab project.
#  Educational use only. Use only on systems you own or have permission to test.
#  -------------------------------------------------------------------------
#
# ===========================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("DC01","DC01Phase2","MAILSRV1","WEBSRV1","CLIENT01","CLIENT02")]
    [string]$Role
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Author Banner ──────────────────────────────────────────────
function Write-AuthorBanner {
    Write-Host ""
    Write-Host "  NullyBlissful | MAYAN_SUTHAR" -ForegroundColor Magenta
    Write-Host "  github.com/MayanSuthar | medium.com/@mayan230848" -ForegroundColor DarkMagenta
    Write-Host "  Corp AD Lab v3.0" -ForegroundColor DarkMagenta
    Write-Host ""
}

# ── Output Helpers ─────────────────────────────────────────────
function Write-Banner {
    param([string]$Text)
    $line = "=" * 70
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$line`n" -ForegroundColor Cyan
}
function Write-Step { param([string]$t) Write-Host "[*] $t" -ForegroundColor Yellow }
function Write-OK   { param([string]$t) Write-Host "[+] $t" -ForegroundColor Green  }
function Write-Warn { param([string]$t) Write-Host "[!] $t" -ForegroundColor Red    }

# ── Global Variables ───────────────────────────────────────────
$Domain          = "corp.local"
$NetBios         = "CORP"
$DomainAdminPass = "P@ssw0rd123!"
$SafeModePass    = "P@ssw0rd123!"
$KaliIP          = "192.168.56.5"
$DCip            = "10.10.10.10"
$MAILSRV1_ExtIP  = "192.168.56.10"
$MAILSRV1_IntIP  = "10.10.10.11"
$WEBSRV1_ExtIP   = "192.168.56.11"
$WEBSRV1_IntIP   = "10.10.10.12"
$CLIENT01_IP     = "10.10.10.20"
$CLIENT02_IP     = "10.10.10.30"
$ToolsDir        = "C:\Tools"
$TempDir         = "C:\Temp"

# ── Common Setup — runs on every machine ───────────────────────
function Invoke-CommonSetup {
    Write-Banner "COMMON SETUP"

    foreach ($d in @($ToolsDir, $TempDir, "C:\Tasks", "C:\IT_Share", "C:\Mail_Backup")) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
    Write-OK "Directories created: C:\Tools C:\Temp C:\Tasks C:\IT_Share C:\Mail_Backup"

    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath $ToolsDir, $TempDir -ErrorAction SilentlyContinue
        Write-OK "Defender real-time monitoring disabled"
    } catch { Write-Warn "Defender disable skipped: $_" }

    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False -ErrorAction SilentlyContinue
    Write-OK "Firewall disabled on all profiles"

    New-NetFirewallRule `
        -Name "Allow-ICMPv4-In" `
        -DisplayName "Allow ICMPv4 Inbound (Lab)" `
        -Protocol ICMPv4 -IcmpType 8 -Direction Inbound `
        -Action Allow -Enabled True `
        -ErrorAction SilentlyContinue | Out-Null
    Write-OK "ICMP ping allowed"

    Enable-PSRemoting -Force -ErrorAction SilentlyContinue
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force -ErrorAction SilentlyContinue
    Set-Service -Name WinRM -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service WinRM -ErrorAction SilentlyContinue
    Write-OK "WinRM enabled and set to automatic"
}

# ── DC01 Phase 1 — Install AD DS + promote to DC ───────────────
function Invoke-DC01Setup {
    Write-Banner "DC01 - PHASE 1: ACTIVE DIRECTORY INSTALLATION"

    Write-Step "Configuring static IP: $DCip"
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($nic) {
        Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $nic.ifIndex `
            -IPAddress $DCip -PrefixLength 24 -DefaultGateway "10.10.10.1" `
            -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex `
            -ServerAddresses "127.0.0.1" -ErrorAction SilentlyContinue
        Write-OK "Static IP: $DCip / 24   Gateway: 10.10.10.1   DNS: 127.0.0.1"
    } else {
        Write-Warn "No active NIC found - set IP manually"
    }

    if ($env:COMPUTERNAME -ne "DC01") {
        Rename-Computer -NewName "DC01" -Force -ErrorAction SilentlyContinue
        Write-OK "Computer renamed to DC01"
    }

    Write-Step "Installing AD-Domain-Services role (2-5 minutes)..."
    $result = Install-WindowsFeature `
        -Name AD-Domain-Services, DNS, RSAT-AD-Tools `
        -IncludeManagementTools -IncludeAllSubFeature
    if ($result.Success) { Write-OK "AD-Domain-Services role installed" }
    else { Write-Warn "AD DS role install had issues — check output above" }

    Write-Step "Registering Phase 2 RunOnce key for after reboot..."
    $scriptPath = $MyInvocation.ScriptName
    if ($scriptPath) {
        Set-ItemProperty `
            -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
            -Name "CorpLabDC01Phase2" `
            -Value "powershell.exe -ExecutionPolicy Bypass -NonInteractive -File `"$scriptPath`" -Role DC01Phase2" `
            -ErrorAction SilentlyContinue
        Write-OK "Phase 2 will run automatically after reboot"
    }

    Write-Step "Promoting to Domain Controller for $Domain (will reboot)..."
    $safePwd = ConvertTo-SecureString $SafeModePass -AsPlainText -Force
    Install-ADDSForest `
        -DomainName          $Domain `
        -DomainNetbiosName   $NetBios `
        -InstallDns `
        -SafeModeAdministratorPassword $safePwd `
        -NoRebootOnCompletion:$false `
        -Force:$true

    Write-OK "DC01 Phase 1 complete — rebooting..."
    Start-Sleep -Seconds 3
    Restart-Computer -Force
}

# ── DC01 Phase 2 — Create all AD objects ───────────────────────
function Invoke-DC01Phase2 {
    Write-Banner "DC01 - PHASE 2: AD OBJECTS AND VULNERABLE CONFIGURATIONS"

    Write-Step "Waiting for Active Directory to be ready..."
    $retries = 0
    while ($retries -lt 12) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            Get-ADDomain -ErrorAction Stop | Out-Null
            Write-OK "Active Directory is ready"
            break
        } catch {
            $retries++
            Write-Step "Not ready yet, waiting 15s... ($retries/12)"
            Start-Sleep -Seconds 15
        }
    }

    # OUs
    Write-Step "Creating Organizational Units..."
    @(
        @{ Name="Corp";            Path="DC=corp,DC=local" },
        @{ Name="Users";           Path="OU=Corp,DC=corp,DC=local" },
        @{ Name="Computers";       Path="OU=Corp,DC=corp,DC=local" },
        @{ Name="ServiceAccounts"; Path="OU=Corp,DC=corp,DC=local" },
        @{ Name="Admins";          Path="OU=Corp,DC=corp,DC=local" }
    ) | ForEach-Object {
        New-ADOrganizationalUnit -Name $_.Name -Path $_.Path -ErrorAction SilentlyContinue
    }
    Write-OK "OUs created"

    # Users
    Write-Step "Creating domain users..."
    $users = @(
        @{ Sam="j.watson";   Name="John Watson";   Pass="Password123";  Path="OU=Users,OU=Corp,DC=corp,DC=local";           Desc="IT Department" },
        @{ Sam="m.johnson";  Name="Mary Johnson";  Pass="Password123";  Path="OU=Users,OU=Corp,DC=corp,DC=local";           Desc="HR Department" },
        @{ Sam="t.richards"; Name="Tom Richards";  Pass="Password123";  Path="OU=Users,OU=Corp,DC=corp,DC=local";           Desc="IT Helpdesk" },
        @{ Sam="s.noauth";   Name="Sam Noauth";    Pass="Summer2023!";  Path="OU=Users,OU=Corp,DC=corp,DC=local";           Desc="Legacy - pre-auth disabled" },
        @{ Sam="itadmin";    Name="IT Admin";      Pass="Sup3rS3cur3!"; Path="OU=Admins,OU=Corp,DC=corp,DC=local";          Desc="IT Administrator" },
        @{ Sam="d.backup";   Name="Dave Backup";   Pass="Backup2023!";  Path="OU=Admins,OU=Corp,DC=corp,DC=local";          Desc="Backup Admin - DA" },
        @{ Sam="svc_sql";    Name="SQL Service";   Pass="Sqlpassword1"; Path="OU=ServiceAccounts,OU=Corp,DC=corp,DC=local"; Desc="SQL Server Service Account" },
        @{ Sam="svc_web";    Name="Web Service";   Pass="Webservice1";  Path="OU=ServiceAccounts,OU=Corp,DC=corp,DC=local"; Desc="Web Server Service Account" }
    )

    foreach ($u in $users) {
        $parts = $u.Name -split " "
        New-ADUser `
            -Name              $u.Name `
            -GivenName         $parts[0] `
            -Surname           ($parts[1..99] -join " ") `
            -SamAccountName    $u.Sam `
            -UserPrincipalName "$($u.Sam)@$Domain" `
            -Path              $u.Path `
            -AccountPassword   (ConvertTo-SecureString $u.Pass -AsPlainText -Force) `
            -Enabled           $true `
            -Description       $u.Desc `
            -ErrorAction SilentlyContinue
        Write-OK "  User: $($u.Sam)  /  $($u.Pass)"
    }

    Add-ADGroupMember -Identity "Domain Admins" -Members "d.backup" -ErrorAction SilentlyContinue
    Write-OK "d.backup added to Domain Admins"

    # SPNs for Kerberoasting
    Write-Step "Setting SPNs (Kerberoasting targets)..."
    Set-ADUser -Identity "svc_sql" -ServicePrincipalNames @{ Add="MSSQLSvc/dc01.corp.local:1433" } -ErrorAction SilentlyContinue
    Set-ADUser -Identity "svc_web" -ServicePrincipalNames @{ Add="HTTP/websrv1.corp.local"         } -ErrorAction SilentlyContinue
    Write-OK "SPNs set: svc_sql (MSSQLSvc) and svc_web (HTTP)"

    # AS-REP Roasting
    Write-Step "Disabling Kerberos pre-auth on s.noauth (AS-REP target)..."
    Set-ADAccountControl -Identity "s.noauth" -DoesNotRequirePreAuth $true -ErrorAction SilentlyContinue
    Write-OK "AS-REP Roasting enabled for s.noauth"

    # Groups
    Write-Step "Creating security groups..."
    @("IT Department", "HR Department", "Remote Management Users") | ForEach-Object {
        New-ADGroup -Name $_ -GroupScope Global -GroupCategory Security `
            -Path "OU=Corp,DC=corp,DC=local" -ErrorAction SilentlyContinue
    }
    Add-ADGroupMember -Identity "IT Department"           -Members "itadmin","j.watson"    -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "HR Department"           -Members "m.johnson","t.richards" -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "Remote Management Users" -Members "itadmin","j.watson"    -ErrorAction SilentlyContinue
    Write-OK "Groups created and populated"

    # Misconfigured ACL
    Write-Step "Adding GenericAll ACL misconfiguration (j.watson -> CLIENT01)..."
    try {
        $sid = (Get-ADUser j.watson -ErrorAction Stop).SID
        $dn  = (Get-ADComputer CLIENT01 -ErrorAction Stop).DistinguishedName
        $acl = Get-Acl "AD:$dn"
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid,
            [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($ace)
        Set-Acl "AD:$dn" $acl
        Write-OK "GenericAll ACL: j.watson -> CLIENT01"
    } catch {
        Write-Warn "ACL skipped (CLIENT01 not in domain yet) — re-run after CLIENT01 joins"
    }

    # DNS records
    Write-Step "Adding DNS records..."
    @(
        @{ Name="mailsrv1"; IP=$MAILSRV1_IntIP },
        @{ Name="websrv1";  IP=$WEBSRV1_IntIP  },
        @{ Name="client01"; IP=$CLIENT01_IP     },
        @{ Name="client02"; IP=$CLIENT02_IP     }
    ) | ForEach-Object {
        Add-DnsServerResourceRecordA -ZoneName $Domain -Name $_.Name -IPv4Address $_.IP -ErrorAction SilentlyContinue
        Write-OK "  DNS: $($_.Name).corp.local -> $($_.IP)"
    }

    # IT_Share with credential bait
    Write-Step "Creating IT_Share with credential bait..."
    New-Item -Path "C:\IT_Share" -ItemType Directory -Force | Out-Null
    Set-Content "C:\IT_Share\credentials.txt" @"
=== IT Department Credentials — CONFIDENTIAL ===
Web Portal:   admin / admin123
Database:     svc_sql / Sqlpassword1
Web Service:  svc_web / Webservice1
IT Admin:     itadmin / Sup3rS3cur3!
Backup Admin: d.backup / Backup2023!
NOTE: Migrate to password manager before Q2!
"@
    New-SmbShare -Name "IT_Share" -Path "C:\IT_Share" `
        -FullAccess "CORP\itadmin" -ReadAccess "CORP\Domain Users" `
        -ErrorAction SilentlyContinue | Out-Null
    Write-OK "IT_Share created (readable by all domain users)"

    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
    vssadmin create shadow /for=C: 2>&1 | Out-Null
    Set-ADDefaultDomainPasswordPolicy -Identity $Domain `
        -MinPasswordLength 0 -PasswordHistoryCount 0 `
        -ComplexityEnabled $false -MaxPasswordAge "0" `
        -ErrorAction SilentlyContinue
    Write-OK "SMBv1 enabled, shadow copy created, password policy relaxed"

    Write-Banner "DC01 PHASE 2 COMPLETE"
    Write-OK "Domain     : $Domain"
    Write-OK "Admin      : CORP\Administrator / $DomainAdminPass"
    Write-OK "Domain DA  : CORP\d.backup / Backup2023!"
    Write-OK "Users      : j.watson, m.johnson, t.richards, s.noauth"
    Write-OK "           : itadmin, d.backup, svc_sql, svc_web"
    Write-AuthorBanner
}

# ── WEBSRV1 — Web server, SSH, IIS, credential bait ────────────
function Invoke-WEBSRV1Setup {
    Write-Banner "WEBSRV1 SETUP - WEB SERVER / PIVOT"

    Write-Step "Configuring dual-homed IPs..."
    $nics = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    if ($nics.Count -ge 2) {
        foreach ($nic in $nics) {
            Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        }
        New-NetIPAddress -InterfaceIndex $nics[0].ifIndex -IPAddress $WEBSRV1_ExtIP `
            -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
        New-NetIPAddress -InterfaceIndex $nics[1].ifIndex -IPAddress $WEBSRV1_IntIP `
            -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nics[1].ifIndex `
            -ServerAddresses $DCip -ErrorAction SilentlyContinue
        Write-OK "External: $WEBSRV1_ExtIP  |  Internal: $WEBSRV1_IntIP"
    } else {
        Write-Warn "Only $($nics.Count) NIC(s) found — need 2 adapters for dual-homed setup"
        if ($nics.Count -ge 1) {
            New-NetIPAddress -InterfaceIndex $nics[0].ifIndex -IPAddress $WEBSRV1_ExtIP `
                -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Rename-Computer -NewName "WEBSRV1" -Force -ErrorAction SilentlyContinue

    # OpenSSH (brute-force target)
    Write-Step "Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 `
        -ErrorAction SilentlyContinue | Out-Null
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
    net user Administrator "admin123" 2>&1 | Out-Null
    Write-OK "OpenSSH installed — SSH target: Administrator:admin123"

    # IIS (HTTP login form target)
    Write-Step "Installing IIS + ASP.NET..."
    Install-WindowsFeature -Name Web-Server,Web-Asp-Net45,Web-Net-Ext45,Web-ISAPI-Ext,Web-ISAPI-Filter `
        -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    Write-OK "IIS installed"

    # Vulnerable login page
    Write-Step "Creating vulnerable login page..."
    $loginDir = "C:\inetpub\wwwroot\login"
    New-Item -ItemType Directory -Path $loginDir -Force | Out-Null
    @'
<%@ Page Language="C#" %>
<%
    string msg = "";
    string u = Request.Form["username"] ?? "";
    string p = Request.Form["password"] ?? "";
    if (Request.HttpMethod == "POST") {
        if (u == "admin" && p == "admin123")
            msg = "<div style='color:#00ff41;border:1px solid #00ff41;padding:10px'>LOGIN SUCCESS — Welcome Administrator! FLAG{HTTP_LOGIN_PWNED}</div>";
        else if (u == "j.watson" && p == "Password123")
            msg = "<div style='color:#00ff41;border:1px solid #00ff41;padding:10px'>LOGIN SUCCESS — Welcome John Watson!</div>";
        else if (u != "")
            msg = "<div style='color:#e94560;border:1px solid #e94560;padding:10px'>Login Failed — Invalid credentials</div>";
    }
%>
<!DOCTYPE html><html>
<head><title>Corp Portal</title>
<style>body{font-family:Arial;background:#0d1117;color:#c9d1d9;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}
.box{background:#161b22;padding:40px;border-radius:8px;width:360px;border:1px solid #30363d}
h2{color:#e94560;text-align:center}label{display:block;margin-bottom:5px;color:#8b949e;font-size:13px}
input{width:100%;padding:10px;margin-bottom:14px;box-sizing:border-box;background:#0d1117;border:1px solid #30363d;color:#c9d1d9;border-radius:4px}
button{width:100%;padding:12px;background:#e94560;border:none;color:#fff;font-size:15px;cursor:pointer;border-radius:4px}
</style></head><body><div class="box">
<h2>Corp Portal Login</h2><%=msg%>
<form method="POST" style="margin-top:14px">
<label>Username</label><input type="text" name="username" autocomplete="off">
<label>Password</label><input type="password" name="password">
<button type="submit">Sign In</button>
</form></div></body></html>
'@ | Out-File -FilePath "$loginDir\default.aspx" -Encoding ASCII
    Write-OK "Login page: http://$WEBSRV1_ExtIP/login/ (admin:admin123)"

    # Credential bait files
    Write-Step "Planting credential files..."
    Set-Content "C:\inetpub\wwwroot\config.bak" @"
DB_HOST=10.10.10.10
DB_USER=svc_sql
DB_PASS=Sqlpassword1
ADMIN_USER=itadmin
ADMIN_PASS=Sup3rS3cur3!
"@
    Set-Content "C:\inetpub\wwwroot\web.config.bak" '<add key="DBConn" value="Server=DC01;User=svc_sql;Password=Sqlpassword1;"/>'
    New-Item -ItemType Directory "C:\inetpub\wwwroot\backup" -Force | Out-Null
    Set-Content "C:\inetpub\wwwroot\backup\deploy_notes.txt" @"
FTP:    websrv1admin / FtpP@ss2023
DB:     svc_sql / Sqlpassword1
Admin:  itadmin / Sup3rS3cur3!
DA:     d.backup / Backup2023!
"@
    Write-OK "Credential bait: config.bak, web.config.bak, backup/deploy_notes.txt"

    # RDP
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-OK "RDP enabled"

    # SMB share + netsh proxy
    New-Item -Path "C:\Mail_Backup" -ItemType Directory -Force | Out-Null
    New-SmbShare -Name "Mail_Backup" -Path "C:\Mail_Backup" -FullAccess "Everyone" `
        -ErrorAction SilentlyContinue | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=$WEBSRV1_ExtIP listenport=18080 connectaddress=$DCip connectport=80 2>&1 | Out-Null
    Write-OK "Mail_Backup share and netsh proxy created"

    Write-Banner "WEBSRV1 COMPLETE"
    Write-OK "SSH target  : administrator@$WEBSRV1_ExtIP  (admin123)"
    Write-OK "HTTP target : http://$WEBSRV1_ExtIP/login/  (admin:admin123)"
    Write-OK "Cred file   : http://$WEBSRV1_ExtIP/config.bak"
    Write-OK "NEXT: join domain → Add-Computer -DomainName corp.local -Credential CORP\Administrator -Restart"
    Write-AuthorBanner
}

# ── MAILSRV1 ────────────────────────────────────────────────────
function Invoke-MAILSRV1Setup {
    Write-Banner "MAILSRV1 SETUP - MAIL SERVER / PIVOT"

    Write-Step "Configuring dual-homed IPs..."
    $nics = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    if ($nics.Count -ge 2) {
        foreach ($nic in $nics) {
            Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        }
        New-NetIPAddress -InterfaceIndex $nics[0].ifIndex -IPAddress $MAILSRV1_ExtIP `
            -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
        New-NetIPAddress -InterfaceIndex $nics[1].ifIndex -IPAddress $MAILSRV1_IntIP `
            -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nics[1].ifIndex `
            -ServerAddresses $DCip -ErrorAction SilentlyContinue
        Write-OK "External: $MAILSRV1_ExtIP  |  Internal: $MAILSRV1_IntIP"
    } else {
        Write-Warn "Only $($nics.Count) NIC(s) found — add a second adapter"
        if ($nics.Count -ge 1) {
            New-NetIPAddress -InterfaceIndex $nics[0].ifIndex -IPAddress $MAILSRV1_ExtIP `
                -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Rename-Computer -NewName "MAILSRV1" -Force -ErrorAction SilentlyContinue

    net user Administrator "Mail@2023" 2>&1 | Out-Null
    Write-OK "Weak admin password: Mail@2023 (brute-force target)"

    New-Item -Path "C:\Mail_Backup" -ItemType Directory -Force | Out-Null
    Set-Content "C:\Mail_Backup\it_dept_email_export.txt" @"
From: itadmin@corp.local
To: d.backup@corp.local
Subject: New DC backup credentials
Body:
  DC Backup password: Backup2023!
  SQL Service: svc_sql / Sqlpassword1
  Please destroy after saving to vault.
"@
    New-SmbShare -Name "MailStore" -Path "C:\Mail_Backup" -FullAccess "Everyone" `
        -ErrorAction SilentlyContinue | Out-Null
    Write-OK "MailStore share with credential bait created"

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue

    Write-Banner "MAILSRV1 COMPLETE"
    Write-OK "External: $MAILSRV1_ExtIP  |  Internal: $MAILSRV1_IntIP"
    Write-OK "NEXT: join domain → Add-Computer -DomainName corp.local -Credential CORP\Administrator -Restart"
    Write-AuthorBanner
}

# ── CLIENT01 — All PrivEsc targets ─────────────────────────────
function Invoke-CLIENT01Setup {
    Write-Banner "CLIENT01 SETUP - VULNERABLE WORKSTATION"

    Write-Step "Static IP: $CLIENT01_IP"
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($nic) {
        Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $CLIENT01_IP `
            -PrefixLength 24 -DefaultGateway "10.10.10.1" -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex `
            -ServerAddresses $DCip -ErrorAction SilentlyContinue
        Write-OK "IP: $CLIENT01_IP  DNS: $DCip"
    }
    Rename-Computer -NewName "CLIENT01" -Force -ErrorAction SilentlyContinue

    Write-Step "Joining domain $Domain..."
    try {
        Add-Computer -DomainName $Domain `
            -Credential (New-Object PSCredential("$NetBios\Administrator",
                (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))) `
            -ErrorAction Stop
        Write-OK "Joined $Domain"
    } catch { Write-Warn "Domain join: $_ — ensure DC01 is running" }

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "LocalAccountTokenFilterPolicy" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    Write-OK "RDP enabled | LocalAccountTokenFilterPolicy disabled (PtH)"

    # ── Module: Service Binary Hijacking ────────────────────
    Write-Step "Creating Service Binary Hijacking target..."
    $vulnDir = "C:\Program Files\VulnService"
    New-Item -ItemType Directory -Path $vulnDir -Force | Out-Null
    icacls $vulnDir /grant "Everyone:(F)" /T 2>&1 | Out-Null
    $svcCode = @'
using System; using System.ServiceProcess; using System.Threading;
namespace VulnSvc {
    public class VulnService : ServiceBase {
        public VulnService() { ServiceName = "VulnService"; }
        static void Main() { Run(new VulnService()); }
        protected override void OnStart(string[] args) { Thread.Sleep(Timeout.Infinite); }
        protected override void OnStop() { }
    }
}
'@
    $svcCode | Set-Content "$TempDir\VulnSvc.cs" -Encoding ASCII
    try {
        Add-Type -TypeDefinition (Get-Content "$TempDir\VulnSvc.cs" -Raw) `
            -OutputAssembly "$vulnDir\VulnService.exe" `
            -ReferencedAssemblies "System.ServiceProcess" -ErrorAction Stop
        sc.exe create VulnService binPath= "`"$vulnDir\VulnService.exe`"" start= auto obj= LocalSystem 2>&1 | Out-Null
        sc.exe start VulnService 2>&1 | Out-Null
        Write-OK "VulnService: $vulnDir\VulnService.exe (Everyone:F)"
    } catch {
        Set-Content "$vulnDir\VulnService.exe" "placeholder"
        icacls "$vulnDir\VulnService.exe" /grant "Everyone:(F)" 2>&1 | Out-Null
        Write-Warn "VulnService placeholder created (compile failed)"
    }

    # ── Module: Unquoted Service Path ───────────────────────
    Write-Step "Creating Unquoted Service Path target..."
    $uqBase = "C:\Program Files\Vulnerable Service"
    $uqBin  = "$uqBase\bin"
    New-Item -ItemType Directory -Path $uqBin -Force | Out-Null
    icacls $uqBase /grant "Everyone:(F)" /T 2>&1 | Out-Null
    if (Test-Path "$vulnDir\VulnService.exe") {
        Copy-Item "$vulnDir\VulnService.exe" "$uqBin\service.exe" -ErrorAction SilentlyContinue
    } else { Set-Content "$uqBin\service.exe" "placeholder" }
    sc.exe create UnquotedSvc binPath= "C:\Program Files\Vulnerable Service\bin\service.exe" start= auto obj= LocalSystem DisplayName= "Unquoted Path Service" 2>&1 | Out-Null
    Write-OK "UnquotedSvc: plant payload at 'C:\Program Files\Vulnerable.exe'"

    # ── Module: DLL Hijacking ────────────────────────────────
    Write-Step "Creating DLL Hijacking target..."
    $dllDir = "C:\Program Files\DLLHijackSvc"
    New-Item -ItemType Directory -Path $dllDir -Force | Out-Null
    icacls $dllDir /grant "BUILTIN\Users:(W)" 2>&1 | Out-Null
    Set-Content "$dllDir\README.txt" "Loads wlbsctrl.dll from local dir. Users have Write access here."
    Write-OK "DLLHijackSvc: $dllDir (Users:W)"

    # ── Module: Scheduled Task ──────────────────────────────
    Write-Step "Creating Scheduled Task PrivEsc target..."
    New-Item -ItemType Directory -Path "C:\Tasks" -Force | Out-Null
    icacls "C:\Tasks" /grant "Everyone:(F)" 2>&1 | Out-Null
    Set-Content "C:\Tasks\cleanup.bat" "@echo off`ndel /q C:\Temp\*.tmp 2>nul`necho Done"
    $action    = New-ScheduledTaskAction -Execute "C:\Tasks\cleanup.bat"
    $trigger   = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date)
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal `
        -TaskName "SystemCleanup" -Description "Routine maintenance" -Force | Out-Null
    Write-OK "SystemCleanup: C:\Tasks\cleanup.bat runs as SYSTEM every 5 min (Everyone:F)"

    # ── Credential Goldmines ─────────────────────────────────
    Write-Step "Planting credential bait..."
    New-Item -ItemType Directory "C:\Users\Public\Desktop" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "C:\Users\Public\Desktop\credentials.txt" @"
Web Portal: admin / admin123
Database:   svc_sql / Sqlpassword1
IT Admin:   itadmin / Sup3rS3cur3!
"@
    reg add "HKLM\SOFTWARE\CorpApp" /v "DBPassword"  /t REG_SZ /d "Sqlpassword1"  /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\CorpApp" /v "AdminUser"   /t REG_SZ /d "itadmin"       /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\CorpApp" /v "AdminPass"   /t REG_SZ /d "Sup3rS3cur3!"  /f 2>&1 | Out-Null
    New-Item -ItemType Directory "C:\inetpub\wwwroot" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "C:\inetpub\wwwroot\web.config.bak" '<add key="DBConn" value="Server=DC01;User=svc_sql;Password=Sqlpassword1;"/>'
    New-Item -ItemType Directory "C:\Windows\Panther" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "C:\Windows\Panther\unattend.xml" @'
<?xml version="1.0"?>
<unattend><settings pass="specialize"><component name="Microsoft-Windows-Shell-Setup">
<AutoLogon><Password><Value>UGFzc3dvcmQxMjM=</Value><PlainText>false</PlainText></Password>
<Username>Administrator</Username><Enabled>true</Enabled></AutoLogon>
</component></settings></unattend>
'@
    $histPath = "C:\Users\j.watson\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine"
    New-Item -ItemType Directory -Path $histPath -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "$histPath\ConsoleHost_history.txt" @"
Get-ADUser -Filter *
net use \\DC01\IT_Share /user:CORP\itadmin Sup3rS3cur3!
Enter-PSSession -ComputerName DC01 -Credential (New-Object PSCredential('CORP\itadmin',(ConvertTo-SecureString 'Sup3rS3cur3!' -AsPlainText -Force)))
"@
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon"    /t REG_SZ /d "1"          /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultUsername"   /t REG_SZ /d "j.watson"   /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultPassword"   /t REG_SZ /d "Password123" /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultDomainName" /t REG_SZ /d "CORP"        /f 2>&1 | Out-Null
    Write-OK "Credentials planted: Desktop, Registry, web.config.bak, unattend.xml, PS history, AutoLogon"

    Write-Banner "CLIENT01 COMPLETE"
    Write-OK "PrivEsc targets: VulnService, UnquotedSvc, DLLHijackSvc, SystemCleanup task"
    Write-OK "Cred locations: Desktop, HKLM\SOFTWARE\CorpApp, Panther\unattend.xml, PS history, Winlogon"
    Write-OK "REBOOT to complete domain join"
    Write-AuthorBanner
}

# ── CLIENT02 ────────────────────────────────────────────────────
function Invoke-CLIENT02Setup {
    Write-Banner "CLIENT02 SETUP - LATERAL MOVEMENT TARGET"

    Write-Step "Static IP: $CLIENT02_IP"
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($nic) {
        Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $CLIENT02_IP `
            -PrefixLength 24 -DefaultGateway "10.10.10.1" -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex `
            -ServerAddresses $DCip -ErrorAction SilentlyContinue
        Write-OK "IP: $CLIENT02_IP"
    }
    Rename-Computer -NewName "CLIENT02" -Force -ErrorAction SilentlyContinue

    Write-Step "Joining domain $Domain..."
    try {
        Add-Computer -DomainName $Domain `
            -Credential (New-Object PSCredential("$NetBios\Administrator",
                (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))) `
            -ErrorAction Stop
        Write-OK "Joined $Domain"
    } catch { Write-Warn "Domain join: $_ — ensure DC01 is running" }

    net localgroup administrators "CORP\itadmin" /add 2>&1 | Out-Null
    Write-OK "itadmin added as local administrator"
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "LocalAccountTokenFilterPolicy" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Set-Content "C:\Users\Public\notes.txt" @"
itadmin creds: Sup3rS3cur3!
DA backup: d.backup / Backup2023!
Delete this file!
"@

    Write-Banner "CLIENT02 COMPLETE"
    Write-OK "IP: $CLIENT02_IP  |  itadmin is local admin here"
    Write-OK "REBOOT to complete domain join"
    Write-AuthorBanner
}

# ── Main Dispatcher ─────────────────────────────────────────────
Write-AuthorBanner
Write-Banner "CORP AD LAB BUILDER v3.0 — Role: $Role"
Write-Step "Started at $(Get-Date)"
Write-Step "Running as: $(whoami)"

Invoke-CommonSetup

switch ($Role) {
    "DC01"       { Invoke-DC01Setup     }
    "DC01Phase2" { Invoke-DC01Phase2    }
    "WEBSRV1"    { Invoke-WEBSRV1Setup  }
    "MAILSRV1"   { Invoke-MAILSRV1Setup }
    "CLIENT01"   { Invoke-CLIENT01Setup }
    "CLIENT02"   { Invoke-CLIENT02Setup }
}

Write-Banner "DONE — $Role completed at $(Get-Date)"
Write-Host "Reboot recommended to apply all changes." -ForegroundColor Magenta
Write-AuthorBanner

# ===========================================================================
#  END OF SCRIPT
#  NullyBlissful | MAYAN_SUTHAR | github.com/MayanSuthar
# ===========================================================================
