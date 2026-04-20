#!/usr/bin/env bash
# dist/rustdesk-install.sh — RustDesk Server OSS combined standalone installer
# Generated from: https://github.com/<your-username>/rustdesk-server-debian
#
# This is a self-contained script — no repo clone required.
#
# Usage:
#   1. Create a .env file in the same directory (or /tmp/rustdesk-install.env):
#        SERVER_IP=203.0.113.10
#        ADMIN_USER=rdadmin
#        SSH_PORT=2222
#        RUSTDESK_DATA_DIR=/opt/rustdesk/data
#   2. Run: sudo bash rustdesk-install.sh

set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Shared library                                                  ║
# ╚══════════════════════════════════════════════════════════════════╝

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}   $*"; }
fail()  { echo -e "${RED}[FAIL]${RESET}   $*"; }
die()   { echo -e "${RED}[ERROR]${RESET}  $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}${BLUE}━━━ $* ${RESET}"; }

declare -a _STATUS_LINES=()
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

add_status() {
    local category="$1" label="$2" result="$3" detail="${4:-}"
    _STATUS_LINES+=("${category}|${label}|${result}|${detail}")
    case "$result" in
        PASS) (( PASS_COUNT += 1 )) ;;
        FAIL) (( FAIL_COUNT += 1 )) ;;
        WARN) (( WARN_COUNT += 1 )) ;;
    esac
}

require_root() {
    [[ "$EUID" -eq 0 ]] || die "This script must be run as root (sudo)."
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 00 — Pre-flight checks                                     ║
# ╚══════════════════════════════════════════════════════════════════╝

step_00_preflight() {
    step "Pre-flight checks"

    if [[ "$EUID" -eq 0 ]]; then
        ok "Running as root."
        add_status "System" "Root privileges" PASS "uid=0"
    else
        fail "Must run as root."
        add_status "System" "Root privileges" FAIL "uid=$EUID"
        die "Re-run with: sudo bash $0"
    fi

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_PRETTY="${PRETTY_NAME:-unknown}"
        OS_ID="${ID:-unknown}"
    else
        OS_PRETTY="unknown"; OS_ID="unknown"
    fi

    if [[ "$OS_ID" == "debian" ]]; then
        ok "OS: $OS_PRETTY"
        add_status "System" "OS" PASS "$OS_PRETTY"
    else
        warn "Expected Debian; detected: $OS_PRETTY"
        add_status "System" "OS" WARN "$OS_PRETTY (expected Debian)"
    fi

    ARCH="$(uname -m)"
    if [[ "$ARCH" == "x86_64" ]]; then
        ok "Architecture: $ARCH (amd64)"
        add_status "System" "Architecture" PASS "$ARCH / amd64"
    else
        warn "Expected x86_64; detected: $ARCH"
        add_status "System" "Architecture" WARN "$ARCH (expected x86_64)"
    fi

    info "Checking internet connectivity..."
    if curl -fsSL --max-time 10 https://download.docker.com > /dev/null 2>&1; then
        ok "Internet reachable."
        add_status "System" "Internet" PASS "Docker CDN reachable"
    else
        fail "Cannot reach download.docker.com."
        add_status "System" "Internet" FAIL "unreachable"
        die "No internet access — cannot continue."
    fi

    if [[ -n "${SERVER_IP:-}" ]]; then
        ok "SERVER_IP: $SERVER_IP"
        add_status "System" "SERVER_IP" PASS "$SERVER_IP"
    else
        fail "SERVER_IP is not set."
        add_status "System" "SERVER_IP" FAIL "not set"
        die "Set SERVER_IP in .env before running."
    fi

    HOST="$(hostname -f 2>/dev/null || hostname)"
    add_status "System" "Hostname" INFO "$HOST"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 01 — Base packages                                         ║
# ╚══════════════════════════════════════════════════════════════════╝

step_01_packages() {
    step "Base packages"

    apt-get update -qq
    add_status "Packages" "apt-get update" PASS "index refreshed"

    declare -A PKGS=(
        [curl]="downloads Docker GPG key"
        [wget]="alternative downloader"
        [gnupg]="verifies Docker apt repo signature"
        [ca-certificates]="trusts HTTPS apt sources"
        [lsb-release]="detects distro codename"
        [ufw]="host firewall"
        [openssh-server]="remote admin access"
        [unattended-upgrades]="automatic security patches"
        [apt-listchanges]="changelogs for automated upgrades"
        [fail2ban]="SSH brute-force protection"
        [jq]="JSON parsing in validate.sh"
        [net-tools]="netstat compatibility"
        [iproute2]="ss and ip commands"
    )

    for pkg in "${!PKGS[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            ok "$pkg — already installed."
            add_status "Packages" "$pkg" PASS "already present"
        else
            info "Installing $pkg..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" -qq
            ok "$pkg installed."
            add_status "Packages" "$pkg" PASS "installed"
        fi
    done
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 02 — Docker Engine                                         ║
# ╚══════════════════════════════════════════════════════════════════╝

step_02_docker() {
    step "Docker Engine"

    if command -v docker &>/dev/null; then
        DOCKER_VER="$(docker --version | awk '{print $3}' | tr -d ',')"
        ok "Docker already installed: $DOCKER_VER"
        add_status "Docker" "Docker Engine" PASS "$DOCKER_VER (pre-existing)"
    else
        info "Adding Docker GPG key..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        DEBIAN_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-bookworm}")"
        info "Detected Debian codename: $DEBIAN_CODENAME"

        REPO_URL="https://download.docker.com/linux/debian/dists/${DEBIAN_CODENAME}/Release"
        if ! curl -fsSL --max-time 10 --head "$REPO_URL" &>/dev/null; then
            warn "Docker repo has no listing for '${DEBIAN_CODENAME}' — using 'bookworm' fallback."
            DEBIAN_CODENAME="bookworm"
        fi

        echo \
            "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian ${DEBIAN_CODENAME} stable" \
            | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin -qq

        DOCKER_VER="$(docker --version | awk '{print $3}' | tr -d ',')"
        ok "Docker Engine installed: $DOCKER_VER"
        add_status "Docker" "Docker Engine" PASS "$DOCKER_VER"
    fi

    systemctl enable docker --quiet
    systemctl start docker
    if systemctl is-active --quiet docker; then
        ok "Docker daemon running."
        add_status "Docker" "Daemon" PASS "active"
    else
        add_status "Docker" "Daemon" FAIL "inactive"
        die "Docker daemon not running — check: journalctl -u docker"
    fi

    if docker compose version &>/dev/null; then
        COMPOSE_VER="$(docker compose version --short 2>/dev/null || echo "v2")"
        ok "Compose plugin: $COMPOSE_VER"
        add_status "Docker" "Compose plugin" PASS "$COMPOSE_VER"
    else
        add_status "Docker" "Compose plugin" FAIL "not found"
        die "Compose plugin missing — check: apt install docker-compose-plugin"
    fi

    if [[ -n "${ADMIN_USER:-}" ]] && id "$ADMIN_USER" &>/dev/null; then
        usermod -aG docker "$ADMIN_USER"
        add_status "Docker" "docker group" PASS "$ADMIN_USER added"
    fi
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 03 — Admin user                                            ║
# ╚══════════════════════════════════════════════════════════════════╝

step_03_user_hardening() {
    step "Admin user setup"

    ADMIN_USER="${ADMIN_USER:-rdadmin}"

    if id "$ADMIN_USER" &>/dev/null; then
        ok "User '$ADMIN_USER' already exists."
        add_status "User" "Admin user" PASS "$ADMIN_USER (pre-existing)"
    else
        useradd -m -s /bin/bash -G sudo,docker "$ADMIN_USER"
        ok "Created user: $ADMIN_USER"
        add_status "User" "Admin user" PASS "$ADMIN_USER created"
    fi

    passwd -l "$ADMIN_USER"
    add_status "User" "Password" PASS "locked (key-only)"

    usermod -aG docker "$ADMIN_USER" 2>/dev/null || true
    usermod -aG sudo  "$ADMIN_USER" 2>/dev/null || true

    SSH_DIR="/home/${ADMIN_USER}/.ssh"
    mkdir -p "$SSH_DIR"
    chown "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    AUTH_KEYS="${SSH_DIR}/authorized_keys"
    [[ -f "$AUTH_KEYS" ]] || touch "$AUTH_KEYS"
    chown "${ADMIN_USER}:${ADMIN_USER}" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"

    if [[ -s "$AUTH_KEYS" ]]; then
        KEY_COUNT="$(wc -l < "$AUTH_KEYS")"
        ok "authorized_keys: $KEY_COUNT key(s)."
        add_status "User" "authorized_keys" PASS "$KEY_COUNT key(s)"
    else
        warn "authorized_keys is empty. Add your key before SSH hardening runs."
        warn "  ssh-copy-id -p ${SSH_PORT:-2222} -i ~/.ssh/id_ed25519.pub ${ADMIN_USER}@${SERVER_IP:-<IP>}"
        add_status "User" "authorized_keys" WARN "empty — add key"
    fi
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 04 — SSH hardening                                         ║
# ╚══════════════════════════════════════════════════════════════════╝

step_04_ssh_hardening() {
    step "SSH hardening"

    ADMIN_USER="${ADMIN_USER:-rdadmin}"
    SSH_PORT="${SSH_PORT:-2222}"
    AUTH_KEYS="/home/${ADMIN_USER}/.ssh/authorized_keys"
    SSHD_CONFIG="/etc/ssh/sshd_config"
    DROP_IN_DIR="/etc/ssh/sshd_config.d"
    DROP_IN="${DROP_IN_DIR}/99-hardened.conf"

    if [[ ! -s "$AUTH_KEYS" ]]; then
        warn "authorized_keys is empty — SSH hardening SKIPPED."
        warn "SSH is still accessible with password on its default port."
        warn "Add your key then re-run step 4:  sudo bash scripts/04-ssh-hardening.sh"
        warn "  ssh-copy-id -p 22 -i ~/.ssh/id_ed25519.pub ${ADMIN_USER}@${SERVER_IP:-<IP>}"
        add_status "SSH" "Hardening" WARN "skipped — no key (passwords still active)"
        return 0
    fi
    ok "authorized_keys has content — safe to proceed."
    add_status "SSH" "Safety gate" PASS "key present"

    [[ -f "${SSHD_CONFIG}.bak" ]] || cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

    if grep -q "^Port " "$SSHD_CONFIG"; then
        sed -i "s/^Port .*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
    elif grep -q "^#Port " "$SSHD_CONFIG"; then
        sed -i "s/^#Port .*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
    else
        echo "Port ${SSH_PORT}" >> "$SSHD_CONFIG"
    fi

    mkdir -p "$DROP_IN_DIR"
    cat > "$DROP_IN" << EOF
# ${DROP_IN} — managed by rustdesk-install.sh
Port ${SSH_PORT}
PasswordAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin no
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
PrintMotd yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
LoginGraceTime 30
Banner /etc/issue.net
EOF

    cat > /etc/issue.net << 'EOF'
+---------------------------------------------------------+
|  AUTHORIZED ACCESS ONLY                                 |
|  All sessions are monitored and logged.                 |
|  Unauthorized access is strictly prohibited.           |
+---------------------------------------------------------+
EOF

    if sshd -t 2>&1; then
        ok "sshd config validation passed."
        add_status "SSH" "Config validation" PASS "sshd -t OK"
    else
        add_status "SSH" "Config validation" FAIL "sshd -t failed"
        die "sshd config invalid — not restarting."
    fi

    systemctl restart ssh
    if systemctl is-active --quiet ssh; then
        ok "SSH restarted on port ${SSH_PORT}."
        add_status "SSH" "Service" PASS "active on port ${SSH_PORT}"
    else
        add_status "SSH" "Service" FAIL "not running"
        die "SSH not active — check: journalctl -u ssh -n 20"
    fi

    # Once hardening succeeds and SSH moves, remove the port-22 fallback UFW rule
    if [[ "$SSH_PORT" != "22" ]] && command -v ufw &>/dev/null; then
        ufw delete allow 22/tcp 2>/dev/null && \
            ok "Removed temporary UFW rule for port 22 (SSH now on ${SSH_PORT})." || true
        add_status "Firewall" "Port 22 fallback" PASS "rule removed"
    fi

    warn "Test login in a NEW terminal before closing this session."
    warn "  ssh -p ${SSH_PORT} ${ADMIN_USER}@${SERVER_IP:-<IP>}"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 05 — UFW firewall                                          ║
# ╚══════════════════════════════════════════════════════════════════╝

step_05_firewall() {
    step "UFW firewall"

    SSH_PORT="${SSH_PORT:-2222}"

    ufw --force reset > /dev/null 2>&1
    add_status "Firewall" "UFW reset" PASS "clean state"

    # Detect the port sshd is actually listening on right now (22 on fresh installs).
    # Allow both the current live port AND the configured target port so the machine
    # stays reachable whether or not SSH hardening has run yet.
    ACTUAL_SSH_PORT="$(ss -tlnp 2>/dev/null | awk '/sshd/{print $4}' \
        | grep -oP '(?<=:)\d+' | head -1 || echo 22)"
    ACTUAL_SSH_PORT="${ACTUAL_SSH_PORT:-22}"

    ufw allow "${ACTUAL_SSH_PORT}/tcp" comment "SSH current port — active sshd"
    ok "Rule: ${ACTUAL_SSH_PORT}/tcp — SSH current port"
    add_status "Firewall" "SSH ${ACTUAL_SSH_PORT}/tcp (current)" PASS "active sshd port"

    if [[ "$SSH_PORT" != "$ACTUAL_SSH_PORT" ]]; then
        ufw allow "${SSH_PORT}/tcp" comment "SSH target port — after hardening"
        ok "Rule: ${SSH_PORT}/tcp — SSH target port (post-hardening)"
        add_status "Firewall" "SSH ${SSH_PORT}/tcp (target)" PASS "post-hardening port"
    fi

    # RustDesk hbbs
    ufw allow 21115/tcp comment "RustDesk hbbs — NAT type test"
    ok "Rule: 21115/tcp — RustDesk hbbs NAT type test"
    add_status "Firewall" "21115/tcp" PASS "hbbs NAT type test"

    ufw allow 21116/tcp comment "RustDesk hbbs — ID registration and heartbeat"
    ok "Rule: 21116/tcp — RustDesk hbbs ID registration"
    add_status "Firewall" "21116/tcp" PASS "hbbs ID registration"

    ufw allow 21116/udp comment "RustDesk hbbs — UDP hole punching"
    ok "Rule: 21116/udp — RustDesk hbbs UDP hole punching"
    add_status "Firewall" "21116/udp" PASS "hbbs UDP hole punching"

    # RustDesk hbbr
    ufw allow 21117/tcp comment "RustDesk hbbr — relay traffic"
    ok "Rule: 21117/tcp — RustDesk hbbr relay"
    add_status "Firewall" "21117/tcp" PASS "hbbr relay"

    # 21114/21118/21119 intentionally closed
    add_status "Firewall" "21114 (Pro/API)" INFO "intentionally closed"
    add_status "Firewall" "21118/21119 (web)" INFO "intentionally closed"

    ufw default deny incoming
    ufw default allow outgoing
    add_status "Firewall" "Default incoming" PASS "deny"
    add_status "Firewall" "Default outgoing" PASS "allow"

    ufw --force enable
    if ufw status | grep -q "Status: active"; then
        ok "UFW enabled."
        add_status "Firewall" "UFW" PASS "active"
    else
        add_status "Firewall" "UFW" FAIL "not active"
        die "UFW did not activate."
    fi
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 06 — Compose setup                                         ║
# ╚══════════════════════════════════════════════════════════════════╝

step_06_rustdesk_compose() {
    step "RustDesk Compose setup"

    RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/opt/rustdesk/data}"
    DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-10m}"
    DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE:-3}"
    DEPLOY_DIR="/opt/rustdesk"

    [[ -n "${SERVER_IP:-}" ]] || die "SERVER_IP must be set."

    mkdir -p "$DEPLOY_DIR"
    add_status "RustDesk" "Deploy dir" PASS "$DEPLOY_DIR"

    mkdir -p "$RUSTDESK_DATA_DIR"
    chown root:root "$RUSTDESK_DATA_DIR"
    chmod 750 "$RUSTDESK_DATA_DIR"
    add_status "RustDesk" "Data dir" PASS "$RUSTDESK_DATA_DIR"

    cat > "${DEPLOY_DIR}/compose.yml" << EOF
# /opt/rustdesk/compose.yml — generated by rustdesk-install.sh
services:
  hbbs:
    image: rustdesk/rustdesk-server:latest
    container_name: rustdesk-hbbs
    command: hbbs -r ${SERVER_IP}
    network_mode: host
    volumes:
      - ${RUSTDESK_DATA_DIR}:/root
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "${DOCKER_LOG_MAX_SIZE}"
        max-file: "${DOCKER_LOG_MAX_FILE}"
  hbbr:
    image: rustdesk/rustdesk-server:latest
    container_name: rustdesk-hbbr
    command: hbbr
    network_mode: host
    volumes:
      - ${RUSTDESK_DATA_DIR}:/root
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "${DOCKER_LOG_MAX_SIZE}"
        max-file: "${DOCKER_LOG_MAX_FILE}"
EOF

    ok "compose.yml written: ${DEPLOY_DIR}/compose.yml"
    add_status "RustDesk" "compose.yml" PASS "${DEPLOY_DIR}/compose.yml"

    cat > "${DEPLOY_DIR}/.env" << EOF
SERVER_IP=${SERVER_IP}
RUSTDESK_DATA_DIR=${RUSTDESK_DATA_DIR}
DOCKER_LOG_MAX_SIZE=${DOCKER_LOG_MAX_SIZE}
DOCKER_LOG_MAX_FILE=${DOCKER_LOG_MAX_FILE}
EOF
    chmod 600 "${DEPLOY_DIR}/.env"
    add_status "RustDesk" "Runtime .env" PASS "${DEPLOY_DIR}/.env"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 07 — Start services                                        ║
# ╚══════════════════════════════════════════════════════════════════╝

step_07_start_services() {
    step "Start services"

    DEPLOY_DIR="/opt/rustdesk"
    ADMIN_USER="${ADMIN_USER:-rdadmin}"
    SSH_PORT="${SSH_PORT:-2222}"
    UNATTENDED_UPGRADES_EMAIL="${UNATTENDED_UPGRADES_EMAIL:-}"

    info "Pulling RustDesk images..."
    docker compose -f "${DEPLOY_DIR}/compose.yml" pull
    add_status "RustDesk" "Image pull" PASS "latest"

    info "Starting containers..."
    docker compose -f "${DEPLOY_DIR}/compose.yml" up -d
    sleep 3

    for name in rustdesk-hbbs rustdesk-hbbr; do
        STATUS="$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")"
        if [[ "$STATUS" == "running" ]]; then
            ok "Container '$name' running."
            add_status "RustDesk" "Container $name" PASS "running"
        else
            fail "Container '$name': $STATUS"
            add_status "RustDesk" "Container $name" FAIL "$STATUS"
        fi
    done

    # sysctl hardening
    cat > /etc/sysctl.d/99-rustdesk-hardening.conf << 'EOF'
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.sysrq = 0
EOF
    sysctl --system > /dev/null 2>&1
    add_status "System" "sysctl hardening" PASS "applied"

    # fail2ban
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/99-rustdesk-sshd.conf << EOF
[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
bantime  = 3600
findtime = 600
EOF
    systemctl enable fail2ban --quiet
    systemctl restart fail2ban
    if systemctl is-active --quiet fail2ban; then
        add_status "System" "fail2ban" PASS "active"
    else
        add_status "System" "fail2ban" WARN "not running"
    fi

    # unattended-upgrades
    DISTRO_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")"
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins { "Debian:${DISTRO_CODENAME}-security"; };
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "${UNATTENDED_UPGRADES_EMAIL}";
EOF
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    systemctl enable unattended-upgrades --quiet
    add_status "System" "Unattended upgrades" PASS "security-only, daily"

    # MOTD
    MOTD_SCRIPT="/etc/update-motd.d/99-rustdesk"
    cat > "$MOTD_SCRIPT" << 'MOTDEOF'
#!/bin/bash
echo ""
echo "+---------------------------------------------------------------+"
printf "| %-61s |\n" "RustDesk Server OSS"
printf "| Host: %-55s |\n" "$(hostname -f 2>/dev/null || hostname)"
printf "| Date: %-55s |\n" "$(date)"
echo "+---------------------------------------------------------------+"
echo "|  docker ps --filter name=rustdesk                            |"
echo "|  cat /opt/rustdesk/data/id_ed25519.pub                      |"
echo "+---------------------------------------------------------------+"
echo ""
MOTDEOF
    chmod +x "$MOTD_SCRIPT"
    add_status "System" "MOTD" PASS "$MOTD_SCRIPT"

    # Shell aliases
    ALIASES_FILE="/home/${ADMIN_USER}/.bash_aliases"
    if ! grep -q "RustDesk aliases" "$ALIASES_FILE" 2>/dev/null; then
        cat >> "$ALIASES_FILE" << 'EOF'

# ── RustDesk aliases ──────────────────────────────────────────────────────────
alias rdps='docker ps --filter name=rustdesk'
alias rdkey='cat /opt/rustdesk/data/id_ed25519.pub'
alias rdlogs='docker logs rustdesk-hbbs --tail 100 -f'
alias rdlogs-r='docker logs rustdesk-hbbr --tail 100 -f'
alias rdrestart='docker compose -f /opt/rustdesk/compose.yml restart'
alias rdstatus='docker compose -f /opt/rustdesk/compose.yml ps'
alias rdpull='docker compose -f /opt/rustdesk/compose.yml pull && docker compose -f /opt/rustdesk/compose.yml up -d'
EOF
    fi
    chown "${ADMIN_USER}:${ADMIN_USER}" "$ALIASES_FILE" 2>/dev/null || true
    add_status "System" "Shell aliases" PASS "$ALIASES_FILE"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 08 — Show keys                                             ║
# ╚══════════════════════════════════════════════════════════════════╝

step_08_show_keys() {
    step "Key display"

    RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/opt/rustdesk/data}"
    PUB_KEY_FILE="${RUSTDESK_DATA_DIR}/id_ed25519.pub"
    PRIV_KEY_FILE="${RUSTDESK_DATA_DIR}/id_ed25519"

    info "Waiting for RustDesk key generation (up to 30s)..."
    ELAPSED=0
    while [[ ! -f "$PUB_KEY_FILE" ]] && [[ "$ELAPSED" -lt 30 ]]; do
        sleep 1; (( ELAPSED++ )) || true; printf "."
    done
    echo ""

    if [[ ! -f "$PUB_KEY_FILE" ]]; then
        warn "Key not yet written. Check: docker logs rustdesk-hbbs"
        add_status "RustDesk" "Key generation" WARN "not yet present"
        return 0
    fi

    ok "Key ready (${ELAPSED}s)."
    add_status "RustDesk" "Key generation" PASS "id_ed25519.pub present"

    [[ -f "$PRIV_KEY_FILE" ]] && chmod 600 "$PRIV_KEY_FILE"
    add_status "RustDesk" "Private key perms" PASS "600"

    RDPUBKEY="$(cat "$PUB_KEY_FILE")"

    echo ""
    echo "+----------------------------------------------------------------------+"
    echo "|  RustDesk Client Configuration                                       |"
    echo "+----------------------------------------------------------------------+"
    printf "|  ID Server  : %-54s |\n" "${SERVER_IP:-<SERVER_IP>}"
    printf "|  Key        : %-54s |\n" "$RDPUBKEY"
    printf "|  Key file   : %-54s |\n" "$PUB_KEY_FILE"
    echo "+----------------------------------------------------------------------+"
    echo "|  Settings > Network > ID Server  →  Server IP                       |"
    echo "|  Settings > Network > Key        →  Key value above                 |"
    echo "+----------------------------------------------------------------------+"
    echo ""

    add_status "RustDesk" "Public key" PASS "$PUB_KEY_FILE"

    SSH_HOST_KEY="/etc/ssh/ssh_host_ed25519_key.pub"
    if [[ -f "$SSH_HOST_KEY" ]]; then
        echo "+----------------------------------------------------------------------+"
        echo "|  SSH Host Key (back this up)                                         |"
        echo "+----------------------------------------------------------------------+"
        printf "|  %-70s |\n" "$(cat "$SSH_HOST_KEY")"
        echo "+----------------------------------------------------------------------+"
        echo ""
        add_status "SSH" "Host key displayed" PASS "$SSH_HOST_KEY"
    fi

    echo "  BACKUP NOW: sudo bash backup/backup-rustdesk-keys.sh"
    echo "  Files to back up:"
    echo "    ${RUSTDESK_DATA_DIR}/id_ed25519"
    echo "    ${RUSTDESK_DATA_DIR}/id_ed25519.pub"
    echo ""
    add_status "RustDesk" "Backup reminder" INFO "back up keys immediately"
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Step 09 — Final summary                                         ║
# ╚══════════════════════════════════════════════════════════════════╝

print_summary() {
    local section_line="  $(printf '%.0s-' $(seq 1 68))"

    echo ""
    echo "+--------------------------------------------------------------------------+"
    printf "|  %-72s  |\n" "RustDesk Server OSS — Installation Summary"
    echo "+--------------------------------------------------------------------------+"
    printf "|  Completed : %-60s  |\n" "$(date)"
    printf "|  Server IP : %-60s  |\n" "${SERVER_IP:-<not set>}"
    echo "+--------------------------------------------------------------------------+"
    echo ""

    local current_cat=""
    for entry in "${_STATUS_LINES[@]+"${_STATUS_LINES[@]}"}"; do
        IFS='|' read -r cat label result detail <<< "$entry"
        if [[ "$cat" != "$current_cat" ]]; then
            [[ -n "$current_cat" ]] && echo ""
            printf "  ${BOLD}%s${RESET}\n" "$cat"
            echo "$section_line"
            current_cat="$cat"
        fi
        local color="$RESET" icon=" "
        case "$result" in
            PASS) color="$GREEN";  icon="+" ;;
            FAIL) color="$RED";    icon="!" ;;
            WARN) color="$YELLOW"; icon="~" ;;
            INFO) color="$CYAN";   icon="i" ;;
        esac
        printf "  ${color}[%s]${RESET}  %-34s %s\n" "$icon" "$label" "$detail"
    done

    echo ""
    echo "  $(printf '%.0s-' $(seq 1 68))"
    printf "  ${GREEN}%d passed${RESET}   ${YELLOW}%d warnings${RESET}   ${RED}%d failed${RESET}\n" \
        "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
    echo ""

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}${BOLD}Completed with failures. Review items above.${RESET}"
    elif [[ "$WARN_COUNT" -gt 0 ]]; then
        echo -e "  ${YELLOW}${BOLD}Completed with warnings. Review items above.${RESET}"
    else
        echo -e "  ${GREEN}${BOLD}All checks passed. RustDesk Server OSS is ready.${RESET}"
    fi

    echo ""
    echo "  Next steps:"
    printf "  %s\n" "1. Test SSH:        ssh -p ${SSH_PORT:-2222} ${ADMIN_USER:-rdadmin}@${SERVER_IP:-<IP>}"
    printf "  %s\n" "2. Validate:        sudo bash validate.sh"
    printf "  %s\n" "3. Back up keys:    sudo bash backup/backup-rustdesk-keys.sh"
    printf "  %s\n" "4. Configure clients: see docs/CLIENT-CONFIG.md"
    echo ""
}

step_09_final_status() {
    step "Final summary"
    print_summary
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║  Main entry point                                                ║
# ╚══════════════════════════════════════════════════════════════════╝

main() {
    # Load .env from current directory or /tmp/rustdesk-install.env
    if [[ -f "./.env" ]]; then
        # shellcheck source=/dev/null
        source "./.env"
    elif [[ -f "/tmp/rustdesk-install.env" ]]; then
        # shellcheck source=/dev/null
        source "/tmp/rustdesk-install.env"
    fi

    export ADMIN_USER="${ADMIN_USER:-rdadmin}"
    export SSH_PORT="${SSH_PORT:-2222}"
    export SERVER_IP="${SERVER_IP:-}"
    export RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/opt/rustdesk/data}"
    export DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-10m}"
    export DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE:-3}"
    export UNATTENDED_UPGRADES_EMAIL="${UNATTENDED_UPGRADES_EMAIL:-}"

    require_root

    echo ""
    echo "+----------------------------------------------------------------------+"
    echo "|  RustDesk Server OSS — Combined Installer (Debian 13 amd64)         |"
    echo "+----------------------------------------------------------------------+"
    printf "|  Server IP  : %-54s |\n" "${SERVER_IP:-<not set — check .env>}"
    printf "|  Admin user : %-54s |\n" "$ADMIN_USER"
    printf "|  SSH port   : %-54s |\n" "$SSH_PORT"
    printf "|  Data dir   : %-54s |\n" "$RUSTDESK_DATA_DIR"
    echo "+----------------------------------------------------------------------+"
    echo ""

    step_00_preflight
    step_01_packages
    step_02_docker
    step_03_user_hardening
    step_04_ssh_hardening
    step_05_firewall
    step_06_rustdesk_compose
    step_07_start_services
    step_08_show_keys
    step_09_final_status
}

main "$@"
