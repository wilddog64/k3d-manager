# Web console part B — capture kit (guided scripts for the remaining captures)

**Status:** SPEC rev 1 — written 2026-11-27; Fable + Neon blind review pending; intents not yet approved
**Priority:** P2 (enhancement)
**Release:** unslotted — v1.47.0 candidate for `/release-groom` 2026-11-29 (v1.47.0 is at its 5-plan cap; enters only by
displacing a not-started plan)
**Branch:** `k3d-manager-v1.47.0` (if slotted)
**Filed:** 2026-11-27, Claude
**Approval:** operator, 2026-11-27 ("actually I wonder if you can write script for me to execute these probes?", then
"sounds good" to: re-scope, kit spec, run in sittings; "can you also write the spec ... and have Fable/Neon review")
**Intent approved:** pending
**Risk:** high — the kit stages and runs a root LaunchDaemon on the operator's Macs, reads a Cloudflare token from the
Keychain and talks to the Cloudflare API. Every Cloudflare call stays `GET`; the kit never touches the production console.
**Parent:** [`v1.45.0-web-console-b-captures.md`](v1.45.0-web-console-b-captures.md) (capture plan, DRAFT v5; its
safety rules, filters and per-capture methods are the contract this kit implements). Umbrella:
[`v1.45.0-web-console-ssh-behind-cloudflare-access.md`](v1.45.0-web-console-ssh-behind-cloudflare-access.md).
**Prior art:** exact-slug glob `docs/plans/*capture-kit*`: none; the 2026-11-19 captures used an uncommitted root driver
(`docs/captures/2026-11-19-web-console/README.md:3`, `root-steps.log`) — this kit is that pattern made reviewable.
**Implementer:** split at dispatch — Luna (`bin/` + `scripts/lib/wcb_capture/` + tests), Flash (how-to + plan fixes).
Never Neon (it reviews this spec).

## Why

The re-scope of 2026-11-27 (C1–C17 against the part A and part C capture files) found six captures done (C6, C10,
C11, C12, C16, C17), five partial (C2, C7, C8, C13, C14) and six not started (C1, C3, C4, C5, C9, C15). Nothing has
been captured against Cloudflare: every part A and part C proof used a local `ssh` client, never the browser-rendered
path through Access. Done by hand from the capture plan, the remainder is about 4.5–5 hours of exact command typing,
with three daemon reconfigurations in the middle of the browser session. The operator asked for scripts.

The kit's job is to make each sitting a sequence of "follow the prompt" steps, keep every safety rule of the capture
plan mechanically (not by the operator's care), and produce filtered capture files Claude can read and the operator
approves before they are committed. It does not change what is captured or what each capture proves.

## What the operator does

| Sitting | Captures | Where | Operator actions | Time |
|---|---|---|---|---|
| 1 | C1, C3, C2 (API half), C8 tunnel object | home, any Mac | create the read-only capture token in the dashboard and store it in the Keychain; run `api`; read the filtered files | ~20 min |
| 2a | setup for 2b and 2c | home | follow the dashboard checklist (throwaway Access SSH app + policy + remotely managed tunnel); save the connector token to the scratch file; run `stage` (sudo once) and `browser-up` | ~25 min |
| 2b | C5, C4 (logins 1 and 2), C15 (logins 1 and 2) | iPad, Safari (see decision K1) | open the throwaway hostname, log in, follow the recorder's prompts; five logins in total | ~30–45 min |
| 2c | C8 enforcement requests (a)–(d), C2 dashboard half | home | toggle the dashboard Access setting when the kit says; create the second throwaway app for (d); run `c8` | ~30 min |
| 3 | C13(c), C7, C14 plain terminal, C9 | home | run `root-checks` (sudo once); run `c14-plain` in a plain Terminal window; C9 follows the dashboard revoke steps the kit prompts | ~60–75 min |
| end | — | home | `down` (removes both scratch dirs and every capture label); delete the throwaway apps, tunnel and capture token in the dashboard; read and approve the capture files | ~15 min |

## Design

### 1. One CLI, fixed scratch layout, hard isolation

`bin/k3dm-wcb-capture <subcommand>` (Python 3 stdlib; the root parts run under
`/Library/Developer/CommandLineTools/usr/bin/python3 -IS`, the interpreter part C already uses). Subcommands: `api`,
`stage`, `browser-up`, `c8`, `root-checks`, `c14-plain`, `status`, `collect`, `down`.

- Scratch directories exactly as the capture plan's safety rules define them: (1) unprivileged
  `/private/tmp/k3dm-captures-<date>/` (`0700`, files `0600`); (2) root `/private/var/db/k3dm-capture-<date>/`
  (`root:wheel 0755`). `<date>` is the local date when `stage` (or `api`, which needs only (1)) first ran; later
  subcommands reuse the existing directory and refuse when there are two.
- The only launchd labels the kit may bootstrap or boot out: `com.k3d-manager.capture-sshd` and, if a capture needs it,
  `com.k3d-manager.capture-idle`. The only port: 42723 on 127.0.0.1.
- A single refusal function, called before every write, `launchctl` call and listener start, refuses any path under
  `/etc/k3dm-web-console`, `/Library/PrivilegedHelperTools/k3dm-web-console`, `/var/db/k3dm-web-console`,
  `/var/db/k3dm-web-console-run`, any label `com.k3d-manager.web-console-*`, and port 42722 (capture plan, isolation
  rule). It also refuses `cloudflared tunnel create` and `cloudflared tunnel login` in any argv the kit builds.
- Port single-owner rule: before starting the foreground scratch sshd or bootstrapping the scratch LaunchDaemon, the
  kit checks `/usr/sbin/netstat -anv -p tcp` for a `127.0.0.1.42723` LISTEN row and refuses if one exists.
- Every capture file starts with the header the plan requires: host, date, `cloudflared --version`, `/usr/sbin/sshd -V`,
  `ssh -V`, `sw_vers -productVersion`.

### 2. `api` — sitting 1 (C1, C3, C2 API half, C8 tunnel object)

- Token: Keychain item `k3dm-cloudflare-access-capture-token`. Presence is checked by exit code only. The value is read
  with `security find-generic-password -w` into a pipe that writes a `curl --config -` stanza
  (`header = "Authorization: Bearer ..."`) on curl's stdin. The token is never in any argv, environment variable, file,
  stdout, stderr or log.
- Identifiers `ACCOUNT_ID`, `APP_ID`, `TUNNEL_ID`: prompted on the tty with echo on (they are not secrets but are
  redacted from every output), held in memory, never written to disk except inside raw files under (1).
- Calls are exactly the plan's GET list: C1's five endpoints; C3's `/access/apps/${APP_ID}/ca` and, if the operator
  answers yes, `/access/gateway_ca`; C8's `/cfd_tunnel/${TUNNEL_ID}`; C2's `/access/apps/${APP_ID}` again after the
  operator says the app was disabled in the dashboard (sitting 2c). curl runs with `--request GET`, no `--data`, no
  `-X` other than `GET`, `--fail-with-body`, `--max-time 30`. An HTTP 403 body with code 10000 is recorded as
  "missing permission: <name>" (C1 records which permissions the endpoints demand).
- Each raw response is written to `(1)/raw/<capture>-<n>.json` (`0600`); `filter` (§7) writes
  `(1)/filtered/<capture>-<n>.json`; only filtered files are printed.

### 3. The recorder — the forced command for every browser login (sitting 2b)

`scripts/lib/wcb_capture/recorder.py`, installed into the root scratch directory by `stage` (§5) and named by the
scratch sshd's `ForceCommand`. It is the only thing the iPad shows. Per profile (§4) it runs a fixed script of steps,
each a prompt line with a step counter, and writes every observation to `(1)/browser/<profile>-<UTC>.log` (`0600`).

- **Profile `c5`:** print `pty=<yes|no>`, `$SSH_ORIGINAL_COMMAND` (length and whether empty), `TERM`, the environment
  variable names (not values); prompt "type any word and press Return" and record its length; raw mode with `ISIG` off,
  prompt in turn for Ctrl-C, Ctrl-Z, Ctrl-backslash and record each byte's hex; `ECHO` off, then 60 s of unprompted
  bytes as hex while the operator is told "switch to another tab and back"; then write `ESC [ 6 n` and `ESC [ c` and
  record the reply bytes for 5 s each (part C P8). Final prompt asks the operator to leave the page idle for 3 minutes
  and record whether it reconnects on its own (the operator answers on the next login's first prompt, recorded).
- **Profile `c4-login1`:** reads `$SSH_USER_AUTH`, takes the line starting `publickey `, strips the prefix, feeds the
  rest to `ssh-keygen -L -f -` and records only the `Principals:`, `Valid:`, `Key ID:` and `Signing CA:` key-type lines,
  each principal and key id replaced by its length and its equality (yes/no) with the local login (capture plan C4,
  Fable B3). Nothing else from the certificate is written.
- **Profile `c4-login2`:** prints "login accepted" (reaching the forced command is the result); the refusal case is
  read from the sshd log by the supervisor.
- **Profiles `c15-a`, `c15-b`:** prints the served host-key fingerprint the supervisor recorded for this login (algorithm
  and length only on screen; the full value only in `(1)`), and prompts "did Safari show a host-key fingerprint, a
  warning, or nothing?" with a fixed answer menu (1/2/3), recorded.
- **Profile `c7`** (sitting 3, local `ssh` client, not browser): runs the plan's C7 commands with outputs reduced to
  exit codes; never `-w`, never `dump-keychain`.

On every step: input is read with a timeout (default 120 s, then the step is recorded as `timeout` and the recorder
moves on); a closed connection is recorded as `HUP` or `EOF` (whichever arrives); the last line written is
`done <profile>` and the recorder creates `(1)/browser/done-<profile>` (empty file). The recorder never runs a shell and
never executes input.

### 4. `browser-up` — the profile supervisor (sitting 2b), so nothing is reconfigured by hand

Runs in the foreground in a plain Terminal window on the Mac at home, and keeps running while the operator is on the
iPad. It owns the scratch sshd on 127.0.0.1:42723 and walks a fixed profile sequence:
`c5` → `c4-login1` → `c4-login2` → `c15-a` → `c15-b`.

- For each profile it writes the scratch `sshd_config` (from §5's staged templates), starts the sshd, waits for the
  recorder's `done-<profile>` file (or the operator's `skip`/`stop` typed in the supervisor window), stops the sshd,
  confirms no 42723 LISTEN row remains, and moves to the next profile. Established sessions are not killed by a listener
  restart (C17a), so the operator's previous browser tab may stay open; the next login is a fresh connection.
- `c4-login1` uses `ExposeAuthInfo yes` and `AuthorizedPrincipalsCommand <(2)>/principals-any %t %k` with
  `AuthorizedPrincipalsCommandUser` the operator (plan C4); `c4-login2` has neither line and no
  `AuthorizedPrincipalsFile`, `LogLevel VERBOSE`, and the supervisor copies the matching `Accepted`/refusal line from the
  sshd log into the capture.
- Which sshd: a non-root foreground sshd may refuse `AuthorizedPrincipalsCommand` (plan C4 says this is unknown). The
  supervisor therefore runs every browser profile on the **scratch LaunchDaemon** (`com.k3d-manager.capture-sshd`, root,
  from (2)), bootstrapped and booted out per profile through the root driver (§5). This is the plan's stated fallback,
  applied to all five profiles so the sequence has one mechanism; the capture file records it.
- `c15-a` → `c15-b`: between the two, the root driver generates a new ed25519 host key in (2) and restarts the job.
  Before each of these logins the supervisor runs `ssh-keyscan -p 42723 -t ed25519 127.0.0.1 | ssh-keygen -lf -` and
  compares it with `ssh-keygen -lf <(2)>/host_key.pub`; it must match the file, and `c15-b`'s must differ from `c15-a`'s.
  On a mismatch the profile is marked `void` and not offered to the iPad (plan C15, Astra 11).
- The connector: the supervisor does not start `cloudflared`. The operator starts it in a second plain Terminal window
  with the exact line the kit prints:
  `cloudflared tunnel --no-autoupdate --loglevel debug run --token-file <(1)>/tunnel-token`, and the kit checks the
  token file exists with mode `0600` before printing it. The connector log is redirected by the printed line to
  `(1)/connector.log`.

### 5. `stage` and the root driver

- `stage` (operator, once per sitting that needs root): creates (2) with `sudo install -d -o root -g wheel -m 0755`,
  then installs, owned `root:wheel` and mode `0755` (scripts) or `0644` (templates), the root driver, the recorder,
  `principals-any`, the sshd config templates and the plist template from the checkout. It prints the checkout commit and
  the sha256 of every installed file, and the operator compares the commit with `origin/k3d-manager-v1.47.0` on GitHub
  before going on (the kit says so and waits for Return). It then starts the root driver with one `sudo` invocation from
  (2), never from the checkout.
- Root driver (`scripts/lib/wcb_capture/rootd.py`, run from (2)): a loop that reads request files from `(1)/req/`. A
  request file's name is the whole request: exactly one of a fixed set
  (`up-<profile>`, `down`, `rekey`, `c13c-swap-<n>`, `c9-stop`, `c9-start`, `quit`); its content is ignored. Any other
  name is logged and deleted. The driver checks before every action that it is running from (2), that (2) and every
  file it executes are owned by root and not group/other-writable, and refuses otherwise. It writes its own log
  `(1)/root-steps.log` (the 2026-11-19 format: `[root HH:MM:SS] <step>`).
- `root-checks` (sitting 3): drives the root driver for C13(c) (two scratch CA keys and a user certificate from each,
  generated in (2); swap the `TrustedUserCAKeys` file content without a restart; two fresh local `ssh` connections:
  new-CA accepted, old-CA refused, then the swap back with both directions checked again); C7 (local `ssh` login on the
  `c7` profile); C9's daemon-stop step (`c9-stop`/`c9-start`) between the operator's dashboard steps, with the kit
  prompting each dashboard step in the plan's revoke order and timestamping the operator's "done" for each.
- `c14-plain` (operator, plain Terminal window): refuses when `$TMUX` or `$STY` is set or the parent process is
  `tmux`/`screen`; runs the plan's C14 command `sudo /Library/Developer/CommandLineTools/usr/bin/python3 -IS -c
  'open("/dev/tty","w").write("ok\n")'` and records the exit code and whether `ok` was written.

### 6. `c8` — enforcement requests (sitting 2c)

Prompts the plan's C8 requests (a)–(d) in order, each with the dashboard state the operator must set first (Access
required on/off; the second throwaway app for (d)) and the exact client command from the plan. For each request it
records the client's exit code and error text, the connector log lines between the request's start and end
timestamps (from `(1)/connector.log`), and the sshd log lines for the same window. It applies the plan's validity rule
mechanically: (a) and (d) are `pass` only when the connector log shows the request arriving **and** (c) reached sshd in
the same session; otherwise `void`. It never contacts the Cloudflare API itself.

### 7. Filters, scan, `collect`

- `scripts/lib/wcb_capture/filters.py`: the plan's FILTER rules as `jq`-free Python allow-list projections per capture
  (C1, C3, C8 object; C6-style text filters for sshd/launchctl output), replacing each identifier, hostname, email, team
  name, AUD tag, certificate body and key body with `<redacted:field>` (keys: `<redacted:public_key length=N>`). The
  login name and home directory are replaced with `<login>` and `~` everywhere, including 16-character-truncated process
  titles (2026-11-19 README).
- Scan: the plan's pattern `bearer|eyJ|BEGIN|ssh-(rsa|ed25519)|@[a-z0-9.-]+\.[a-z]{2,}` (case-insensitive), plus the
  operator's login name, the Mac's host name and every identifier the operator typed in `api`. Any hit blocks that file:
  it is not shown, not collected, and the kit prints which pattern matched (not the matched text).
- `collect`: shows each filtered file, asks the operator to approve it (`y`/`n`), and copies only approved files to
  `docs/captures/<date>-web-console-b/` in the checkout with a `README.md` table (capture, files, result, void/pass)
  in the 2026-11-19 format. It never stages or commits; Claude commits after reading.

### 8. `status` and `down`

- `status`: which scratch directories exist, whether the capture label is loaded, whether 42723 is listening, which
  profiles have `done-*` files, which captures are void.
- `down`: stops the root driver (`quit`), boots out every capture label that is loaded, confirms no 42723 LISTEN row,
  removes (2) with `sudo rm -r` and (1) with `rm -r` after `collect` has run or the operator types `discard`, and prints
  the dashboard cleanup checklist (delete both throwaway apps, the throwaway tunnel and the capture token). It records
  each removal in its output. It is safe to run twice.

### 9. Stale-doc fixes found by the re-scope (Flash child)

- `docs/plans/v1.45.0-web-console-b-captures.md`: add a "Capture status (2026-11-27)" section pointing to
  `docs/captures/2026-11-19-web-console/` and `docs/captures/2026-11-19-web-console-c/` for C6, C11, C12, C14 (partial),
  C16, C17 and the re-scope table; correct the agent-only section, which still lists the m5 `sshd -T` and `launchctl`
  views of C6 as owed (they are in `c6-m5.txt`, `c12-*`); record the `bin/k3dm-web-console-sshd:289` `_wc_check_routes`
  finding (it reads the hub cloudflared configs by default; part B must state whether the console config is added
  beside them or replaces them) as an input to the part B spec; link this kit.
- `docs/plans/v1.45.0-web-console-a-console-sshd.md`: where it says P3 and P5 (C13) remain owed (status line and the
  proof-owed section), state that P3 is covered by live E4 (install after `sudo -k`,
  `docs/bugs/2026-11-20-web-console-priv-open-passes-via-nopasswd-true.md`) and only P5 (CA re-read per
  authentication, C13(c)) remains, owed to this kit's sitting 3.
- New how-to `docs/howto/web-console-b-captures.md`: the sittings table, the dashboard checklist for the throwaway Access
  SSH app, policy, tunnel and second app (field by field, with what to type), the capture token permissions from the
  plan, and the cleanup checklist.

## Files

| File | Change | Child |
|---|---|---|
| `bin/k3dm-wcb-capture` | new: CLI | Luna |
| `scripts/lib/wcb_capture/__init__.py`, `isolation.py`, `api.py`, `recorder.py`, `supervisor.py`, `rootd.py`, `c8.py`, `filters.py`, `collect.py` | new | Luna |
| `scripts/lib/wcb_capture/templates/` (`sshd_config.<profile>`, `capture-sshd.plist`, `principals-any`) | new | Luna |
| `scripts/tests/bin/test_wcb_capture.py` | new: offline tests (pytest, collected by `make test-pytest`) | Luna |
| `docs/howto/web-console-b-captures.md` | new | Flash |
| `docs/plans/v1.45.0-web-console-b-captures.md` | capture status section, stale lines, link | Flash |
| `docs/plans/v1.45.0-web-console-a-console-sshd.md` | P3 closed by E4; P5 owed to this kit | Flash |

## Contract readers

Grepped 2026-11-27 (`grep -rn` over `bin scripts Makefile docs/howto docs/plans`, excluding `docs/captures` and the
v1.45.0 web-console plans):

- Port 42723: readers only in tests as a fixture value (`scripts/tests/bin/web_console_sshd.bats:496,499,835,843,855,
  1066,1077,1099,1128,1445,1499`, `scripts/tests/bin/web_console_totp.bats:346,1671,1674` via `WEB_CONSOLE_SSH_PORT`).
  The kit is the only writer (a listener). Unchanged by this spec.
- Labels `com.k3d-manager.capture-*`, the scratch paths `k3dm-captures-<date>` / `k3dm-capture-<date>`: only in
  `scripts/tests/bin/web_console_sshd.bats:484` (a string replace over a 2026-11-19 capture file). The kit is the only
  writer.
- Keychain item `k3dm-cloudflare-access-capture-token`: no reader or writer in code today; defined by the capture plan.
  Reader: the kit (`api`). Writer: the operator (dashboard, then `security add-generic-password`, from the how-to).
- `scripts/lib/web_console_common.sh` (`_wc_priv`, `_wc_priv_open`): not used by the kit; C13(a)/(b) are already covered
  (re-scope), and C13(c) needs only the root driver.

## Decisions for the operator

- **K1 — Do the browser logins have to be off the home network?** The capture plan says "from a browser on mobile data".
  The throwaway hostname is public, so from home Wi-Fi Safari still goes iPad → Cloudflare edge → the outbound tunnel →
  the Mac; there is no LAN shortcut to the scratch sshd, which listens on 127.0.0.1 only. (a) Home Wi-Fi is acceptable
  for C5, C4 and C15; one extra C5 login from cellular is recorded as a realism check (about 5 minutes outside).
  (b) All browser logins from cellular, as the plan says. **Recommended: (a).**
- **K2 — C9 "a second GitHub account is denied at Access".** (a) The operator has or creates a second GitHub account for
  the test. (b) Use a different identity the Access login page offers (for example a one-time PIN to an email the policy
  does not allow), recorded as "a non-allowed identity", not "a second GitHub account". (c) Drop the step; C9 records it
  as not run. **Recommended: (b)** if C1 shows a second login method; otherwise (a).
- **K3 — Where the kit lives.** (a) In the repo (`bin/` + `scripts/lib/wcb_capture/`) with offline tests, removed in the
  release after part B ships. (b) Scratch only, like 2026-11-19. **Recommended: (a)**: it runs as root on two Macs, so it
  gets the same review and tests as any root tool, and part B's live drills may reuse the recorder.
- **K4 — Root staging trust.** `stage` copies files from the operator-writable checkout into root-owned (2) and runs them
  as root. (a) As written: print the commit and sha256 of each file and wait for the operator to compare the commit with
  GitHub on a second device (the `bin/k3dm-verified-stage` habit, without its bootstrap). (b) Use
  `bin/k3dm-verified-stage` itself to stage the kit. **Recommended: (a)** for a scratch-only, one-week tool; (b) adds a
  stage-manifest change to a security tool for a throwaway.

## What NOT to Do

- No Cloudflare or GitHub call other than `GET`; never `cloudflared tunnel create`/`login`; never `--token <value>`.
- Never touch the production console's labels, paths or port 42722, nor `~/.cloudflared`, the hub tunnel's config,
  credentials or plist, or any file listed in the capture plan's C10.
- Never print, log or write a token, private key, certificate body, AUD tag or team name; never `security ... -w` to a
  terminal or file; never `dump-keychain`.
- Never run a root-owned action from a path the operator's user can write.
- Do not change part A or part C code, or what any capture proves. Do not commit capture files (Claude does, after the
  operator approves them).

## Acceptance

```yaml
must:
  - id: K-M1
    text: "api performs only the capture plan's GET list, with the token passed to curl on stdin and never in argv, env, files, stdout, stderr or logs; 403 code 10000 is recorded as a missing permission"
  - id: K-M2
    text: "the recorder runs each profile's fixed steps under a pty, records control-key bytes, unprompted bytes and terminal replies as hex, applies a per-step timeout, records HUP or EOF, never executes input, and writes done-<profile> last"
  - id: K-M3
    text: "browser-up walks c5, c4-login1, c4-login2, c15-a, c15-b on the scratch LaunchDaemon through the root driver, advancing only on done-<profile>, skip or stop, and marks a c15 login void unless the served fingerprint equals the file's and c15-b's differs from c15-a's"
  - id: K-M4
    text: "the root driver accepts only the fixed request names, runs only from root-owned, non-group/other-writable files in the root scratch directory, and logs each step"
  - id: K-M5
    text: "filters replace every identifier, hostname, email, team name, AUD, key and certificate body, login name and home path; the scan blocks a file on any listed pattern, the login, the host name or a typed identifier, naming the pattern and not the text"
  - id: K-M6
    text: "c8 records client, connector and sshd evidence per request and marks (a) and (d) pass only when the connector saw the request and (c) reached sshd in the same session, else void"
  - id: K-M7
    text: "down boots out every capture label, confirms 42723 is free, removes both scratch directories and prints the dashboard cleanup list; running it twice succeeds"
  - id: K-M8
    text: "the how-to and the two plan fixes match section 9"
must_not:
  - id: K-N1
    text: "any kit code path writes to, bootstraps, boots out or listens on a production console label, path or port 42722, or builds a cloudflared tunnel create/login argv (paired: the capture label, scratch paths and 42723 are accepted)"
  - id: K-N2
    text: "a curl invocation built by the kit has a method other than GET, a --data/--form/--upload option, or the token in argv (paired: a GET with the token on stdin succeeds against the stub)"
  - id: K-N3
    text: "the root driver acts on a request name outside the fixed set, or runs a file that is not root-owned or is group/other-writable (paired: a listed request on root-owned files runs)"
  - id: K-N4
    text: "a filtered capture containing a token, certificate or key body, email, login or typed identifier is shown or collected (paired: a clean filtered file is shown and collected)"
  - id: K-N5
    text: "a c15-b login is offered while the served host-key fingerprint is still c15-a's (paired: after a real rekey it is offered)"
evidence:
  - id: K-E1
    proves: [K-M1, K-N2]
    kind: offline
    command: "python3 -m pytest scripts/tests/bin/test_wcb_capture.py -q -k api: stub curl and security on PATH (fixture asserts the stub dir is first on PATH and the stub logged its own path), stub records argv, env and stdin; the fake token appears only in curl's stdin; every argv has --request GET and no data option; a 403 code 10000 fixture body yields 'missing permission'. Red controls, each restored byte-identical: (a) pass the token with -H in argv — the argv-leak test fails; (b) add --data to one call — the GET-only test fails"
    intent: "The script that reads your Cloudflare settings can only read, never change anything, and your capture token never shows up in a command line, log or file."
  - id: K-E2
    proves: [K-M2]
    kind: offline
    command: "pytest -k recorder: the recorder runs under a pty from Python's pty module with fake answers; the log holds the expected hex for 0x03, 0x1a, 0x1c, the unprompted-byte window, the ESC[6n/ESC[c replies, a timeout step and HUP on close; a typed '$(touch X)' line creates no file X. Red control: remove the timeout — the timeout test hangs past its 10 s guard and fails"
    intent: "When you log in from Safari, the screen tells you exactly what to press, and everything it needs is written down for you, even if you take too long or the connection drops."
  - id: K-E3
    proves: [K-M3, K-N5]
    kind: offline
    command: "pytest -k supervisor: stub root driver and stub ssh-keyscan/ssh-keygen; the sequence advances only on done files, skip or stop; a stale fingerprint after rekey marks c15-b void and it is not offered; a real changed fingerprint offers it. Red control: skip the fingerprint comparison — the void test fails"
    intent: "The Mac switches its test setup between your logins by itself, and a host-key test that would give a false answer is thrown out instead of counted."
  - id: K-E4
    proves: [K-M4, K-N3, K-N1]
    kind: offline
    command: "pytest -k 'rootd or isolation': with an injectable stat and a fake root directory (fixture asserts its base is under tmp_path), the driver refuses an unknown request name, a group-writable file and a non-root owner, and runs a listed request on root-owned files; the isolation function refuses each production label, path and 42722 and a tunnel create/login argv, and accepts capture-sshd, the scratch paths and 42723. Red controls: (a) accept any request name — the unknown-name test fails; (b) drop the 42722 check — the isolation test fails"
    intent: "The part that runs as root only does the handful of things it is built for, only from files you cannot have tampered with, and can never touch your real web console."
  - id: K-E5
    proves: [K-M5, K-N4]
    kind: offline
    command: "pytest -k filters: fixtures modelled on the 2026-11-19 capture files and a C1-shaped JSON with planted token, eyJ JWT, BEGIN block, ssh-ed25519 key, email, login and a typed account id; each planted value is redacted or blocks the file with the pattern named and the text not printed; a clean file passes and collect copies it. Red control: remove the email pattern — the planted-email test fails"
    intent: "Nothing private (tokens, keys, emails, account ids, your login name) can end up in a capture file I read or in the repo."
  - id: K-E6
    proves: [K-M6, K-M7]
    kind: offline
    command: "pytest -k 'c8 or down': c8 over fixture connector/sshd logs gives pass for (a) with (c) reached, void when the connector shows nothing or (c) fails; down against stub launchctl/netstat/rm boots out only capture labels, removes both fake scratch dirs, and a second run exits 0. Red control: make c8 ignore (c) — the void test fails"
    intent: "The enforcement test is only counted as passing when the evidence really shows it, and one command cleans everything up afterwards."
  - id: K-E7
    proves: [K-M8]
    kind: offline
    command: "make test-pytest rc 0 (collects test_wcb_capture.py once); make lint-python clean; check-doc-links passes for the how-to and the two plans; Claude reads the three doc changes against section 9"
    intent: "The step-by-step guide and the two corrected plans say what the kit actually does."
  - id: K-E8
    proves: [K-M1, K-M5]
    kind: live
    command: "sitting 1 on m4 by the operator: api completes C1, C3, C2 API half and the C8 tunnel object; every filtered file passes the scan; operator approves; collect writes docs/captures/<date>-web-console-b/"
    intent: "You run one command at home and get readable, scrubbed copies of how your Cloudflare Access is set up."
  - id: K-E9
    proves: [K-M2, K-M3, K-M6]
    kind: live
    command: "sittings 2a-2c on m4 by the operator with Claude reading the filtered files: C5, C4 logins 1 and 2, C15 a and b from the iPad in Safari (per decision K1), C8 (a)-(d); each capture pass or void with its reason"
    intent: "From the iPad you just log in and follow the prompts; afterwards we know how Cloudflare's browser SSH really behaves, which part B's design depends on."
  - id: K-E10
    proves: [K-M4, K-M7]
    kind: live
    command: "sitting 3 and down on m4 by the operator: C13(c) both directions, C7, C14 plain terminal, C9 revoke order with timestamps; down leaves no capture label, no 42723 listener and neither scratch directory (ls and launchctl print shown)"
    intent: "The remaining root-level checks run with one sudo prompt, and afterwards nothing from the test is left on the Mac."
interface: "New CLI bin/k3dm-wcb-capture {api,stage,browser-up,c8,root-checks,c14-plain,status,collect,down}; new package scripts/lib/wcb_capture; new Keychain reader k3dm-cloudflare-access-capture-token; new how-to docs/howto/web-console-b-captures.md."
```

Pre-fix, every kit file is absent, so each `must_not` is shown red by its red control (precedent:
`docs/plans/v1.46.0-tailscale-break-glass-p7a-policy.md`).

## Worker definition of done

Report each command, its rc and the proving lines; show each red control failing and `git diff --stat` after restoring
it; list every error seen, including ones you think are unrelated. Run under the hub PATH
`/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin` as well. Commit nothing; Claude lands.
