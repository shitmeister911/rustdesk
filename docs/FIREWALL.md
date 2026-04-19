# Firewall Configuration

This document explains every UFW rule used by this setup, what each port does, and what remains closed by default.

---

## Why UFW?

UFW (Uncomplicated Firewall) is the standard host firewall on Debian. It wraps `iptables` with a simple CLI. This setup uses **host networking** for Docker, which means UFW rules on the host directly protect all RustDesk ports — there is no Docker NAT layer in between.

---

## Rule Order Matters

The install script adds the **SSH rule first** before enabling UFW. This is critical. If UFW is enabled with no SSH rule present, all active SSH sessions are cut immediately and the server becomes unreachable remotely.

```bash
# CORRECT order in 05-firewall.sh:
ufw allow 2222/tcp comment "SSH admin access"   # 1. SSH first
ufw allow 21115/tcp ...                          # 2. then RustDesk
ufw --force enable                               # 3. enable last
```

---

## Open Ports

| Port | Protocol | Service | Purpose | Required? |
|------|----------|---------|---------|-----------|
| `SSH_PORT` | TCP | sshd | Admin remote access | Yes |
| 21115 | TCP | hbbs | NAT type test — clients probe server NAT type before connecting | Yes |
| 21116 | TCP | hbbs | ID registration and heartbeat — clients register their ID and stay alive | Yes |
| 21116 | UDP | hbbs | UDP hole punching — enables direct peer-to-peer connections | Yes |
| 21117 | TCP | hbbr | Relay traffic — encrypted fallback when direct connection fails | Yes |

---

## Closed Ports

These ports are intentionally **not opened**. They are documented here to prevent confusion.

| Port | Reason Closed |
|------|---------------|
| 21114 | RustDesk Pro API server only — OSS does not use this port |
| 21118 | hbbs web client interface — not enabled in this OSS setup |
| 21119 | hbbr web client interface — not enabled in this OSS setup |

> **Note:** Opening 21114, 21118, or 21119 will not make OSS work better. These ports serve Pro and web client features that are not present in the OSS binary.

---

## Why Host Networking?

RustDesk uses **UDP hole punching** on port 21116 to establish direct connections between peers. This technique requires that the UDP source port seen by the rendezvous server (hbbs) matches the port the peer is actually listening on.

Docker's bridge networking uses NAT, which rewrites source ports. This breaks hole punching. With `network_mode: host`, containers bind directly to the host's network interfaces and no port rewriting occurs.

---

## UFW Rule Comments

Every UFW rule in this setup includes a `comment` field. Comments are visible in `ufw status` output and serve as inline documentation — no need to remember what each port does.

```bash
# View all rules with comments:
ufw status numbered
```

---

## View Current Rules

```bash
# Full status with comments
ufw status verbose

# Numbered list (useful for deleting individual rules)
ufw status numbered

# Delete a rule by number
ufw delete 3
```

---

## Adding Optional Rules

To open a port not in the default setup:

```bash
ufw allow <port>/tcp comment "description of why"
```

To close a port that was previously opened:

```bash
ufw deny <port>/tcp comment "blocking reason"
```

Always add a comment. Future you will thank present you.
