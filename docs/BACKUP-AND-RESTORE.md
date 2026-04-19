# Backup and Restore

Back up your keys immediately after install. This is not optional.

---

## What to Back Up

### RustDesk ed25519 Key Pair

| File | Location | Sensitivity |
|------|----------|-------------|
| `id_ed25519` | `/opt/rustdesk/data/id_ed25519` | **Private — never share** |
| `id_ed25519.pub` | `/opt/rustdesk/data/id_ed25519.pub` | Public — safe to share |

**Why these matter:** The public key is what every RustDesk client must be configured with. The private key is what the server uses to authenticate sessions. If you lose the private key:
- All clients will fail to connect
- You must generate a new key pair
- Every client must be updated with the new public key

Losing the keys on a server with hundreds of connected clients is a significant recovery event.

### SSH Host Keys

SSH host keys are located at `/etc/ssh/ssh_host_*`. They identify the server to clients. If you rebuild the server without restoring these keys, SSH clients will see a "host key changed" warning and refuse to connect until the old entry is removed.

For most home/small setups, the SSH host keys are less critical than the RustDesk keys, but backing them up prevents connection warnings after a server rebuild.

---

## When to Back Up

- **Immediately after install** — before anything else
- **After any server rebuild** — verify keys are intact and match what clients expect
- **Periodically** — especially if you rotate keys intentionally

---

## Automated Backup Script

The included script handles encryption automatically:

```bash
sudo bash backup/backup-rustdesk-keys.sh
```

This will:
1. Create `~/rustdesk-backups/rustdesk-keys-<timestamp>.tar.gz`
2. Encrypt it with GPG (AES256) if GPG is available
3. Print instructions for copying it off-server

---

## Manual Backup

### Option A — SCP to local machine

```bash
# From your LOCAL machine:
scp -P 2222 root@<SERVER_IP>:/opt/rustdesk/data/id_ed25519  ~/rustdesk-backup/
scp -P 2222 root@<SERVER_IP>:/opt/rustdesk/data/id_ed25519.pub ~/rustdesk-backup/
```

### Option B — GPG-encrypted archive on server, then SCP

```bash
# On the SERVER (as root):
tar czf - /opt/rustdesk/data/id_ed25519 /opt/rustdesk/data/id_ed25519.pub \
  | gpg --symmetric --cipher-algo AES256 -o ~/rustdesk-keys-$(date +%Y%m%d).tar.gz.gpg

# Then from your LOCAL machine:
scp -P 2222 root@<SERVER_IP>:~/rustdesk-keys-*.tar.gz.gpg ~/rustdesk-backup/
```

### Where to store the backup

- Password manager file attachment (1Password, Bitwarden, KeePass)
- Encrypted USB drive kept offline
- Encrypted cloud storage (Veracrypt container, etc.)

Do **not** store unencrypted key files in Dropbox, Google Drive, or unencrypted email.

---

## Restore Procedure

Use the included restore script:

```bash
sudo bash restore/restore-rustdesk-keys.sh /path/to/rustdesk-keys-<timestamp>.tar.gz.gpg
```

The script will:
1. Stop the RustDesk containers
2. Prompt for GPG passphrase (if encrypted)
3. Extract and replace key files
4. Fix file permissions
5. Restart containers
6. Display the restored public key

### Manual restore (if not using the script)

```bash
# 1. Stop containers
docker compose -f /opt/rustdesk/compose.yml down

# 2. Decrypt and extract (if GPG-encrypted)
gpg --decrypt rustdesk-keys.tar.gz.gpg | tar xz -C /tmp/

# 3. Copy keys into place
cp /tmp/opt/rustdesk/data/id_ed25519     /opt/rustdesk/data/id_ed25519
cp /tmp/opt/rustdesk/data/id_ed25519.pub /opt/rustdesk/data/id_ed25519.pub

# 4. Fix permissions
chmod 600 /opt/rustdesk/data/id_ed25519
chmod 644 /opt/rustdesk/data/id_ed25519.pub
chown root:root /opt/rustdesk/data/id_ed25519*

# 5. Restart containers
docker compose -f /opt/rustdesk/compose.yml up -d

# 6. Verify
sudo bash validate.sh
```

---

## After a Restore

- **Same key pair restored** → existing clients need no changes; they will reconnect automatically
- **New/different key pair** → distribute the new `id_ed25519.pub` to all clients via Settings > Network > Key
