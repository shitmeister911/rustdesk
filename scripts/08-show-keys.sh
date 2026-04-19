#!/usr/bin/env bash
# 08-show-keys.sh — wait for RustDesk key generation then display client config
#
# RustDesk hbbs generates id_ed25519 + id_ed25519.pub asynchronously on first
# startup. This script polls up to 30 seconds before giving up gracefully.
# Also displays the SSH host key for backup purposes.
#
# Standalone: sudo bash scripts/08-show-keys.sh
# Sourced by: install.sh

set -euo pipefail

step_08_show_keys() {
    step "Key display"

    RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/opt/rustdesk/data}"
    SERVER_IP="${SERVER_IP:-<SERVER_IP>}"
    PUB_KEY_FILE="${RUSTDESK_DATA_DIR}/id_ed25519.pub"
    PRIV_KEY_FILE="${RUSTDESK_DATA_DIR}/id_ed25519"

    # ── Wait for key generation ───────────────────────────────────────────────
    info "Waiting for RustDesk to generate ed25519 key pair (up to 30s)..."
    ELAPSED=0
    while [[ ! -f "$PUB_KEY_FILE" ]] && [[ "$ELAPSED" -lt 30 ]]; do
        sleep 1
        (( ELAPSED++ )) || true
        printf "."
    done
    echo ""

    if [[ ! -f "$PUB_KEY_FILE" ]]; then
        warn "Public key not yet written after 30s."
        warn "Check container logs: docker logs rustdesk-hbbs --tail 20"
        add_status "RustDesk" "Key generation" WARN "not yet present — check container logs"
        return 0
    fi

    ok "Key pair ready (${ELAPSED}s)."
    add_status "RustDesk" "Key generation" PASS "id_ed25519.pub present"

    # ── Secure private key permissions ────────────────────────────────────────
    if [[ -f "$PRIV_KEY_FILE" ]]; then
        chmod 600 "$PRIV_KEY_FILE"
        add_status "RustDesk" "Private key perms" PASS "600"
    fi

    # ── Display RustDesk client config ────────────────────────────────────────
    RDPUBKEY="$(cat "$PUB_KEY_FILE")"

    echo ""
    echo "+----------------------------------------------------------------------+"
    echo "|  RustDesk Client Configuration                                       |"
    echo "+----------------------------------------------------------------------+"
    printf "|  ID Server  : %-54s |\n" "$SERVER_IP"
    printf "|  Key        : %-54s |\n" "$RDPUBKEY"
    printf "|  Key file   : %-54s |\n" "$PUB_KEY_FILE"
    echo "+----------------------------------------------------------------------+"
    echo "|  In the RustDesk client:                                             |"
    echo "|    Settings > Network > ID Server  →  paste Server IP               |"
    echo "|    Settings > Network > Key        →  paste Key value               |"
    echo "+----------------------------------------------------------------------+"
    echo ""

    add_status "RustDesk" "Public key" PASS "$PUB_KEY_FILE"

    # ── SSH host public key ───────────────────────────────────────────────────
    SSH_HOST_KEY="/etc/ssh/ssh_host_ed25519_key.pub"
    if [[ -f "$SSH_HOST_KEY" ]]; then
        echo "+----------------------------------------------------------------------+"
        echo "|  SSH Host Key (back this up — used to verify server identity)        |"
        echo "+----------------------------------------------------------------------+"
        printf "|  %-70s |\n" "$(cat "$SSH_HOST_KEY")"
        echo "+----------------------------------------------------------------------+"
        echo ""
        add_status "SSH" "Host key displayed" PASS "$SSH_HOST_KEY"
    fi

    # ── Backup reminder ───────────────────────────────────────────────────────
    echo "  BACKUP NOW — if these keys are lost, all clients must be reconfigured:"
    echo "    ${RUSTDESK_DATA_DIR}/id_ed25519"
    echo "    ${RUSTDESK_DATA_DIR}/id_ed25519.pub"
    echo ""
    echo "  Run:  sudo bash backup/backup-rustdesk-keys.sh"
    echo "  Docs: docs/BACKUP-AND-RESTORE.md"
    echo ""

    add_status "RustDesk" "Backup reminder" INFO "back up keys immediately"
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    require_root
    step_08_show_keys
fi
# STANDALONE_ONLY_END
