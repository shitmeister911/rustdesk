#!/usr/bin/env bash
# 00-preflight.sh — pre-flight checks before any changes are made
# Verifies: root, Debian OS, amd64 arch, internet, required env vars.
#
# Standalone: sudo bash scripts/00-preflight.sh
# Sourced by: install.sh

set -euo pipefail

step_00_preflight() {
    step "Pre-flight checks"

    # ── Root ──────────────────────────────────────────────────────────────────
    if [[ "$EUID" -eq 0 ]]; then
        ok "Running as root."
        add_status "System" "Root privileges" PASS "uid=0"
    else
        fail "Must run as root (sudo)."
        add_status "System" "Root privileges" FAIL "uid=$EUID"
        die "Re-run with: sudo bash install.sh"
    fi

    # ── OS detection ──────────────────────────────────────────────────────────
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_PRETTY="${PRETTY_NAME:-unknown}"
        OS_ID="${ID:-unknown}"
    else
        OS_PRETTY="unknown"
        OS_ID="unknown"
    fi

    if [[ "$OS_ID" == "debian" ]]; then
        ok "OS: $OS_PRETTY"
        add_status "System" "OS" PASS "$OS_PRETTY"
    else
        warn "Expected Debian; detected: $OS_PRETTY — proceed with caution."
        add_status "System" "OS" WARN "$OS_PRETTY (expected Debian)"
    fi

    # ── Architecture ──────────────────────────────────────────────────────────
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "x86_64" ]]; then
        ok "Architecture: $ARCH (amd64)"
        add_status "System" "Architecture" PASS "$ARCH / amd64"
    else
        warn "Expected x86_64; detected: $ARCH — Docker install may fail."
        add_status "System" "Architecture" WARN "$ARCH (expected x86_64)"
    fi

    # ── Internet connectivity ─────────────────────────────────────────────────
    info "Checking internet connectivity..."
    if curl -fsSL --max-time 10 https://download.docker.com > /dev/null 2>&1; then
        ok "Internet reachable (Docker CDN)."
        add_status "System" "Internet connectivity" PASS "Docker CDN reachable"
    else
        fail "Cannot reach download.docker.com. Check network/DNS."
        add_status "System" "Internet connectivity" FAIL "download.docker.com unreachable"
        die "No internet access — cannot continue."
    fi

    # ── SERVER_IP ─────────────────────────────────────────────────────────────
    if [[ -n "${SERVER_IP:-}" ]]; then
        ok "SERVER_IP set: $SERVER_IP"
        add_status "System" "SERVER_IP" PASS "$SERVER_IP"
    else
        fail "SERVER_IP is not set. Copy .env.example to .env and fill it in."
        add_status "System" "SERVER_IP" FAIL "not set"
        die "SERVER_IP required. See .env.example."
    fi

    # ── Hostname ──────────────────────────────────────────────────────────────
    HOST="$(hostname -f 2>/dev/null || hostname)"
    info "Hostname: $HOST"
    add_status "System" "Hostname" INFO "$HOST"

    ok "Pre-flight checks passed."
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    step_00_preflight
fi
# STANDALONE_ONLY_END
