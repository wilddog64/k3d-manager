# Bug: a browser agent exits 78 forever when the legacy root daemon left its log root-owned, so the public frontend returns 502 after `make install-browser-relays`

**Status:** OPEN — root cause proven on the M5; not dispatched
**Priority:** P1
**Severity:** high. The Hostinger frontend is unreachable from the hub, publicly and in a browser, and nothing reports why. A one-time manual `chown` recovers it, but the install prints success and leaves the agent retrying.
**Approval:** Filing: Claude, 2026-11-06, told the operator when reporting the 502. Dispatch: pending.
**Filed:** 2026-11-06
**Detected by:** Claude (M5 live checks after D3 Part B, 2026-11-06)
**Affected:** `bin/install-browser-relays.sh`, `com.k3d-manager.browser.hostinger-frontend-http`
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-05-launchdaemon-d3-part-b-user-listeners.md` (the migration that exposed this); `docs/bugs/2026-11-06-hostinger-refresh-skips-argocd-keycloak-browser-agents.md`; `docs/bugs/2026-10-03-root-owned-state-logs-dir-kills-grafana-port-forward.md` (same class, on the logs directory rather than one file)

## Observed failure

Captured on the M5 (`m5-air.local`), 2026-11-06 about 04:26 PST, after the operator ran `make install-browser-relays`, `make install-sudoers` and `CLUSTER_PROVIDER=k3s-hostinger make refresh-edge`:

- `launchctl print gui/501/com.k3d-manager.browser.hostinger-frontend-http`: `state = spawn scheduled`, `last exit code = 78: EX_CONFIG`, `runs` climbing.
- `lsof` shows no listener on `127.0.0.2:18082`.
- `https://frontend.3ai-talk.org/` returns 502. Argo CD, Keycloak, Grafana, Prometheus, Alertmanager and the webhook answer normally.
- `-rw-r--r--  1 root  staff  46041 Nov  6 03:41 frontend-browser-http.log`; every other file in that directory is owned by `cliang`.
- The plist's `StandardOutPath` and `StandardErrorPath` both name that file. `test -w` on it fails as `cliang`.

## Root cause

Not reproduced in isolation. The evidence above identifies it: launchd opens the agent's log paths before it runs the program, and a user agent cannot open a root-owned file.

The legacy `com.k3d-manager.frontend-browser-http` root daemon wrote that log. `bin/install-browser-relays.sh` removes the daemon and leaves the file. The argocd and keycloak agents escaped because their logs were not root-owned, so this hits a host according to which legacy daemons last wrote there. The M4's three logs are owned by `cliang` (read 2026-11-06), which is why its Part B pass did not see this.

The Part B and Part B gap tests start from an empty state directory, so they could not see it.

## Fix

In `bin/install-browser-relays.sh`, install mode only, after the legacy daemons are removed:

1. For each regular file matching `*-browser-http*.log` or `*-browser-https*.log` directly in `$HOME/.local/share/k3d-manager/logs/`, if it is owned by root, change it to the invoking user with `_run_command --interactive-sudo -- /usr/sbin/chown -h <user> -- <path>`. When the script itself runs as root, the invoking user is `SUDO_USER`; refuse to change ownership if that is unset.
2. Leave files already owned by the user alone, and do not follow symlinks. Do not recurse, and do not touch anything else in the directory.
3. A failed `chown` prints the file and exits non-zero, so the install does not report success with an agent that cannot start.

Dry-run and uninstall modes change no ownership. No new sudoers rule: this runs under the operator's interactive `make`.

## Files

- `bin/install-browser-relays.sh`
- `scripts/tests/bin/install_browser_relays.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "After the install, a root-owned frontend-browser-http.log in the state logs directory is owned by the invoking user."
  - id: M2
    text: "The same holds for the argocd and keycloak browser logs and their launchctl logs (paired positive control for N1)."
  - id: M3
    text: "A chown that fails makes the install exit non-zero and names the file."
must_not:
  - id: N1
    text: "A log already owned by the user gets no chown call."
  - id: N2
    text: "A file in that directory not matching the browser log patterns, a file in a subdirectory, and a symlink are not changed; a chown never follows a symlink."
  - id: N3
    text: "Dry-run and uninstall make no ownership change."
  - id: N4
    text: "When run as root with SUDO_USER unset, no file is given to root or to an empty user."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2, N3, N4], kind: offline, text: "BATS with HOME in BATS_TEST_TMPDIR (asserted first) and stubs logging every chown call. The owner reported by the stat stub comes from a real capture, with host and date in a comment. M1 shown red on the pre-fix commit; each must_not shown red by a mutant."}
  - {id: E2, proves: [M1], kind: live, text: "Operator on the M5, once a file is root-owned again or on the next hub rebuild: make install-browser-relays; Claude checks the file's owner, the agent running, a listener on 127.0.0.2:18082, and frontend.3ai-talk.org answering."}
interface:
  - "bin/install-browser-relays.sh [--dry-run|--uninstall]"
  - "env: HOME, K3DM_LAUNCHD_DIR, SUDO_USER, PATH (stat, chown, launchctl, sudo stubs)"
```
