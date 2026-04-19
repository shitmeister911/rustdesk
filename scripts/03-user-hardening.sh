#!/usr/bin/env bash
# 03-user-hardening.sh — create non-root admin user for server management
# Password is locked by default — SSH key-only access enforced in 04-ssh-hardening.sh.
# Idempotent: skips user creation if user already exists.
#
# Standalone: sudo bash scripts/03-user-hardening.sh
# Sourced by: install.sh

set -euo pipefail

step_03_user_hardening() {
    step "Admin user setup"

    ADMIN_USER="${ADMIN_USER:-rdadmin}"

    # ── Create user ───────────────────────────────────────────────────────────
    if id "$ADMIN_USER" &>/dev/null; then
        ok "User '$ADMIN_USER' already exists — skipping creation."
        add_status "User" "Admin user" PASS "$ADMIN_USER (pre-existing)"
    else
        useradd -m -s /bin/bash -G sudo,docker "$ADMIN_USER"
        ok "Created user: $ADMIN_USER (groups: sudo, docker)"
        add_status "User" "Admin user" PASS "$ADMIN_USER created"
    fi

    # Lock password — key-only SSH is enforced in 04-ssh-hardening.sh.
    # A locked password prevents password-based su as well.
    passwd -l "$ADMIN_USER"
    add_status "User" "Password" PASS "locked (key-only enforced later)"

    # Ensure docker group membership (idempotent)
    usermod -aG docker "$ADMIN_USER" 2>/dev/null || true
    usermod -aG sudo  "$ADMIN_USER" 2>/dev/null || true

    # ── .ssh directory ────────────────────────────────────────────────────────
    SSH_DIR="/home/${ADMIN_USER}/.ssh"
    mkdir -p "$SSH_DIR"
    chown "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    ok ".ssh directory ready: $SSH_DIR (700)"

    # ── authorized_keys ───────────────────────────────────────────────────────
    AUTH_KEYS="${SSH_DIR}/authorized_keys"
    if [[ ! -f "$AUTH_KEYS" ]]; then
        touch "$AUTH_KEYS"
    fi
    chown "${ADMIN_USER}:${ADMIN_USER}" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"

    if [[ -s "$AUTH_KEYS" ]]; then
        KEY_COUNT="$(wc -l < "$AUTH_KEYS")"
        ok "authorized_keys: $KEY_COUNT key(s) present."
        add_status "User" "authorized_keys" PASS "$KEY_COUNT key(s)"
    else
        warn "authorized_keys is empty."
        warn "Add your SSH public key before running 04-ssh-hardening.sh:"
        warn "  ssh-copy-id -p ${SSH_PORT:-2222} -i ~/.ssh/id_ed25519.pub ${ADMIN_USER}@${SERVER_IP:-<SERVER_IP>}"
        add_status "User" "authorized_keys" WARN "empty — add key before SSH hardening"
    fi
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    require_root
    step_03_user_hardening
fi
# STANDALONE_ONLY_END
