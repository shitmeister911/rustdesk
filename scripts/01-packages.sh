#!/usr/bin/env bash
# 01-packages.sh — install required base system packages
# Idempotent: checks each package before installing.
#
# Standalone: sudo bash scripts/01-packages.sh
# Sourced by: install.sh

set -euo pipefail

step_01_packages() {
    step "Base packages"

    info "Updating apt package index..."
    apt-get update -qq
    add_status "Packages" "apt-get update" PASS "index refreshed"

    # Packages and why each one is needed
    declare -A PKGS=(
        [curl]="downloads Docker GPG key and tests connectivity"
        [wget]="alternative downloader"
        [gnupg]="verifies Docker apt repo GPG signature"
        [ca-certificates]="trusts HTTPS apt sources"
        [lsb-release]="detects distro codename for Docker repo URL"
        [ufw]="host firewall"
        [openssh-server]="remote admin access"
        [unattended-upgrades]="automatic security-only patches"
        [apt-listchanges]="shows changelogs for automated upgrades"
        [fail2ban]="bans IPs after repeated auth failures"
        [jq]="JSON parsing in validate.sh"
        [net-tools]="netstat — legacy compatibility"
        [iproute2]="ss and ip — used in validate.sh"
    )

    for pkg in "${!PKGS[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            ok "$pkg — already installed."
            add_status "Packages" "$pkg" PASS "already present"
        else
            info "Installing $pkg (${PKGS[$pkg]})..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" -qq
            ok "$pkg installed."
            add_status "Packages" "$pkg" PASS "installed"
        fi
    done
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    require_root
    step_01_packages
fi
# STANDALONE_ONLY_END
