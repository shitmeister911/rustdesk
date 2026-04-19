#!/usr/bin/env bash
# 05-firewall.sh — configure UFW with minimum required ports for RustDesk OSS
#
# SSH rule is added FIRST to prevent lockout when UFW is enabled.
# Every rule includes a comment explaining its purpose.
# Ports 21114, 21118, 21119 are intentionally left closed.
#
# Standalone: sudo bash scripts/05-firewall.sh
# Sourced by: install.sh

set -euo pipefail

step_05_firewall() {
    step "UFW firewall"

    SSH_PORT="${SSH_PORT:-2222}"

    # ── Reset to clean state ──────────────────────────────────────────────────
    # --force suppresses the interactive prompt
    info "Resetting UFW to a clean state..."
    ufw --force reset > /dev/null 2>&1
    add_status "Firewall" "UFW reset" PASS "clean state"

    # ── SSH — MUST be first ───────────────────────────────────────────────────
    # Adding the SSH rule before 'ufw enable' guarantees you keep access.
    # If UFW enabled with no SSH rule, all remote sessions are cut immediately.
    ufw allow "${SSH_PORT}/tcp" comment "SSH admin access"
    ok "Rule added: ${SSH_PORT}/tcp — SSH admin access"
    add_status "Firewall" "SSH ${SSH_PORT}/tcp" PASS "admin access"

    # ── RustDesk hbbs (ID / rendezvous server) ────────────────────────────────

    # 21115/tcp — NAT type detection probe from clients before they connect
    ufw allow 21115/tcp comment "RustDesk hbbs — NAT type test"
    ok "Rule added: 21115/tcp — RustDesk hbbs NAT type test"
    add_status "Firewall" "21115/tcp" PASS "hbbs NAT type test"

    # 21116/tcp — client ID registration, peer lookup, and heartbeats
    ufw allow 21116/tcp comment "RustDesk hbbs — ID registration and heartbeat"
    ok "Rule added: 21116/tcp — RustDesk hbbs ID registration and heartbeat"
    add_status "Firewall" "21116/tcp" PASS "hbbs ID registration"

    # 21116/udp — UDP hole punching for direct peer-to-peer connections
    # This REQUIRES host networking — Docker bridge breaks UDP source ports.
    ufw allow 21116/udp comment "RustDesk hbbs — UDP hole punching"
    ok "Rule added: 21116/udp — RustDesk hbbs UDP hole punching"
    add_status "Firewall" "21116/udp" PASS "hbbs UDP hole punching"

    # ── RustDesk hbbr (relay server) ──────────────────────────────────────────

    # 21117/tcp — encrypted relay when direct connection fails (NAT, firewall)
    ufw allow 21117/tcp comment "RustDesk hbbr — relay traffic"
    ok "Rule added: 21117/tcp — RustDesk hbbr relay traffic"
    add_status "Firewall" "21117/tcp" PASS "hbbr relay"

    # ── Intentionally closed ports (documented, not opened) ───────────────────
    # 21114 — RustDesk Pro API server only — OSS does not use this port
    # 21118 — hbbs web client interface — not enabled in this setup
    # 21119 — hbbr web client interface — not enabled in this setup
    add_status "Firewall" "21114 (Pro/API)" INFO "intentionally closed"
    add_status "Firewall" "21118/21119 (web)" INFO "intentionally closed"

    # ── Default policies ──────────────────────────────────────────────────────
    ufw default deny incoming
    ufw default allow outgoing
    ok "Defaults set: deny incoming, allow outgoing."
    add_status "Firewall" "Default incoming" PASS "deny"
    add_status "Firewall" "Default outgoing" PASS "allow"

    # ── Enable UFW ────────────────────────────────────────────────────────────
    ufw --force enable
    if ufw status | grep -q "Status: active"; then
        ok "UFW is active."
        add_status "Firewall" "UFW enabled" PASS "active"
    else
        fail "UFW failed to enable."
        add_status "Firewall" "UFW enabled" FAIL "not active"
        die "UFW did not activate — check: ufw status"
    fi

    echo ""
    ufw status verbose
    echo ""
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    require_root
    step_05_firewall
fi
# STANDALONE_ONLY_END
