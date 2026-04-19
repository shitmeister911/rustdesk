#!/usr/bin/env bash
# backup/backup-rustdesk-keys.sh — back up RustDesk ed25519 key pair
#
# Creates an encrypted .tar.gz of the RustDesk key pair and optionally
# copies it off-server via scp. If GPG is not available, creates an
# unencrypted archive and warns loudly.
#
# Usage: sudo bash backup/backup-rustdesk-keys.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../scripts/lib-common.sh
source "${REPO_DIR}/scripts/lib-common.sh"
load_env "$REPO_DIR"

require_root

RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/opt/rustdesk/data}"
BACKUP_DIR="${HOME}/rustdesk-backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/rustdesk-keys-${TIMESTAMP}.tar.gz"
GPG_FILE="${BACKUP_FILE}.gpg"

# ── Create backup directory ────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# ── Check source files ─────────────────────────────────────────────────────────
PUB_KEY="${RUSTDESK_DATA_DIR}/id_ed25519.pub"
PRIV_KEY="${RUSTDESK_DATA_DIR}/id_ed25519"

if [[ ! -f "$PRIV_KEY" ]] || [[ ! -f "$PUB_KEY" ]]; then
    fail "Key files not found in ${RUSTDESK_DATA_DIR}"
    fail "Has hbbs run at least once? Check: docker logs rustdesk-hbbs"
    exit 1
fi

info "Source: $RUSTDESK_DATA_DIR"
info "Destination: $BACKUP_DIR"
echo ""

# ── Create tar archive ────────────────────────────────────────────────────────
tar czf "$BACKUP_FILE" \
    -C "$(dirname "$RUSTDESK_DATA_DIR")" \
    "$(basename "$RUSTDESK_DATA_DIR")/id_ed25519" \
    "$(basename "$RUSTDESK_DATA_DIR")/id_ed25519.pub"

ok "Archive created: $BACKUP_FILE"

# ── Encrypt if GPG is available ───────────────────────────────────────────────
if command -v gpg &>/dev/null; then
    info "Encrypting archive with GPG symmetric encryption (AES256)..."
    info "You will be prompted for a passphrase — store it somewhere safe."
    echo ""
    gpg --symmetric --cipher-algo AES256 --output "$GPG_FILE" "$BACKUP_FILE"
    rm -f "$BACKUP_FILE"  # remove unencrypted copy
    chmod 600 "$GPG_FILE"
    ok "Encrypted backup: $GPG_FILE"
    echo ""
    echo "  Store this file in an encrypted location:"
    echo "    - 1Password / Bitwarden file attachment"
    echo "    - Encrypted USB drive"
    echo "    - Offline storage"
    echo ""
    echo "  To decrypt later:"
    echo "    gpg --decrypt $GPG_FILE | tar xz -C /tmp/"
else
    warn "GPG not installed — backup is UNENCRYPTED."
    warn "Install GPG and re-run, or encrypt the file manually:"
    warn "  apt-get install gpg"
    chmod 600 "$BACKUP_FILE"
    ok "Unencrypted backup: $BACKUP_FILE (chmod 600)"
fi

# ── Optional: SCP to remote ───────────────────────────────────────────────────
echo ""
echo "  To copy the backup to your local machine:"
FINAL_FILE="${GPG_FILE:-$BACKUP_FILE}"
echo "    scp -P ${SSH_PORT:-2222} root@${SERVER_IP:-<SERVER_IP>}:${FINAL_FILE} ~/rustdesk-backups/"
echo ""
echo "  See: docs/BACKUP-AND-RESTORE.md for full restore instructions."
echo ""
