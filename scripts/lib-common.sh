#!/usr/bin/env bash
# lib-common.sh — shared functions, output helpers, and status tracking
# Sourced by install.sh and each step script. Never run directly.

# ── Terminal colours ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Output helpers ─────────────────────────────────────────────────────────────
info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}   $*"; }
fail()  { echo -e "${RED}[FAIL]${RESET}   $*"; }
die()   { echo -e "${RED}[ERROR]${RESET}  $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}${BLUE}━━━ $* ${RESET}"; }

# ── Status accumulator ─────────────────────────────────────────────────────────
# Each entry: "CATEGORY|LABEL|RESULT|DETAIL"
# Populated by add_status() throughout all sourced step scripts.
declare -a _STATUS_LINES=()
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# add_status CATEGORY LABEL RESULT DETAIL
# RESULT must be one of: PASS FAIL WARN INFO
add_status() {
    local category="$1"
    local label="$2"
    local result="$3"
    local detail="${4:-}"
    _STATUS_LINES+=("${category}|${label}|${result}|${detail}")
    case "$result" in
        PASS) (( PASS_COUNT += 1 )) ;;
        FAIL) (( FAIL_COUNT += 1 )) ;;
        WARN) (( WARN_COUNT += 1 )) ;;
    esac
}

# ── Environment loader ─────────────────────────────────────────────────────────
# Finds and sources the nearest .env file relative to a given directory.
# Usage: load_env /path/to/script
load_env() {
    local base_dir
    base_dir="$(cd "${1:-$(dirname "${BASH_SOURCE[1]}")}" && pwd)"
    local env_file=""

    # Walk up from script dir to find .env
    local dir="$base_dir"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.env" ]]; then
            env_file="$dir/.env"
            break
        fi
        dir="$(dirname "$dir")"
    done

    if [[ -n "$env_file" ]]; then
        # shellcheck source=/dev/null
        source "$env_file"
    fi
}

# ── Root guard ─────────────────────────────────────────────────────────────────
require_root() {
    [[ "$EUID" -eq 0 ]] || die "This script must be run as root (sudo)."
}
