# SSH Configuration

This document explains the SSH hardening applied by this setup, how key authentication works, and how to connect from different operating systems.

---

## Why Password Login is Disabled

Password-based SSH is the primary target of automated brute-force attacks. Bots continuously scan the internet for port 22 (and common alternates) and attempt thousands of credential combinations per minute. Disabling password authentication eliminates this entire attack surface.

With `PasswordAuthentication no` set, only clients holding a private key that matches an entry in `authorized_keys` can authenticate. A stolen password is useless. A missing key is a complete block.

---

## Why Root Login is Disabled

Direct root SSH access is disabled with `PermitRootLogin no`. This forces all admin work through a named user with `sudo`. Benefits:

- Audit logs show the real user, not just "root"
- A compromised session requires an additional privilege escalation step
- Limits the blast radius of a stolen SSH key

All admin tasks on this server are performed by the `ADMIN_USER` (default: `rdadmin`) using `sudo`.

---

## How Key Authentication Works

1. You generate an SSH key pair on your local machine (private key + public key)
2. The public key is placed in `~/.ssh/authorized_keys` on the server
3. When you connect, your SSH client presents a cryptographic proof using your private key
4. The server verifies the proof against the stored public key — no password exchange ever occurs

The private key never leaves your machine. Even if the server is fully compromised, an attacker cannot learn your private key from `authorized_keys`.

---

## Generate an SSH Key (if you don't have one)

**Linux / macOS:**
```bash
ssh-keygen -t ed25519 -C "your@email.com"
# Key saved to: ~/.ssh/id_ed25519
# Public key:   ~/.ssh/id_ed25519.pub
```

**Windows (PowerShell):**
```powershell
ssh-keygen -t ed25519 -C "your@email.com"
# Key saved to: C:\Users\<you>\.ssh\id_ed25519
# Public key:   C:\Users\<you>\.ssh\id_ed25519.pub
```

---

## Add Your Public Key to the Server

Do this **before** running `02-harden.sh` — once passwords are disabled, you need the key to log in.

**Linux / macOS:**
```bash
ssh-copy-id -p 2222 -i ~/.ssh/id_ed25519.pub rdadmin@<SERVER_IP>
```

**Windows (PowerShell) — manual method:**
```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p 2222 rdadmin@<SERVER_IP> "cat >> ~/.ssh/authorized_keys"
```

---

## Connect from Linux / macOS

```bash
ssh -p 2222 rdadmin@<SERVER_IP>
```

Or add an entry to `~/.ssh/config`:

```
Host rustdesk
  HostName <SERVER_IP>
  User rdadmin
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
```

Then simply:
```bash
ssh rustdesk
```

---

## Connect from Windows

Windows 10 (1809+) and Windows 11 include a built-in OpenSSH client.

**Step 1:** Open `C:\Users\<YourUsername>\.ssh\config` (create if it doesn't exist) and add:

```
Host rustdesk
  HostName <SERVER_IP>
  User rdadmin
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

A ready-to-edit example is in [`examples/windows-ssh-config-example.txt`](../examples/windows-ssh-config-example.txt).

**Step 2:** Open PowerShell or Windows Terminal and run:

```powershell
ssh rustdesk
```

---

## Hardening Settings Applied

The drop-in file `/etc/ssh/sshd_config.d/99-hardened.conf` contains:

| Setting | Value | Reason |
|---------|-------|--------|
| `PasswordAuthentication` | `no` | Eliminates brute-force attack surface |
| `PermitRootLogin` | `no` | Forces named-user + sudo workflow |
| `PubkeyAuthentication` | `yes` | Explicit key auth requirement |
| `PermitEmptyPasswords` | `no` | Prevents blank-password accounts |
| `X11Forwarding` | `no` | Removes GUI tunneling attack surface |
| `AllowTcpForwarding` | `no` | Disables port-forwarding abuse |
| `MaxAuthTries` | `3` | Limits per-connection brute attempts |
| `LoginGraceTime` | `30` | Disconnects unauthenticated sessions after 30s |
| `ClientAliveInterval` | `300` | Detects dead connections every 5 min |
| `ClientAliveCountMax` | `2` | Drops after 2 missed keepalives (~10 min) |
| `Banner` | `/etc/issue.net` | Legal warning displayed before authentication |

The drop-in lives in `sshd_config.d/` so it survives `apt upgrade openssh-server` without being overwritten.

---

## Verify SSH Hardening

```bash
# Check current config (as root)
sshd -T | grep -E 'passwordauth|permitroot|pubkeyauth|port'

# Check listening port
ss -lnt | grep ':2222'

# Check drop-in is loaded
cat /etc/ssh/sshd_config.d/99-hardened.conf
```
