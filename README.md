# rustdesk-server-debian

Self-hosted [RustDesk Server OSS](https://github.com/rustdesk/rustdesk-server) on **Debian 13 amd64** using Docker Compose.  
A clean, modular, security-first deployment — zero cost, no proprietary dependencies.

---

## Features

- **100% free** — RustDesk Server OSS only, no Pro license required
- **Docker Compose** with host networking for correct UDP hole-punching
- **Modular scripts** — one file per task, easy to audit and modify
- **Combined single-file installer** — deploy with one script and a `.env` file
- **UFW firewall** — minimum required ports, every rule commented
- **SSH hardening** — key-only auth, no root login, sshd drop-in config
- **fail2ban** — SSH brute-force protection
- **Unattended-upgrades** — automatic security patches only
- **Idempotent** — safe to re-run without breaking things
- **Human-readable install summary** — PASS/FAIL/WARN per item at the end
- **Backup and restore scripts** — GPG-encrypted key backup included
- **Windows SSH alias** — connect with `ssh rustdesk` from PowerShell

---

> **Platform:** Debian 13 (trixie) amd64  
> **Cost:** Zero — uses RustDesk OSS + Docker CE  
> **Networking:** Docker host mode (required for UDP hole-punching)  
> **No paid features, no web panel, no third-party services**

---

## Quick Start

```bash
# 1. Clone the repo onto the server (or copy the combined installer)
git clone https://github.com/<you>/rustdesk-server-debian.git
cd rustdesk-server-debian

# 2. Configure
cp .env.example .env
nano .env          # set SERVER_IP at minimum

# 3. Add your SSH public key (before hardening!)
ssh-copy-id -p 2222 -i ~/.ssh/id_ed25519.pub rdadmin@<SERVER_IP>

# 4. Run the installer (as root)
sudo bash install.sh

# 5. Validate
sudo bash validate.sh
```

---

## Prerequisites

Before running the installer:

- Fresh Debian 13 amd64 server (VPS, bare-metal, or VM)
- Root or sudo access
- Your SSH public key ready (generate with `ssh-keygen -t ed25519`)
- Server's public IP address or FQDN
- Cloud provider firewall allows inbound: TCP 21115, 21116, 21117 and UDP 21116
- Outbound internet access from the server (to pull Docker images)

---

## Full Installation Flow

```
01-packages.sh   — install curl, ufw, openssh-server, fail2ban, etc.
02-docker.sh     — Docker Engine + Compose plugin (official apt repo)
03-user.sh       — create non-root admin user, lock password
04-ssh.sh        — key-only auth, no root, sshd drop-in config
05-firewall.sh   — UFW rules (SSH first, then RustDesk ports)
06-compose.sh    — write compose.yml + .env to /opt/rustdesk/
07-services.sh   — start containers, configure fail2ban, sysctl, MOTD
08-keys.sh       — wait for key generation, display client config
09-summary.sh    — print PASS/FAIL/WARN summary for every step
```

See [docs/INSTALL-FLOW.md](docs/INSTALL-FLOW.md) for detailed step-by-step documentation.

---

## Single-File Installer

For servers where cloning a repo is inconvenient:

```bash
# On your local machine: build the combined installer
bash build-single.sh
# Output: dist/rustdesk-install.sh

# Deploy
scp dist/rustdesk-install.sh root@<SERVER_IP>:/tmp/
scp .env root@<SERVER_IP>:/tmp/rustdesk-install.env
ssh root@<SERVER_IP> 'bash /tmp/rustdesk-install.sh'
```

The combined installer contains all script logic in a single file and produces the same result as the modular install.

---

## Repo Layout

```
rustdesk-server-debian/
├── README.md                         — this file
├── LICENSE                           — MIT
├── .gitignore
├── .env.example                      — configuration template
├── install.sh                        — main installer (sources scripts/)
├── build-single.sh                   — combines scripts into dist/
├── validate.sh                       — post-install health check
│
├── dist/
│   └── rustdesk-install.sh           — generated combined installer
│
├── scripts/
│   ├── lib-common.sh                 — shared helpers and status tracking
│   ├── 00-preflight.sh               — pre-flight checks
│   ├── 01-packages.sh                — base package install
│   ├── 02-docker.sh                  — Docker Engine + Compose plugin
│   ├── 03-user-hardening.sh          — admin user creation
│   ├── 04-ssh-hardening.sh           — SSH key-only hardening
│   ├── 05-firewall.sh                — UFW firewall rules
│   ├── 06-rustdesk-compose.sh        — deploy compose.yml to /opt/rustdesk/
│   ├── 07-start-services.sh          — start containers + system services
│   ├── 08-show-keys.sh               — display client config and keys
│   └── 09-final-status.sh            — install summary printer
│
├── docker/
│   └── compose.yml                   — reference Docker Compose template
│
├── backup/
│   └── backup-rustdesk-keys.sh       — GPG-encrypted key backup
│
├── restore/
│   └── restore-rustdesk-keys.sh      — key restore with container restart
│
├── docs/
│   ├── INSTALL-FLOW.md               — detailed step documentation
│   ├── FIREWALL.md                   — port reference and UFW explanation
│   ├── SSH.md                        — SSH hardening and connection guide
│   ├── BACKUP-AND-RESTORE.md         — key backup procedures
│   ├── CLIENT-CONFIG.md              — RustDesk client onboarding
│   └── TROUBLESHOOTING.md            — common problems and fixes
│
└── examples/
    └── windows-ssh-config-example.txt — SSH config for Windows users
```

---

## Security Defaults

| Feature | Setting |
|---------|---------|
| SSH password auth | Disabled |
| SSH root login | Disabled |
| SSH port | 2222 (configurable) |
| SSH auth method | Public key only |
| UFW default incoming | Deny |
| UFW default outgoing | Allow |
| fail2ban SSH | Enabled (5 retries, 1h ban) |
| Unattended upgrades | Security patches only |
| RustDesk web ports (21118/21119) | Closed |
| RustDesk Pro/API port (21114) | Closed |
| Docker log rotation | 10 MB × 3 files per container |

---

## Firewall Ports

| Port | Proto | Service | Purpose | Open? |
|------|-------|---------|---------|-------|
| `SSH_PORT` | TCP | sshd | Admin remote access | Yes |
| 21115 | TCP | hbbs | NAT type test | Yes |
| 21116 | TCP | hbbs | ID registration and heartbeat | Yes |
| 21116 | UDP | hbbs | UDP hole punching (direct connections) | Yes |
| 21117 | TCP | hbbr | Relay traffic (fallback) | Yes |
| 21114 | TCP | — | Pro/API server — not used in OSS | **No** |
| 21118 | TCP | — | Web client (hbbs) — not enabled | **No** |
| 21119 | TCP | — | Web client (hbbr) — not enabled | **No** |

See [docs/FIREWALL.md](docs/FIREWALL.md) for full explanation.

---

## SSH Hardening Summary

- Password authentication: **disabled**
- Root login: **disabled**
- Authentication: **public key only**
- Config drop-in: `/etc/ssh/sshd_config.d/99-hardened.conf`  
  (survives `apt upgrade openssh-server`)
- Legal banner displayed before authentication

See [docs/SSH.md](docs/SSH.md) for connection instructions and details.

---

## RustDesk Client Setup

After install, the script displays everything clients need:

```
+----------------------------------------------------------------------+
|  RustDesk Client Configuration                                       |
+----------------------------------------------------------------------+
|  ID Server  : 203.0.113.10                                           |
|  Key        : <ed25519 public key>                                   |
+----------------------------------------------------------------------+
```

In the RustDesk client:  
**Settings → Network → ID Server** = your server IP  
**Settings → Network → Key** = contents of `id_ed25519.pub`  
Leave **Relay Server** blank.

See [docs/CLIENT-CONFIG.md](docs/CLIENT-CONFIG.md) for step-by-step onboarding.

---

## Where the RustDesk Key is Stored

```
/opt/rustdesk/data/id_ed25519.pub   ← public key (paste into clients)
/opt/rustdesk/data/id_ed25519       ← private key (never share)
```

Retrieve the public key at any time:

```bash
cat /opt/rustdesk/data/id_ed25519.pub

# Or with the shell alias (after login as admin user)
rdkey
```

---

## Validation

```bash
sudo bash validate.sh
```

Checks and reports on: Docker daemon, container status, all expected ports listening, all expected ports closed, UFW rules, SSH daemon and port, key file existence and permissions.

---

## Backup and Restore

```bash
# Back up keys (encrypted with GPG)
sudo bash backup/backup-rustdesk-keys.sh

# Restore keys from backup
sudo bash restore/restore-rustdesk-keys.sh /path/to/backup.tar.gz.gpg
```

See [docs/BACKUP-AND-RESTORE.md](docs/BACKUP-AND-RESTORE.md) for manual procedures.

**Back up immediately after install.** If the key pair is lost, all clients must be reconfigured.

---

## Windows SSH Alias

Add this to `C:\Users\<you>\.ssh\config`:

```
Host rustdesk
  HostName <SERVER_IP>
  User rdadmin
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

Then connect with:

```powershell
ssh rustdesk
```

A ready-to-edit example is in [`examples/windows-ssh-config-example.txt`](examples/windows-ssh-config-example.txt).

---

## Useful Commands After Install

```bash
# Container status
docker ps --filter name=rustdesk

# Live logs
docker logs rustdesk-hbbs -f --tail 50
docker logs rustdesk-hbbr -f --tail 50

# Update RustDesk to latest version
docker compose -f /opt/rustdesk/compose.yml pull
docker compose -f /opt/rustdesk/compose.yml up -d

# UFW rules
ufw status verbose

# Retrieve public key
cat /opt/rustdesk/data/id_ed25519.pub

# Shell aliases (available after login as admin user)
rdps          # docker ps for RustDesk containers
rdkey         # print public key
rdlogs        # tail hbbs logs
rdlogs-r      # tail hbbr logs
rdrestart     # restart both containers
rdpull        # pull new images and restart
```

---

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for help with:

- Docker installation failures
- Container not starting
- Clients cannot connect
- SSH lockout prevention
- Missing key files
- UFW blocking legitimate traffic

---

## Customisation Ideas

All free. All optional.

- **Change SSH port** — edit `SSH_PORT` in `.env` before install
- **Custom admin username** — edit `ADMIN_USER` in `.env`
- **Pin Docker image version** — edit `image:` in `docker/compose.yml` (e.g., `rustdesk/rustdesk-server:1.1.11`)
- **Larger log files** — increase `DOCKER_LOG_MAX_SIZE` and `DOCKER_LOG_MAX_FILE` in `.env`
- **Email security patch notices** — set `UNATTENDED_UPGRADES_EMAIL` in `.env`
- **Allow reboot after kernel updates** — set `Automatic-Reboot "true"` in `/etc/apt/apt.conf.d/50unattended-upgrades`
- **Enable web client ports** — add UFW rules for 21118/21119 (requires Pro for full feature set)

---

## Disclaimer

This repo automates the setup of RustDesk Server OSS. It is tested against Debian 13 amd64. It makes opinionated security choices. Review the scripts before running them on a production machine. You are responsible for your own deployment.

RustDesk is a separate open-source project — this repo has no affiliation with the RustDesk project or Purslane Ltd.
