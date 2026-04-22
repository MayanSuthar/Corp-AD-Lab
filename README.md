<div align="center">

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=700&size=22&pause=1000&color=E94560&center=true&vCenter=true&width=750&lines=Active+Directory+Penetration+Testing+Lab;Fully+Automated+%7C+VMware+%7C+Windows+Server+2022;5+Machines+%7C+20%2B+Attack+Techniques;by+NullyBlissful" alt="Typing SVG" />

<br/>

![Machines](https://img.shields.io/badge/Machines-5_VMs-E94560?style=for-the-badge&logo=windows&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-VMware_Workstation-607078?style=for-the-badge&logo=vmware&logoColor=white)
![OS](https://img.shields.io/badge/OS-Windows_Server_2022-0078d4?style=for-the-badge&logo=windows&logoColor=white)
![Attacker](https://img.shields.io/badge/Attacker-Kali_Linux-557C94?style=for-the-badge&logo=kalilinux&logoColor=white)
![Automated](https://img.shields.io/badge/Setup-Fully_Automated-3fb950?style=for-the-badge)

> *"I am not a body. I am not even the mind." — NullyBlissful*

**[📝 Medium Writeups](https://medium.com/@mayan230848)** · **[🔗 LinkedIn](http://linkedin.com/in/mayan-suthar-5625b1229/)** · **[⚔️ Web Vulnerabilities](https://github.com/MayanSuthar/Web-Vulnerability)** · **[🔺 Privilege Escalation](https://github.com/MayanSuthar/Escalation)**

</div>

---

## 📖 What Is This?

A **fully automated, self-contained Active Directory home lab** that simulates a real corporate network for penetration testing practice. Built from scratch after 205+ boxes across HackTheBox, TryHackMe, VulnHub, PG Play, and PG Practice.

One PowerShell script configures every Windows machine automatically. One bash script sets up the Kali attacker. You focus on attacking, not on setup.

---

## 🎯 What You Will Practice

| Category | Techniques |
|----------|-----------|
| **Password Attacks** | SSH & RDP brute force, HTTP login form attacks, Net-NTLMv2 capture, NTLM relay |
| **Hash Attacks** | NTLM cracking, Pass-the-Hash, Net-NTLMv2 cracking |
| **Windows PrivEsc** | Service binary hijacking, Unquoted service paths, DLL hijacking, Scheduled task abuse, Credential hunting, Registry creds |
| **AD Enumeration** | PowerView, BloodHound, SharpHound, manual LDAP, SPN enumeration |
| **AD Auth Attacks** | Password spray, AS-REP Roasting, Kerberoasting, Silver Tickets, DCSync |
| **Lateral Movement** | WMI, WinRM, PsExec, Pass-the-Hash, Overpass-the-Hash, Pass-the-Ticket, DCOM |
| **Persistence** | Golden Ticket, Shadow Copies, DCSync |
| **Tunneling & Pivoting** | SSH tunnels, Chisel, Ligolo-ng, sshuttle, Netsh port proxy |
| **DPI Bypass** | Chisel HTTP tunnel, dnscat2 DNS tunnel |
| **Full Chain** | External recon → foothold → pivot → AD compromise → Domain Admin |

---

## 🗺️ Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   ATTACKER MACHINE                          │
│              Kali Linux  192.168.56.5                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
          ┌────────────▼────────────┐
          │   VMnet1 - External     │  192.168.56.0/24
          └────────────┬────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
    ┌──────▼──────┐         ┌──────▼──────┐
    │  MAILSRV1   │         │   WEBSRV1   │
    │ 192.168.56.10│        │ 192.168.56.11│
    │  10.10.10.11 │        │  10.10.10.12 │
    │ (dual-homed) │        │ (dual-homed) │
    └──────┬───────┘        └──────┬───────┘
           │                       │
           └──────────┬────────────┘
                      │
          ┌───────────▼─────────────┐
          │   VMnet2 - Internal     │  10.10.10.0/24
          └───────────┬─────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
  ┌─────▼─────┐ ┌────▼─────┐ ┌────▼─────┐
  │   DC01    │ │ CLIENT01 │ │ CLIENT02 │
  │10.10.10.10│ │10.10.10.20│ │10.10.10.30│
  │corp.local │ │  Domain  │ │  Domain  │
  │    DC     │ │Workstation│ │Workstation│
  └───────────┘ └──────────┘ └──────────┘
```

---

## 🖥️ Virtual Machine Overview

| VM | OS | Role | IPs | Key Vulnerabilities |
|----|----|----|-----|---------------------|
| **DC01** | Windows Server 2022 | Domain Controller | `10.10.10.10` | Kerberoastable SPNs, AS-REP users, DCSync target |
| **WEBSRV1** | Windows Server 2022 | Web Server / Pivot | `192.168.56.11` / `10.10.10.12` | Weak SSH, HTTP login form, credential files, dual-homed pivot |
| **MAILSRV1** | Windows Server 2022 | Mail Server / Pivot | `192.168.56.10` / `10.10.10.11` | Credential bait shares, dual-homed pivot |
| **CLIENT01** | Windows 10 Enterprise | Vulnerable Workstation | `10.10.10.20` | Service hijacking, unquoted paths, scheduled tasks, credential hunting |
| **CLIENT02** | Windows 10 Enterprise | Lateral Movement Target | `10.10.10.30` | itadmin local admin, Pass-the-Hash enabled |

---

## 👥 Domain Users (corp.local)

| Username | Password | Type | Attack Vector |
|----------|----------|------|---------------|
| `j.watson` | `Password123` | Standard user | Password spray, enumeration |
| `m.johnson` | `Password123` | Standard user | Password spray |
| `t.richards` | `Password123` | Standard user | Password spray |
| `s.noauth` | `Summer2023!` | Standard user | **AS-REP Roasting** (pre-auth disabled) |
| `itadmin` | `Sup3rS3cur3!` | IT Admin | **Pass-the-Hash**, lateral movement |
| `d.backup` | `Backup2023!` | **Domain Admin** | Final escalation target |
| `svc_sql` | `Sqlpassword1` | Service account | **Kerberoasting** (MSSQLSvc SPN) |
| `svc_web` | `Webservice1` | Service account | **Kerberoasting** (HTTP SPN) |

---

## ⚙️ Requirements — Download These Free

> **No Windows ISO download links are included here intentionally.**  
> Microsoft provides free evaluation ISOs directly. Use the official links below.

| Software | Download | Notes |
|----------|----------|-------|
| **VMware Workstation Pro** | [broadcom.com](https://www.vmware.com/products/desktop-hypervisor/workstation-and-fusion) | Free for personal use since 2024 |
| **Windows Server 2022** | [microsoft.com/evalcenter](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) | Free 180-day evaluation ISO |
| **Windows 10 Enterprise** | [microsoft.com/evalcenter](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise) | Free 90-day evaluation ISO |
| **Kali Linux** | [kali.org](https://www.kali.org/get-kali/#kali-virtual-machines) | Free — download VMware OVA |

**Minimum host requirements:**
- RAM: 16 GB (32 GB recommended)
- Disk: 250 GB free
- CPU: 4 cores (8 recommended, with virtualisation enabled in BIOS)

---

## 🚀 Quick Start

### Step 1 — Create VMware Networks

```
VMware → Edit → Virtual Network Editor → Add Network

VMnet1  Type: Host-only  Subnet: 192.168.56.0/24  DHCP: OFF
VMnet2  Type: Host-only  Subnet: 10.10.10.0/24    DHCP: OFF
```

### Step 2 — Build Each Machine (in order)

```
1. DC01     → Windows Server 2022 → VMnet2 only
2. WEBSRV1  → Windows Server 2022 → VMnet1 + VMnet2
3. MAILSRV1 → Windows Server 2022 → VMnet1 + VMnet2
4. CLIENT01 → Windows 10 Ent     → VMnet2 only
5. CLIENT02 → Windows 10 Ent     → VMnet2 only
6. Kali     → Import OVA         → VMnet1 only
```

### Step 3 — Run the Automation Script on Each Windows VM

```powershell
# Copy Setup-CorpLab.ps1 to each VM via VMware clipboard or shared folder
# Then run with the correct role for each machine:

Set-ExecutionPolicy Bypass -Scope Process -Force

.\Setup-CorpLab.ps1 -Role DC01         # Phase 1 — installs AD, reboots
.\Setup-CorpLab.ps1 -Role DC01Phase2   # Phase 2 — creates users, SPNs, shares
.\Setup-CorpLab.ps1 -Role WEBSRV1
.\Setup-CorpLab.ps1 -Role MAILSRV1
.\Setup-CorpLab.ps1 -Role CLIENT01
.\Setup-CorpLab.ps1 -Role CLIENT02
```

### Step 4 — Set Up Kali

```bash
sudo bash setup-kali.sh
# Installs: Hydra, Hashcat, Impacket, CrackMapExec, BloodHound,
#           evil-winrm, Chisel, Ligolo-ng, Responder, kerbrute,
#           PowerView, SharpHound, winPEAS, Mimikatz and more
```

### Step 5 — Take Snapshots

```
VMware → VM → Snapshot → Take Snapshot → "Clean - Lab Ready"
Do this for ALL 6 machines before you start attacking.
```

---

## 📂 Repository Structure

```
Corp-AD-Lab/
│
├── README.md                    ← You are here
├── Setup-CorpLab.ps1            ← Windows automation script (all roles)
├── setup-kali.sh                ← Kali attacker setup script
└── docs/
    └── AD-Lab-Build-Guide.pdf   ← Full step-by-step PDF guide
```

---

## 📋 Full Setup Guide

The complete step-by-step build guide including:
- Detailed VMware configuration for every machine
- Windows Server 2022 installation walkthrough
- All PowerShell commands with explanations
- Full attack walkthroughs for every technique
- Quick reference credentials and Hashcat modes

👉 **[Download AD-Lab-Build-Guide.pdf](./docs/AD-Lab-Build-Guide.pdf)**

---

## 🔗 Related Repositories

> Part of the **NullyBlissful Penetration Testing Notes Series**

[![Web Vulnerabilities](https://img.shields.io/badge/Web_Vulnerabilities-LFI_%7C_SQLi_%7C_CMDi_%7C_Uploads-E94560?style=flat-square)](https://github.com/MayanSuthar/Web-Vulnerability)
[![Privilege Escalation](https://img.shields.io/badge/Privilege_Escalation-Linux_%26_Windows-3fb950?style=flat-square)](https://github.com/MayanSuthar/Escalation)
[![Pivoting](https://img.shields.io/badge/Pivoting-SSH_%7C_Chisel_%7C_Ligolo-1f6feb?style=flat-square)](https://github.com/MayanSuthar/Pivoting)
[![Shell Upgrade](https://img.shields.io/badge/Shell_Upgrade-TTY_Stabilisation-d29922?style=flat-square)](https://github.com/MayanSuthar/Shell-Upgrade)
[![Methodology](https://img.shields.io/badge/OSCP_Methodology-Full_Attack_Playbook-8957e5?style=flat-square)](https://github.com/MayanSuthar/OSCP-Methodology)

---

## ⚠️ Legal Disclaimer

This lab is for **educational purposes only** in a controlled, isolated environment.

- All VMs run on a private host-only network with no internet access
- Never use these techniques against systems you do not own or have explicit permission to test
- The Windows evaluation ISOs are downloaded directly from Microsoft — no modified or pirated software is distributed here
- This repository contains only automation scripts and documentation — no proprietary software

---

## 👤 Author

<div align="center">

**NullyBlissful**

*"Null is peace. Bliss is the overflow."*

[![Medium](https://img.shields.io/badge/Medium-Writeups-black?style=for-the-badge&logo=medium)](https://medium.com/@mayan230848)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-0077b5?style=for-the-badge&logo=linkedin)](http://linkedin.com/in/mayan-suthar-5625b1229/)
[![GitHub](https://img.shields.io/badge/GitHub-MayanSuthar-181717?style=for-the-badge&logo=github)](https://github.com/MayanSuthar)

*205+ machines solved across HTB · THM · VulnHub · PG Play · PG Practice*

</div>

---

<div align="center">

**If this helped you — drop a ⭐ star. It means a lot.**

</div>
