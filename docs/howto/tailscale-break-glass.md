# Tailscale break-glass access (SSH and Screen Sharing from the iPad)

## What it is and is not

This is a secondary, human-only emergency break-glass route into the Macs (providing SSH on port 22 and Screen Sharing on port 5900) when normal access channels fail. It does not depend on cloudflared, the webhook, the cloud bridge or GitHub.

This path is not for agents: no AI agent, subagent or automated workflow receives a Tailscale identity, credentials or access.

It cannot reach a Mac that is powered off or waiting at the FileVault unlock screen after a reboot. Furthermore, the Standalone client is not a Tailscale SSH server; incoming shell access uses standard macOS Remote Login (OpenSSH).

## Before you start

- Maintain a dedicated Tailscale login secured with Multi-Factor Authentication (MFA), using a passkey or hardware security key (FIDO2/WebAuthn).
- Install the required client applications on the iPad (Decision D4):
  - A VNC client that supports macOS Screen Sharing authentication.
  - An SSH client that stores a dedicated, per-iPad private key in the iOS Keychain or Secure Enclave.
- Complete the P1 baseline verification on the home LAN before rolling out Tailscale:
  - Enable Screen Sharing on `m2` with "Only these users" set to your operator account and legacy VNC password off.
  - Connect from the iPad over local Wi-Fi while `m2` is clamshelled (lid closed) with no external monitor attached.
  - Verify that the desktop renders, the lock screen unlocks by typing the macOS password, and a modal system dialog (such as TCC or Keychain) can be dismissed.
  - If the display is black or renders in a tiny resolution without an active screen, attach an HDMI dummy plug (display emulator).
  - Turn Screen Sharing back off until the rollout reaches that machine.
- Verify that no work, corporate or shared devices are enrolled under this Tailscale login; it is strictly dedicated to the operator's personal administration.

## Set the policy first

Paste `docs/howto/tailscale/policy.hujson` with the real login substituted for `operator@example.com` into the Tailscale admin console policy editor before enrolling anything:

```json
{
  "groups": {"group:operator": ["operator@example.com"]},
  "tagOwners": {"tag:k3dm-mac": ["group:operator"]},
  "grants": [
    {"src": ["group:operator"], "dst": ["tag:k3dm-mac"], "ip": ["tcp:22", "tcp:5900"]},
    {"src": ["tag:k3dm-mac"], "dst": ["tag:k3dm-mac"], "ip": ["tcp:22"]}
  ],
  "tests": [
    {"src": "operator@example.com", "proto": "tcp", "accept": ["tag:k3dm-mac:22", "tag:k3dm-mac:5900"], "deny": ["tag:k3dm-mac:443", "tag:k3dm-mac:8080"]},
    {"src": "operator@example.com", "proto": "udp", "deny": ["tag:k3dm-mac:22", "tag:k3dm-mac:5900"]},
    {"src": "tag:k3dm-mac", "proto": "tcp", "accept": ["tag:k3dm-mac:22"], "deny": ["tag:k3dm-mac:5900", "tag:k3dm-mac:443"]}
  ]
}
```

- The save succeeds only if its tests pass; Tailscale evaluates test assertions before accepting policy updates.
- Remove the default allow-all rule so all traffic is blocked by default.
- Turn on device approval in the Tailscale admin console under Device management settings.
- Perform the P2 verification check:
  - Temporarily modify one test assertion in the editor to expect an invalid result (for example, change `"accept": ["tag:k3dm-mac:22"]` to `"deny"`).
  - Attempt to save the policy and confirm the console rejects the update with an error.
  - Restore the test assertion to its valid state and save the policy.

## Enroll the Macs and the iPad

- Enroll devices one at a time in the Decision D2 order: `m2` (operator desk, lowest operational risk), then `m5` (the hub cluster and webhook host), then `m4` (worker and agent runner).
- Install only the Standalone variant on each Mac, from a login shell in the k3d-manager checkout:
  ```bash
  make install-tailscale
  ```
  It installs the Standalone app (`brew install --cask tailscale-app`, bundle ID `io.tailscale.ipn.macsys`), checks the
  result, and does nothing if it is already there. It refuses, with instructions, when the Homebrew `tailscale` formula
  or the App Store variant is present, so only one network extension ever exists. Homebrew's installer asks for your
  macOS password; then open Tailscale from Applications and allow its system extension.
  - On `m4`: it refuses until you remove the Homebrew formula (`brew services stop tailscale; brew uninstall tailscale`)
    and the App Store copy (quit Tailscale, delete `/Applications/Tailscale.app`); run it again afterwards.
- Apply `tag:k3dm-mac` immediately during enrollment so no Mac ever sits untagged.
- Leave "Use Tailscale DNS settings" off in Tailscale preferences on the Macs to prevent MagicDNS from interfering with the hub's local DNS resolvers (`k3d`, `cloudflared`).
- Sign in from a terminal on the Mac, which tags the device, turns Tailscale DNS off and sets its name in one step
  (use the Mac's own short name):
  ```bash
  /Applications/Tailscale.app/Contents/MacOS/Tailscale up --advertise-tags=tag:k3dm-mac --accept-dns=false --hostname=<mac>
  ```
  Open the printed login link, sign in, then approve the device in the admin console. On `m2` (2026-11-26) the app's
  own "Sign in to your network" button did nothing, which is why this is the documented path.
- After a terminal sign-in, the menu-bar app can keep showing "Not Connected / Please log in" and hang on Quit, while
  the tunnel is up. Force Quit it (Option-Command-Escape, "Tailscale") and open it again; the tunnel is unaffected.
- The app's "Start at login" / "Launch Tailscale at login" toggle can fail with "Start on Login could not be set".
  Add `/Applications/Tailscale.app` under System Settings -> General -> Login Items & Extensions -> Open at Login
  instead, and prove it with a logout and login. Do not run `sfltool resetbtm`: it resets every app's background
  permissions.
- After the Mac's checks pass, turn on VPN On Demand (Settings -> VPN On Demand -> Manage...): Wi-Fi and Ethernet
  "Always", "Detect MagicDNS hostnames" off. Not on the iPad.
- Confirm in the admin console that key expiry shows disabled for each tagged Mac node (`tag:k3dm-mac`).
- On the iPad:
  - Install the Tailscale app from the iOS App Store and sign in with the operator login.
  - Confirm the iPad is held in unapproved state and is refused connection while unapproved.
  - In the Tailscale admin console, approve the iPad device.
- After enrolling `m5`:
  - Run the hub health check (webhook health endpoint) and one end-to-end read-only Slack request.
  - Run `scutil --dns` on `m5` and confirm no Tailscale resolver is present.
  - If any check fails, immediately turn VPN On Demand off and then disconnect Tailscale on `m5` as the rollback
    trigger (per L-E1); with On Demand on, a plain Disconnect is undone by macOS.

## Set up SSH from the iPad

- Make each Mac's SSH key-only first (the macOS default also accepts passwords). In System Settings -> General ->
  Sharing -> Remote Login -> (i), set "Allow access for" to "Only these users" with only the operator account. Then, in
  that Mac's terminal:
  ```bash
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/100-k3dm-key-only.conf
  ```
  It applies to new connections at once. Check from another machine with no credentials:
  `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=none <user>@<mac>.local true` must answer
  `Permission denied (publickey)`. Undo: `sudo rm /etc/ssh/sshd_config.d/100-k3dm-key-only.conf`.
- Generate a dedicated SSH key pair inside the iPad SSH application (using the Secure Enclave or iOS Keychain).
- Append the public key to `~/.ssh/authorized_keys` on each Mac (`m2`, `m5`, `m4`), adding an explicit comment naming the iPad (for example, `operator-ipad-break-glass`).
- Compare each Mac's host-key fingerprint on the home LAN (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`) before the first tailnet connection, and verify the host-key fingerprint matches when connecting from the iPad.

## Turn on Screen Sharing

- On each Mac, open System Settings -> General -> Sharing, and turn on Screen Sharing.
- Under "Allow access for", configure "Only these users" and select only the operator account.
- Ensure "VNC viewers may control screen with password" is off (legacy VNC password disabled).
- Type the macOS user account password each time when connecting; never save the macOS password in the iPad VNC app (since it also secures `sudo` and the login Keychain).
- Apply the P1 display finding: if a headless or clamshelled Mac renders a black or tiny display, insert an HDMI dummy plug into an available port.

## Before each trip

- Check the iPad's key-expiry date in the Tailscale admin console (the iPad key expires every 180 days by default); re-authenticate if under 30 days remain.
- Pause macOS automatic updates in System Settings on the Macs and disable automatic updates in Tailscale Standalone preferences while away (an unexpected restart or update prompt cuts the path).
- Perform one test connection (SSH and Screen Sharing) from the iPad using a phone hotspot or cellular data network with home Wi-Fi turned off.

## Use it while travelling

- Connect to Tailscale VPN in the iPad app.
- For shell access, SSH to the target Mac using its MagicDNS name:
  ```bash
  ssh <login>@<mac>
  ```
- For graphical access, connect the VNC client to `<mac>:5900`.
- To inspect connection status, check the node details in the iPad Tailscale app or run the Standalone CLI on a Mac:
  ```bash
  /Applications/Tailscale.app/Contents/MacOS/Tailscale status
  ```
  The status output indicates whether each link is `direct` (WireGuard peer-to-peer) or `relay` (DERP server). Relayed connections have higher latency but work normally.

## Answer a stuck dialog

Follow this procedure for the 2026-11-22 case where an unattended clamshelled Mac is blocked by a modal dialog (such as a TCC permission or Keychain unlock prompt):

1. Connect to the Mac via Screen Sharing from the iPad VNC app.
2. If the lock screen is active, unlock it by typing the macOS password.
3. Click the dialog prompt to allow or dismiss it.
4. Lock the Mac's screen before disconnecting (via Apple Menu -> Lock Screen or `Cmd+Ctrl+Q`).
5. Disconnect the VNC session.

## Webhook outage

If external alerts report the webhook unresponsive while offsite, follow the evidence-first sequence from `docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md`:

1. SSH into the hub (`m5`), which runs the webhook, from the iPad over Tailscale. (The bug doc predates the hub move and says m4.)
2. Collect diagnostic state without changing anything:
   ```bash
   date -u
   launchctl print "gui/$(id -u)/com.k3d-manager.webhook" | head -60
   pgrep -fl 'k3dm-webhook' || true
   lsof -nP -iTCP:7443 -sTCP:LISTEN || true
   tail -n 80 "$HOME/Library/Logs/k3dm-webhook.log"
   ```
3. If the webhook is confirmed locally nonresponsive or its process/listener is missing while the host is otherwise healthy, execute at most one restart invocation:
   ```bash
   make restart-webhook
   ```
4. Verify recovery end to end: repeat the process, listener and log checks, test the local authenticated health endpoint, and confirm an end-to-end read-only Slack or cloud-bridge request succeeds.
5. Never run restart in a loop or as a demonstration; if the single restart does not restore service, investigate system logs.

## Lost or stolen iPad

If the iPad is lost or stolen:

1. Open the Tailscale admin console from any web browser and remove the iPad device immediately.
2. Remove the iPad's public key line from `~/.ssh/authorized_keys` on each Mac (`m2`, `m5`, `m4`), via another enrolled device or upon returning home.
3. If the macOS account password was ever saved on the iPad, change the macOS password immediately on every Mac.
4. When replacing the device, enroll the new iPad and approve it in the Tailscale admin console (using device approval, D5).

## Roll back

To completely remove the break-glass path:

1. In the Tailscale admin console, remove all ACL grants or restore default settings.
2. Delete all enrolled devices (`m2`, `m5`, `m4` and the iPad) from the Tailscale admin console.
3. Uninstall the Tailscale client application from all Macs (`/Applications/Tailscale.app`) and the iPad.
4. Turn Screen Sharing off in System Settings on each Mac.
   Turn VPN On Demand off on each Mac before uninstalling, and remove Tailscale from Open at Login.
5. Remove the iPad's SSH public key entry from `~/.ssh/authorized_keys` on each Mac.

## Limits

- FileVault after a reboot: after any system reboot, FileVault prevents macOS from starting network services until the disk is unlocked with a passphrase at the physical keyboard. No remote connection (neither Tailscale nor SSH) can be established while waiting at the FileVault unlock screen.
- Power cuts: the Macs operate with `sleep 0`, `womp 1` and no `autorestart`. A power cut leaves them unpowered until someone physically presses the power button.
- Tailscale outages: an outage of Tailscale's control plane or global DERP relay infrastructure interrupts access.
- Screen Sharing network scope: Screen Sharing (`tcp:5900`) listens on the local LAN as well; the "Only these users" restriction and strong macOS password serve as the fence there.
- The Standalone client is not a Tailscale SSH server: Tailscale SSH is not supported by the macOS Standalone client; Remote Login (OpenSSH) handles incoming SSH sessions.
- Tailnet Lock is not used (D5): device approval is enabled instead, because Tailnet Lock and device approval are mutually exclusive features in Tailscale, and Tailnet Lock would leave a lost or replacement iPad unapprovable while away from signing nodes.
