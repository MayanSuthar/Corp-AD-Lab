#Requires -RunAsAdministrator
# ===========================================================================
#  AUTHOR  : NullyBlissful | MAYAN_SUTHAR
#  GITHUB  : github.com/MayanSuthar
#  VERSION : 3.1 (Bug-fixed)
#  REPO    : github.com/MayanSuthar/Corp-AD-Lab
# ---------------------------------------------------------------------------
#  USAGE:
#    .\Setup-CorpLab.ps1 -Role DC01          # Renames (if needed), installs AD, reboots
#    .\Setup-CorpLab.ps1 -Role DC01          # Run again after rename reboot — installs AD, reboots
#    .\Setup-CorpLab.ps1 -Role DC01Phase2    # Runs auto via scheduled task after AD reboot
#    .\Setup-CorpLab.ps1 -Role WEBSRV1
#    .\Setup-CorpLab.ps1 -Role MAILSRV1
#    .\Setup-CorpLab.ps1 -Role CLIENT01
#    .\Setup-CorpLab.ps1 -Role CLIENT02
# ===========================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("DC01","DC01Phase2","MAILSRV1","WEBSRV1","CLIENT01","CLIENT02")]
    [string]$Role
)

Set-StrictMode -Version Latest
 $ErrorActionPreference = "Continue"

# ── Output Helpers ─────────────────────────────────────────────
function Write-AuthorBanner {
    Write-Host ""
    Write-Host "  NullyBlissful | MAYAN_SUTHAR" -ForegroundColor Magenta
    Write-Host "  github.com/MayanSuthar | medium.com/@mayan230848" -ForegroundColor DarkMagenta
    Write-Host "  Corp AD Lab v3.1" -ForegroundColor DarkMagenta
    Write-Host ""
}
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
# FIX #6: Auto-detect External/Internal NICs by current IP subnet
function Find-DualHomedNics {
    $nics = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object Name)
    if ($nics.Count -lt 2) {
        Write-Warn "Expected 2 active NICs, found $($nics.Count)"
        return @{ ExtNic = $nics[0]; IntNic = $null; Count = $nics.Count }
    }
    $extNic = $null; $intNic = $null
    foreach ($nic in $nics) {
        $ips = @(Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 `
                 -ErrorAction SilentlyContinue |
                 Where-Object { $_.PrefixOrigin -ne "WellKnown" -and $_.IPAddress -ne "0.0.0.0" })
        foreach ($ip in $ips) {
            if ($ip.IPAddress -like "192.168.56.*") { $extNic = $nic }
            if ($ip.IPAddress -like "10.10.10.*")   { $intNic = $nic }
        }
    }
    if ($extNic -and $intNic) {
        Write-OK "Auto-detected NICs: Ext=$($extNic.Name), Int=$($intNic.Name)"
        return @{ ExtNic = $extNic; IntNic = $intNic; Count = $nics.Count }
    }
    Write-Warn "Could not auto-detect NIC roles. Using sorted order as fallback."
    return @{ ExtNic = $nics[0]; IntNic = $nics[1]; Count = $nics.Count }
}

# ── Service Binary Compiler ────────────────────────────────────
# FIX #1: Use csc.exe instead of Add-Type (which makes DLLs, not EXEs)
# FIX #20: Compile separate binaries with correct ServiceName for each
function New-LabServiceBinary {
    param([string]$ServiceName, [string]$OutputPath)
    $code = @"
using System; using System.ServiceProcess; using System.Threading;
namespace LabSvc {
    public class LabService : ServiceBase {
        private Thread _worker;
        public LabService() { ServiceName = "$ServiceName"; }
        static void Main() { Run(new LabService()); }
        protected override void OnStart(string[] args) {
            _worker = new Thread(() => { while (true) Thread.Sleep(60000); });
            _worker.IsBackground = true; _worker.Start();
        }
        protected override void OnStop() { if (_worker != null) { try { _worker.Abort(); } catch { } } }
    }
}
"@
    $csFile = Join-Path $TempDir "$ServiceName.cs"
    $code | Set-Content $csFile -Encoding ASCII
    $cscPath = $null
    foreach ($fx in @("v4.0.30319", "v3.5")) {
        $candidate = Join-Path $env:WINDIR "Microsoft.NET\Framework64\$fx\csc.exe"
        if (Test-Path $candidate) { $cscPath = $candidate; break }
    }
    if (-not $cscPath) { Write-Warn "csc.exe not found"; return $false }
    $outDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    & $cscPath /nologo /out:"$OutputPath" /target:winexe /reference:System.ServiceProcess.dll "$csFile" 2>&1 | Out-Null
    return (Test-Path $OutputPath)
}

# ── Common Setup — runs on every machine ───────────────────────
function Invoke-CommonSetup {
    Write-Banner "COMMON SETUP"
    foreach ($d in @($ToolsDir, $TempDir, "C:\Tasks", "C:\IT_Share", "C:\Mail_Backup")) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    Write-OK "Directories created"
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath $ToolsDir, $TempDir -ErrorAction SilentlyContinue
        Write-OK "Defender real-time monitoring disabled"
    } catch { Write-Warn "Defender disable skipped" }

    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction SilentlyContinue
    Write-OK "Firewall disabled"
    New-NetFirewallRule -Name "Allow-ICMPv4-In" -DisplayName "Allow ICMPv4 Inbound (Lab)" `
        -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow -Enabled True `
        -ErrorAction SilentlyContinue | Out-Null
    Write-OK "ICMP ping allowed"

    Enable-PSRemoting -Force -ErrorAction SilentlyContinue
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force -ErrorAction SilentlyContinue
    Set-Service -Name WinRM -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service WinRM -ErrorAction SilentlyContinue
    Write-OK "WinRM enabled"

    # FIX #24: SMBv1 on ALL machines
    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
    Write-OK "SMBv1 enabled"

    # FIX #26: Disable Windows Update to prevent unexpected reboots
    $wusvc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($wusvc) {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Set-Service -Name wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
        Write-OK "Windows Update service disabled"
    }
    # FIX #27: Time sync for Kerberos
    w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /update 2>&1 | Out-Null
    net start w32time 2>&1 | Out-Null
    w32tm /resync 2>&1 | Out-Null
    Write-OK "Time sync configured"
}

# ── DC01 Phase 1 ───────────────────────────────────────────────
function Invoke-DC01Setup {
    Write-Banner "DC01 - PHASE 1: ACTIVE DIRECTORY INSTALLATION"

    # FIX #2 (DC01): Reboot BEFORE installing AD if name isn't DC01
    if ($env:COMPUTERNAME -ne "DC01") {
        Write-Step "Computer name is '$($env:COMPUTERNAME)' — renaming to DC01..."
        Rename-Computer -NewName "DC01" -Force -ErrorAction SilentlyContinue
        if ($?) {
            Write-OK "Computer renamed to DC01"
            Write-Warn "Rebooting for rename. RUN THIS SCRIPT AGAIN after reboot."
            Start-Sleep -Seconds 5; Restart-Computer -Force; return
        }
    }

    Write-Step "Configuring static IP: $DCip"
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($nic) {
        Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        # NOTE: Gateway 10.10.10.1 does not exist, but harmless.
        New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $DCip -PrefixLength 24 `
            -DefaultGateway "10.10.10.1" -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses "127.0.0.1" -ErrorAction SilentlyContinue
        Write-OK "Static IP: $DCip / 24   DNS: 127.0.0.1"
    } else { Write-Warn "No active NIC found" }

    # FIX #3: Set local Admin password BEFORE promoting to match $DomainAdminPass
    Write-Step "Setting local Administrator password..."
    net user Administrator $DomainAdminPass 2>&1 | Out-Null
    Write-OK "Local Administrator password set"

    Write-Step "Installing AD-Domain-Services role (2-5 minutes)..."
    $result = Install-WindowsFeature -Name AD-Domain-Services,DNS,RSAT-AD-Tools -IncludeManagementTools -IncludeAllSubFeature
    if ($result.Success) { Write-OK "AD-Domain-Services role installed" }
    else { Write-Warn "AD DS role install had issues" }

    # FIX #8 + #9: Scheduled Task at startup as SYSTEM instead of RunOnce
    Write-Step "Registering Phase 2 scheduled task..."
    $scriptPath = $PSCommandPath
    if ($scriptPath) {
        try {
            Unregister-ScheduledTask -TaskName "CorpLab-DC01Phase2" -Confirm:$false -ErrorAction SilentlyContinue
            $action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" -Role DC01Phase2"
            $trigger   = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName "CorpLab-DC01Phase2" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
            Write-OK "Phase 2 scheduled task registered"
        } catch { Write-Warn "Scheduled task failed: $_" }
    }

    # FIX #10: Dead code after Install-ADDSForest removed
    Write-Step "Promoting to Domain Controller for $Domain (will reboot)..."
    $safePwd = ConvertTo-SecureString $SafeModePass -AsPlainText -Force
    Install-ADDSForest -DomainName $Domain -DomainNetbiosName $NetBios -InstallDns `
        -SafeModeAdministratorPassword $safePwd -NoRebootOnCompletion:$false -Force:$true
}

# ── DC01 Phase 2 ───────────────────────────────────────────────
function Invoke-DC01Phase2 {
    Write-Banner "DC01 - PHASE 2: AD OBJECTS"
    Unregister-ScheduledTask -TaskName "CorpLab-DC01Phase2" -Confirm:$false -ErrorAction SilentlyContinue

    # FIX #4: Abort if AD never becomes ready
    Write-Step "Waiting for Active Directory..."
    $retries = 0; $adReady = $false
    while ($retries -lt 12) {
        try { Import-Module ActiveDirectory -ErrorAction Stop; Get-ADDomain -ErrorAction Stop | Out-Null; $adReady = $true; break }
        catch { $retries++; Write-Step "Not ready, waiting 15s... ($retries/12)"; Start-Sleep -Seconds 15 }
    }
    if (-not $adReady) { Write-Warn "AD never became ready. Aborting Phase 2."; return }

    Write-Step "Creating OUs..."
    @(
        @{ Name="Corp";            Path="DC=corp,DC=local" },
        @{ Name="Users";           Path="OU=Corp,DC=corp,DC=local" },
        @{ Name="Computers";       Path="OU=Corp,DC=corp,DC=local" },
        @{ Name="ServiceAccounts"; Path="OU=Corp,DC=corp,DC=local" },
        @{ Name="Admins";          Path="OU=Corp,DC=corp,DC=local" }
    ) | ForEach-Object {
        New-ADOrganizationalUnit -Name $_.Name -Path $_.Path -ErrorAction SilentlyContinue
        # FIX #5: Check $? before reporting success
        if ($?) { Write-OK "  OU: $($_.Name)" } else { Write-Warn "  OU: $($_.Name) failed" }
    }

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
        New-ADUser -Name $u.Name -GivenName $parts[0] -Surname ($parts[1..99] -join " ") `
            -SamAccountName $u.Sam -UserPrincipalName "$($u.Sam)@$Domain" -Path $u.Path `
            -AccountPassword (ConvertTo-SecureString $u.Pass -AsPlainText -Force) `
            -Enabled $true -Description $u.Desc -ErrorAction SilentlyContinue
        if ($?) { Write-OK "  User: $($u.Sam) / $($u.Pass)" } else { Write-Warn "  User: $($u.Sam) FAILED" }
    }

    Add-ADGroupMember -Identity "Domain Admins" -Members "d.backup" -ErrorAction SilentlyContinue
    if ($?) { Write-OK "d.backup added to Domain Admins" }

    Write-Step "Setting SPNs (Kerberoasting)..."
    Set-ADUser -Identity "svc_sql" -ServicePrincipalNames @{ Add="MSSQLSvc/dc01.corp.local:1433" } -ErrorAction SilentlyContinue
    Set-ADUser -Identity "svc_web" -ServicePrincipalNames @{ Add="HTTP/websrv1.corp.local" } -ErrorAction SilentlyContinue
    Write-OK "SPNs set"

    Write-Step "AS-REP Roasting target..."
    Set-ADAccountControl -Identity "s.noauth" -DoesNotRequirePreAuth $true -ErrorAction SilentlyContinue
    Write-OK "s.noauth pre-auth disabled"

    Write-Step "Creating groups..."
    @("IT Department", "HR Department", "Remote Management Users") | ForEach-Object {
        New-ADGroup -Name $_ -GroupScope Global -GroupCategory Security -Path "OU=Corp,DC=corp,DC=local" -ErrorAction SilentlyContinue
    }
    Add-ADGroupMember -Identity "IT Department" -Members "itadmin","j.watson" -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "HR Department" -Members "m.johnson","t.richards" -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "Remote Management Users" -Members "itadmin","j.watson" -ErrorAction SilentlyContinue
    Write-OK "Groups populated"

    Write-Step "GenericAll ACL (j.watson -> CLIENT01)..."
    try {
        $sid = (Get-ADUser j.watson -ErrorAction Stop).SID
        $dn  = (Get-ADComputer CLIENT01 -ErrorAction Stop).DistinguishedName
        $acl = Get-Acl "AD:$dn"; $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, [System.DirectoryServices.ActiveDirectoryRights]::GenericAll, [System.Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($ace); Set-Acl "AD:$dn" $acl; Write-OK "ACL set"
    } catch { Write-Warn "ACL skipped (CLIENT01 not in domain yet)" }

    Write-Step "DNS records..."
    @(
        @{ Name="mailsrv1"; IP=$MAILSRV1_IntIP }, @{ Name="websrv1"; IP=$WEBSRV1_IntIP },
        @{ Name="client01"; IP=$CLIENT01_IP },     @{ Name="client02"; IP=$CLIENT02_IP }
    ) | ForEach-Object { Add-DnsServerResourceRecordA -ZoneName $Domain -Name $_.Name -IPv4Address $_.IP -ErrorAction SilentlyContinue }
    Write-OK "DNS records added"

    Write-Step "IT_Share with credential bait..."
    New-Item -Path "C:\IT_Share" -ItemType Directory -Force | Out-Null
    Set-Content "C:\IT_Share\credentials.txt" @"
=== IT Department Credentials — CONFIDENTIAL ===
Web Portal:   admin / admin123
Database:     svc_sql / Sqlpassword1
Web Service:  svc_web / Webservice1
IT Admin:     itadmin / Sup3rS3cur3!
Backup Admin: d.backup / Backup2023!
"@ -Encoding UTF8
    New-SmbShare -Name "IT_Share" -Path "C:\IT_Share" -FullAccess "CORP\itadmin" -ReadAccess "CORP\Domain Users" -ErrorAction SilentlyContinue | Out-Null
    Write-OK "IT_Share created"

    vssadmin create shadow /for=C: 2>&1 | Out-Null
    # FIX #21: MaxPasswordAge needs a valid TimeSpan
    Set-ADDefaultDomainPasswordPolicy -Identity $Domain -MinPasswordLength 0 -PasswordHistoryCount 0 -ComplexityEnabled $false -MaxPasswordAge (New-TimeSpan -Days 365) -ErrorAction SilentlyContinue
    Write-OK "Shadow copy created, password policy relaxed"

    Write-Banner "DC01 PHASE 2 COMPLETE"
    Write-OK "Domain     : $Domain"
    Write-OK "Admin      : CORP\Administrator / $DomainAdminPass"
    Write-AuthorBanner
}

# ── WEBSRV1 ────────────────────────────────────────────────────
function Invoke-WEBSRV1Setup {
    Write-Banner "WEBSRV1 SETUP - WEB SERVER / PIVOT"

    # FIX #6 + #15: NIC auto-detection + metrics
    Write-Step "Configuring dual-homed IPs..."
    $nicInfo = Find-DualHomedNics
    if ($nicInfo.Count -ge 2 -and $nicInfo.ExtNic -and $nicInfo.IntNic) {
        foreach ($nic in @($nicInfo.ExtNic, $nicInfo.IntNic)) {
            Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        }
        New-NetIPAddress -InterfaceIndex $nicInfo.ExtNic.ifIndex -IPAddress $WEBSRV1_ExtIP -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nicInfo.ExtNic.ifIndex -ServerAddresses $DCip -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $nicInfo.IntNic.ifIndex -IPAddress $WEBSRV1_IntIP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nicInfo.IntNic.ifIndex -ServerAddresses $DCip -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $nicInfo.ExtNic.ifIndex -InterfaceMetric 100 -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $nicInfo.IntNic.ifIndex -InterfaceMetric 5 -ErrorAction SilentlyContinue
        Write-OK "Ext: $WEBSRV1_ExtIP (100) | Int: $WEBSRV1_IntIP (5)"
    } else { Write-Warn "Need 2 NICs" }

    # FIX #22: Domain join + rename in one step
    Write-Step "Joining domain $Domain..."
    $domainJoined = $false
    try {
        $cred = New-Object PSCredential("$NetBios\Administrator", (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))
        if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) { $domainJoined = $true; Write-OK "Already joined" }
        elseif ($env:COMPUTERNAME -eq "WEBSRV1") { Add-Computer -DomainName $Domain -Credential $cred -ErrorAction Stop; $domainJoined = $true; Write-OK "Joined $Domain" }
        else { Add-Computer -DomainName $Domain -NewName "WEBSRV1" -Credential $cred -ErrorAction Stop; $domainJoined = $true; Write-OK "Renamed & joined $Domain" }
    } catch {
        Write-Warn "Domain join failed: $_"
        if ($env:COMPUTERNAME -ne "WEBSRV1") { Rename-Computer -NewName "WEBSRV1" -Force -ErrorAction SilentlyContinue }
    }

    Write-Step "Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
    Start-Service sshd -ErrorAction SilentlyContinue; Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
    net user Administrator "admin123" 2>&1 | Out-Null
    Write-OK "SSH target: Administrator:admin123"

    Write-Step "Installing IIS + ASP.NET..."
    Install-WindowsFeature -Name Web-Server,Web-Asp-Net45,Web-Net-Ext45,Web-ISAPI-Ext,Web-ISAPI-Filter -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    Write-OK "IIS installed"

    Write-Step "Creating vulnerable login page..."
    $loginDir = "C:\inetpub\wwwroot\login"; New-Item -ItemType Directory -Path $loginDir -Force | Out-Null
    # FIX #16: ASCII encoding for ASPX
    @'
<%@ Page Language="C#" %>
<%
    string msg = ""; string u = Request.Form["username"] ?? ""; string p = Request.Form["password"] ?? "";
    if (Request.HttpMethod == "POST") {
        if (u == "admin" && p == "admin123") msg = "<div style='color:#00ff41'>LOGIN SUCCESS - Administrator FLAG{HTTP_LOGIN_PWNED}</div>";
        else if (u == "j.watson" && p == "Password123") msg = "<div style='color:#00ff41'>LOGIN SUCCESS - John Watson</div>";
        else if (u != "") msg = "<div style='color:#e94560'>Login Failed</div>";
    }
%>
<!DOCTYPE html><html><head><title>Corp Portal</title>
<style>body{font-family:Arial;background:#0d1117;color:#c9d1d9;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}
.box{background:#161b22;padding:40px;border-radius:8px;width:360px;border:1px solid #30363d}h2{color:#e94560;text-align:center}
input{width:100%;padding:10px;margin-bottom:14px;box-sizing:border-box;background:#0d1117;border:1px solid #30363d;color:#c9d1d9;border-radius:4px}
button{width:100%;padding:12px;background:#e94560;border:none;color:#fff;font-size:15px;cursor:pointer;border-radius:4px}</style></head>
<body><div class="box"><h2>Corp Portal Login</h2><%=msg%><form method="POST" style="margin-top:14px">
<label>Username</label><input type="text" name="username" autocomplete="off"><label>Password</label><input type="password" name="password">
<button type="submit">Sign In</button></form></div></body></html>
'@ | Out-File -FilePath "$loginDir\default.aspx" -Encoding ASCII
    Write-OK "Login page deployed"

    Write-Step "Planting credential files..."
    Set-Content "C:\inetpub\wwwroot\config.bak" "DB_HOST=10.10.10.10`nDB_USER=svc_sql`nDB_PASS=Sqlpassword1`nADMIN_USER=itadmin`nADMIN_PASS=Sup3rS3cur3!" -Encoding UTF8
    Set-Content "C:\inetpub\wwwroot\web.config.bak" '<add key="DBConn" value="Server=DC01;User=svc_sql;Password=Sqlpassword1;"/>' -Encoding UTF8
    New-Item -ItemType Directory "C:\inetpub\wwwroot\backup" -Force | Out-Null
    Set-Content "C:\inetpub\wwwroot\backup\deploy_notes.txt" "FTP: websrv1admin / FtpP@ss2023`nDB: svc_sql / Sqlpassword1`nDA: d.backup / Backup2023!" -Encoding UTF8

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    # FIX #17: Renamed to WebBackup
    New-Item -Path "C:\WebBackup" -ItemType Directory -Force | Out-Null
    Set-Content "C:\WebBackup\iis_logs_export.txt" "IIS Admin: websrv1admin / FtpP@ss2023`nAdmin: itadmin / Sup3rS3cur3!" -Encoding UTF8
    New-SmbShare -Name "WebBackup" -Path "C:\WebBackup" -FullAccess "Everyone" -ErrorAction SilentlyContinue | Out-Null
    # FIX #12: Removed bad portproxy to DC01:80

    Write-Banner "WEBSRV1 COMPLETE"
    if (-not $domainJoined) { Write-Warn "NOT domain joined - join manually after reboot" }
    Write-Step "Rebooting in 10 seconds..."; Start-Sleep -Seconds 10; Restart-Computer -Force
    Write-AuthorBanner
}

# ── MAILSRV1 ───────────────────────────────────────────────────
function Invoke-MAILSRV1Setup {
    Write-Banner "MAILSRV1 SETUP - MAIL SERVER / PIVOT"

    Write-Step "Configuring dual-homed IPs..."
    $nicInfo = Find-DualHomedNics
    if ($nicInfo.Count -ge 2 -and $nicInfo.ExtNic -and $nicInfo.IntNic) {
        foreach ($nic in @($nicInfo.ExtNic, $nicInfo.IntNic)) {
            Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        }
        New-NetIPAddress -InterfaceIndex $nicInfo.ExtNic.ifIndex -IPAddress $MAILSRV1_ExtIP -PrefixLength 24 -DefaultGateway "192.168.56.1" -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nicInfo.ExtNic.ifIndex -ServerAddresses $DCip -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $nicInfo.IntNic.ifIndex -IPAddress $MAILSRV1_IntIP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nicInfo.IntNic.ifIndex -ServerAddresses $DCip -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $nicInfo.ExtNic.ifIndex -InterfaceMetric 100 -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $nicInfo.IntNic.ifIndex -InterfaceMetric 5 -ErrorAction SilentlyContinue
        Write-OK "Ext: $MAILSRV1_ExtIP (100) | Int: $MAILSRV1_IntIP (5)"
    } else { Write-Warn "Need 2 NICs" }

    Write-Step "Joining domain $Domain..."
    $domainJoined = $false
    try {
        $cred = New-Object PSCredential("$NetBios\Administrator", (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))
        if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) { $domainJoined = $true; Write-OK "Already joined" }
        elseif ($env:COMPUTERNAME -eq "MAILSRV1") { Add-Computer -DomainName $Domain -Credential $cred -ErrorAction Stop; $domainJoined = $true; Write-OK "Joined $Domain" }
        else { Add-Computer -DomainName $Domain -NewName "MAILSRV1" -Credential $cred -ErrorAction Stop; $domainJoined = $true; Write-OK "Renamed & joined $Domain" }
    } catch {
        Write-Warn "Domain join failed: $_"
        if ($env:COMPUTERNAME -ne "MAILSRV1") { Rename-Computer -NewName "MAILSRV1" -Force -ErrorAction SilentlyContinue }
    }

    net user Administrator "Mail@2023" 2>&1 | Out-Null
    Write-OK "Weak admin password: Mail@2023"

    New-Item -Path "C:\Mail_Backup" -ItemType Directory -Force | Out-Null
    Set-Content "C:\Mail_Backup\it_dept_email_export.txt" "From: itadmin@corp.local`nTo: d.backup@corp.local`nSubject: DC backup creds`nDC Backup: Backup2023!`nSQL: svc_sql / Sqlpassword1" -Encoding UTF8
    New-SmbShare -Name "MailStore" -Path "C:\Mail_Backup" -FullAccess "Everyone" -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    Write-Banner "MAILSRV1 COMPLETE"
    if (-not $domainJoined) { Write-Warn "NOT domain joined - join manually after reboot" }
    Write-Step "Rebooting in 10 seconds..."; Start-Sleep -Seconds 10; Restart-Computer -Force
    Write-AuthorBanner
}

# ── CLIENT01 ───────────────────────────────────────────────────
function Invoke-CLIENT01Setup {
    Write-Banner "CLIENT01 SETUP - VULNERABLE WORKSTATION"

    Write-Step "Static IP: $CLIENT01_IP"
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($nic) {
        Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $CLIENT01_IP -PrefixLength 24 -DefaultGateway "10.10.10.1" -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $DCip -ErrorAction SilentlyContinue
    }

    # FIX #2 & #3: Combined rename + join with correct credentials
    Write-Step "Joining domain $Domain..."
    $domainJoined = $false
    try {
        $cred = New-Object PSCredential("$NetBios\Administrator", (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))
        if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) { $domainJoined = $true; Write-OK "Already joined" }
        elseif ($env:COMPUTERNAME -eq "CLIENT01") { Add-Computer -DomainName $Domain -Credential $cred -ErrorAction Stop; $domainJoined = $true; Write-OK "Joined $Domain" }
        else { Add-Computer -DomainName $Domain -NewName "CLIENT01" -Credential $cred -ErrorAction Stop; $domainJoined = $true; Write-OK "Renamed & joined $Domain" }
    } catch {
        Write-Warn "Domain join failed: $_"
        if ($env:COMPUTERNAME -ne "CLIENT01") { Rename-Computer -NewName "CLIENT01" -Force -ErrorAction SilentlyContinue }
    }

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "LocalAccountTokenFilterPolicy" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    Write-OK "RDP + PtH enabled"

    # Service Binary Hijacking
    Write-Step "Service Binary Hijacking target..."
    $vulnDir = "C:\Program Files\VulnService"; New-Item -ItemType Directory -Path $vulnDir -Force | Out-Null
    icacls $vulnDir /grant "Everyone:(F)" /T 2>&1 | Out-Null
    # FIX #1 & #20: Compile valid EXE with correct ServiceName
    if (New-LabServiceBinary -ServiceName "VulnService" -OutputPath "$vulnDir\VulnService.exe") {
        sc.exe create VulnService binPath= "`"$vulnDir\VulnService.exe`"" start= auto obj= LocalSystem 2>&1 | Out-Null
        sc.exe start VulnService 2>&1 | Out-Null
        Write-OK "VulnService created (Everyone:F)"
    } else {
        [System.IO.File]::WriteAllBytes("$vulnDir\VulnService.exe", [System.Text.Encoding]::ASCII.GetBytes("PLACEHOLDER"))
        icacls "$vulnDir\VulnService.exe" /grant "Everyone:(F)" 2>&1 | Out-Null
        Write-Warn "VulnService placeholder (won't start)"
    }

    # Unquoted Service Path
    # Changed to C:\Program Files\Corp Apps\ to make it writable/exploitable
    Write-Step "Unquoted Service Path target..."
    $uqBase = "C:\Program Files\Corp Apps"; $uqSvcDir = "$uqBase\Update Service"; $uqBin = "$uqSvcDir\service.exe"
    New-Item -ItemType Directory -Path $uqSvcDir -Force | Out-Null
    if (-not (New-LabServiceBinary -ServiceName "UnquotedSvc" -OutputPath $uqBin)) {
        [System.IO.File]::WriteAllBytes($uqBin, [System.Text.Encoding]::ASCII.GetBytes("PLACEHOLDER"))
    }
    icacls $uqBase /grant "BUILTIN\Users:(F)" /T 2>&1 | Out-Null
    # FIX #19: PowerShell auto-quotes sc.exe args. Force unquoted via Registry
    sc.exe create UnquotedSvc binPath= "`"$uqBin`"" start= auto obj= LocalSystem DisplayName= "Unquoted Path Service" 2>&1 | Out-Null
    try {
        $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services\UnquotedSvc", $true)
        $regKey.SetValue("ImagePath", "C:\Program Files\Corp Apps\Update Service\service.exe", [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $regKey.Close()
        Write-OK "UnquotedSvc path set (drop Update.exe in Corp Apps\)"
    } catch { Write-Warn "Failed to set unquoted ImagePath" }

    # DLL Hijacking
    Write-Step "DLL Hijacking target..."
    $dllDir = "C:\Program Files\DLLHijackSvc"; New-Item -ItemType Directory -Path $dllDir -Force | Out-Null
    icacls $dllDir /grant "BUILTIN\Users:(W)" 2>&1 | Out-Null
    Set-Content "$dllDir\README.txt" "Loads wlbsctrl.dll. Users have Write." -Encoding UTF8

    # Scheduled Task
    Write-Step "Scheduled Task PrivEsc target..."
    New-Item -ItemType Directory -Path "C:\Tasks" -Force | Out-Null
    icacls "C:\Tasks" /grant "Everyone:(F)" 2>&1 | Out-Null
    Set-Content "C:\Tasks\cleanup.bat" "@echo off`ndel /q C:\Temp\*.tmp 2>nul" -Encoding ASCII
    # FIX #11: Added RepetitionDuration
    $action = New-ScheduledTaskAction -Execute "C:\Tasks\cleanup.bat"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -TaskName "SystemCleanup" -Force | Out-Null
    Write-OK "SystemCleanup task runs as SYSTEM every 5m"

    # Credential Goldmines
    Write-Step "Planting credentials..."
    New-Item -ItemType Directory "C:\Users\Public\Desktop" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "C:\Users\Public\Desktop\credentials.txt" "Web Portal: admin / admin123`nDatabase: svc_sql / Sqlpassword1`nIT Admin: itadmin / Sup3rS3cur3!" -Encoding UTF8
    reg add "HKLM\SOFTWARE\CorpApp" /v "DBPassword" /t REG_SZ /d "Sqlpassword1" /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\CorpApp" /v "AdminUser"  /t REG_SZ /d "itadmin"      /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\CorpApp" /v "AdminPass"  /t REG_SZ /d "Sup3rS3cur3!" /f 2>&1 | Out-Null
    New-Item -ItemType Directory "C:\inetpub\wwwroot" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "C:\inetpub\wwwroot\web.config.bak" '<add key="DBConn" value="Server=DC01;User=svc_sql;Password=Sqlpassword1;"/>' -Encoding UTF8
    New-Item -ItemType Directory "C:\Windows\Panther" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content "C:\Windows\Panther\unattend.xml" '<?xml version="1.0"?><unattend><settings pass="specialize"><component name="Microsoft-Windows-Shell-Setup"><AutoLogon><Password><Value>UGFzc3dvcmQxMjM=</Value><PlainText>false</PlainText></Password><Username>Administrator</Username><Enabled>true</Enabled></AutoLogon></component></settings></unattend>' -Encoding UTF8

    # FIX #7: PSReadLine history via startup script (resolves to correct profile path on first login)
    $dropHistContent = @'
 $histDir = Join-Path $env:APPDATA "Microsoft\Windows\PowerShell\PSReadLine"
 $histFile = Join-Path $histDir "ConsoleHost_history.txt"
if ($env:USERNAME -eq "j.watson" -and -not (Test-Path $histFile)) {
    if (-not (Test-Path $histDir)) { New-Item -ItemType Directory -Path $histDir -Force | Out-Null }
    "Get-ADUser -Filter *`nnet use \\DC01\IT_Share /user:CORP\itadmin Sup3rS3cur3!`nEnter-PSSession -ComputerName DC01 -Credential (New-Object PSCredential('CORP\itadmin',(ConvertTo-SecureString 'Sup3rS3cur3!' -AsPlainText -Force)))" | Set-Content $histFile -Encoding UTF8
}
'@
    Set-Content "$ToolsDir\Drop-PSHistory.ps1" $dropHistContent -Encoding UTF8
    Set-Content "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Drop-PSHistory.bat" "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ToolsDir\Drop-PSHistory.ps1`"" -Encoding ASCII
    Write-OK "PS history bait: drops on j.watson first login"

    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon"    /t REG_SZ /d "1"          /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultUsername"   /t REG_SZ /d "j.watson"   /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultPassword"   /t REG_SZ /d "Password123" /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultDomainName" /t REG_SZ /d "CORP"        /f 2>&1 | Out-Null

    Write-Banner "CLIENT01 COMPLETE"
    if (-not $domainJoined) { Write-Warn "NOT domain joined - join manually after reboot" }
    Write-Step "Rebooting in 10 seconds..."; Start-Sleep -Seconds 10; Restart-Computer -Force
    Write-AuthorBanner
}

# ── CLIENT02 ───────────────────────────────────────────────────
function Invoke-CLIENT02Setup {
    Write-Banner "CLIENT02 SETUP - LATERAL MOVEMENT TARGET"

    Write-Step "Static IP: $CLIENT02_IP"
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($nic) {
        Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $CLIENT02_IP -PrefixLength 24 -DefaultGateway "10.10.10.1" -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $DCip -ErrorAction SilentlyContinue
    }

    Write-Step "Joining domain $Domain..."
    $domainJoined = $false
    try {
        $cred = New-Object PSCredential("$NetBios\Administrator", (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))
        if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) { $domainJoined = $true; Write-OK "Already joined" }
        elseif ($env:COMPUTERNAME -eq "CLIENT02") { Add-Computer -DomainName $Domain -Credential $cred -ErrorAction Stop; $domainJoined = $true; Write-OK "Joined $Domain" }
        else { Add-Computer -DomainName $Domain -NewName "CLIENT02" -Credential $cred -ErrorAction Stop; $domainJoined = $true; Write-OK "Renamed & joined $Domain" }
    } catch {
        Write-Warn "Domain join failed: $_"
        if ($env:COMPUTERNAME -ne "CLIENT02") { Rename-Computer -NewName "CLIENT02" -Force -ErrorAction SilentlyContinue }
    }

    net localgroup administrators "CORP\itadmin" /add 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "LocalAccountTokenFilterPolicy" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Set-Content "C:\Users\Public\notes.txt" "itadmin creds: Sup3rS3cur3!`nDA backup: d.backup / Backup2023!`nDelete this file!" -Encoding UTF8

    Write-Banner "CLIENT02 COMPLETE"
    if (-not $domainJoined) { Write-Warn "NOT domain joined - join manually after reboot" }
    Write-Step "Rebooting in 10 seconds..."; Start-Sleep -Seconds 10; Restart-Computer -Force
    Write-AuthorBanner
}

# ── Main Dispatcher ────────────────────────────────────────────
Write-AuthorBanner
Write-Banner "CORP AD LAB BUILDER v3.1 — Role: $Role"
Write-Step "Started at $(Get-Date)"

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
Write-AuthorBanner
