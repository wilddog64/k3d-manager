# Bug: D3 Part B — browser listeners still run as root LaunchDaemons and need passwordless LaunchDaemon sudo

**Status:** FIXED — `7e6d9324` (Luna, corrections by Claude) + `b122ffb1` (cloudflared drift fixture follows the 18082 origin). Landed 2026-11-05, 400/400 in the land gate (stdin `</dev/null`, see the hub-restore Recurrence in `docs/bugs/2026-10-06-hub-restore-test-hangs-on-embeddings-prompt.md`). Independent verify PASS 2026-11-06. Live E5 PARTIAL on the M4 2026-11-06 (see below); agents, URLs, `make up` and the M5 pass are not proven.
**Priority:** P1
**Severity:** high. This is the second half of the LaunchDaemon root-escalation fix. Until it lands, `cluster-up` keeps writing root LaunchDaemons that run user-writable wrappers, and `/etc/sudoers.d/k3d-manager` keeps the passwordless `install … /Library/LaunchDaemons/com.k3d-manager.*.plist` and `launchctl bootstrap system …` rules. Those rules are root-equivalent.
**Filed:** 2026-11-05
**Detected by:** Claude, as the planned Part B of `docs/bugs/2026-11-05-sudoers-launchdaemon-plist-rule-is-root-equivalent.md`
**Branch:** `k3d-manager-v1.43.14`
**Approval:** D3 operator go 2026-11-05 ("let's get D3 a shot"). Part B dispatch go, operator 2026-11-05: "go ahead for Part B".
**Depends on:** D3 Part A landed (`84da2bcc`): `bin/install-browser-relays.sh` installs the four root relays and the alias job.
**Related:** `docs/bugs/2026-11-05-sudoers-launchdaemon-plist-rule-is-root-equivalent.md` (parent, has the D3 table and the spike); `docs/bugs/2026-11-05-sudoers-passwordless-rules-grant-root-escalation.md`

## Evidence

Root LaunchDaemons that run user-writable code (`k3d-manager-v1.43.14`, `f4536a9e`). Each plist has `ProgramArguments [/bin/bash, <wrapper under $HOME>]`:

| Listener | Writer | Bind today | Lifecycle code |
|---|---|---|---|
| `argocd-browser-https` | `bin/cluster-up` ~837–930 | socat TLS, 127.0.0.1:443 | `cluster-up` installs it; `bin/cluster-down` ~355 removes it; `k3s-hostinger.sh` ~715 restarts it |
| `keycloak-browser-http` | `bin/cluster-up` ~1522–1600 | port-forward, 127.0.0.1:80 | `cluster-up`; `cluster-down` ~330; `k3s-hostinger.sh` ~719 |
| `sandbox.frontend-browser-http` | `bin/cluster-up` ~1698–1835 | port-forward, 127.0.0.3:80 | `cluster-up`; `cluster-down` ~221 |
| `frontend-browser-http` (Hostinger) | `k3s-hostinger.sh` `_hostinger_write_frontend_browser_plist` ~413, wrapper ~400 | port-forward, 127.0.0.2:80 | `k3s-hostinger.sh` ~722–740 |
| `sandbox.loopback-alias` | `bin/cluster-up` ~1706–1757 | `ifconfig lo0 alias 127.0.0.3` | also a direct `_run_command --interactive-sudo ifconfig` at 1708 |

`_acg_has_launchdaemon_sudo` (`bin/cluster-up:150`, `bin/cluster-down:32`) probes with a direct `sudo -n`. These listeners are its only callers.

The sudoers rules to drop are in `bin/install-sudoers.sh` `_SUDOERS_CONTENT`:
- lines 41–43: `ifconfig lo0 alias *` and `-alias *`
- lines 45–47: `launchctl bootstrap` and `bootout system /Library/LaunchDaemons/com.k3d-manager.*.plist`
- lines 49–51: `install -m 644 *` and `rm -f` under `/Library/LaunchDaemons`

Both `alias *` rules let any same-user process alias any address onto `lo0`, for example a GitHub IP.

## Fix

The listeners move to the user side, on the high ports from the D3 table. The root side is the Part A relays, installed once by the operator.

1. **Four user LaunchAgents.** Each is in `~/Library/LaunchAgents`, bootstrapped into `gui/$(id -u)`, with no sudo.

   | New label | Binds | Replaces |
   |---|---|---|
   | `com.k3d-manager.browser.argocd-https` | socat TLS, 127.0.0.1:18443 | `argocd-browser-https` |
   | `com.k3d-manager.browser.keycloak-http` | port-forward, 127.0.0.1:18080 → svc 80 | `keycloak-browser-http` |
   | `com.k3d-manager.browser.hostinger-frontend-http` | port-forward, 127.0.0.2:18082 → svc 80 | `frontend-browser-http` |
   | `com.k3d-manager.browser.sandbox-frontend-http` | port-forward, 127.0.0.3:18083 → svc 80 | `sandbox.frontend-browser-http` |

   - The wrapper scripts keep their current shape. Only the local bind port changes.
   - Each wrapper's own health probe targets its high port directly, so the wrapper works whether or not the relays are installed.
   - The user-facing URLs (`https://argocd.shopping-cart.local`, `http://keycloak.shopping-cart.local`, and so on) do not change. They reach the agents through the relays.
2. **No sudo on the listener paths.** In `bin/cluster-up`, `bin/cluster-down` and `scripts/lib/providers/k3s-hostinger.sh`, every `/Library/LaunchDaemons` write, every `launchctl … system` call for these five labels, and the `ifconfig lo0 alias` call at `cluster-up:1708` go away. The Hostinger restarts use `_hostinger_restart_launchd … user` with the new label and plist.
3. **Relay check, not a sudo prompt.**
   - When a browser URL is needed, `cluster-up` checks that the relay plist exists in `/Library/LaunchDaemons`. It also checks that the alias exists for the two alias-bound listeners (`/sbin/ifconfig lo0` lists it).
   - If either check fails, `cluster-up` prints one warning naming `make install-browser-relays`. It skips the browser-URL readiness wait and carries on. It never prompts for sudo, and never fails the run because of this.
   - When the relays are installed, the existing readiness checks on the browser URL stay as they are.
4. **Delete the old sandbox loopback-alias installer** (`cluster-up` ~1706–1757). The Part A alias job owns both aliases. Also delete `_acg_has_launchdaemon_sudo` from `bin/cluster-up` and `bin/cluster-down`, because it has no callers left. That removes the direct `sudo -n` at `cluster-up:152`, which the parent bug left as a P3, so no separate P3 is needed.
5. **Cloudflare tunnel origin.** `scripts/etc/cloudflared-config.yml.tmpl`, `scripts/etc/cloudflared/config.yml` and every row of `scripts/etc/cloudflared/origins.tsv` that points at `http://127.0.0.2:80` change to `http://127.0.0.2:18082`. That only holds if the row is served by the Hostinger frontend listener moved above. Check each row (including `k3s-aws`), and leave any row that a different listener serves unchanged, with a note. After this change the public frontend no longer passes through a root process at all.
6. **Sudoers.** In `bin/install-sudoers.sh`:
   - Drop the six rules listed under Evidence.
   - **C:** write the Linux-only rules (`/usr/bin/systemctl *`, `apt-get`, `dnf`, `yum`, `microdnf`) only when `uname -s` is `Linux`.
   - The k3s rules (`/usr/local/bin/k3s *`, `k3s-uninstall.sh`, `k3s-killall.sh`) are a separate item, below. Leave them in.
   - Leave every other rule byte for byte.
7. **Classification.** Add the four `browser.*` labels to `scripts/etc/machine/not-installed.list` ("user LaunchAgent managed by cluster-up"). Change the five legacy entries' reason to "legacy system LaunchDaemon, removed by make install-browser-relays". `agent_classification.bats` and `machine_setup_acceptance.bats` must stay green.

Out of scope:
- The k3s rules. `k3s *` is still a root-equivalent wildcard on any Mac that has `/usr/local/bin/k3s`. It needs its own design for Linux k3s nodes, so file it separately.
- `bin/install-browser-relays.sh`, apart from bug fixes found while testing.
- Live install. The operator runs `make install-browser-relays` after this lands (parent E3).

## Files

- `bin/cluster-up`
- `bin/cluster-down`
- `bin/cluster-refresh` (added 2026-11-05, correction 3)
- `scripts/tests/bin/cluster_refresh.bats`
- `scripts/lib/providers/k3s-hostinger.sh`
- `bin/install-sudoers.sh`
- `scripts/etc/cloudflared-config.yml.tmpl`
- `scripts/etc/cloudflared/config.yml`
- `scripts/etc/cloudflared/origins.tsv`
- `scripts/etc/machine/not-installed.list`
- `scripts/tests/bin/cluster_up.bats`
- `scripts/tests/bin/install_sudoers.bats`
- `scripts/tests/lib/argocd_browser_listener_defaults.bats`
- `scripts/tests/bin/browser_user_listeners.bats` (new)
- `docs/bugs/2026-11-05-launchdaemon-d3-part-b-user-listeners.md`

## Acceptance

```yaml
must:
  - id: M1
    text: "cluster-up writes each of the four browser listeners as a plist under $HOME/Library/LaunchAgents with the new label from the Fix table, and bootstraps it into gui/<uid>."
  - id: M2
    text: "Each listener wrapper binds the address and high port from the Fix table (127.0.0.1:18443, 127.0.0.1:18080, 127.0.0.2:18082, 127.0.0.3:18083), and its own health probe targets that high port."
  - id: M3
    text: "When a relay plist or a required loopback alias is missing, cluster-up prints a single warning naming `make install-browser-relays`, skips that listener's browser-URL wait, and continues (exit status not changed by this)."
  - id: M4
    text: "When relays and aliases are present, cluster-up still waits on the browser URL as before (paired positive control for M3)."
  - id: M5
    text: "cluster-down and the Hostinger refresh stop and restart the four user agents in gui/<uid>."
  - id: M6
    text: "Cloudflare origins served by the Hostinger frontend listener point at http://127.0.0.2:18082."
  - id: M7
    text: "install-sudoers --dry-run on Linux still contains the systemctl/apt-get/dnf/yum/microdnf rules; every rule not named in the Fix is unchanged."
  - id: M8
    text: "cluster-refresh regenerates the argocd, keycloak and sandbox-frontend wrappers on their high ports and ensures the three browser.* user agents in gui/<uid> (added 2026-11-05, correction 3)."
must_not:
  - id: N1
    text: "No code path in cluster-up, cluster-down, cluster-refresh or k3s-hostinger.sh writes under /Library/LaunchDaemons, calls launchctl in the system domain, or runs ifconfig, for any of the five legacy labels or the four new ones."
  - id: N2
    text: "cluster-up never invokes sudo (directly or via _run_command) for browser listeners, including when relays are missing and stdin is not a TTY."
  - id: N3
    text: "install-sudoers --dry-run output has no rule naming /Library/LaunchDaemons, `launchctl bootstrap system`, `launchctl bootout system`, or `ifconfig lo0`; on macOS (uname Darwin) it has no systemctl/apt-get/dnf/yum/microdnf rule."
  - id: N4
    text: "No generated LaunchAgent plist for these listeners is written outside $HOME/Library/LaunchAgents, and none sets UserName or binds a non-loopback address."
evidence:
  - {id: E1, proves: [M1, M2, M5, N1, N4], kind: offline, text: "BATS with HOME and the LaunchAgents dir in BATS_TEST_TMPDIR (fixture asserts HOME is not the real home), launchctl/kubectl/socat/sudo stubs on PATH that log args (stubs asserted by command -v first); N1 red on f4536a9e."}
  - {id: E2, proves: [M3, M4, N2], kind: offline, text: "BATS with relay plist dir and ifconfig output stubbed absent then present, stdin not a TTY; sudo stub log empty in both; M4 shows the wait call happens when present."}
  - {id: E3, proves: [M7, N3], kind: offline, text: "install_sudoers.bats dry-run with uname stubbed Darwin and Linux; N3 red on f4536a9e."}
  - {id: E4, proves: [M6], kind: offline, text: "Static check of the three cloudflared files: every 127.0.0.2 origin row tied to the Hostinger frontend uses port 18082."}
  - {id: E5, proves: [M1, M2, M3, M6, N2], kind: live, text: "Operator, M4 then M5: make install-browser-relays, make install-sudoers, reboot; Claude checks launchctl print gui/<uid>/com.k3d-manager.browser.* is running, the four browser URLs answer, the public frontend answers, `sudo -n -l` lists no LaunchDaemon or ifconfig rule, and make up / acg-up never prompts for a password."}
interface:
  - "bin/cluster-up (ACG and Hostinger browser listener steps)"
  - "bin/cluster-down"
  - "bin/cluster-refresh (section 5, launchd browser listeners)"
  - "scripts/lib/providers/k3s-hostinger.sh refresh path (_hostinger_restart_launchd callers)"
  - "bin/install-sudoers.sh --dry-run"
  - "env: HOME, PATH (stubs), K3DM_LAUNCHD_DIR (relay plist dir lookup, test only, ignored as root)"
```

## Correction 3 (Claude review, 2026-11-05): `bin/cluster-refresh` was missed

The spec's writer table left out `bin/cluster-refresh`. Its section 5 ("launchd daemons (system-domain)", ~506–571) still does the following for `argocd-browser-https`, `keycloak-browser-http` and `sandbox.frontend-browser-http`:
- writes the wrapper on the old ports (443; 127.0.0.3:80);
- writes each plist to `/Library/LaunchDaemons` through `_system_daemon_install_if_missing`;
- bootstraps it into the system domain with `_launchd_ensure … system`.

After `make install-browser-relays` removes the legacy daemons, the next `make refresh` would put them back as root daemons running wrappers under `$HOME`. Those daemons bind the same ports as the relays. This breaks N1 and E5.

Fix:
- Section 5 regenerates the three wrappers exactly the way `cluster-up` now does: same helper functions, high ports 18443, 18080 and 18083, health probes on those ports.
- It writes and ensures the three `com.k3d-manager.browser.*` plists in `$HOME/Library/LaunchAgents`, using `_launchd_ensure … user`. Reuse `cluster-up`'s plist writer if one can be shared; otherwise write the same plist content.
- It never calls sudo, `/Library/LaunchDaemons` or `launchctl … system` for these labels.
- Delete `_system_daemon_install_if_missing` if nothing calls it any more.
- The Cloudflare tunnel restart (section 6) stays as it is.
- Tests in `scripts/tests/bin/cluster_refresh.bats`:
  - M8;
  - N1 for `cluster-refresh`, using the block-extraction style already in that file, with `HOME` in `BATS_TEST_TMPDIR`, and the stubs asserted on PATH and logging their arguments. Show N1 red on the current worktree version of `cluster-refresh` (which still has the system-daemon code) before fixing it.

## Independent verification (2026-11-06)

A Sonnet verifier wrote 25 BATS tests from the Acceptance block (plus the Fix table's labels and binds) only, against `git archive` copies of `b122ffb1` (fix) and `3d369254` (pre-fix) in the scratchpad, with logging stubs for launchctl, sudo, ifconfig, kubectl and socat, and HOME under `BATS_TEST_TMPDIR`. Claude reran them with stdin `</dev/null`:
- Fix `b122ffb1`: rc 0, 25/25.
- Pre-fix `3d369254`: rc 1, 21 fail, covering N1, N2, N3, N4, M1–M6 and M8. The four passes on pre are the unchanged Linux sudoers rules (M7, two tests), the helper's positive control, and one cluster-down N1 test that passes vacuously because pre-fix cluster-down stops at a sudo gate when headless; the passwordless-sudo N1 variant is red on pre.
- cluster-up and cluster-refresh were run as fragments, because the whole scripts start Chrome/Playwright. E5 is live and not covered.
- Two notes from the verifier, both not defects: `cluster-refresh` `_launchd_ensure` uses `launchctl load` on the `~/Library/LaunchAgents` plist (it loads into `gui/<uid>`); `cluster-down` does not stop the Hostinger frontend agent, whose lifecycle the Fix table puts in `k3s-hostinger.sh` only.
- Repo `git status` was clean afterwards. Recorded with `k3dm-codex-dispatch verify`.

## Live E5 on the M4 (2026-11-06, partial)

Read-only checks after the operator's reboot:

| Check | Result |
|---|---|
| `sudo -n -l` | PASS: no LaunchDaemon, `ifconfig` or Linux-only NOPASSWD rules; the `k3s` rules are a known separate item |
| `/Library/LaunchDaemons` | PASS: only the 4 relays and `loopback-aliases`, all loaded |
| Aliases `127.0.0.2`, `127.0.0.3` | PASS: present after the reboot |
| Relay sockets `127.0.0.1:443`, `127.0.0.1:80`, `127.0.0.2:80`, `127.0.0.3:80` | PASS: `nc` rc 0 |
| Four `browser.*` agents and their high ports | NOT PROVEN: no plists, because no `cluster-up` or refresh has run on the M4 since the fix, and its cluster is stopped |
| Local browser URLs | NOT PROVEN: argocd rc 35, keycloak rc 56, frontend rc 56, because the relays have no backend |
| `make up` without a password prompt | NOT RUN |

launchd's override database still lists `com.k3d-manager.frontend-browser-http` as enabled; the plist is gone.

The reboot also exposed a separate outage, not caused by Part B: `docs/bugs/2026-11-06-hub-cutover-old-hub-agents-return-on-reboot.md`.
