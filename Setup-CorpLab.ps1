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
#  VERSION : 3.1 (Bug-fixed)
#  REPO    : github.com/MayanSuthar/Corp-AD-Lab
# ---------------------------------------------------------------------------
#
#  Corp Active Directory Penetration Testing Lab
#  Automated setup script for all Windows VMs
#
#  USAGE:
#    .\Setup-CorpLab.ps1 -Role DC01          # Phase 1 - rename (if needed), install AD, reboot
#    .\Setup-CorpLab.ps1 -Role DC01          # Run again after rename reboot — installs AD, reboot
#    .\Setup-CorpLab.ps1 -Role DC01Phase2    # Phase 2 - runs auto via scheduled task after reboot
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
    Write-Host "  Corp AD Lab v3.1" -ForegroundColor DarkMagenta
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

# ── NIC Auto-Detection for Dual-Homed Servers ──────────────────
# FIX #6: Instead of assuming $nics[0]=External, $nics[1]=Internal,
#         auto-detect by current IP subnet. Fall back to sorted order
#         with a clear warning if detection fails.
function Find-DualHomedNics {
    $nics = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object Name)

    if ($nics.Count -lt 2) {
        Write-Warn "Expected 2 active NICs for dual-homed setup, found $($nics.Count)"
        return @{ ExtNic = $nics[0]; IntNic = $null; Count = $nics.Count }
    }

    # Attempt 1: Auto-detect by current IP address
    $extNic = $null
    $intNic = $null
    foreach ($nic in $nics) {
        $ips = @(Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.PrefixOrigin -ne "WellKnown" -and $_.IPAddress -ne "0.0.0.0" })
        foreach ($ip in $ips) {
            if ($ip.IPAddress -like "192.168.56.*") { $extNic = $nic }
            if ($ip.IPAddress -like "10.10.10.*")   { $intNic = $nic }
        }
    }

    if ($extNic -and $intNic) {
        Write-OK "Auto-detected NICs by IP: External=$($extNic.Name), Internal=$($intNic.Name)"
        return @{ ExtNic = $extNic; IntNic = $intNic; Count = $nics.Count }
    }

    # Attempt 2: Fall back to sorted order (first = External, second = Internal)
    Write-Warn "Could not auto-detect NIC roles by IP address."
    Write-Warn "Using first adapter ('$($nics[0].Name)') as External, second ('$($nics[1].Name)') as Internal."
    Write-Warn "If incorrect, manually swap IP assignments after setup."
    return @{ ExtNic = $nics[0]; IntNic = $nics[1]; Count = $nics.Count }
}

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

    # FIX #2 (DC01 part): If the computer name is not DC01, rename and reboot
    # BEFORE installing AD DS. Install-ADDSForest uses the CURRENT computer name,
    # and Rename-Computer only takes effect after reboot. Without this check,
    # the domain gets created with the wrong name.
    if ($env:COMPUTERNAME -ne "DC01") {
        Write-Step "Computer name is '$($env:COMPUTERNAME)' — renaming to DC01..."
        Rename-Computer -NewName "DC01" -Force -ErrorAction SilentlyContinue
        Write-OK "Computer renamed to DC01"
        Write-Warn "Rebooting for rename to take effect. Run this script again after reboot."
        Write-Step "Rebooting in 5 seconds..."
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        return   # Exit — user must re-run the script after reboot
    }

    Write-Step "Configuring static IP: $DCip"
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($nic) {
        Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        # FIX #14: Gateway 10.10.10.1 does not exist in this lab, but keeping it
        # does not cause harm and is standard practice. Remove if desired.
        New-NetIPAddress -InterfaceIndex $nic.ifIndex `
            -IPAddress $DCip -PrefixLength 24 -DefaultGateway "10.10.10.1" `
            -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex `
            -ServerAddresses "127.0.0.1" -ErrorAction SilentlyContinue
        Write-OK "Static IP: $DCip / 24   Gateway: 10.10.10.1   DNS: 127.0.0.1"
    } else {
        Write-Warn "No active NIC found - set IP manually"
    }

    # FIX #3: Set the local Administrator password BEFORE promoting to DC.
    # Install-ADDSForest creates the Domain Administrator account from the
    # current local Administrator password. If it doesn't match $DomainAdminPass,
    # CLIENT01/CLIENT02 domain joins will fail.
    Write-Step "Setting local Administrator password to match DomainAdminPass..."
    net user Administrator $DomainAdminPass 2>&1 | Out-Null
    Write-OK "Local Administrator password set"

    Write-Step "Installing AD-Domain-Services role (2-5 minutes)..."
    $result = Install-WindowsFeature `
        -Name AD-Domain-Services, DNS, RSAT-AD-Tools `
        -IncludeManagementTools -IncludeAllSubFeature
    if ($result.Success) { Write-OK "AD-Domain-Services role installed" }
    else { Write-Warn "AD DS role install had issues — check output above" }

    # FIX #8 + #9: Replace RunOnce with a Scheduled Task that runs at startup
    # as SYSTEM. RunOnce requires interactive logon + elevation, which is
    # unreliable after an unattended reboot. $PSCommandPath is always absolute,
    # unlike $MyInvocation.ScriptName which can be relative.
    Write-Step "Registering Phase 2 scheduled task for after reboot..."
    $scriptPath = $PSCommandPath
    if ($scriptPath) {
        try {
            # Remove any existing task from a previous attempt
            Unregister-ScheduledTask -TaskName "CorpLab-DC01Phase2" -Confirm:$false -ErrorAction SilentlyContinue

            $action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" -Role DC01Phase2"
            $trigger   = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
                -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName "CorpLab-DC01Phase2" `
                -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
            Write-OK "Phase 2 scheduled task registered (runs at startup as SYSTEM)"
        } catch {
            Write-Warn "Failed to register scheduled task: $_"
            Write-Warn "You must run Phase 2 manually: .\Setup-CorpLab.ps1 -Role DC01Phase2"
        }
    } else {
        Write-Warn "Could not determine script path — run Phase 2 manually: .\Setup-CorpLab.ps1 -Role DC01Phase2"
    }

    # FIX #10: Install-ADDSForest with -NoRebootOnCompletion:$false triggers
    # the reboot itself. Any code after this call is dead — the process is
    # terminated by the reboot. Removed the unreachable Restart-Computer.
    Write-Step "Promoting to Domain Controller for $Domain (will reboot)..."
    $safePwd = ConvertTo-SecureString $SafeModePass -AsPlainText -Force
    Install-ADDSForest `
        -DomainName          $Domain `
        -DomainNetbiosName   $NetBios `
        -InstallDns `
        -SafeModeAdministratorPassword $safePwd `
        -NoRebootOnCompletion:$false `
        -Force:$true
    # Script is terminated by the AD DS reboot — nothing below here runs
}

# ── DC01 Phase 2 — Create all AD objects ───────────────────────
function Invoke-DC01Phase2 {
    Write-Banner "DC01 - PHASE 2: AD OBJECTS AND VULNERABLE CONFIGURATIONS"

    # FIX #8 cleanup: Remove the Phase 2 scheduled task immediately so it
    # doesn't run again on subsequent reboots.
    Unregister-ScheduledTask -TaskName "CorpLab-DC01Phase2" -Confirm:$false -ErrorAction SilentlyContinue

    # FIX #4: Wait for AD to be ready, and ABORT if it never becomes ready
    # instead of continuing into guaranteed failures.
    Write-Step "Waiting for Active Directory to be ready..."
    $retries = 0
    $adReady = $false
    while ($retries -lt 12) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            Get-ADDomain -ErrorAction Stop | Out-Null
            Write-OK "Active Directory is ready"
            $adReady = $true
            break
        } catch {
            $retries++
            Write-Step "Not ready yet, waiting 15s... ($retries/12)"
            Start-Sleep -Seconds 15
        }
    }

    if (-not $adReady) {
        Write-Warn "Active Directory never became ready after 12 retries (~3 min) — aborting Phase 2"
        Write-Warn "Re-run this script with -Role DC01Phase2 after AD is available."
        return
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
        # FIX #5: Only report success if the cmdlet actually succeeded
        if ($?) { Write-OK "  OU: $($_.Name)" }
        else    { Write-Warn "  OU: $($_.Name) — may already exist or failed" }
    }

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
        # FIX #5: Check actual success before printing green OK
        if ($?) { Write-OK "  User: $($u.Sam)  /  $($u.Pass)" }
        else    { Write-Warn "  User: $($u.Sam) — FAILED (may already exist)" }
    }

    Add-ADGroupMember -Identity "Domain Admins" -Members "d.backup" -ErrorAction SilentlyContinue
    if ($?) { Write-OK "d.backup added to Domain Admins" }
    else    { Write-Warn "d.backup → Domain Admins FAILED" }

    # SPNs for Kerberoasting
    Write-Step "Setting SPNs (Kerberoasting targets)..."
    Set-ADUser -Identity "svc_sql" -ServicePrincipalNames @{ Add="MSSQLSvc/dc01.corp.local:1433" } -ErrorAction SilentlyContinue
    if ($?) { Write-OK "  SPN: svc_sql → MSSQLSvc/dc01.corp.local:1433" }
    else    { Write-Warn "  SPN: svc_sql FAILED" }

    Set-ADUser -Identity "svc_web" -ServicePrincipalNames @{ Add="HTTP/websrv1.corp.local" } -ErrorAction SilentlyContinue
    if ($?) { Write-OK "  SPN: svc_web → HTTP/websrv1.corp.local" }
    else    { Write-Warn "  SPN: svc_web FAILED" }

    # AS-REP Roasting
    Write-Step "Disabling Kerberos pre-auth on s.noauth (AS-REP target)..."
    Set-ADAccountControl -Identity "s.noauth" -DoesNotRequirePreAuth $true -ErrorAction SilentlyContinue
    if ($?) { Write-OK "AS-REP Roasting enabled for s.noauth" }
    else    { Write-Warn "AS-REP Roasting config FAILED for s.noauth" }

    # Groups
    Write-Step "Creating security groups..."
    @("IT Department", "HR Department", "Remote Management Users") | ForEach-Object {
        New-ADGroup -Name $_ -GroupScope Global -GroupCategory Security `
            -Path "OU=Corp,DC=corp,DC=local" -ErrorAction SilentlyContinue
        if ($?) { Write-OK "  Group: $_" }
        else    { Write-Warn "  Group: $_ — may already exist" }
    }
    Add-ADGroupMember -Identity "IT Department"           -Members "itadmin","j.watson"    -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "HR Department"           -Members "m.johnson","t.richards" -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "Remote Management Users" -Members "itadmin","j.watson"    -ErrorAction SilentlyContinue
    Write-OK "Group memberships configured"

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
        if ($?) { Write-OK "  DNS: $($_.Name).corp.local -> $($_.IP)" }
        else    { Write-Warn "  DNS: $($_.Name) — may already exist" }
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
"@ -Encoding UTF8
    New-SmbShare -Name "IT_Share" -Path "C:\IT_Share" `
        -FullAccess "CORP\itadmin" -ReadAccess "CORP\Domain Users" `
        -ErrorAction SilentlyContinue | Out-Null
    if ($?) { Write-OK "IT_Share created (readable by all domain users)" }
    else    { Write-Warn "IT_Share creation failed — may already exist" }

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

    # FIX #6: Use NIC auto-detection instead of assuming $nics[0]=External
    # FIX #15: Set DNS on both NICs and set interface metrics so the
    #          internal NIC is preferred for domain DNS resolution.
    Write-Step "Configuring dual-homed IPs..."
    $nicInfo = Find-DualHomedNics

    if ($nicInfo.Count -ge 2 -and $nicInfo.ExtNic -and $nicInfo.IntNic) {
        $extNic = $nicInfo.ExtNic
        $intNic = $nicInfo.IntNic

        # Clear existing IP config on both NICs
        foreach ($nic in @($extNic, $intNic)) {
            Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        }

        # External NIC — VMnet1 (192.168.56.0/24)
        New-NetIPAddress -InterfaceIndex $extNic.ifIndex -IPAddress $WEBSRV1_ExtIP `
            -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
        # FIX #15: Set DNS on external NIC too (DC as primary for domain resolution)
        Set-DnsClientServerAddress -InterfaceIndex $extNic.ifIndex `
            -ServerAddresses $DCip -ErrorAction SilentlyContinue

        # Internal NIC — VMnet2 (10.10.10.0/24)
        New-NetIPAddress -InterfaceIndex $intNic.ifIndex -IPAddress $WEBSRV1_IntIP `
            -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $intNic.ifIndex `
            -ServerAddresses $DCip -ErrorAction SilentlyContinue

        # FIX #15: Set interface metrics — lower = preferred route.
        # Internal NIC (metric 5) preferred over External (metric 100) for
        # domain DNS resolution and AD communication.
        Set-NetIPInterface -InterfaceIndex $extNic.ifIndex -InterfaceMetric 100 -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $intNic.ifIndex -InterfaceMetric 5   -ErrorAction SilentlyContinue

        Write-OK "External: $WEBSRV1_ExtIP (metric 100)  |  Internal: $WEBSRV1_IntIP (metric 5)"
    } else {
        Write-Warn "Only $($nicInfo.Count) NIC(s) found — need 2 adapters for dual-homed setup"
        if ($nicInfo.ExtNic) {
            New-NetIPAddress -InterfaceIndex $nicInfo.ExtNic.ifIndex -IPAddress $WEBSRV1_ExtIP `
                -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
            Set-DnsClientServerAddress -InterfaceIndex $nicInfo.ExtNic.ifIndex `
                -ServerAddresses $DCip -ErrorAction SilentlyContinue
        }
    }

    Rename-Computer -NewName "WEBSRV1" -Force -ErrorAction SilentlyContinue
    Write-OK "Computer renamed to WEBSRV1 (applies after reboot)"

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
    # FIX #16: Use ASCII encoding for ASPX file to avoid BOM issues with IIS
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
"@ -Encoding UTF8
    Set-Content "C:\inetpub\wwwroot\web.config.bak" '<add key="DBConn" value="Server=DC01;User=svc_sql;Password=Sqlpassword1;"/>' -Encoding UTF8
    New-Item -ItemType Directory "C:\inetpub\wwwroot\backup" -Force | Out-Null
    Set-Content "C:\inetpub\wwwroot\backup\deploy_notes.txt" @"
FTP:    websrv1admin / FtpP@ss2023
DB:     svc_sql / Sqlpassword1
Admin:  itadmin / Sup3rS3cur3!
DA:     d.backup / Backup2023!
"@ -Encoding UTF8
    Write-OK "Credential bait: config.bak, web.config.bak, backup/deploy_notes.txt"

    # RDP
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-OK "RDP enabled"

    # FIX #17: Renamed "Mail_Backup" to "WebBackup" — this is a web server,
    # not a mail server. MAILSRV1 has the MailStore share.
    New-Item -Path "C:\WebBackup" -ItemType Directory -Force | Out-Null
    Set-Content "C:\WebBackup\iis_logs_export.txt" @"
IIS Admin:  websrv1admin / FtpP@ss2023
DB:         svc_sql / Sqlpassword1
Admin:      itadmin / Sup3rS3cur3!
"@ -Encoding UTF8
    New-SmbShare -Name "WebBackup" -Path "C:\WebBackup" -FullAccess "Everyone" `
        -ErrorAction SilentlyContinue | Out-Null
    Write-OK "WebBackup share created"

    # FIX #12: Removed port proxy to DC01:80 — nothing listens on DC01 port 80.
    # If you want a pivot target, install a web listener on DC01 first, then add:
    #   netsh interface portproxy add v4tov4 listenaddress=$WEBSRV1_ExtIP listenport=18080 connectaddress=$DCip connectport=80

    # FIX #18: Enable SMBv1 on WEBSRV1 for consistency with other lab machines
    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
    Write-OK "SMBv1 enabled"

    Write-Banner "WEBSRV1 COMPLETE"
    Write-OK "SSH target  : administrator@$WEBSRV1_ExtIP  (admin123)"
    Write-OK "HTTP target : http://$WEBSRV1_ExtIP/login/  (admin:admin123)"
    Write-OK "Cred file   : http://$WEBSRV1_ExtIP/config.bak"
    Write-OK "NEXT: reboot, then join domain → Add-Computer -DomainName corp.local -Credential CORP\Administrator -Restart"
    Write-Step "Rebooting in 10 seconds..."
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    Write-AuthorBanner
}

# ── MAILSRV1 ────────────────────────────────────────────────────
function Invoke-MAILSRV1Setup {
    Write-Banner "MAILSRV1 SETUP - MAIL SERVER / PIVOT"

    # FIX #6 + #15: NIC auto-detection with proper DNS + metrics
    Write-Step "Configuring dual-homed IPs..."
    $nicInfo = Find-DualHomedNics

    if ($nicInfo.Count -ge 2 -and $nicInfo.ExtNic -and $nicInfo.IntNic) {
        $extNic = $nicInfo.ExtNic
        $intNic = $nicInfo.IntNic

        foreach ($nic in @($extNic, $intNic)) {
            Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        }

        New-NetIPAddress -InterfaceIndex $extNic.ifIndex -IPAddress $MAILSRV1_ExtIP `
            -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $extNic.ifIndex `
            -ServerAddresses $DCip -ErrorAction SilentlyContinue

        New-NetIPAddress -InterfaceIndex $intNic.ifIndex -IPAddress $MAILSRV1_IntIP `
            -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $intNic.ifIndex `
            -ServerAddresses $DCip -ErrorAction SilentlyContinue

        Set-NetIPInterface -InterfaceIndex $extNic.ifIndex -InterfaceMetric 100 -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $intNic.ifIndex -InterfaceMetric 5   -ErrorAction SilentlyContinue

        Write-OK "External: $MAILSRV1_ExtIP (metric 100)  |  Internal: $MAILSRV1_IntIP (metric 5)"
    } else {
        Write-Warn "Only $($nicInfo.Count) NIC(s) found — add a second adapter"
        if ($nicInfo.ExtNic) {
            New-NetIPAddress -InterfaceIndex $nicInfo.ExtNic.ifIndex -IPAddress $MAILSRV1_ExtIP `
                -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
            Set-DnsClientServerAddress -InterfaceIndex $nicInfo.ExtNic.ifIndex `
                -ServerAddresses $DCip -ErrorAction SilentlyContinue
        }
    }

    Rename-Computer -NewName "MAILSRV1" -Force -ErrorAction SilentlyContinue
    Write-OK "Computer renamed to MAILSRV1 (applies after reboot)"

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
"@ -Encoding UTF8
    New-SmbShare -Name "MailStore" -Path "C:\Mail_Backup" -FullAccess "Everyone" `
        -ErrorAction SilentlyContinue | Out-Null
    Write-OK "MailStore share with credential bait created"

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue

    Write-Banner "MAILSRV1 COMPLETE"
    Write-OK "External: $MAILSRV1_ExtIP  |  Internal: $MAILSRV1_IntIP"
    Write-OK "NEXT: reboot, then join domain → Add-Computer -DomainName corp.local -Credential CORP\Administrator -Restart"
    Write-Step "Rebooting in 10 seconds..."
    Start-Sleep -Seconds 10
    Restart-Computer -Force
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

    # FIX #2 (CLIENT01 part): Use Add-Computer -NewName to handle rename + domain
    # join in a single operation. This avoids the bug where Rename-Computer queues
    # a rename that conflicts with the domain join after reboot.
    # FIX #3: The domain join credential now matches the actual Domain Admin
    # password because we set it explicitly in Invoke-DC01Setup before promotion.
    Write-Step "Joining domain $Domain (with rename to CLIENT01 if needed)..."
    $domainJoined = $false
    try {
        $cred = New-Object PSCredential("$NetBios\Administrator",
            (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))

        if ((Get-WmiObject Win32_ComputerSystem).PartOfDomain) {
            Write-OK "Already domain-joined — skipping domain join"
            $domainJoined = $true
        } elseif ($env:COMPUTERNAME -eq "CLIENT01") {
            Add-Computer -DomainName $Domain -Credential $cred -ErrorAction Stop
            $domainJoined = $true
            Write-OK "Joined $Domain"
        } else {
            # Rename + domain join in one operation
            Add-Computer -DomainName $Domain -NewName "CLIENT01" -Credential $cred -ErrorAction Stop
            $domainJoined = $true
            Write-OK "Renamed to CLIENT01 and joined $Domain"
        }
    } catch {
        Write-Warn "Domain join failed: $_"
        Write-Warn "Continuing with local setup. Fix domain join manually after reboot."
        # Fall back to standalone rename if domain join fails
        if ($env:COMPUTERNAME -ne "CLIENT01") {
            Rename-Computer -NewName "CLIENT01" -Force -ErrorAction SilentlyContinue
            Write-OK "Computer will be renamed to CLIENT01 after reboot"
        }
    }

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

    # FIX #1: Add-Type -OutputAssembly always produces a DLL regardless of the
    # file extension. Use csc.exe directly to produce a real EXE.
    # Also fix: Thread.Sleep(Timeout.Infinite) in OnStart blocks the SCM and
    # causes a service start timeout. Use a background worker thread instead.
    $svcCode = @'
using System; using System.ServiceProcess; using System.Threading;
namespace VulnSvc {
    public class VulnService : ServiceBase {
        private Thread _worker;
        public VulnService() { ServiceName = "VulnService"; }
        static void Main() { Run(new VulnService()); }
        protected override void OnStart(string[] args) {
            _worker = new Thread(() => {
                while (true) Thread.Sleep(60000);
            });
            _worker.IsBackground = true;
            _worker.Start();
        }
        protected override void OnStop() {
            if (_worker != null) { try { _worker.Abort(); } catch { } }
        }
    }
}
'@
    $svcCode | Set-Content "$TempDir\VulnSvc.cs" -Encoding ASCII

    $cscPath = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $cscPath)) {
        $cscPath = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v3.5\csc.exe"
    }

    $serviceCompiled = $false
    if (Test-Path $cscPath) {
        try {
            & $cscPath /nologo /out:"$vulnDir\VulnService.exe" /target:winexe `
                /reference:System.ServiceProcess.dll "$TempDir\VulnSvc.cs" 2>&1 | Out-Null
            if (Test-Path "$vulnDir\VulnService.exe") {
                $serviceCompiled = $true
            }
        } catch {
            Write-Warn "csc.exe compile error: $_"
        }
    }

    if ($serviceCompiled) {
        sc.exe create VulnService binPath= "`"$vulnDir\VulnService.exe`"" start= auto obj= LocalSystem 2>&1 | Out-Null
        sc.exe start VulnService 2>&1 | Out-Null
        Write-OK "VulnService: $vulnDir\VulnService.exe (Everyone:F, compiled with csc.exe)"
    } else {
        # Fallback: create a dummy file with weak permissions so the
        # permissions-based exercise still works even if compilation fails
        Write-Warn "csc.exe not found or compilation failed — creating placeholder binary"
        $dummyBytes = [System.Text.Encoding]::ASCII.GetBytes("PLACEHOLDER")
        [System.IO.File]::WriteAllBytes("$vulnDir\VulnService.exe", $dummyBytes)
        icacls "$vulnDir\VulnService.exe" /grant "Everyone:(F)" 2>&1 | Out-Null
        Write-Warn "VulnService placeholder created — service won't start, but permissions exercise works"
    }

    # ── Module: Unquoted Service Path ───────────────────────
    # FIX (unquoted path exploitability): Changed from
    #   "C:\Program Files\Vulnerable Service\bin\service.exe"
    # to
    #   "C:\Program Files\Corp Apps\Update Service\service.exe"
    # The original path was not exploitable because C:\Program Files\
    # is not writable by regular users. With the new path, the attacker
    # can place "C:\Program Files\Corp Apps\Update.exe" because
    # "C:\Program Files\Corp Apps\" is writable.
    Write-Step "Creating Unquoted Service Path target..."
    $uqBase = "C:\Program Files\Corp Apps"
    $uqSvc  = "$uqBase\Update Service"
    $uqBin  = "$uqSvc\service.exe"
    New-Item -ItemType Directory -Path (Split-Path $uqBin -Parent) -Force | Out-Null
    # Make "C:\Program Files\Corp Apps\" writable — this is what makes the
    # unquoted path exploitable (drop "Update.exe" here)
    icacls $uqBase /grant "BUILTIN\Users:(F)" /T 2>&1 | Out-Null
    if (Test-Path "$vulnDir\VulnService.exe") {
        Copy-Item "$vulnDir\VulnService.exe" $uqBin -ErrorAction SilentlyContinue
    } else {
        $dummyBytes = [System.Text.Encoding]::ASCII.GetBytes("PLACEHOLDER")
        [System.IO.File]::WriteAllBytes($uqBin, $dummyBytes)
    }
    sc.exe create UnquotedSvc binPath= "C:\Program Files\Corp Apps\Update Service\service.exe" start= auto obj= LocalSystem DisplayName= "Unquoted Path Service" 2>&1 | Out-Null
    Write-OK "UnquotedSvc: drop payload at 'C:\Program Files\Corp Apps\Update.exe'"

    # ── Module: DLL Hijacking ────────────────────────────────
    Write-Step "Creating DLL Hijacking target..."
    $dllDir = "C:\Program Files\DLLHijackSvc"
    New-Item -ItemType Directory -Path $dllDir -Force | Out-Null
    icacls $dllDir /grant "BUILTIN\Users:(W)" 2>&1 | Out-Null
    Set-Content "$dllDir\README.txt" "Loads wlbsctrl.dll from local dir. Users have Write access here." -Encoding UTF8
    Write-OK "DLLHijackSvc: $dllDir (Users:W)"

    # ── Module: Scheduled Task ──────────────────────────────
    Write-Step "Creating Scheduled Task PrivEsc target..."
    New-Item -ItemType Directory -Path "C:\Tasks" -Force | Out-Null
    icacls "C:\Tasks" /grant "Everyone:(F)" 2>&1 | Out-Null
    Set-Content "C:\Tasks\cleanup.bat" "@echo off`ndel /q C:\Temp\*.tmp 2>nul`necho Done" -Encoding ASCII

    # FIX #11: Added -RepetitionDuration. Without it, many Windows builds
    # either throw an error or create a task that never actually repeats.
    $action    = New-ScheduledTaskAction -Execute "C:\Tasks\cleanup.bat"
    $trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration (New-TimeSpan -Days 365)
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
"@ -Encoding UTF8
    reg add "HKLM\SOFTWARE\CorpApp" /v "DBPassword"  /t REG_SZ /d "Sqlpassword1"  /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\CorpApp" /v "AdminUser"   /t REG_SZ /d "itadmin"       /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\CorpApp" /v "AdminPass"   /t REG_SZ /d "Sup3rS3cur3!"  /f 2>&1 | Out-Null
    New-Item -ItemType Directory "C:\inetpub\wwwroot" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "C:\inetpub\wwwroot\web.config.bak" '<add key="DBConn" value="Server=DC01;User=svc_sql;Password=Sqlpassword1;"/>' -Encoding UTF8
    New-Item -ItemType Directory "C:\Windows\Panther" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "C:\Windows\Panther\unattend.xml" @'
<?xml version="1.0"?>
<unattend><settings pass="specialize"><component name="Microsoft-Windows-Shell-Setup">
<AutoLogon><Password><Value>UGFzc3dvcmQxMjM=</Value><PlainText>false</PlainText></Password>
<Username>Administrator</Username><Enabled>true</Enabled></AutoLogon>
</component></settings></unattend>
'@ -Encoding UTF8

    # FIX #7: PSReadLine history — the original code wrote to C:\Users\j.watson\
    # which may not be the actual profile path after domain join (Windows may
    # create C:\Users\j.watson.CORP instead). Using a Startup script that
    # writes the history file at j.watson's FIRST login, when the real profile
    # path is known.
    $dropHistContent = @'
$histDir = Join-Path $env:APPDATA "Microsoft\Windows\PowerShell\PSReadLine"
$histFile = Join-Path $histDir "ConsoleHost_history.txt"
if ($env:USERNAME -eq "j.watson" -and -not (Test-Path $histFile)) {
    if (-not (Test-Path $histDir)) { New-Item -ItemType Directory -Path $histDir -Force | Out-Null }
    @"
Get-ADUser -Filter *
net use \\DC01\IT_Share /user:CORP\itadmin Sup3rS3cur3!
Enter-PSSession -ComputerName DC01 -Credential (New-Object PSCredential('CORP\itadmin',(ConvertTo-SecureString 'Sup3rS3cur3!' -AsPlainText -Force)))
"@ | Set-Content $histFile -Encoding UTF8
}
'@
    Set-Content "$ToolsDir\Drop-PSHistory.ps1" $dropHistContent -Encoding UTF8
    $startupFolder = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    Set-Content "$startupFolder\Drop-PSHistory.bat" "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ToolsDir\Drop-PSHistory.ps1`"" -Encoding ASCII
    Write-OK "PS history bait: will be written to j.watson's profile on first login"

    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon"    /t REG_SZ /d "1"          /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultUsername"   /t REG_SZ /d "j.watson"   /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultPassword"   /t REG_SZ /d "Password123" /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultDomainName" /t REG_SZ /d "CORP"        /f 2>&1 | Out-Null
    Write-
# ===========================================================================
#  END OF SCRIPT
#  NullyBlissful | MAYAN_SUTHAR | github.com/MayanSuthar
# ===========================================================================
