# Web console part B — capture kit how-to guide

> **Short version:** [the one-page card](web-console-b-captures-card.md). Since capture kit child c (`6b479708`), `api` asks only for the account ID (it resolves the app `wcb-capture`, the tunnel `k3dm-capture-tunnel`, the hostname and the team, and prompts only for a value it cannot resolve), offers to store a missing capture token through macOS's hidden prompt, and `stage` takes the connector token with one hidden paste. Steps 2 and 5 below (Keychain command, hand-made token file) and the five-ID list are kept for reference only.

This guide walks the operator through running the remaining Web Console Part B captures (C1–C5, C7–C9, C13(c), C14 plain, C15) using the guided capture tool `bin/k3dm-wcb-capture`.

Parent capture plan: [`docs/plans/v1.45.0-web-console-b-captures.md`](../plans/v1.45.0-web-console-b-captures.md).
Kit design and specification: [`docs/plans/web-console-b-capture-kit.md`](../plans/web-console-b-capture-kit.md).

---

## Where and when

- **Mac:** `m4` only (dev node at the desk). The m5 views required by the plan are already captured ([`docs/captures/2026-11-19-web-console/c6-m5.txt`](../captures/2026-11-19-web-console/README.md)).
- **Seat:** Operator at m4's own keyboard, using plain Terminal windows. Do not run over SSH (the login Keychain is typically locked there, plan C7) and do not run inside `tmux` or `screen` (capture plan safety rule: no capture where an agent reads the screen). Subcommands `api`, `browser-up`, `c8`, `c9`, `collect`, and `c14-plain` refuse when `$TMUX` or `$STY` is set or an ancestor process is `tmux` or `screen`.
- **Browser:** iPad in Safari on home Wi-Fi (decision K1; cellular is an optional later repeat).
- **No reboot of m4 between sitting 1 and `down`:** macOS clears `/private/tmp` on reboot. If unprivileged scratch `(1)` (`/private/tmp/k3dm-captures-<date>/`) is lost while root scratch `(2)` (`/private/var/db/k3dm-capture-<date>/`) exists, every subcommand except `down` refuses with: `"scratch directory lost (reboot?): run down, then start again from sitting 1"`.

---

## Sittings

| Sitting | Captures | Operator actions | Time |
|---|---|---|---|
| 1 | setup, C1, C3, C8 tunnel object, C2 API schema | create the read-only capture token and store it in the Keychain; create the throwaway Access SSH app, its policy and the remotely managed throwaway tunnel from the how-to checklist; save the connector token to the scratch file; run `api`; run `stage` (sudo once) | ~45 min |
| 2 | C5 (three profiles), C4 (two logins), C15 (two logins), C8 (a)–(d), C2 dashboard half, C9 | keep three Terminal windows open on m4 (the root driver started with one `sudo`, `browser-up`, the connector); log in from the iPad and follow the recorder; between logins nothing is changed by hand; at the end run `c8` and the C9 steps the kit prompts | ~2–2.5 h |
| 3 | C13(c), C7, C14 plain terminal | run `root-checks` and `c14-plain` | ~30 min |
| end | — | run `collect`, read and approve each file; run `down`; delete the throwaway apps, tunnel and capture token in the dashboard | ~15 min |

Sitting 2 may be split at any profile boundary: `browser-up` resumes at the first profile without a `done-*` marker file.

---

## Step-by-step: Sitting 1

### 1. Dashboard setup checklist

1. **Create read-only capture token:**
   In Cloudflare Dashboard (`My Profile > API Tokens > Create Token > Custom token`), create a read-only token with exactly the permissions from the plan:
   - Account | Access: Apps and Policies | Read
   - Account | Access: Certificates | Read
   - Account | Cloudflare Tunnel | Read
   - Account | Access: Organizations, Identity Providers, and Groups | Read
   - Zone | DNS | Read (for the zone of `<your-domain>`)
   TTL: 24 hours.

2. **Store capture token in Keychain:**
   Store the token in the macOS login Keychain without displaying or echoing it:
   ```sh
   security add-generic-password -a <login> -s k3dm-cloudflare-access-capture-token -w
   ```
   (Type or paste the token at the secure password prompt). Verify presence by exit code only:
   ```sh
   security find-generic-password -s k3dm-cloudflare-access-capture-token >/dev/null && echo "Token present"
   ```

3. **Create throwaway Access SSH application:**
   In Zero Trust Dashboard (`Access > Applications > Add an application > Self-Hosted`):
   - Application Name: e.g. `wcb-capture`
   - Application Domain / Public Hostname: e.g. `capture.<your-domain>`
   - Application Type: SSH (browser-rendered terminal)
   - Session Duration: `6 hours`
   - Identity Providers: pin GitHub (uncheck others)
   - Policy: exactly one rule: Action `Allow`, rule type `Include`, Selector `Emails` or `Login Methods` matching the operator's GitHub login
   - Additional Settings: Short-lived Certificate CA enabled for this app

4. **Create remotely managed throwaway tunnel:**
   In Zero Trust Dashboard (`Networks > Tunnels > Add a tunnel > Cloudflare managed`):
   - Tunnel Name: e.g. `k3dm-capture-tunnel`
   - Public Hostname: `capture.<your-domain>`
   - Service Type: `SSH`
   - Service URL: `ssh://127.0.0.1:42723`
   - Save tunnel. Copy the connector installation token (the token string itself, not the installation command line).

5. **Save connector token to scratch:**
   Create the unprivileged scratch directory `(1)` for today's date if not already created, and save the connector token mode `0600`:
   ```sh
   DATE=$(date +%Y-%m-%d)
   mkdir -m 0700 -p "/private/tmp/k3dm-captures-${DATE}"
   cat > "/private/tmp/k3dm-captures-${DATE}/tunnel-token"
   # (Paste connector token, press Return, then Ctrl-D)
   chmod 0600 "/private/tmp/k3dm-captures-${DATE}/tunnel-token"
   ```

### 2. Run `api`

Run the read-only Cloudflare API collector:
```sh
bin/k3dm-wcb-capture api
```
The command prompts for:
- `ACCOUNT_ID` (32 hex characters)
- `APP_ID` (32 hex characters or UUID)
- `TUNNEL_ID` (32 hex characters or UUID)
- Public hostname (e.g. `capture.<your-domain>`)
- Team name

It queries the C1 endpoints, C3 CA endpoint, and C8 tunnel object, validates the retrieved CA public key, and saves raw and filtered captures to `(1)/raw/` and `(1)/filtered/`.

### 3. Run `stage`

Ensure your working directory has a clean git status:
```sh
bin/k3dm-wcb-capture stage
```
The command:
- Checks `git status --porcelain` on the kit source files.
- Reads files with `git show <commit>:<path>`, displaying the commit and blob IDs.
- Prompts the operator to confirm matching origin on GitHub and type `yes`.
- Prompts for `sudo` to install root driver files into `/private/var/db/k3dm-capture-<date>/` mode `0755`/`0644`.
- Prints the exact command to start the root driver in Sitting 2.

---

## Step-by-step: Sitting 2

Sitting 2 requires three plain Terminal windows open on `m4`.

### 1. The three Terminal windows

- **Window 1 (Root driver):**
  Run the exact command printed by `stage`:
  ```sh
  sudo /Library/Developer/CommandLineTools/usr/bin/python3 -IS /private/var/db/k3dm-capture-<date>/rootd.py --scratch /private/tmp/k3dm-captures-<date> --login <login> --expect ...
  ```
  The driver validates file ownership and expected blob IDs, takes `rootd.lock`, and listens for supervisor requests.

- **Window 2 (Supervisor):**
  Start the supervisor:
  ```sh
  bin/k3dm-wcb-capture browser-up
  ```
  It verifies CA installation, prints the connector launch line for Window 3, and drives the profile sequence.

- **Window 3 (Connector):**
  Run `cloudflared` in the foreground with scratch `HOME`:
  ```sh
  HOME=/private/tmp/k3dm-captures-<date>/cfhome cloudflared tunnel --no-autoupdate --loglevel debug --logfile /private/tmp/k3dm-captures-<date>/connector.log run --token-file /private/tmp/k3dm-captures-<date>/tunnel-token
  ```
  > [!NOTE]
  > While the throwaway connector runs, part A's `make web-console-sshd-check` or `bin/k3dm-web-console-sshd check` may report its tunnel item as indeterminate because `ps` sees a running `cloudflared` process. This is expected and harmless during Sitting 2.

### 2. Browser logins on the iPad

Open Safari on the iPad connected to home Wi-Fi and navigate to:
`https://capture.<your-domain>`

Follow the recorder prompts displayed in the browser terminal:
- **Attended start:** Press Return within 120 seconds to begin each profile ("press Return to start <profile>").
- **Previous-session question:** For all profiles after `c5`, the recorder asks what Safari showed when the previous session ended (error page, reconnected automatically, blank, or other). Select the corresponding option.
- **`c5`:** Follow terminal checks: Ctrl-C, Ctrl-Z, Ctrl-\, 60-second unprompted window (switch tabs and back), terminal attribute query replies, and a 3-minute idle hold.
- **`c5-exit`:** Verifies non-zero exit code (exits 3).
- **`c5-notty`:** Verifies behaviour with `PermitTTY no`.
- **`c4-login1`:** Certificate inspection via `AuthorizedPrincipalsCommand` and `$SSH_USER_AUTH`.
- **`c4-login2`:** Default certificate mapping without principals command.
- **`c15-a` & `c15-b`:** Host-key verification and rekey comparison (answers whether Safari displayed fingerprint, warning, or nothing).

Between logins, nothing is changed by hand on m4; the supervisor and root driver manage transitions.

### 3. C8 probe requests

After the browser profiles complete, run:
```sh
bin/k3dm-wcb-capture c8
```
1. Close all open iPad tabs pointing to `capture.<your-domain>`.
2. Follow prompts for requests (a)–(d):
   - **(a):** Access required `true`, request without an Access JWT (the kit prints the exact client command).
   - **(b):** Access required `true`, valid JWT for the app.
   - **(c):** Access required `false` (toggled in dashboard), request without JWT.
   - **(d):** Request with valid JWT issued for a different app audience:
     In Cloudflare Dashboard, create a second throwaway Access app (e.g. `capture-other.<your-domain>`). The exact method (log in to the second app under the scratch `HOME` `<(1)>/cfhome`, then send that app's token to `capture.<your-domain>`) is settled once request (b) has shown the token layout under the scratch `HOME`; if the client cannot send another app's token, (d) is recorded `not run`.

### 4. C2 dashboard half

In Cloudflare Dashboard, check whether the self-hosted Access app has a disable switch. Try disabling the app, then run:
```sh
bin/k3dm-wcb-capture api --after-disable
```

### 5. C9 end-to-end and revoke ordering

Run:
```sh
bin/k3dm-wcb-capture c9
```
Follow the timestamped steps:
1. Confirm initial login with operator's GitHub account on iPad works (`c9-hold` profile).
2. **K2 (d) dummy-email test:**
   - In Cloudflare Dashboard, temporarily edit the throwaway Access app's allow rule: change the allowed email to dummy email `nobody@example.invalid`.
   - On the iPad, open a **private Safari tab** to `https://capture.<your-domain>` and attempt login.
   - Confirm and record Access denial.
   - **Restore:** Change the allow rule back to the operator's real GitHub email immediately.
3. In Cloudflare Dashboard, click **Revoke existing sessions**. Record whether the open session survives and whether a fresh login requires re-authentication.
4. Stop driver (`c9-stop` boots out label). Record session fate and verify port 42723 is free.
5. Re-run `up-c9-hold`. Delete the throwaway application in Cloudflare Dashboard. Record open session fate and fresh attempt refusal.
6. Remove the public hostname entry from the tunnel in Cloudflare Dashboard. Record DNS resolution and fresh attempt results.

---

## Step-by-step: Sitting 3

Sitting 3 runs local checks on `m4` in a plain Terminal:

```sh
bin/k3dm-wcb-capture root-checks
bin/k3dm-wcb-capture c14-plain
```

- **`root-checks`:**
  - **C13(c):** Generates two throwaway user key pairs as you in `(1)/ca/`; the root driver creates two scratch CA keys in `(2)/c13/` (they never leave it), signs each user key, and puts CA-1 in `TrustedUserCAKeys`. It swaps the file to CA-2 without restarting sshd (the sshd PID is logged before and after), checks that cert 2 succeeds and cert 1 fails, swaps back and checks both again. The local `ssh` client runs as you, never under `sudo`.
  - **C7:** Runs profile `c7` with local `ssh` client and throwaway key to observe Keychain access from an SSH session and verify that root-only scratch directory `/private/var/db/k3dm-capture-<date>/denied` is denied.
- **`c14-plain`:**
  - Verifies `/dev/tty` availability inside `sudo` in a plain terminal (outside tmux/screen).

---

## End of session and cleanup checklist

### 1. Collect capture artifacts

Run:
```sh
bin/k3dm-wcb-capture collect
```
Review each scanned and filtered capture file. Type `y` to accept clean files. The tool copies accepted files to `docs/captures/<date>-web-console-b/` and writes a summary `README.md`. It does not commit or stage.

### 2. Teardown local scratch resources

Run:
```sh
bin/k3dm-wcb-capture down
```
This boots out `com.k3d-manager.capture-sshd`, confirms port 42723 is free and removes `/private/var/db/k3dm-capture-<date>/`. It removes `/private/tmp/k3dm-captures-<date>/` only after `collect` has run or you choose to discard the captures, and is safe to run again.

### 3. Cloudflare dashboard cleanup checklist

Complete the following cleanup steps in Cloudflare Zero Trust:
- [ ] Delete primary throwaway Access app (`capture.<your-domain>`).
- [ ] Delete secondary throwaway Access app if created for C8 (d) (`capture-other.<your-domain>`).
- [ ] Delete throwaway Cloudflare Tunnel (`k3dm-capture-tunnel`).
- [ ] Delete or revoke the read-only capture API token.
- [ ] Delete Keychain item on `m4`:
  ```sh
  security delete-generic-password -s k3dm-cloudflare-access-capture-token
  ```
- [ ] Confirm no stray policy or DNS entry remains for `<your-domain>`.
