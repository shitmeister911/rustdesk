# Troubleshooting

Common problems and how to fix them.

---

## Docker Not Installing

**Symptom:** `apt-get install docker-ce` fails or the apt source returns 404.

**Cause:** Docker's apt repo may not yet list the Debian codename for your release (e.g., `trixie` for Debian 13).

**Fix:** The install script auto-detects this and falls back to `bookworm`. If you are running the script manually:

```bash
# Check what codename was detected
. /etc/os-release && echo $VERSION_CODENAME

# Test if Docker's repo has it
curl -fsSL --head https://download.docker.com/linux/debian/dists/trixie/Release

# If 404, use bookworm manually
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian bookworm stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

---

## Docker Daemon Not Starting

**Symptom:** `systemctl status docker` shows failed or inactive.

**Diagnosis:**
```bash
journalctl -u docker -n 50 --no-pager
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| containerd not running | `systemctl start containerd && systemctl start docker` |
| Storage driver conflict | Check `/etc/docker/daemon.json` for errors |
| Disk full | `df -h` — free space and retry |

---

## Docker Compose Plugin Missing

**Symptom:** `docker compose version` returns "command not found" or `docker: 'compose' is not a docker command`.

**Fix:**
```bash
sudo apt-get install -y docker-compose-plugin

# Verify
docker compose version
```

The old standalone `docker-compose` (v1) is different from the Compose plugin (`docker compose`). This setup requires the plugin.

---

## UFW Enabled but Access Blocked

**Symptom:** UFW is active but RustDesk clients cannot connect.

**Check rules:**
```bash
ufw status numbered
```

**Check that all required rules exist:**
```bash
ufw status | grep -E '21115|21116|21117'
```

**If rules are missing, add them:**
```bash
ufw allow 21115/tcp comment "RustDesk hbbs NAT type test"
ufw allow 21116/tcp comment "RustDesk hbbs ID registration"
ufw allow 21116/udp comment "RustDesk hbbs UDP hole punching"
ufw allow 21117/tcp comment "RustDesk hbbr relay"
ufw reload
```

**Also check:** Cloud provider firewall/security groups. UFW only controls the host firewall. If your VPS has a separate network-level firewall (e.g., AWS Security Groups, GCP Firewall Rules, Hetzner Firewall), those ports must be open there too.

---

## SSH Lockout Prevention

**Before running `04-ssh-hardening.sh`:**

1. Add your SSH public key to `authorized_keys`
2. Test that key-based login works in a **new terminal** (keep the original session open)
3. Only then run the hardening script

**If you are already locked out:**

- Use your VPS provider's web console or VNC to access the server
- Check `/etc/ssh/sshd_config.d/99-hardened.conf`
- To temporarily re-enable passwords (emergency only):
  ```bash
  sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/99-hardened.conf
  systemctl restart ssh
  # Add your key, then restore: PasswordAuthentication no
  ```

**Check SSH is listening on the right port:**
```bash
ss -lnt | grep ':2222'
journalctl -u ssh -n 20
```

---

## RustDesk Containers Not Running

**Symptom:** `docker ps` does not show rustdesk-hbbs or rustdesk-hbbr.

**Diagnosis:**
```bash
# Check container state (even stopped containers)
docker ps -a --filter name=rustdesk

# View logs
docker logs rustdesk-hbbs --tail 50
docker logs rustdesk-hbbr --tail 50
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| compose.yml missing | Check `/opt/rustdesk/compose.yml` exists |
| SERVER_IP not set | Edit `/opt/rustdesk/.env` and restart |
| Port already in use | `ss -lntu \| grep 21116` — find conflicting process |
| Image pull failed | `docker compose -f /opt/rustdesk/compose.yml pull` |

**Restart containers:**
```bash
docker compose -f /opt/rustdesk/compose.yml up -d
```

---

## RustDesk Key Missing

**Symptom:** `/opt/rustdesk/data/id_ed25519.pub` does not exist.

**Cause:** hbbs generates the key pair on first startup. If hbbs has not run or exited immediately, the key may not be written.

**Fix:**
```bash
# Check if hbbs is running
docker logs rustdesk-hbbs --tail 50

# If hbbs crashed, check why and restart
docker compose -f /opt/rustdesk/compose.yml up -d

# Wait 30 seconds and check again
sleep 30 && ls -la /opt/rustdesk/data/
```

If the data directory permissions are wrong:
```bash
chmod 750 /opt/rustdesk/data
chown root:root /opt/rustdesk/data
docker compose -f /opt/rustdesk/compose.yml restart hbbs
```

---

## DNS or Public IP Mistakes

**Symptom:** Clients register on the server but cannot connect to each other (relay fails).

**Cause:** The `SERVER_IP` used in the `hbbs -r` command is not reachable from the internet.

**Common mistakes:**
- Using a private IP (10.x.x.x, 192.168.x.x) instead of the public IP
- Using `127.0.0.1` or `localhost`
- DNS name that resolves differently for internal vs. external clients

**Fix:**
```bash
# Check what address hbbs is advertising
docker logs rustdesk-hbbs | grep -i relay

# Update SERVER_IP in /opt/rustdesk/.env
nano /opt/rustdesk/.env

# Regenerate compose.yml with correct IP (re-run step 6)
# Edit /opt/rustdesk/compose.yml — change the -r flag
nano /opt/rustdesk/compose.yml

# Restart
docker compose -f /opt/rustdesk/compose.yml up -d
```

---

## Verification Commands

```bash
# Full validation
sudo bash validate.sh

# Container status
docker ps --filter name=rustdesk

# Container logs (live)
docker logs rustdesk-hbbs -f --tail 50
docker logs rustdesk-hbbr -f --tail 50

# Listening ports
ss -lntu | grep -E '21115|21116|21117'

# UFW status
ufw status verbose

# SSH status
systemctl status ssh
ss -lnt | grep ':2222'

# RustDesk key
cat /opt/rustdesk/data/id_ed25519.pub

# fail2ban status
fail2ban-client status sshd

# Docker daemon
systemctl status docker
```
