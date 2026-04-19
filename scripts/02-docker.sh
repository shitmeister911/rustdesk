#!/usr/bin/env bash
# 02-docker.sh — install Docker Engine and Docker Compose plugin
# Uses Docker's official apt repo. Handles Debian 13 "trixie" fallback to
# "bookworm" if trixie is not yet listed (packages are ABI-compatible on amd64).
# Idempotent: skips install if Docker is already present.
#
# Standalone: sudo bash scripts/02-docker.sh
# Sourced by: install.sh

set -euo pipefail

step_02_docker() {
    step "Docker Engine"

    # ── Skip if already installed ─────────────────────────────────────────────
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

        # Detect Debian codename (trixie for Debian 13)
        DEBIAN_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-bookworm}")"
        info "Detected Debian codename: $DEBIAN_CODENAME"

        # Probe Docker's repo to confirm the codename is listed.
        # Falls back to bookworm — Docker .deb packages are compatible with trixie amd64.
        REPO_URL="https://download.docker.com/linux/debian/dists/${DEBIAN_CODENAME}/Release"
        if ! curl -fsSL --max-time 10 --head "$REPO_URL" &>/dev/null; then
            warn "Docker apt repo has no listing for '${DEBIAN_CODENAME}' — using 'bookworm' fallback."
            DEBIAN_CODENAME="bookworm"
        fi

        info "Adding Docker apt source (${DEBIAN_CODENAME})..."
        echo \
            "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian ${DEBIAN_CODENAME} stable" \
            | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -qq

        info "Installing Docker Engine..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin -qq

        DOCKER_VER="$(docker --version | awk '{print $3}' | tr -d ',')"
        ok "Docker Engine installed: $DOCKER_VER"
        add_status "Docker" "Docker Engine" PASS "$DOCKER_VER"
    fi

    # ── Docker service ────────────────────────────────────────────────────────
    systemctl enable docker --quiet
    systemctl start docker
    if systemctl is-active --quiet docker; then
        ok "Docker daemon is running."
        add_status "Docker" "Daemon" PASS "active"
    else
        fail "Docker daemon failed to start."
        add_status "Docker" "Daemon" FAIL "inactive"
        die "Docker daemon not running — check: journalctl -u docker"
    fi

    # ── Compose plugin ────────────────────────────────────────────────────────
    if docker compose version &>/dev/null; then
        COMPOSE_VER="$(docker compose version --short 2>/dev/null || docker compose version | awk '{print $NF}')"
        ok "Docker Compose plugin: $COMPOSE_VER"
        add_status "Docker" "Compose plugin" PASS "$COMPOSE_VER"
    else
        fail "Docker Compose plugin not found."
        add_status "Docker" "Compose plugin" FAIL "not found"
        die "Compose plugin missing — check: apt install docker-compose-plugin"
    fi

    # ── Add admin user to docker group ────────────────────────────────────────
    if [[ -n "${ADMIN_USER:-}" ]] && id "$ADMIN_USER" &>/dev/null; then
        usermod -aG docker "$ADMIN_USER"
        ok "Added $ADMIN_USER to docker group."
        add_status "Docker" "docker group" PASS "$ADMIN_USER added"
    fi
}

# ── Standalone execution ───────────────────────────────────────────────────────
# STANDALONE_ONLY_BEGIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib-common.sh"
    load_env "$SCRIPT_DIR"
    require_root
    step_02_docker
fi
# STANDALONE_ONLY_END
