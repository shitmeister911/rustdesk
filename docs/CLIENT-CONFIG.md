# RustDesk Client Configuration

How to point your RustDesk clients at your self-hosted server.

---

## What You Need

After install, the server displays the following. Keep these values handy.

| Field | Where to get it |
|-------|-----------------|
| **ID Server** | The `SERVER_IP` you set in `.env` |
| **Key** | Contents of `/opt/rustdesk/data/id_ed25519.pub` |
| **Relay Server** | Leave blank — hbbs advertises hbbr automatically |

> **Tip:** The install script and `validate.sh` both print these values at the end. You can also retrieve the key at any time:
> ```bash
> cat /opt/rustdesk/data/id_ed25519.pub
> ```

---

## Step-by-Step Client Setup

These steps are the same on Windows, macOS, and Linux.

**1.** Open RustDesk and click the menu icon (three dots or gear icon near the ID field).

**2.** Go to **Settings** → **Network**.

**3.** Unlock the network settings if prompted.

**4.** Fill in:
   - **ID Server**: your server's public IP address or domain name
   - **Relay Server**: leave empty
   - **API Server**: leave empty (Pro only — not used here)
   - **Key**: paste the full contents of `id_ed25519.pub`

**5.** Click **Apply** or **OK**.

**6.** RustDesk will reconnect and register with your server. The ID displayed in the main window is now registered on your server.

---

## What the Key Field Does

The `Key` field in the client is the server's ed25519 public key. It serves two purposes:

1. **Authentication** — the client verifies it is talking to your server and not an impostor
2. **Encryption** — session negotiation is signed with this key

If the key is wrong or missing, clients will connect to the ID server but relay sessions will fail or be untrusted.

---

## Mobile Clients (Android / iOS)

The same settings apply on mobile:

- Open RustDesk → **Settings** → **Network** (or server icon)
- ID Server: your IP
- Key: paste the public key
- Relay: leave empty

---

## Verify the Client is Connected

After configuration, the RustDesk client status bar should show a green dot or "Ready". If it shows "Connecting..." indefinitely:

- Check that ports 21115, 21116 (TCP+UDP), and 21117 are open on the server
- Check that the cloud provider firewall (security groups, etc.) allows those ports
- Verify the server IP is correct and publicly reachable
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for more

---

## Retrieve the Key Later

```bash
# On the server
cat /opt/rustdesk/data/id_ed25519.pub

# Or with the built-in alias (after login)
rdkey
```

---

## Multiple Clients on One Server

All clients point to the same server IP and use the same key. Each device registers its own unique ID on your server automatically when it connects.

---

## Updating the Key on Clients

If you restore from backup with a **different** key pair (e.g., disaster recovery to a new server with new keys):

1. Retrieve the new public key from the server
2. Update the **Key** field in each client's network settings
3. Clients will reconnect and re-register

If you restore the **same** key pair, no client changes are needed.
