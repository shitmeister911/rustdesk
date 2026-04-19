#!/usr/bin/env bash
# restore/restore-rustdesk-keys.sh — restore RustDesk ed25519 key pair from backup
#
# Stops containers, replaces key files, fixes permissions, restarts containers.
# Works with both encrypted (.tar.gz.gpg) and unencrypted (.tar.gz) archives.
#
# Usage: sudo bash restore/restore-rustdesk-keys.sh <path-to-backup-file>
# Example:
#   sudo bash restore/restore-rustdesk-keys.sh ~/rustdesk-backups/rustdesk-keys-20250101-120000.tar.gz.gpg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../scripts/lib-common.sh
source "${REPO_DIR}/scripts/lib-common.sh"
load_env "$REPO_DIR"

require_root

BACKUP_FILE="${1:-}"
RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/opt/rustdesk/data}"
DEPLOY_DIR="/opt/rustdesk"

# ── Validate arguments ─────────────────────────────────────────────────────────
if [[ -z "$BACKUP_FILE" ]]; then
    echo ""
    echo "Usage: sudo bash restore/restore-rustdesk-keys.sh <backup-file>"
    echo ""
    echo "Examples:"
    echo "  sudo bash restore/restore-rustdesk-keys.sh ~/rustdesk-backups/rustdesk-keys-20250101.tar.gz.gpg"
    echo "  sudo bash restore/restore-rustdesk-keys.sh ~/rustdesk-backups/rustdesk-keys-20250101.tar.gz"
    echo ""
    exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    die "Backup file not found: $BACKUP_FILE"
fi

echo ""
info "Restore from: $BACKUP_FILE"
info "Destination:  $RUSTDESK_DATA_DIR"
echo ""
warn "This will REPLACE the current key files."
warn "After restore, clients configured with the old key may need updating."
echo ""
read -rp "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Restore cancelled."; exit 0; }
echo ""

# ── Stop containers ───────────────────────────────────────────────────────────
info "Stopping RustDesk containers..."
if docker compose -f "${DEPLOY_DIR}/compose.yml" ps --quiet 2>/dev/null | grep -q .; then
    docker compose -f "${DEPLOY_DIR}/compose.yml" down
    ok "Containers stopped."
else
    info "Containers not running — continuing."
fi

# ── Extract backup ────────────────────────────────────────────────────────────
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ "$BACKUP_FILE" == *.gpg ]]; then
    info "Decrypting backup (you will be prompted for the GPG passphrase)..."
    gpg --decrypt "$BACKUP_FILE" | tar xz -C "$WORK_DIR"
    ok "Decrypted and extracted."
else
    info "Extracting archive..."
    tar xzf "$BACKUP_FILE" -C "$WORK_DIR"
    ok "Extracted."
fi

# ── Locate key files in extracted content ─────────────────────────────────────
EXTRACTED_PRIV="$(find "$WORK_DIR" -name 'id_ed25519' ! -name '*.pub' | head -1)"
EXTRACTED_PUB="$(find "$WORK_DIR" -name 'id_ed25519.pub' | head -1)"

[[ -n "$EXTRACTED_PRIV" ]] || die "id_ed25519 not found in archive."
[[ -n "$EXTRACTED_PUB"  ]] || die "id_ed25519.pub not found in archive."

# ── Restore key files ─────────────────────────────────────────────────────────
mkdir -p "$RUSTDESK_DATA_DIR"

cp "$EXTRACTED_PRIV" "${RUSTDESK_DATA_DIR}/id_ed25519"
cp "$EXTRACTED_PUB"  "${RUSTDESK_DATA_DIR}/id_ed25519.pub"

chmod 600 "${RUSTDESK_DATA_DIR}/id_ed25519"
chmod 644 "${RUSTDESK_DATA_DIR}/id_ed25519.pub"
chown root:root "${RUSTDESK_DATA_DIR}/id_ed25519" "${RUSTDESK_DATA_DIR}/id_ed25519.pub"

ok "Keys restored to $RUSTDESK_DATA_DIR"

# ── Start containers ──────────────────────────────────────────────────────────
info "Starting RustDesk containers..."
docker compose -f "${DEPLOY_DIR}/compose.yml" up -d
sleep 3

for name in rustdesk-hbbs rustdesk-hbbr; do
    STATUS="$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")"
    if [[ "$STATUS" == "running" ]]; then
        ok "Container '$name' is running."
    else
        fail "Container '$name' status: $STATUS"
    fi
done

echo ""
ok "Restore complete."
echo ""
echo "  Restored public key:"
cat "${RUSTDESK_DATA_DIR}/id_ed25519.pub"
echo ""
echo "  If the key changed from what clients previously had, update clients:"
echo "    Settings > Network > Key  →  paste the key above"
echo ""
echo "  Run validation: sudo bash validate.sh"
echo ""
