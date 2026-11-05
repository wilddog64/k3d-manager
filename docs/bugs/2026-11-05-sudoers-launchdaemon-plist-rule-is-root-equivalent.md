# Bug: LaunchDaemon and exec wildcard sudoers rules are root-equivalent

**Status:** OPEN — design needed; not dispatched
**Priority:** P1
**Severity:** high — local privilege escalation through rules that headless `acg-up` currently relies on.
**Filed:** 2026-11-05
**Detected by:** `docs/issues/2026-11-02-acg-phase-c-privileged-inventory.md` (Terra Phase C worktree), confirmed by Claude against `bin/install-sudoers.sh` at `7c9927e9`.
**Branch:** `k3d-manager-v1.43.14`
**Approval:** pending — the operator chooses a design before any dispatch
**Related:** `docs/bugs/2026-11-05-sudoers-passwordless-rules-grant-root-escalation.md` (narrow fix, dispatched first)

## Evidence

- `NOPASSWD: /usr/bin/install -m 644 * /Library/LaunchDaemons/com.k3d-manager.*.plist` together with `NOPASSWD: /bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.*.plist`.
  The caller writes the plist, chooses its `ProgramArguments`, and bootstraps it as a root daemon.
  Headless callers: `bin/cluster-up:906,1573,1748,1813` and `scripts/lib/providers/k3s-hostinger.sh:730`.
- `NOPASSWD: /bin/rm -f /Library/LaunchDaemons/com.k3d-manager.*.plist *`: the trailing `*` lets the caller delete any file as root.
- `NOPASSWD: /usr/local/bin/k3s *`, `/usr/bin/systemctl *`, `/usr/bin/apt-get *`, `dnf *`, `yum *` and `microdnf *` are each root-equivalent wherever the binary exists (for example `apt-get -o APT::Update::Pre-Invoke::=...`).
  They are harmless on macOS only while those paths stay absent.

## Design options (for the operator)

- **A.** A root-owned plist installer: `/usr/local/bin/k3d-manager-install-daemon <label> <port>...`. It renders each plist from a fixed template in a root-owned directory and accepts only allowlisted labels and numeric ports. The sudoers file would then allow only this helper.
- **B.** Drop passwordless plist install entirely. The listeners are installed once with a password by a `make browser-listeners` target, and headless runs only `bootstrap`/`bootout` the existing root-owned plists.
- **C.** Split the sudoers file per OS so the Linux wildcards never appear on macOS, and the reverse.

Recommendation: B plus C. They are the smallest change and need no new privileged code, which is the lesson from `2026-11-02-acg-up-stalls-at-system-keychain-trust`.

## Acceptance

To be written once a design is chosen.
