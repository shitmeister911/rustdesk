# Installation Flow

A complete walkthrough of what happens during installation — what each script does, in what order, and what changes are made to the system.

---

## Two Ways to Run

### Option A — Modular (from repo clone)

Clone the repo, configure `.env`, run `install.sh`. Each step runs from its own file.

```bash
git clone https://github.com/<you>/rustdesk-server-debian.git
cd rustdesk-server-debian
cp .env.example .env && nano .env
sudo bash install.sh
```

### Option B — Combined single-file installer

Copy one file to the server and run it. No repo clone needed.

```bash
# On your local machine: build the combined installer
bash build-single.sh
# Output: dist/rustdesk-install.sh

# Copy to server
scp dist/rustdesk-install.sh root@<SERVER_IP>:/tmp/
scp .env root@<SERVER_IP>:/tmp/rustdesk-install.env

# Run on server
ssh root@<SERVER_IP> 'bash /tmp/rustdesk-install.sh'
```

Both options run identical logic — `build-single.sh` simply concatenates the modular files into one.

---

## Installation Steps

### Step 00 — Pre-flight checks (`scripts/00-preflight.sh`)

Verifies conditions before making any changes:

- Script is running as root
- OS is Debian (warns if not)
- Architecture is x86_64 / amd64
- Internet connectivity reaches Docker's CDN
- `SERVER_IP` is set in the environment
- Logs hostname and runtime info

Exits immediately if any critical check fails.

---

### Step 01 — Base packages (`scripts/01-packages.sh`)

Installs required system packages via `apt-get`. Idempotent — checks each package before installing.

Installed packages:

| Package | Purpose |
|---------|---------|
| `curl` | Downloads Docker GPG key |
| `wget` | Alternative downloader |
| `gnupg` | Verifies Docker apt repo signature |
| `ca-certificates` | Trusts HTTPS apt sources |
| `lsb-release` | Detects Debian codename for Docker repo |
| `ufw` | Host firewall |
| `openssh-server` | Remote admin access |
| `unattended-upgrades` | Automatic security patches |
| `apt-listchanges` | Shows changelogs for auto upgrades |
| `fail2ban` | Bans IPs after repeated auth failures |
| `jq` | JSON parsing used in validate.sh |
| `net-tools` | netstat — legacy compatibility |
| `iproute2` | ss, ip — used in validate.sh |

---

### Step 02 — Docker Engine (`scripts/02-docker.sh`)

Installs Docker Engine and the Docker Compose plugin from Docker's official apt repository.

Key behaviour:

- Adds Docker's GPG key to `/etc/apt/keyrings/docker.gpg`
- Detects the Debian codename (`trixie` for Debian 13)
- **Debian 13 fallback:** If `trixie` is not yet listed in Docker's repo (can happen shortly after a new Debian release), falls back to `bookworm` — Docker packages are binary-compatible with trixie on amd64
- Installs: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`
- Enables and starts the Docker daemon
- Adds `ADMIN_USER` to the `docker` group

---

### Step 03 — Admin user (`scripts/03-user-hardening.sh`)

Creates a non-root admin user for server management.

- Creates user `ADMIN_USER` (default: `rdadmin`) if not already present
- Adds to `sudo` and `docker` groups
- Locks the account password (key-only SSH enforced in the next step)
- Creates `~/.ssh/` with permissions 700
- Creates `~/.ssh/authorized_keys` with permissions 600
- **Warns** if `authorized_keys` is empty — you must add your public key before the next step

---

### Step 04 — SSH hardening (`scripts/04-ssh-hardening.sh`)

Hardens the OpenSSH server configuration.

**Safety gate:** Refuses to disable password auth if `authorized_keys` is empty. This prevents permanent lockout.

Changes made:

- Backs up original `/etc/ssh/sshd_config` to `sshd_config.bak`
- Updates `Port` to `SSH_PORT` in the base config
- Writes hardening drop-in to `/etc/ssh/sshd_config.d/99-hardened.conf`:
  - `PasswordAuthentication no`
  - `PermitRootLogin no`
  - `X11Forwarding no`
  - `AllowTcpForwarding no`
  - `MaxAuthTries 3`
  - `LoginGraceTime 30`
  - Session keepalive settings
- Writes legal banner to `/etc/issue.net`
- Validates config with `sshd -t` before restarting
- Restarts SSH daemon

---

### Step 05 — UFW firewall (`scripts/05-firewall.sh`)

Configures the host firewall with minimum required ports.

Rule order:

1. **Reset UFW** to clean state
2. **SSH rule first** — prevents lockout when UFW is enabled
3. RustDesk hbbs rules (21115/tcp, 21116/tcp, 21116/udp)
4. RustDesk hbbr rule (21117/tcp)
5. Default policies: deny incoming, allow outgoing
6. **Enable UFW**

Ports 21114, 21118, 21119 are explicitly left closed and documented.

---

### Step 06 — Compose setup (`scripts/06-rustdesk-compose.sh`)

Deploys runtime files to `/opt/rustdesk/`:

- Creates `/opt/rustdesk/` (deploy directory)
- Creates `RUSTDESK_DATA_DIR` (default: `/opt/rustdesk/data`) with permissions 750
- Writes `/opt/rustdesk/compose.yml` with values from `.env` substituted in
- Writes `/opt/rustdesk/.env` with runtime variables (permissions 600)

---

### Step 07 — Start services (`scripts/07-start-services.sh`)

Pulls images and starts containers, then configures supporting services.

- `docker compose pull` — pulls latest RustDesk OSS images
- `docker compose up -d` — starts hbbs and hbbr
- Writes `/etc/sysctl.d/99-rustdesk-hardening.conf` and applies it
- Configures fail2ban jail for SSH
- Configures unattended-upgrades (security patches only)
- Writes MOTD to `/etc/update-motd.d/99-rustdesk`
- Writes shell aliases to `~/.bash_aliases` for `ADMIN_USER`

---

### Step 08 — Show keys (`scripts/08-show-keys.sh`)

Waits for hbbs to generate its ed25519 key pair (up to 30 seconds), then displays:

- RustDesk public key — paste into clients
- Server IP — ID server address for clients
- SSH host public key — for backup reference
- Backup reminder with instructions

---

### Step 09 — Final summary (`scripts/09-final-status.sh`)

Prints a formatted installation summary with PASS/FAIL/WARN/INFO status for every check performed during the install, plus next-step instructions.

---

## System Changes Summary

| Location | Change |
|----------|--------|
| `/etc/apt/keyrings/docker.gpg` | Docker GPG key |
| `/etc/apt/sources.list.d/docker.list` | Docker apt source |
| `/etc/ssh/sshd_config` | SSH port updated |
| `/etc/ssh/sshd_config.d/99-hardened.conf` | SSH hardening drop-in |
| `/etc/issue.net` | Legal banner |
| `/etc/sysctl.d/99-rustdesk-hardening.conf` | Kernel hardening |
| `/etc/fail2ban/jail.d/99-rustdesk-sshd.conf` | fail2ban SSH jail |
| `/etc/apt/apt.conf.d/50unattended-upgrades` | Auto security updates |
| `/etc/update-motd.d/99-rustdesk` | Login notice |
| `/opt/rustdesk/compose.yml` | Docker Compose file |
| `/opt/rustdesk/.env` | Runtime environment |
| `/opt/rustdesk/data/` | RustDesk keys + database |
| `/home/<admin>/.bash_aliases` | Shell aliases |

---

## After Install

```bash
# Test SSH in a new terminal FIRST
ssh -p 2222 rdadmin@<SERVER_IP>

# Validate the deployment
sudo bash validate.sh

# Back up keys immediately
sudo bash backup/backup-rustdesk-keys.sh

# Configure RustDesk clients
# See: docs/CLIENT-CONFIG.md
```
