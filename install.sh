#!/usr/bin/env bash
# install.sh — RustDesk Server OSS — main installer for Debian 13 amd64
#
# Orchestrates all setup steps in sequence. Run as root.
# Each step is a separate script in scripts/ for readability and modularity.
#
# Usage:
#   cp .env.example .env && nano .env   # fill in SERVER_IP at minimum
#   sudo bash install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Check .env ────────────────────────────────────────────────────────────────
if [[ ! -f "${REPO_DIR}/.env" ]]; then
    echo ""
    echo "[ERROR]  .env not found in ${REPO_DIR}"
    echo "         Copy the template and fill in your SERVER_IP:"
    echo "           cp .env.example .env"
    echo "           nano .env"
    echo ""
    exit 1
fi

# ── Load shared library ───────────────────────────────────────────────────────
# shellcheck source=scripts/lib-common.sh
source "${REPO_DIR}/scripts/lib-common.sh"

# Load .env (SERVER_IP, ADMIN_USER, SSH_PORT, etc.)
load_env "$REPO_DIR"

require_root

# ── Variables with defaults ───────────────────────────────────────────────────
export ADMIN_USER="${ADMIN_USER:-rdadmin}"
export SSH_PORT="${SSH_PORT:-2222}"
export SERVER_IP="${SERVER_IP:-}"
export RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/opt/rustdesk/data}"
export DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-10m}"
export DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE:-3}"
export UNATTENDED_UPGRADES_EMAIL="${UNATTENDED_UPGRADES_EMAIL:-}"
export REPO_DIR

# ── Source step scripts (defines functions; does not run them yet) ────────────
# shellcheck source=scripts/00-preflight.sh
source "${REPO_DIR}/scripts/00-preflight.sh"
# shellcheck source=scripts/01-packages.sh
source "${REPO_DIR}/scripts/01-packages.sh"
# shellcheck source=scripts/02-docker.sh
source "${REPO_DIR}/scripts/02-docker.sh"
# shellcheck source=scripts/03-user-hardening.sh
source "${REPO_DIR}/scripts/03-user-hardening.sh"
# shellcheck source=scripts/04-ssh-hardening.sh
source "${REPO_DIR}/scripts/04-ssh-hardening.sh"
# shellcheck source=scripts/05-firewall.sh
source "${REPO_DIR}/scripts/05-firewall.sh"
# shellcheck source=scripts/06-rustdesk-compose.sh
source "${REPO_DIR}/scripts/06-rustdesk-compose.sh"
# shellcheck source=scripts/07-start-services.sh
source "${REPO_DIR}/scripts/07-start-services.sh"
# shellcheck source=scripts/08-show-keys.sh
source "${REPO_DIR}/scripts/08-show-keys.sh"
# shellcheck source=scripts/09-final-status.sh
source "${REPO_DIR}/scripts/09-final-status.sh"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "+----------------------------------------------------------------------+"
echo "|  RustDesk Server OSS — Debian 13 amd64 Installer                    |"
echo "+----------------------------------------------------------------------+"
printf "|  Server IP  : %-54s |\n" "${SERVER_IP:-<not set>}"
printf "|  Admin user : %-54s |\n" "$ADMIN_USER"
printf "|  SSH port   : %-54s |\n" "$SSH_PORT"
printf "|  Data dir   : %-54s |\n" "$RUSTDESK_DATA_DIR"
echo "+----------------------------------------------------------------------+"
echo ""

# ── Run steps in order ────────────────────────────────────────────────────────
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
