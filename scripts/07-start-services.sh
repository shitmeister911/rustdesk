#!/usr/bin/env bash
# 07-start-services.sh — start RustDesk containers and configure system services
# Handles: Docker Compose, sysctl hardening, fail2ban, unattended-upgrades,
#          MOTD, shell aliases.
#
# Standalone: sudo bash scripts/07-start-services.sh
# Sourced by: install.sh

set -euo pipefail

step_07_start_services() {
    step "Start services"

    DEPLOY_DIR="/opt/rustdesk"
    ADMIN_USER="${ADMIN_USER:-rdadmin}"
    SSH_PORT="${SSH_PORT:-2222}"
    UNATTENDED_UPGRADES_EMAIL="${UNATTENDED_UPGRADES_EMAIL:-}"

    # ── Pull images ───────────────────────────────────────────────────────────
    info "Pulling RustDesk images..."
    docker compose -f "${DEPLOY_DIR}/compose.yml" pull
    add_status "RustDesk" "Image pull" PASS "rustdesk/rustdesk-server:latest"

    # ── Start containers ──────────────────────────────────────────────────────
    info "Starting RustDesk containers..."
    docker compose -f "${DEPLOY_DIR}/compose.yml" up -d

    sleep 3  # brief pause to let containers initialise

    for name in rustdesk-hbbs rustdesk-hbbr; do
        STATUS="$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")"
        if [[ "$STATUS" == "running" ]]; then
            ok "Container '$name' is running."
            add_status "RustDesk" "Container $name" PASS "running"
        else
            fail "Container '$name' status: $STATUS"
            add_status "RustDesk" "Container $name" FAIL "$STATUS"
        fi
    done

    # ── sysctl hardening ──────────────────────────────────────────────────────
    info "Applying sysctl hardening..."
    cat > /etc/sysctl.d/99-rustdesk-hardening.conf << 'EOF'
# /etc/sysctl.d/99-rustdesk-hardening.conf

# Disable IP source routing — prevents spoofed-route attacks
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Reject ICMP redirects — prevents routing table poisoning
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# SYN flood protection via SYN cookies
net.ipv4.tcp_syncookies = 1

# Ignore ICMP broadcasts — mitigates Smurf amplification
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log packets with impossible source addresses (martians)
net.ipv4.conf.all.log_martians = 1

# Larger UDP receive/send buffers — improves hbbs hole-punching under load
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000

# Restrict /proc/kallsyms and kernel pointer exposure
kernel.kptr_restrict = 2

# Restrict dmesg access to root
kernel.dmesg_restrict = 1

# Disable magic SysRq on headless servers
kernel.sysrq = 0
EOF

    sysctl --system > /dev/null 2>&1
    ok "sysctl hardening applied."
    add_status "System" "sysctl" PASS "/etc/sysctl.d/99-rustdesk-hardening.conf"

    # ── fail2ban ──────────────────────────────────────────────────────────────
    # Override file in jail.d/ — survives fail2ban package upgrades (jail.conf gets clobbered)
    info "Configuring fail2ban..."
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/99-rustdesk-sshd.conf << EOF
# 99-rustdesk-sshd.conf — managed by 07-start-services.sh
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
        ok "fail2ban active."
        add_status "System" "fail2ban" PASS "active (SSH port ${SSH_PORT})"
    else
        warn "fail2ban did not start — check: journalctl -u fail2ban -n 20"
        add_status "System" "fail2ban" WARN "not running"
    fi

    # ── unattended-upgrades ───────────────────────────────────────────────────
    # Security patches only — no dist-upgrades or regular package bumps.
    info "Configuring unattended-upgrades..."
    DISTRO_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")"

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "Debian:${DISTRO_CODENAME}-security";
};
Unattended-Upgrade::Package-Blacklist {};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "${UNATTENDED_UPGRADES_EMAIL}";
Unattended-Upgrade::MailReport "on-change";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    systemctl enable unattended-upgrades --quiet
    ok "Unattended security upgrades configured (${DISTRO_CODENAME}-security only)."
    add_status "System" "Unattended upgrades" PASS "daily, security-only"

    # ── MOTD ──────────────────────────────────────────────────────────────────
    info "Writing MOTD..."
    MOTD_SCRIPT="/etc/update-motd.d/99-rustdesk"
    cat > "$MOTD_SCRIPT" << 'MOTDEOF'
#!/bin/bash
# 99-rustdesk MOTD — managed by install.sh
echo ""
echo "+---------------------------------------------------------------+"
printf "| %-61s |\n" "RustDesk Server OSS"
printf "| Host: %-55s |\n" "$(hostname -f 2>/dev/null || hostname)"
printf "| Date: %-55s |\n" "$(date)"
echo "+---------------------------------------------------------------+"
echo "|  Useful commands:                                             |"
echo "|    docker ps --filter name=rustdesk                          |"
echo "|    cat /opt/rustdesk/data/id_ed25519.pub                     |"
echo "|    docker logs rustdesk-hbbs --tail 50                       |"
echo "|    sudo bash /opt/rustdesk-server-debian/validate.sh         |"
echo "+---------------------------------------------------------------+"
echo ""
MOTDEOF

    chmod +x "$MOTD_SCRIPT"
    ok "MOTD written: $MOTD_SCRIPT"
    add_status "System" "MOTD" PASS "$MOTD_SCRIPT"

    # ── Shell aliases ─────────────────────────────────────────────────────────
    info "Writing shell aliases for $ADMIN_USER..."
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
    chown "${ADMIN_USER}:${ADMIN_USER}" "$ALIASES_FILE"
    ok "Aliases written: $ALIASES_FILE"
    add_status "System" "Shell aliases" PASS "$ALIASES_FILE"
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    require_root
    step_07_start_services
fi
# STANDALONE_ONLY_END
