#!/usr/bin/env bash
# validate.sh — verify RustDesk Server OSS deployment health
#
# Run after install or at any time to check system state.
# Checks: Docker, containers, listening ports, UFW rules, SSH, key files.
#
# Usage: sudo bash validate.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib-common.sh
source "${REPO_DIR}/scripts/lib-common.sh"

# shellcheck source=scripts/09-final-status.sh
source "${REPO_DIR}/scripts/09-final-status.sh"

load_env "$REPO_DIR"

require_root

ADMIN_USER="${ADMIN_USER:-rdadmin}"
SSH_PORT="${SSH_PORT:-2222}"
SERVER_IP="${SERVER_IP:-<not set>}"
RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/opt/rustdesk/data}"

echo ""
echo "+----------------------------------------------------------------------+"
echo "|  RustDesk Server OSS — Validation                                    |"
echo "+----------------------------------------------------------------------+"
printf "|  Run at   : %-56s |\n" "$(date)"
printf "|  Server IP: %-56s |\n" "$SERVER_IP"
echo "+----------------------------------------------------------------------+"
echo ""

# ── Docker daemon ──────────────────────────────────────────────────────────────
step "Docker"
if systemctl is-active --quiet docker; then
    ok "Docker daemon: running"
    add_status "Docker" "Daemon" PASS "active"
else
    fail "Docker daemon: not running"
    add_status "Docker" "Daemon" FAIL "inactive — run: systemctl start docker"
fi

# ── Containers ─────────────────────────────────────────────────────────────────
step "Containers"
for name in rustdesk-hbbs rustdesk-hbbr; do
    STATUS="$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")"
    if [[ "$STATUS" == "running" ]]; then
        ok "Container $name: running"
        add_status "Containers" "$name" PASS "running"
    else
        fail "Container $name: $STATUS"
        add_status "Containers" "$name" FAIL "$STATUS"
    fi
done

# ── Listening ports ────────────────────────────────────────────────────────────
step "Ports"
declare -A EXPECTED_PORTS=(
    ["21115"]="tcp|hbbs NAT type test"
    ["21116"]="tcp|hbbs ID registration"
    ["21117"]="tcp|hbbr relay"
)

for port in "${!EXPECTED_PORTS[@]}"; do
    IFS='|' read -r proto desc <<< "${EXPECTED_PORTS[$port]}"
    if ss -lntu | grep -q ":${port} "; then
        ok "Port ${port}/${proto}: LISTENING (${desc})"
        add_status "Ports" "${port}/${proto}" PASS "$desc"
    else
        fail "Port ${port}/${proto}: NOT listening"
        add_status "Ports" "${port}/${proto}" FAIL "not listening"
    fi
done

# UDP 21116 (hole punching)
if ss -lnu | grep -q ":21116 "; then
    ok "Port 21116/udp: LISTENING (hbbs UDP hole punching)"
    add_status "Ports" "21116/udp" PASS "hbbs hole punching"
else
    fail "Port 21116/udp: NOT listening"
    add_status "Ports" "21116/udp" FAIL "not listening"
fi

# Verify closed ports stay closed
step "Closed ports"
for closed in 21114 21118 21119; do
    if ss -lntu | grep -q ":${closed} "; then
        warn "Port ${closed} is unexpectedly OPEN — review your setup"
        add_status "Closed ports" "$closed" WARN "unexpectedly open"
    else
        ok "Port ${closed}: correctly closed"
        add_status "Closed ports" "$closed" PASS "not listening"
    fi
done

# ── UFW ────────────────────────────────────────────────────────────────────────
step "Firewall"
if ufw status | grep -q "Status: active"; then
    ok "UFW: active"
    add_status "Firewall" "UFW" PASS "active"
else
    fail "UFW: inactive"
    add_status "Firewall" "UFW" FAIL "inactive — run: ufw enable"
fi

if ufw status | grep -q "${SSH_PORT}/tcp"; then
    ok "UFW SSH rule: present (port ${SSH_PORT}/tcp)"
    add_status "Firewall" "SSH rule" PASS "port ${SSH_PORT}/tcp present"
else
    fail "UFW SSH rule: MISSING for port ${SSH_PORT}"
    add_status "Firewall" "SSH rule" FAIL "missing — risk of lockout"
fi

echo ""
ufw status numbered
echo ""

# ── SSH ────────────────────────────────────────────────────────────────────────
step "SSH"
if systemctl is-active --quiet ssh; then
    ok "SSH daemon: running"
    add_status "SSH" "Daemon" PASS "active"
else
    fail "SSH daemon: not running"
    add_status "SSH" "Daemon" FAIL "inactive"
fi

if ss -lnt | grep -q ":${SSH_PORT} "; then
    ok "SSH: listening on port ${SSH_PORT}"
    add_status "SSH" "Port ${SSH_PORT}" PASS "listening"
else
    fail "SSH: not listening on port ${SSH_PORT}"
    add_status "SSH" "Port ${SSH_PORT}" FAIL "not listening"
fi

# ── RustDesk keys ──────────────────────────────────────────────────────────────
step "Keys"
PUB_KEY="${RUSTDESK_DATA_DIR}/id_ed25519.pub"
PRIV_KEY="${RUSTDESK_DATA_DIR}/id_ed25519"

if [[ -f "$PUB_KEY" ]]; then
    ok "Public key: $PUB_KEY"
    add_status "Keys" "Public key" PASS "$PUB_KEY"
    echo ""
    echo "  RustDesk Public Key (paste into client):"
    echo "  $(cat "$PUB_KEY")"
    echo ""
else
    fail "Public key not found: $PUB_KEY"
    add_status "Keys" "Public key" FAIL "not found — is hbbs running?"
fi

if [[ -f "$PRIV_KEY" ]]; then
    PRIV_PERMS="$(stat -c '%a' "$PRIV_KEY")"
    if [[ "$PRIV_PERMS" == "600" ]]; then
        ok "Private key: $PRIV_KEY (perms: $PRIV_PERMS)"
        add_status "Keys" "Private key perms" PASS "$PRIV_PERMS"
    else
        warn "Private key perms are $PRIV_PERMS — should be 600"
        add_status "Keys" "Private key perms" WARN "$PRIV_PERMS (fix: chmod 600 $PRIV_KEY)"
    fi
else
    fail "Private key not found: $PRIV_KEY"
    add_status "Keys" "Private key" FAIL "not found"
fi

# ── Print summary ──────────────────────────────────────────────────────────────
print_summary
