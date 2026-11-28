# Web console part B — capture kit (guided scripts for the remaining captures)

**Status:** SPEC rev 2 — 2026-11-27; rev 1 reviewed blind by Fable and Neon (both NEEDS FIXES), every finding applied
or answered in `## Review log`; intents approved; Fable re-review of rev 2 pending
**Priority:** P2 (enhancement)
**Release:** unslotted — v1.47.0 candidate for `/release-groom` 2026-11-29 (v1.47.0 is at its 5-plan cap; enters only by
displacing a not-started plan)
**Branch:** `k3d-manager-v1.47.0` (if slotted)
**Filed:** 2026-11-27, Claude
**Approval:** operator, 2026-11-27 ("actually I wonder if you can write script for me to execute these probes?", then
"sounds good" to: re-scope, kit spec, run in sittings; "can you also write the spec ... and have Fable/Neon review")
**Intent approved:** operator, 2026-11-27
**Intent approval words:** "agree, and itents approved" (K-E1..K-E10 as written in rev 2; "agree" = K2 (d) and a Fable re-review of rev 2)
**Risk:** high — the kit stages and runs a root LaunchDaemon on m4, reads a Cloudflare token from the Keychain and calls
the Cloudflare API. Every Cloudflare call stays `GET`; the kit never touches the production console.
**Parent:** [`v1.45.0-web-console-b-captures.md`](v1.45.0-web-console-b-captures.md) (capture plan, DRAFT v5; its
safety rules, filters and per-capture methods are the contract this kit implements). Umbrella:
[`v1.45.0-web-console-ssh-behind-cloudflare-access.md`](v1.45.0-web-console-ssh-behind-cloudflare-access.md).
**Prior art:** exact-slug glob `docs/plans/*capture-kit*`: none; the 2026-11-19 captures used an uncommitted root driver
(`docs/captures/2026-11-19-web-console/README.md:3`, `root-steps.log`) — this kit is that pattern made reviewable.
**Dispatch:** this file is the design and the umbrella Acceptance. Before dispatch it is split into two child specs with
their own `## Files` and `## Acceptance` (full repo-relative paths): `web-console-b-capture-kit-a-code.md` (Luna: code,
templates, tests, machine list) and `web-console-b-capture-kit-b-docs.md` (Flash: how-to and plan fixes). Never Neon
(it reviewed this spec).

## Why

The re-scope of 2026-11-27 (C1–C17 against the part A and part C capture files) found six captures done (C6, C10,
C11, C12, C16, C17), five partial (C2, C7, C8, C13, C14) and six not started (C1, C3, C4, C5, C9, C15). Nothing has
been captured against Cloudflare: every part A and part C proof used a local `ssh` client, never the browser-rendered
path through Access. By hand, the remainder is about 4.5–5 hours of exact command typing with daemon reconfigurations
in the middle of the browser session. The operator asked for scripts.

The kit makes each sitting a sequence of "follow the prompt" steps, enforces the capture plan's safety rules in code,
and produces filtered capture files that the operator approves before Claude commits them. It changes how captures are
driven, never what they must prove; where it changes a capture's method, `## Method changes` says so and why the proof
still holds.

## Where and when

- **Mac:** m4 only (a part B target, holds the earlier C6/C11/C12/C17 captures, not the hub). The m5 views the plan
  needed are already captured (`docs/captures/2026-11-19-web-console/c6-m5.txt`).
- **Seat:** the operator at m4's own keyboard, in plain Terminal windows: not over SSH (the login Keychain is usually
  locked there, plan C7) and not inside tmux or screen (plan safety rule: no capture where an agent reads the screen).
  `api`, `browser-up`, `c8`, `collect` and `c14-plain` refuse when `$TMUX` or `$STY` is set or an ancestor process is
  `tmux` or `screen`.
- **Browser:** the iPad in Safari on home Wi-Fi (decision K1, operator 2026-11-27). Cellular is an optional later repeat.
- **No reboot of m4 between the start of sitting 1 and `down`:** macOS clears `/private/tmp` on boot. If `(1)` is gone
  while `(2)` exists, every subcommand except `down` refuses with "scratch directory lost (reboot?): run down, then start
  again from sitting 1".

## Sittings

| Sitting | Captures | Operator actions | Time |
|---|---|---|---|
| 1 | setup, C1, C3, C8 tunnel object, C2 API schema | create the read-only capture token and store it in the Keychain; create the throwaway Access SSH app, its policy and the remotely managed throwaway tunnel from the how-to checklist; save the connector token to the scratch file; run `api`; run `stage` (sudo once) | ~45 min |
| 2 | C5 (three profiles), C4 (two logins), C15 (two logins), C8 (a)–(d), C2 dashboard half, C9 | keep two Terminal windows open on m4 (`browser-up`, the connector); log in from the iPad and follow the recorder; between logins nothing is changed by hand; at the end run `c8` and the C9 steps the kit prompts | ~2–2.5 h |
| 3 | C13(c), C7, C14 plain terminal | run `root-checks` and `c14-plain` | ~30 min |
| end | — | run `collect`, read and approve each file; run `down`; delete the throwaway apps, tunnel and capture token in the dashboard | ~15 min |

Sitting 2 may be split at any profile boundary: `browser-up` resumes at the first profile without a `done-*` file.

## Design

### 1. One CLI, shared scratch layout, hard isolation

`bin/k3dm-wcb-capture <subcommand>` with subcommands `api`, `stage`, `browser-up`, `c8`, `c9`, `root-checks`,
`c14-plain`, `status`, `collect`, `down`. Every kit file is Python 3.9-compatible (the CLT interpreter
`/Library/Developer/CommandLineTools/usr/bin/python3` is 3.9.6 on m4, 2026-11-27) and stdlib only.

- **Scratch directories** as the plan's safety rules define them: (1) unprivileged `/private/tmp/k3dm-captures-<date>/`
  (operator, `0700`, files `0600`); (2) root `/private/var/db/k3dm-capture-<date>/` (`root:wheel 0755`). One `<date>`
  is shared by both: the first subcommand that creates either picks the local date; every later subcommand reuses the
  existing one and refuses when more than one date exists across (1) and (2).
- **Allow-list of writes:** kit code writes only under the realpath of (1), of (2), and (in `collect`) of
  `docs/captures/<date>-web-console-b/` in the checkout. `isolation.check_write(path)` resolves the realpath and refuses
  anything else, and in addition refuses (deny-list, realpath forms included) `/etc/k3dm-web-console`,
  `/private/etc/k3dm-web-console`, `/Library/PrivilegedHelperTools/k3dm-web-console`, `/var/db/k3dm-web-console*` and
  `/private/var/db/k3dm-web-console*`, `/var/log/k3dm-web-console*`, `/Library/LaunchDaemons/`, `/etc/k3dm-console-tunnel`,
  `~/.cloudflared`, `scripts/etc/cloudflared/` and every file named in plan C10.
- **Labels:** the kit may bootstrap or boot out exactly one label, `com.k3d-manager.capture-sshd`, from a plist in (2)
  (`launchctl bootstrap system <(2)>/capture-sshd.plist`; never copied to `/Library/LaunchDaemons`, so nothing loads at
  boot). `isolation.check_label` accepts only that string; production labels are refused by prefix, and the prefix
  string is built at run time (`"com.k3d-manager." + "web-console-"`) so the literal does not enter
  `agent_classification.bats`'s label scan. `capture-sshd` is added to `scripts/etc/machine/not-installed.list`.
- **Port:** only 127.0.0.1:42723. Port single owner: before any bootstrap the kit reads
  `/usr/sbin/netstat -anv -p tcp` and refuses if a `127.0.0.1.42723` LISTEN row exists.
- **cloudflared argv:** the kit builds only `cloudflared --version`, `cloudflared tunnel ... ingress validate|rule`
  (plan C8 offline half, already done), and `cloudflared access ssh ...` (C8 requests). `isolation.check_cloudflared`
  parses argv structurally and refuses a `create` or `login` subcommand anywhere after flags, `--token`/`--token=*`, and
  a `TUNNEL_TOKEN` environment variable.
- Every subcommand that writes, calls `launchctl` or starts a listener goes through these checks; K-E4 proves it end to
  end with recording stubs, not only by unit-testing the check functions.
- **Capture header:** every text capture file starts with `# host <short name> · date · cloudflared <v> · sshd <v> · ssh
  <v> · macOS <v>`; JSON captures carry the same in a top-level `"_capture_header"` object so they stay valid JSON. The
  short host name (`m4-air`, already published in `docs/captures/2026-11-19-web-console/README.md:3`) is allowed; see §7
  for what the scan blocks.

### 2. `api` — sitting 1 (C1, C3, C8 tunnel object, C2 schema)

Runs after the throwaway app and tunnel exist (sitting 1 creates them first), so C1 reads a real SSH-type app, C3 its CA
and C8 its tunnel.

- **Binaries:** `/usr/bin/curl` and `/usr/bin/security` by absolute path; tests inject a stub directory through a
  constructor argument, never through `PATH`.
- **Token:** Keychain item `k3dm-cloudflare-access-capture-token`. Presence by exit code only. The value is read with
  `security find-generic-password -s <item> -w` into the kit's memory, validated against `^[A-Za-z0-9_-]{20,200}$`
  (refuse otherwise, without printing it), and written only into a curl config on curl's stdin.
- **curl:** argv exactly `["/usr/bin/curl", "-q", "--config", "-"]` (`-q` first so `~/.curlrc` is not read: curl(1),
  m4, 2026-11-27). The stdin config carries `url = "..."`, `header = "Authorization: Bearer ..."`, `request = "GET"`,
  `proto = "=https"`, `fail-with-body`, `max-time = 30`, `silent`, `show-error`, and nothing else; no `-v`, `--trace`,
  `--data`, `--form` or `--upload-file`, in argv or config.
- **Identifiers:** `ACCOUNT_ID`, `APP_ID`, `TUNNEL_ID` are prompted (echo on) and validated (`^[0-9a-f]{32}$` for the
  account and app ids, a UUID for the tunnel id). The throwaway hostname and the team name are prompted too, not for any
  call but as scan terms. All five are written to `(1)/terms` (`0600`) for §7's scan, never elsewhere.
- **Calls:** C1's five endpoints (apps list, the throwaway app, its policies, identity providers, organization); C3
  `/access/apps/${APP_ID}/ca` (read twice, a minute apart, to record stability), and `/access/gateway_ca` if the
  operator answers yes; C8 `/cfd_tunnel/${TUNNEL_ID}`. C2's schema half is already captured
  (`v1.45.0-web-console-b-captures.md:146`); `api --after-disable` repeats the app GET once in sitting 2 after the
  operator tries the dashboard disable switch.
- **Errors:** an HTTP 403 body is recorded as "403 on <endpoint path template>, code <n>" (code 10000 does not name the
  permission). A top-level handler replaces any traceback with a one-line error that names the step; no exception text
  that could hold the config reaches stdout, stderr or a file.
- **Outputs:** raw responses to `(1)/raw/` (`0600`), filtered by §7 to `(1)/filtered/`. From the C3 response, the CA
  public key line is validated (`^(ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|ssh-rsa) [A-Za-z0-9+/]+={0,3}$`, under 16
  KiB, single line) and written to `(1)/ca/access_ca.pub` (`0600`); a failing key stops sitting 1.

### 3. `stage` and the root driver

**Stage** (sitting 1, then once per sitting that needs root):

- Refuses when `git status --porcelain -- bin/k3dm-wcb-capture scripts/lib/wcb_capture` is not empty.
- Reads every staged file with `git show <HEAD commit>:<path>` (the commit, not the working tree), prints the commit and
  each file's git blob id (`git rev-parse <commit>:<path>`), and waits for the operator to confirm that the commit is
  the tip of `origin/k3d-manager-v1.47.0` on GitHub (second device) and type `yes` (decision K4 (a), as tightened by
  review). Blob ids can be checked on GitHub; checksums of a working tree could not.
- With one `sudo` invocation of `/usr/bin/install` per file it creates (2) (`root:wheel 0755`) and installs:
  `rootd.py`, `isolation.py`, `recorder.py`, `principals-any`, the sshd config templates and the plist template, owned
  `root:wheel`, `0755` for executables and `0644` otherwise; then `sudo /usr/bin/shasum -a 256` of the installed copies
  is printed next to the blob ids for the record.
- Then the operator starts the root driver, in its own Terminal window, with the single line the kit prints:
  `sudo /Library/Developer/CommandLineTools/usr/bin/python3 -IS <(2)>/rootd.py --scratch <(1)> --login <login>`.

**Root driver** (`rootd.py`, foreground, run from (2)):

- At start: verifies its own path is inside (2); that (2) and every file it will import or execute are owned by uid 0,
  not group- or other-writable, and not symlinks (`lstat`); inserts (2) at `sys.path[0]` explicitly (under `-IS` the
  script directory is not on `sys.path`) and imports `isolation`. Validates `--scratch` against
  `^/private/tmp/k3dm-captures-\d{4}-\d{2}-\d{2}$` and `--login` against `^[a-z_][a-z0-9_-]{0,31}$`, then `lstat`s (1):
  a real directory, owned by that login's uid, mode `0700`. Takes an exclusive `flock` on `(2)/rootd.lock`; a second
  driver exits.
- **Requests:** the driver opens `(1)/req` once with `O_DIRECTORY | O_NOFOLLOW` and keeps the descriptor, and lists it
  with `os.listdir(fd)`. A request is a name only: `<seq>-<verb>` with `<seq>` four digits greater than the last one
  processed and `<verb>` one of `up-<profile>` (profile names from §4), `down`, `rekey`, `install-ca`,
  `c13c-<step>`, `c9-stop`, `quit`. Content is never read. Any other name is ignored and logged. **The driver never
  writes, renames, unlinks or opens files in (1)**, except reading `(1)/ca/access_ca.pub` for `install-ca`, opened with
  `O_NOFOLLOW` relative to a descriptor for `(1)/ca` opened the same way, `fstat`-checked (regular file, owner the
  login, under 16 KiB) and content-validated with §2's regex before it is written to `(2)/access_ca.pub`
  (`root:wheel 0644`).
- **Log:** `(2)/root-steps.log` (`root:wheel 0644`, the 2026-11-19 format `[root HH:MM:SS] <step>`); the supervisor
  reads it. The scratch sshd's log is `(2)/sshd.log` (`0644`), likewise readable.
- **Actions** (all through `isolation`): render the profile's sshd config from the staged template into (2), run
  `/usr/sbin/sshd -T -f <config> -C user=<login>,host=localhost,addr=127.0.0.1` and refuse to bootstrap unless the
  read-back shows every line of §4's baseline; check the port is free; `launchctl bootstrap system <(2)>/capture-sshd.plist`;
  on `down`, `launchctl bootout system/com.k3d-manager.capture-sshd` and confirm no 42723 LISTEN row; `rekey` generates
  a new ed25519 host key in (2).
- **Lifetime:** exits on `quit`, on 4 hours without a request, or on Ctrl-C; each exit path boots out the capture label
  first.
- **`down`'s root part** runs the same staged `rootd.py` with `--teardown --scratch <(1)>` under one `sudo`: boots out the
  label if loaded, confirms 42723 is free, then removes (2) only if its path matches
  `^/private/var/db/k3dm-capture-\d{4}-\d{2}-\d{2}$` and `lstat` shows a real directory owned by root.

### 4. Profiles, the sshd baseline, and `principals-any`

**Baseline in every profile's config** (checked by the `sshd -T -C` read-back before bootstrap): `ListenAddress
127.0.0.1`, `Port 42723`, `AllowUsers <login>`, `PermitRootLogin no`, `PasswordAuthentication no`,
`KbdInteractiveAuthentication no`, `UsePAM no`, `AuthenticationMethods publickey`, `AuthorizedKeysFile none`,
`TrustedUserCAKeys <(2)>/access_ca.pub` (or the C13 scratch CA in sitting 3), `DisableForwarding yes`,
`PermitUserEnvironment no`, `PidFile none`, `LogLevel VERBOSE`, `HostKey <(2)>/host_key`, `ForceCommand <(2)>/recorder.py
<profile>`. Each profile adds only its own lines below.

| Profile | Capture | Extra config | Recorder steps (§5) |
|---|---|---|---|
| `c5` | C5 | `PermitTTY yes` | pty, `TERM`, env names, line length, Ctrl-C/Z/\ bytes, 60 s unprompted bytes with tab switch, ESC[6n and ESC[c replies, 3-minute idle hold |
| `c5-exit` | C5 (non-zero exit) | — | prints one line, exits 3 |
| `c5-notty` | C5 (`PermitTTY`) | `PermitTTY no` | prints `pty=<yes/no>` and exits 0 |
| `c4-login1` | C4 login 1 | `ExposeAuthInfo yes`, `AuthorizedPrincipalsCommand <(2)>/principals-any %u %t %k`, `AuthorizedPrincipalsCommandUser <login>` | certificate inspection from `$SSH_USER_AUTH` |
| `c4-login2` | C4 login 2 | no principals command, no `AuthorizedPrincipalsFile` | prints "login accepted" |
| `c15-a`, `c15-b` | C15 | — (`rekey` between) | fingerprint question |
| `c8` | C8 | — | prints `reached` with a timestamp and exits 0 |
| `c9-hold` | C9 | — | heartbeat line every 5 s until the session ends |
| `c7` | C7 (sitting 3, local client) | `AuthorizedKeysFile <(2)>/c7_authorized_keys` instead of `none`; `TrustedUserCAKeys none` | the plan's C7 commands, outputs reduced to exit codes |

`principals-any` (`root:wheel 0755` in (2)): prints the certificate's own principals (from `ssh-keygen -L -f -` over
`%t %k`) **only when `%u` equals the staged login**; otherwise prints nothing, so sshd refuses. With `AllowUsers <login>`
this keeps the permissive C4 mapping to the operator's own account (review: a root daemon must not admit other users).
It writes nothing; the recorder does the filtered inspection.

C7's key: `stage` installs `(2)/c7_authorized_keys` from a throwaway key pair the kit generates in (1) for sitting 3 and
deletes in `down`. C7's `(2)/denied` directory (`root:wheel 0700`) is created by `rootd` for the C7 step.

### 5. The recorder (`recorder.py`, the `ForceCommand` of every profile)

Runs as the operator (sshd drops privilege before the forced command) from (2). It is the only thing Safari shows. It
never runs a shell, never executes or evaluates input, and writes only `(1)/browser/<profile>-<UTC>.log` (`0600`).

- **Attended start:** the first prompt is "press Return to start <profile> (step 1/n)". With no Return in 120 s the
  session is recorded as `abandoned`, no `done` file is written, and the supervisor offers the same profile again. This
  is the guard against an automatic reconnect landing on the next profile unattended (review).
- **Previous-session question:** the first prompt after the attended start of every profile except `c5` asks what Safari
  showed when the previous session ended (fixed menu: error page, reconnected by itself, blank, other), recorded against
  the previous profile. This is how `c5-exit` (what the page shows on exit 3) and `c5-notty` (whether the page works
  with `PermitTTY no`) get their results.
- **Terminal modes:** line prompts in canonical mode; Ctrl-key, unprompted-byte and reply windows in raw mode
  (`ICANON`, `ECHO` and `ISIG` off, `VMIN 0`, `VTIME 1`); modes restored on every exit path.
- **Timeouts:** each step distinguishes `no bytes` (nothing arrived) from `timeout after partial input`; default 120 s,
  60 s for the unprompted window, 5 s for each reply window.
- **c5 idle hold:** before `done`, the recorder asks the operator to leave the page untouched for 3 minutes, then writes
  `ESC[c` and records whether a reply arrives and whether the session is still the same pid; if the page reconnected,
  the next profile's previous-session question records it.
- **c4-login1:** reads the file named by `$SSH_USER_AUTH`, takes the line starting `publickey `, strips the prefix,
  feeds the rest to `ssh-keygen -L -f -`, and records only the `Principals:`, `Valid:`, `Key ID:` and `Signing CA:`
  key-type lines, each principal and key id replaced by its length and its equality (yes/no) with the local login (plan
  C4, Fable B3). If `$SSH_USER_AUTH` is unset or has no `publickey ` line, C4 is recorded `void` (certificate not
  inspected), never a result.
- **c15:** prints the algorithm and the comparison result the supervisor recorded (§6), then asks whether Safari showed
  a host-key fingerprint, a warning, or nothing (fixed menu).
- **End:** the last line is `done <profile>`, then it creates `(1)/browser/done-<profile>`. A hang-up is recorded as
  `HUP` or `EOF`, whichever arrives first, and leaves no `done` file.

### 6. `browser-up` — the supervisor (sitting 2)

Runs in a plain Terminal window on m4 and drives the root driver through request files. Sequence:
`c5` → `c5-exit` → `c5-notty` → `c4-login1` → `c4-login2` → `c15-a` → `c15-b` → `c8` (left up for `c8`/`c9`).

- Before the first profile: confirms `(2)/access_ca.pub` exists (it sends `install-ca` if not), and prints the connector
  line for the second window: `HOME=<(1)>/cfhome cloudflared tunnel --no-autoupdate --loglevel debug --logfile
  <(1)>/connector.log run --token-file <(1)>/tunnel-token`, after checking the token file is a regular `0600` file owned
  by the operator. `HOME` points at a scratch directory so nothing is written under `~/.cloudflared`.
- Per profile: request `up-<profile>`, wait for `root-steps.log` to show it up, tell the operator "log in now", wait for
  `done-<profile>`, an `abandoned` record (re-offer), or an operator command in the supervisor window: `result
  accepted|refused|other` (for `c4-login2`, `c5-notty` and any login that never reaches the recorder), `skip` (recorded
  as not run) or `stop` (resume later). Then request `down` and confirm 42723 is free.
- **Login outcome from the sshd log:** for every profile the supervisor copies the slice of `(2)/sshd.log` between byte
  offsets taken before the "log in now" prompt and after the outcome (the sshd log has no timestamps:
  `docs/captures/2026-11-19-web-console/sshd-prod.log:1-5`).
- **c15:** after `c15-a` the supervisor sends `rekey` and `up-c15-b`. Before each of the two logins it computes the
  served fingerprint with `ssh-keyscan -p 42723 -t ed25519 127.0.0.1` piped to `ssh-keygen -lf -` and the file's with
  `ssh-keygen -lf <(2)>/host_key.pub`, and compares **field 2 only** (`SHA256:<hash>`; the output shape is `256
  SHA256:<hash> <comment> (ED25519)`, captured on m4 2026-11-27, and the comment differs between the two commands). The
  served value must equal the file's, and `c15-b`'s must differ from `c15-a`'s; otherwise the profile is `void` and not
  offered.

### 7. Filters, scan, `collect`

- **Filters** (`filters.py`): per-capture allow-list projections from the plan's FILTER rules (C1, C3, C8 object), and a
  line filter for text logs (sshd, connector, launchctl, ps). Every value of `id`, `uid`, `account_id`, `zone_id`,
  `tunnel_id`, `aud`, `email`, `domain`, and of `name` when it holds a hostname or person, becomes `<redacted:field>`;
  key bodies become `<redacted:public_key length=N>`; the login and home path become `<login>` and `~` everywhere,
  including 16-character-truncated process titles. The connector log filter keeps the timestamp, level and message
  template and redacts connection ids, IPs, hostnames, account tags and tunnel ids.
- **Scan** (`scan.py`), run on every filtered file **independently of the filters** (a defence in depth: K-E5 tests it
  on pre-filtered files that the filters never saw): case-insensitive `bearer|eyJ|BEGIN|ssh-(rsa|ed25519)|ecdsa-sha2`,
  an email pattern `@[a-z0-9.-]+\.[a-z]{2,}`, IPv4 and IPv6 literals, `\.local\b`, and every term in `(1)/terms`
  (account, app and tunnel ids, the throwaway hostname, the team name) plus the login and home path. The short host
  name in the capture header is allowed. Any hit blocks the file: not shown, not collected; the kit prints the pattern
  name and line number, never the text.
- **`collect`:** shows each filtered file that passed the scan and asks `y`/`n`; copies only `y` files to
  `docs/captures/<date>-web-console-b/` with a `README.md` table (capture, files, result, pass/fail/void/not run, in the
  2026-11-19 format). It never stages or commits. Running `collect` at the end of each sitting is recommended (the
  how-to says so) so a lost `(1)` loses little.

### 8. `c8` and `c9` (end of sitting 2)

**`c8`** with the `c8` profile up: prompts the plan's requests (a)–(d), each preceded by the dashboard state to set
(Access required on or off; the second throwaway app for (d)). Client commands run with `HOME=<(1)>/cfhome`. For each
request it records the client exit code and error text, the connector log slice and the sshd log slice by byte offsets,
and computes:

- `fail` when the sshd slice for (a) or (d) shows a connection (the control was bypassed: plan C8 says item 3 is then
  withdrawn);
- `candidate-pass` when the sshd slice shows nothing **and** (b) and (c) reached sshd in the same session;
- `void` otherwise (including (c) not reaching sshd).

A `candidate-pass` becomes `pass` only after Claude reads the filtered connector slice and confirms the request arrived
at the connector; the shape of a "request arrived" line has never been captured, so the kit does not guess it (it
highlights lines that also appear in the (b) and (c) slices as hints). If every attempt is `void`, the summary says
"origin JWT validation not shown" (plan C8). Request (d) (a valid JWT for a different app's audience) has no exact
command in the plan; the how-to gives the method once (b) has shown the token layout under the scratch `HOME`, and if
the client cannot send another app's token, (d) is recorded `not run`.

**`c9`** (needs the connector, the `c9-hold` profile and the iPad): steps in this order, each timestamped, with the
heartbeat log showing when an open session ends:

1. Login with the operator's GitHub account works (a `c9-hold` session stays open on the iPad).
2. A GitHub login that the policy does not allow is denied at Access (decision K2).
3. Dashboard "Revoke existing sessions": record whether the open session continues and whether a fresh login is asked
   to authenticate again.
4. `c9-stop` (driver boots out the label): the open session's fate; the page shown for a fresh attempt; `netstat`
   shows no 42723 LISTEN row.
5. `up-c9-hold` again, new session open; delete the throwaway app in the dashboard: the open session's fate; a fresh
   connection refused.
6. Remove the tunnel's public hostname in the dashboard: `dscacheutil -q host -a name <hostname>` and a fresh attempt
   both recorded.

This order runs session revocation while the app still exists (the plan lists it last, which cannot work after the app
is deleted); the part B spec decides the production order from these timings.

### 9. Sitting 3: `root-checks` and `c14-plain`

- **C13(c):** `rootd` generates two scratch CA keys and a user certificate from each (principal = login) in (2), then:
  CA-1 in `TrustedUserCAKeys`, bootstrap; a local `ssh` with cert 1 succeeds and cert 2 fails; replace the file content
  with CA-2 **without restarting**; cert 2 succeeds and cert 1 fails; swap back and check both again. Each result is the
  client exit code plus the sshd log slice.
- **C7:** profile `c7` with a local `ssh` client and the throwaway key; outputs are the exit codes the plan lists.
- **`c14-plain`:** refuses inside tmux/screen (§Where and when); runs `sudo /Library/Developer/CommandLineTools/usr/bin/
  python3 -IS -c 'open("/dev/tty","w").write("ok\n")'` and records the exit code and whether `ok` appeared.

### 10. `status` and `down`

- `status`: the shared date, which scratch directories exist, whether the capture label is loaded, whether 42723 is
  listening, which profiles are done, abandoned, void or not run.
- `down`: sends `quit` if the driver runs; runs `rootd.py --teardown` under `sudo`; refuses to remove (1) unless
  `collect` has run since the last capture or the operator types `discard`; removes (1); prints the dashboard cleanup
  checklist (delete both throwaway apps, the throwaway tunnel and the capture token; restore any policy change from
  K2). It is idempotent: a second run reports "nothing to remove" and exits 0.

### 11. Stale-doc fixes found by the re-scope (Flash child)

- `docs/plans/v1.45.0-web-console-b-captures.md`: add "Capture status (2026-11-27)" pointing to
  `docs/captures/2026-11-19-web-console/` and `docs/captures/2026-11-19-web-console-c/` with the re-scope table (done:
  C6, C10, C11, C12, C16, C17; partial: C2, C7, C8, C13, C14; not started: C1, C3, C4, C5, C9, C15); correct the
  agent-only section, which still lists the m5 `sshd -T` and `launchctl` views of C6 as owed (in `c6-m5.txt`, `c12-*`);
  record `_wc_check_routes` (`bin/k3dm-web-console-sshd:290`, reads the hub cloudflared configs by default) as a part B
  design input; link this kit.
- `docs/plans/v1.45.0-web-console-a-console-sshd.md:202` (the "P3 and P5 (C13) remain owed" sentence): P3 is covered by
  live E4 (install after `sudo -k`, `docs/bugs/2026-11-20-web-console-priv-open-passes-via-nopasswd-true.md`); only P5
  (CA re-read per authentication, C13(c)) remains, owed to this kit's sitting 3.
- New how-to `docs/howto/web-console-b-captures.md`: where and when, the sittings, the dashboard checklist (capture token
  permissions from the plan; throwaway Access SSH app, policy, tunnel, second app; the K2 policy step and its restore),
  the C8 (d) method, and the cleanup checklist.

## Method changes (and why each proof still holds)

- **All browser profiles run on the scratch root LaunchDaemon**, not a foreground sshd. The plan allows this as C4's
  fallback (plan C4) and uses the same daemon for C9; one mechanism removes the per-profile foreground restart. C5 then
  observes the browser path against a root-launched sshd, which is closer to production; the capture file records it.
- **C15's rekey goes through the root driver** with the plan's served-fingerprint check (plan C15) before each login.
- **C5's non-zero-exit and `PermitTTY` items** are separate profiles whose result is asked at the start of the next
  login, because the session that shows them has already ended.
- **C9's order** puts session revocation before app deletion (see §8).

## Files

Full repo-relative paths; the child specs carry the same paths split by child.

| File | Change | Child |
|---|---|---|
| `bin/k3dm-wcb-capture` | new: CLI and subcommand dispatch (`status`, `c14-plain` inline) | a |
| `scripts/lib/wcb_capture/__init__.py` | new | a |
| `scripts/lib/wcb_capture/isolation.py` | new: write allow/deny, label, port, cloudflared argv checks | a |
| `scripts/lib/wcb_capture/api.py` | new: `api` | a |
| `scripts/lib/wcb_capture/stage.py` | new: `stage` | a |
| `scripts/lib/wcb_capture/rootd.py` | new: root driver and `--teardown` | a |
| `scripts/lib/wcb_capture/recorder.py` | new: forced command | a |
| `scripts/lib/wcb_capture/supervisor.py` | new: `browser-up` | a |
| `scripts/lib/wcb_capture/c8c9.py` | new: `c8`, `c9` | a |
| `scripts/lib/wcb_capture/rootchecks.py` | new: `root-checks` | a |
| `scripts/lib/wcb_capture/filters.py` | new | a |
| `scripts/lib/wcb_capture/scan.py` | new | a |
| `scripts/lib/wcb_capture/collect.py` | new: `collect`, `down` (operator side) | a |
| `scripts/lib/wcb_capture/templates/sshd_config.base` | new: §4 baseline | a |
| `scripts/lib/wcb_capture/templates/capture-sshd.plist` | new | a |
| `scripts/lib/wcb_capture/templates/principals-any` | new | a |
| `scripts/etc/machine/not-installed.list` | add `capture-sshd` | a |
| `scripts/tests/bin/test_wcb_capture.py` | new: offline tests (pytest) | a |
| `docs/howto/web-console-b-captures.md` | new | b |
| `docs/plans/v1.45.0-web-console-b-captures.md` | capture status section, stale lines, link | b |
| `docs/plans/v1.45.0-web-console-a-console-sshd.md` | line 202: P3 closed by E4; P5 owed to this kit | b |

## Contract readers

Grepped 2026-11-27 (`grep -rn` over `bin scripts Makefile docs/howto docs/plans`, excluding `docs/captures` and the
v1.45.0 web-console plans), each line read:

- **Port 42723:** fixture value only, in `scripts/tests/bin/web_console_sshd.bats:496,499,835,843,855,1066,1077,1099,
  1128,1445,1499,1671,1674` and `scripts/tests/bin/web_console_totp.bats:346`. The kit is the only listener. Unchanged.
- **Label `com.k3d-manager.capture-sshd` and the scratch paths:** strings in tests over 2026-11-19 capture files
  (`scripts/tests/bin/web_console_sshd.bats:321,484,487`, `scripts/tests/bin/web_console_totp.bats:185`). Writer: the
  kit. **Reader that changes:** `scripts/tests/bin/agent_classification.bats:17-24` scans `bin/`, `scripts/lib/` and
  `scripts/plugins/` for `com.k3d-manager.*` literals and requires exactly one classification in
  `scripts/etc/machine/{hub-local,hub-singletons,not-installed}.list`; the kit adds the `capture-sshd` row (format
  `capture-sshd|<reason>`, as `scripts/etc/machine/not-installed.list:44-47`) and builds the production prefix at run
  time.
- **Keychain item `k3dm-cloudflare-access-capture-token`:** no code reader today (defined by the capture plan). Reader:
  `api`. Writer: the operator, per the how-to.
- **`docs/captures/<date>-web-console-b/`:** new; writer `collect`; readers: the part B spec (fixtures).
- **`Makefile` `test-pytest`** globs `scripts/tests/bin/test_*.py` (`Makefile:1748`), so the new test file is collected;
  **`lint-python`** lints only tracked files (`Makefile:1632-1637`), so evidence runs `ruff` on the new files by name.
- **`bin/k3dm-codex-dispatch`** reads `## Files` backtick tokens as path patterns (`bin/k3dm-codex-dispatch:832-835`):
  the child specs use full paths.
- **`bin/k3dm-web-console-sshd:290` `_wc_check_routes`** scans `ps` for `cloudflared`; while the throwaway connector runs,
  part A's `check` (if run on m4) may report its tunnel item as indeterminate. Expected during sitting 2; the how-to
  says so. Not changed.
- `scripts/lib/web_console_common.sh` (`_wc_priv`, `_wc_priv_open`): not used by the kit.

## Decisions for the operator

- **K1 — Browser network.** **Decided (operator, 2026-11-27): home Wi-Fi first.** The throwaway hostname is public, so
  Safari always goes iPad → Cloudflare edge → outbound tunnel → m4, with no LAN shortcut to a 127.0.0.1 listener. Home
  Wi-Fi does not exercise carrier NAT or mobile idle drops, which matter for C5's idle-reconnect step; an optional later
  repeat of `c5` on cellular (iPad cellular or phone hotspot, at home) covers it.
- **K2 — How to show that a GitHub login the policy does not allow is denied (C9 step 2).** (a) A second GitHub account,
  created for the test and deleted after. (c) Skip; C9 records the step as not run. (d) Temporarily change the throwaway
  app's allow rule to a dummy email (`nobody@example.invalid`), log in with the operator's own GitHub account and record
  the denial, then restore the rule (the kit prompts both changes; `down`'s checklist repeats the restore). (d) proves
  the same thing (a GitHub identity that is not on the allow list is refused) without a second account. Option (b) of
  rev 1 (one-time PIN) is withdrawn: Access may send no PIN to a non-allowed email, so the denial may not be observable,
  and part B pins GitHub as the only identity provider. **Decided (operator, 2026-11-27): (d).**
- **K3 — Where the kit lives.** **Decided (operator, 2026-11-27): (a)** in the repo with offline tests, removed in the
  release after part B ships.
- **K4 — Root staging trust.** **Decided (operator, 2026-11-27): (a)**, tightened after review: stage from
  `git show <commit>:<path>` with a clean tree, print git blob ids that can be checked on GitHub, run only from
  root-owned (2) (§3).

## What NOT to Do

- No Cloudflare or GitHub call other than `GET`; never `cloudflared tunnel create`/`login`, `cloudflared login`, or a
  token in argv or environment.
- Never touch the production console's labels, paths or port 42722, `/Library/LaunchDaemons`, `~/.cloudflared`, the hub
  tunnel's config, credentials or plist, or any file listed in plan C10.
- Never print, log or write a token, private key, certificate body, AUD tag or team name; never `security ... -w` to a
  terminal or file; never `dump-keychain`.
- A root process never writes, renames or unlinks in (1), and never executes a file that is not root-owned in (2).
- Do not change part A or part C code, or what any capture proves. Do not commit capture files (Claude does, after the
  operator approves them).

## Acceptance

```yaml
must:
  - id: K-M1
    text: "api performs only the listed GET calls with argv exactly [/usr/bin/curl, -q, --config, -] and url, header and request in the stdin config; the validated token never appears in argv, env, a file under (1) or (2), stdout, stderr or a log, on success or on failure (curl exit 22, timeout, exception); ids are validated; a 403 is recorded with its endpoint"
  - id: K-M2
    text: "the recorder requires an attended start, records control-key bytes, unprompted bytes and terminal replies as hex in raw mode, separates no-bytes from timeout, records HUP or EOF, never executes input, marks c4 void without a publickey line, and writes done-<profile> last"
  - id: K-M3
    text: "browser-up walks the profile sequence through the root driver, advancing on done-<profile>, a result command, skip or stop, re-offering an abandoned profile, and marks a c15 login void unless the served fingerprint hash equals the file's and c15-b's differs from c15-a's"
  - id: K-M4
    text: "the root driver runs only from root-owned, non-group/other-writable, non-symlink files in (2), validates its argv and (1), holds a single-instance lock, acts only on fixed request names with an increasing sequence, never writes, renames or unlinks in (1), logs to (2), refuses to bootstrap a config whose sshd -T read-back lacks the baseline, and boots out the label on every exit path"
  - id: K-M5
    text: "filters redact every identifier, hostname, email, team name, AUD, key and certificate body, login and home path, keep JSON valid with the header in _capture_header, and the scan independently blocks any listed pattern, IP literal, .local name or term from (1)/terms, naming the pattern and line but not the text; collect copies only scanned and approved files"
  - id: K-M6
    text: "c8 computes fail, candidate-pass or void per request from sshd and connector byte-offset slices and the (b)/(c) controls, and summarises all-void as not shown"
  - id: K-M7
    text: "stage refuses a dirty kit tree, installs from git show of the commit with root:wheel ownership and the stated modes, and prints commit and blob ids; down boots out the label, confirms 42723 free, removes (2) only on the exact path pattern, removes (1) only after collect or discard, and is idempotent"
  - id: K-M8
    text: "isolation refuses production labels, paths (realpath forms included), /Library/LaunchDaemons, ~/.cloudflared, plan C10 files, port 42722 and cloudflared create/login/--token/TUNNEL_TOKEN, and every subcommand reaches it before any write, launchctl call or listener start"
  - id: K-M9
    text: "api, browser-up, c8, collect and c14-plain refuse inside tmux or screen; the port single-owner check refuses when 127.0.0.1.42723 is listening; every capture file carries the version header"
  - id: K-M10
    text: "the how-to and the two plan fixes match section 11; capture-sshd has exactly one machine-list classification"
must_not:
  - id: K-N1
    text: "a kit subcommand, run end to end against recording stubs, writes outside (1), (2) or the collect directory, names a production label or port 42722, or builds a cloudflared create/login/--token argv (paired: the same runs write inside (1)/(2) and use capture-sshd and 42723)"
  - id: K-N2
    text: "a curl call differs from the exact argv and stdin-config shape, or the token appears anywhere outside curl's stdin (paired: the exact call succeeds against the stub)"
  - id: K-N3
    text: "the root driver acts on an unlisted or replayed request name, executes or imports a file that is not root-owned, is group/other-writable or is a symlink, or writes, renames or unlinks anything in (1) (paired: a listed request with a new sequence on root-owned files runs)"
  - id: K-N4
    text: "a pre-filtered file containing a token, JWT, key or certificate body, email, IP, .local name, login, home path or a term from (1)/terms is shown or collected (paired: a clean file is shown and, on y, collected; on n, not collected)"
  - id: K-N5
    text: "a c15-b login is offered while the served fingerprint hash is still c15-a's, or c8 reports pass when the sshd slice for (a) or (d) shows a connection (paired: a real rekey offers c15-b; a clean (a) slice with (b) and (c) reaching sshd gives candidate-pass)"
evidence:
  - id: K-E1
    proves: [K-M1, K-N2]
    kind: offline
    command: "pytest scripts/tests/bin/test_wcb_capture.py -k api. Stub curl and security are injected by constructor path (fixture asserts each stub logged its own path and that no real /usr/bin binary ran); argv compared for exact equality; stdin config parsed and compared; after success, curl exit 22, a timeout and a forced exception, a recursive search of (1), (2), captured stdout/stderr and the env snapshot finds the fake token only in the stub's recorded stdin; invalid ids and an invalid token are refused without printing them; a 403 body records the endpoint template. Red controls, each restored byte-identical: (a) move the bearer header into argv; (b) drop -q; (c) add --data to the config; (d) print the exception text in the handler — each makes a named test fail"
    intent: "The script that reads your Cloudflare settings can only read, never change anything, and your capture token never shows up in a command line, log, file or error message."
  - id: K-E2
    proves: [K-M2]
    kind: offline
    command: "pytest -k recorder: each profile runs under a pty from the pty module (fixture asserts the child's stdin is a tty) with scripted input: c5 hex for 0x03, 0x1a, 0x1c, the unprompted window, ESC[6n/ESC[c replies; no-bytes vs partial-input timeout; an unattended start yields abandoned and no done file; a typed '$(touch X)' line creates no file X while a control step that legitimately records input does record it; c4-login1 with a fixture SSH_USER_AUTH (cert made by ssh-keygen in tmp_path) records only the four key-type lines with lengths, and without one records void; c15, c8, c9-hold, c5-exit, c5-notty outputs. Each test runs under a subprocess timeout of 20 s. Red controls: (a) remove the attended-start timeout — the abandoned test fails; (b) leave ISIG on — the Ctrl-C byte test fails"
    intent: "When you log in from Safari, the screen tells you exactly what to press and records it for you; if a session reconnects by itself while you are away, it is not counted as one of your tests."
  - id: K-E3
    proves: [K-M3, K-N5]
    kind: offline
    command: "pytest -k supervisor: stub root driver (records requests in tmp_path; fixture asserts the base is under tmp_path) and stub ssh-keyscan/ssh-keygen whose output shape is the real m4 capture of 2026-11-27 ('256 SHA256:<hash> <comment> (ED25519)'); sequence advances on done, result, skip and stop; abandoned re-offers; differing comments with equal hashes match; a stale hash after rekey voids c15-b and it is not offered; a real changed hash offers it; port 42723 busy refuses. Red control: compare the whole line instead of field 2 — the equal-hash test fails"
    intent: "The Mac switches its test setup between your logins by itself, and a host-key test that would give a false answer is thrown out instead of counted."
  - id: K-E4
    proves: [K-M4, K-M8, K-N1, K-N3]
    kind: offline
    command: "pytest -k 'rootd or isolation or e2e': rootd with injectable lstat/owner and a fake (1)/(2) under tmp_path (fixture asserts both) refuses: unlisted name, replayed sequence, group-writable, other-writable, symlinked and non-root files, a scratch path outside the pattern, (1) not 0700 or wrong owner, a second instance (lock held); a listed request runs; an inotify-free snapshot of (1) before and after shows no write, rename or unlink by rootd; a config whose fake sshd -T read-back lacks PermitRootLogin no is not bootstrapped. isolation refuses each production label, each deny path in plain and /private realpath form, /Library/LaunchDaemons, ~/.cloudflared, 42722, and cloudflared argvs with create/login after flags, --token, --token=x and TUNNEL_TOKEN set; accepts capture-sshd, (1)/(2) paths and 42723. e2e: every subcommand runs against recording stubs for launchctl, sudo, netstat, sshd, curl, security, cloudflared and ssh, and the recorded writes, labels, ports and argvs satisfy K-N1. Red controls: (a) accept any request name; (b) drop the /private realpath check; (c) let rootd unlink an unknown request; (d) skip the read-back check — each makes a named test fail"
    intent: "The part that runs as root only does the few things it is built for, only from files you could not have tampered with, never deletes or writes in your own scratch folder, and can never touch your real web console."
  - id: K-E5
    proves: [K-M5, K-N4]
    kind: offline
    command: "pytest -k 'filters or scan or collect': (a) filters on fixtures modelled on the 2026-11-19 capture files, a C1-shaped JSON and a connector-log fixture redact every listed field and keep valid JSON with _capture_header; (b) scan on pre-filtered files (never passed through filters) blocks each planted value in turn: bearer token, eyJ JWT, BEGIN block, ssh-rsa, ssh-ed25519 and ecdsa key bodies, an email, an IPv4 and an IPv6 literal, a .local name, the login, a 16-character truncated login, the home path, and each term in a fixture (1)/terms; the output names the pattern and line and not the text; a clean file passes; (c) collect copies a clean file on y, not on n, never a blocked file, into a target under tmp_path (asserted). Red controls: (a) drop the email pattern; (b) stop reading (1)/terms — each makes a named test fail"
    intent: "Nothing private (tokens, keys, emails, account ids, addresses, your login name) can end up in a capture file I read or in the repo, even if the scrubbing step missed it."
  - id: K-E6
    proves: [K-M6, K-M7, K-M9]
    kind: offline
    command: "pytest -k 'c8 or stage or down or tmux or header': c8 over byte-offset slices of fixture logs gives fail when the (a) sshd slice shows a connection, candidate-pass for a clean (a) with (b) and (c) reached, void when (c) fails, and all-void summary; stage refuses a dirty tree and, with stub git/sudo/install, installs from git show with root:wheel and the stated modes and prints blob ids; down boots out only capture-sshd, refuses (1) removal before collect or discard, refuses a (2) path outside the pattern, and a second run exits 0; each of api, browser-up, c8, collect, c14-plain refuses with TMUX set; header present in text and JSON captures. Red controls: (a) make c8 pass when sshd saw (a); (b) stage from the working tree — each makes a named test fail"
    intent: "The enforcement test can only pass when the evidence really shows it, the staging step uses exactly the reviewed commit, and one command cleans everything up afterwards."
  - id: K-E7
    proves: [K-M10]
    kind: offline
    command: "make test-pytest rc 0 (collects test_wcb_capture.py once); ruff check -- bin/k3dm-wcb-capture scripts/lib/wcb_capture scripts/tests/bin/test_wcb_capture.py rc 0; /Library/Developer/CommandLineTools/usr/bin/python3 -IS -m py_compile on every kit file rc 0; bats scripts/tests/bin/agent_classification.bats rc 0; check-doc-links passes for the how-to and the two plans; Claude reads the doc changes against section 11"
    intent: "The kit runs on the Mac's built-in Python, passes the repo's checks, and the step-by-step guide and the two corrected plans say what the kit actually does."
  - id: K-E8
    proves: [K-M1, K-M5, K-M7]
    kind: live
    command: "sitting 1 on m4 by the operator (Claude reads only filtered files): api completes C1, C3 (two reads), the C8 tunnel object; access_ca.pub written; stage installs from the confirmed commit; every filtered file passes the scan; operator approves; collect writes docs/captures/<date>-web-console-b/"
    intent: "At home you set up the test app in the Cloudflare dashboard and run two commands; you get scrubbed copies of how your Cloudflare Access is set up, and the test daemon is ready."
  - id: K-E9
    proves: [K-M2, K-M3, K-M6]
    kind: live
    command: "sitting 2 on m4 by the operator with the iPad in Safari on home Wi-Fi: profiles c5, c5-exit, c5-notty, c4-login1, c4-login2, c15-a, c15-b, then c8 (a)-(d) and c9 steps 1-6; each capture pass, fail, void or not run with its reason in the README"
    intent: "From the iPad you log in and follow the prompts; afterwards we know how Cloudflare's browser SSH really behaves and how the emergency stop works, which part B's design depends on."
  - id: K-E10
    proves: [K-M4, K-M7]
    kind: live
    command: "sitting 3 and down on m4 by the operator: C13(c) in both directions without a restart, C7 exit codes, c14-plain; down leaves no capture label, no 42723 listener and neither scratch directory (launchctl print exit 113, netstat, ls shown)"
    intent: "The last root-level checks run with one password prompt, and afterwards nothing from the test is left on the Mac."
interface: "New CLI bin/k3dm-wcb-capture {api,stage,browser-up,c8,c9,root-checks,c14-plain,status,collect,down}; new package scripts/lib/wcb_capture; new Keychain reader k3dm-cloudflare-access-capture-token; new machine-list row capture-sshd; new how-to docs/howto/web-console-b-captures.md."
```

Pre-fix, every kit file is absent, so each `must_not` is shown red by its red control (precedent:
`docs/plans/v1.46.0-tailscale-break-glass-p7a-policy.md`).

## Worker definition of done

Report each command, its rc and the proving lines; show each red control failing and `git diff --stat` after restoring
it; list every error seen, including ones you think are unrelated. Run the tests under the hub PATH
`/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin` as well. Never run `sudo`, `launchctl`, `sshd`, `cloudflared` or
`security` for real; everything is stubbed. Commit nothing; Claude lands.

## Review log

Rev 1 was reviewed blind by Fable (subagent) and Neon (`wcb-kit-review-neon`, agy `gemini-4-neon-high`) on 2026-11-27,
both NEEDS FIXES. Claude checked each finding against the code before applying it (verified: CLT python 3.9.6 and
`-IS` `sys.path`; `curl -q`; `agent_classification.bats:17-24`; `Makefile:1632-1637`; `bin/k3dm-codex-dispatch:832-835`;
sshd log without timestamps; part A line 202; `ssh-keygen -lf` output shape).

| Finding | By | Disposition |
|---|---|---|
| C8 verdict marks a bypassed control as pass; sshd log has no timestamps | both (F B1, N 2, F M4) | §8: fail / candidate-pass / void from byte-offset slices; connector arrival confirmed by Claude, not guessed |
| Root driver writes and unlinks in operator-writable (1) | both (F B2, N 1) | §3: log in (2); requests by name and sequence via a pinned `O_NOFOLLOW` dir fd; never writes, renames or unlinks in (1) |
| Sitting 1 reads app/tunnel before they exist; CA never installed | both (F B3, N 4, N 12) | sitting 1 creates them first; `api` writes `access_ca.pub`; `install-ca` request; baseline sets `TrustedUserCAKeys` |
| Header host name vs scan; JSON header breaks JSON | N 3 | §1/§7: short host name allowed, public hostname, `.local`, IPs blocked; `_capture_header` |
| Machine-list classification; `## Files` tokens | N 5 | `not-installed.list` row; prefix built at run time; full paths; child split |
| Root sshd behind a public hostname admits any user; templates unspecified | F M1, N 4 | §4 baseline with read-back gate; `principals-any` requires `%u` = login |
| Reconnect burns profiles; idle hold after done | F M2, N 6 | attended start, abandoned and re-offer, idle hold inside `c5` |
| C5 non-zero exit and `PermitTTY` dropped; ICANON unspecified | F M3, N 6 | `c5-exit`, `c5-notty`, previous-session question; raw-mode spec |
| C8 not buildable: no listener, unproven (d), `~/.cloudflared` writes | F M4 | `c8` profile; scratch `HOME`; (d) method in how-to or `not run` |
| C9 not mechanised; order impossible | F M5, N 10 | §8 step list with heartbeat profile; order explained |
| Scan terms lost across processes; connector log unfiltered; tmux | F M6 | `(1)/terms`; connector filter; tmux/screen refusal on five subcommands |
| Staging: missing `isolation.py`, `-IS` imports, K4 (a) weak, lock, idle, teardown sudo | F M7, N 8 | §3 rewritten |
| Token: `~/.curlrc`, config injection, ids in argv, PATH stubs, leak search | F M8, N 9 | §2: `-q`, token and id validation, url in stdin config, absolute binaries, recursive leak search incl. failures |
| Isolation misses `/private` forms, C10 paths, `/Library/LaunchDaemons`, cloudflared flag forms | N 7 | §1 allow-list plus expanded deny-list; structural cloudflared parsing |
| Acceptance gaps: stage, port, header, tmux, collect n, c4 void, principals-any, exact argv, e2e confinement, controls, timeout, real fingerprint shape, lint skips untracked files | F M9, N 11 | K-M1..K-M10, K-N1..K-N5 and K-E1..K-E7 rewritten |
| `/private/tmp` lost on reboot; date across sittings | F minor, N 14 | shared date; lost-scratch refusal; collect per sitting |
| Contract readers line numbers; missing readers | F minor, N 15 | rewritten |
| K1 cellular realism; K2 (b) unobservable, missing (d); K3 two Macs vs m4 | F minor, N 13 | K1 decided + optional cellular repeat; K2 (b) withdrawn, (d) added and recommended; m4 only stated |
| `capture-idle` unused | N 15 | dropped |
| `api` needs a GUI session | F minor | Where and when: seat at m4, not over SSH |
