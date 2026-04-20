#!/usr/bin/env bash
# 04-ssh-hardening.sh — harden OpenSSH: key-only auth, no root, legal banner
#
# Safety gate: refuses to disable password auth until authorized_keys is populated.
# Config drop-in: /etc/ssh/sshd_config.d/99-hardened.conf survives openssh-server upgrades.
# Always validates config with `sshd -t` before restarting.
#
# Standalone: sudo bash scripts/04-ssh-hardening.sh
# Sourced by: install.sh

set -euo pipefail

step_04_ssh_hardening() {
    step "SSH hardening"

    ADMIN_USER="${ADMIN_USER:-rdadmin}"
    SSH_PORT="${SSH_PORT:-2222}"
    AUTH_KEYS="/home/${ADMIN_USER}/.ssh/authorized_keys"
    SSHD_CONFIG="/etc/ssh/sshd_config"
    DROP_IN_DIR="/etc/ssh/sshd_config.d"
    DROP_IN="${DROP_IN_DIR}/99-hardened.conf"

    # ── Safety gate ───────────────────────────────────────────────────────────
    # Disabling password auth on an empty authorized_keys causes permanent lockout.
    # When no key is present we skip hardening entirely and leave passwords enabled
    # so the machine stays accessible. Re-run this script after adding a key.
    if [[ ! -s "$AUTH_KEYS" ]]; then
        warn "authorized_keys for '$ADMIN_USER' is empty — SSH hardening SKIPPED."
        warn "SSH is still accessible with password on its default port."
        warn "Add your key then re-run:  sudo bash scripts/04-ssh-hardening.sh"
        warn "  ssh-copy-id -p 22 -i ~/.ssh/id_ed25519.pub ${ADMIN_USER}@${SERVER_IP:-<SERVER_IP>}"
        add_status "SSH" "Hardening" WARN "skipped — no key in authorized_keys (passwords still active)"
        return 0
    fi
    ok "authorized_keys has content — safe to disable password auth."
    add_status "SSH" "Safety gate" PASS "key(s) present"

    # ── Backup original sshd_config ───────────────────────────────────────────
    if [[ ! -f "${SSHD_CONFIG}.bak" ]]; then
        cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
        ok "Backed up: ${SSHD_CONFIG}.bak"
    else
        ok "Backup already exists: ${SSHD_CONFIG}.bak"
    fi

    # ── Set SSH port in base config ───────────────────────────────────────────
    # We set it in the base file for compatibility with older init scripts,
    # and also in the drop-in (which takes precedence on OpenSSH 9.x).
    if grep -q "^Port " "$SSHD_CONFIG"; then
        sed -i "s/^Port .*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
    elif grep -q "^#Port " "$SSHD_CONFIG"; then
        sed -i "s/^#Port .*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
    else
        echo "Port ${SSH_PORT}" >> "$SSHD_CONFIG"
    fi
    ok "SSH port set to ${SSH_PORT}."

    # ── Write hardening drop-in ───────────────────────────────────────────────
    # Drop-in files in sshd_config.d/ survive openssh-server package upgrades.
    mkdir -p "$DROP_IN_DIR"
    cat > "$DROP_IN" << EOF
# ${DROP_IN}
# Managed by 04-ssh-hardening.sh. Re-run to regenerate.

Port ${SSH_PORT}

# Key-only authentication — password login disabled
PasswordAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# No direct root login — use sudo from $ADMIN_USER
PermitRootLogin no

# Required for Debian PAM account/session modules
UsePAM yes

# Reduce attack surface
X11Forwarding no
AllowTcpForwarding no
PrintMotd yes

# Disconnect idle sessions after ~10 minutes (2 × 300s)
ClientAliveInterval 300
ClientAliveCountMax 2

# Limit auth window and retry attempts
MaxAuthTries 3
LoginGraceTime 30

# Show legal warning on connect
Banner /etc/issue.net
EOF

    ok "Drop-in written: ${DROP_IN}"
    add_status "SSH" "Config drop-in" PASS "${DROP_IN}"

    # ── Legal banner ──────────────────────────────────────────────────────────
    cat > /etc/issue.net << 'EOF'
+---------------------------------------------------------+
|  AUTHORIZED ACCESS ONLY                                 |
|  All sessions are monitored and logged.                 |
|  Unauthorized access is strictly prohibited.           |
+---------------------------------------------------------+
EOF
    ok "Legal banner written: /etc/issue.net"
    add_status "SSH" "Legal banner" PASS "/etc/issue.net"

    # ── Validate before restarting ────────────────────────────────────────────
    # Never restart sshd with an invalid config — it would refuse new connections.
    if sshd -t 2>&1; then
        ok "sshd config validation passed."
        add_status "SSH" "Config validation" PASS "sshd -t OK"
    else
        fail "sshd config test FAILED. Review: ${DROP_IN}"
        add_status "SSH" "Config validation" FAIL "sshd -t failed"
        die "sshd config invalid — not restarting. Fix the error above."
    fi

    # ── Restart SSH ───────────────────────────────────────────────────────────
    systemctl restart ssh
    if systemctl is-active --quiet ssh; then
        ok "SSH daemon restarted on port ${SSH_PORT}."
        add_status "SSH" "Service restart" PASS "active on port ${SSH_PORT}"
    else
        fail "SSH daemon failed to start."
        add_status "SSH" "Service restart" FAIL "not running"
        die "SSH not active — check: journalctl -u ssh -n 20"
    fi

    # ── Remove port-22 fallback UFW rule now that SSH has moved ──────────────────
    # 05-firewall.sh opened port 22 as a safety fallback in case hardening was
    # skipped. Since hardening succeeded and SSH moved to ${SSH_PORT}, close 22
    # (unless the target port IS 22, which would be unusual but valid).
    if [[ "$SSH_PORT" != "22" ]] && command -v ufw &>/dev/null; then
        ufw delete allow 22/tcp 2>/dev/null && \
            ok "Removed temporary UFW rule for port 22 (SSH now on ${SSH_PORT})." || true
        add_status "Firewall" "Port 22 fallback" PASS "rule removed — SSH on ${SSH_PORT}"
    fi

    warn "IMPORTANT: Test login in a NEW terminal BEFORE closing this session."
    warn "  ssh -p ${SSH_PORT} ${ADMIN_USER}@${SERVER_IP:-<SERVER_IP>}"
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    require_root
    step_04_ssh_hardening
fi
# STANDALONE_ONLY_END
