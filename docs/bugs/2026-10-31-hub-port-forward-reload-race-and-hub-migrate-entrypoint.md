# Bug: hub port-forward installs race launchd, can undo a cutover, and a migration needs two targets with a stale old-host default

**Status:** OPEN
**Priority:** P2
**Approval:** operator, 2026-10-31 ("go ahead"), in reply to Claude's five-item proposal (hub-migrate, required old host, Makefile reload race, cutover-forward guard, docs)
**Filed:** 2026-10-31
**Detected by:** Claude, after the live `Bootstrap failed: 5` in `make hub-cutover-forwards` (fixed in `bin/hub-cutover` by `ee9cedc5`)
**Affected:** `Makefile` (`install-*-port-forward`, new `hub-migrate`); `bin/hub-new`; `bin/hub-cutover`; docs
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/bugs/2026-10-30-hub-cutover-leaves-old-hub-producers-on-old-pushgateway.md`; `docs/bugs/v1.7.1-bugfix-launchd-ensure-bootout-before-bootstrap.md` (same error class in `bin/cluster-refresh`)

## Observed failures

**F1 — reload race.** The five Makefile targets `install-vault-port-forward`, `install-prometheus-port-forward`,
`install-hub-pushgateway-port-forward`, `install-hub-loki-port-forward` and `install-alertmanager-port-forward`
run `launchctl bootout ... || true` and then `launchctl bootstrap` straight away. `bootout` returns before a
running job is gone, so `bootstrap` can fail with `Bootstrap failed: 5: Input/output error`. This happened live in
`bin/hub-cutover` on 2026-10-31 and left the M4 Pushgateway forward unloaded. `bin/hub-restore` (lines 221–222),
`make up` (`CLUSTER_PROVIDER=k3d`) and so `make hub-recover-all` call these targets, so the monthly in-place M5
rebuild is exposed.

launchctl behaviour, captured on m4-air 2026-10-31T11:57:54Z:
- `launchctl bootout gui/501/<label not loaded>` prints `Boot-out failed: 3: No such process`, exit 3.
- `launchctl print gui/501/<label not loaded>` exits 113.
- `bootstrap` right after `bootout` of a running job: `Bootstrap failed: 5: Input/output error`.

**F2 — an install undoes a cutover.** On the old hub, `hub-cutover` rewrites
`~/Library/LaunchAgents/com.k3d-manager.hub-{pushgateway,loki}-port-forward.plist` to ssh tunnels to the new hub,
keeping the original as `<plist>.pre-cutover`. Running `make install-hub-pushgateway-port-forward` (or `make up`)
on the old hub overwrites the tunnel with a local `kubectl port-forward`. The old hub's producers then push to
the old Pushgateway again with no error.

**F3 — two targets and a stale default.** A migration is `make hub-new` then `make hub-cutover`. Both scripts
default `HUB_OLD_HOST` to `m4-air.local` (`bin/hub-new:19`, `bin/hub-cutover:9`). Once the M4 retires, a move from
the M5 to another machine silently targets the M4 unless the operator remembers to override it.

**F4 — stale doc.** `docs/howto/hub-rebuild-from-gitops-vault.md` step 3 says `make up CLUSTER_PROVIDER=k3d`
"fails outright" and gives a manual seven-command sequence. `make up` now routes `k3d` to `bin/hub-up`, and
`make hub-recover-all` is the supported rebuild.

## Fix

### R1 — `bin/launchd-reload` (new)

`bin/launchd-reload <label> <plist>`, bash, `set -euo pipefail`:
- `launchctl bootout gui/$(id -u)/<label>`; exit 0 or 3 is fine, any other exit is a failure (print it, exit 1).
- Poll `launchctl print gui/$(id -u)/<label>` until it exits non-zero, up to `LAUNCHD_RELOAD_TRIES` (default 30)
  tries `LAUNCHD_RELOAD_WAIT` (default 0.5) seconds apart. Still loaded after that: print
  `launchd-reload: <label> still loaded after bootout` and exit 1 without bootstrapping.
- Then `launchctl bootstrap gui/$(id -u) <plist>`; its exit status is the script's.

All five `install-*-port-forward` targets call `bin/launchd-reload` in place of their bootout/bootstrap pair.
Leave the `uninstall-*` targets and `bin/hub-cutover` (its python `reload()` runs on the remote host) unchanged.

### R2 — refuse to overwrite a cutover tunnel

`install-hub-pushgateway-port-forward` and `install-hub-loki-port-forward` refuse, before writing anything, when
`<plist>.pre-cutover` exists:
`refusing: <plist> is a hub-cutover tunnel to the new hub; run make hub-cutover-rollback to restore it, or set HUB_FORWARD_OVERWRITE=1`.
Exit non-zero. With `HUB_FORWARD_OVERWRITE=1` they proceed as normal (and leave the backup alone).
`bin/hub-restore` and `make up` therefore fail loudly on a cut-over old hub, which is intended.

### R3 — no default old host

- `bin/hub-new`: `HUB_OLD_HOST` is required. Unset or empty: print
  `hub-new: set HUB_OLD_HOST to the old hub (e.g. HUB_OLD_HOST=m4-air.local)` and exit 2 before any stage runs.
  Write `"old_host"` into `hub-new-report.json`.
- `bin/hub-cutover` (default cutover mode): old host = `HUB_OLD_HOST` if set, else `old_host` from the passing
  `hub-new` report; neither: refuse (exit 2) with the same style of message. If both are set and differ, refuse.
  Record the resolved host in `$STATE_DIR/old-host`.
- `--verify`, `--forwards`, `--rollback`: old host = `HUB_OLD_HOST` if set, else `$STATE_DIR/old-host`; neither:
  refuse (exit 2).
- No `m4-air.local` literal remains in either script.

### R4 — `make hub-migrate`

`hub-migrate` runs `bin/hub-new`, then `bin/hub-cutover`, in one recipe, passing `HUB_OLD_HOST` through. It is a
recipe, not a prerequisite chain: `hub-cutover` must not gain `hub-new` as a prerequisite. If `hub-new` fails,
`hub-cutover` does not run. Both typed confirmations (data-recovery approval, `cutover`) stay. Add `hub-migrate`
to `.PHONY` and to `make help`.

### R5 — docs

- `docs/howto/m5-hub-migration.md`: `make hub-migrate HUB_OLD_HOST=<old>` as the main path; `hub-new` /
  `hub-cutover` / `hub-cutover-forwards` / `hub-cutover-verify` / `hub-cutover-rollback` as the step-by-step and
  recovery path; `HUB_OLD_HOST` is required; F2's refusal and how to clear it.
- `docs/howto/hub-rebuild-from-gitops-vault.md` step 3: replace the stale text with `make hub-recover-all` (and
  `make up CLUSTER_PROVIDER=k3d` → `bin/hub-up` for a cluster-only rebuild); keep the debris and verify steps.
- `CHANGELOG.md` `[Unreleased]`.

## Files

- `bin/launchd-reload` (new)
- `bin/hub-new`
- `bin/hub-cutover`
- `Makefile`
- `scripts/tests/bin/launchd_reload.bats` (new)
- `scripts/tests/bin/makefile_hub_port_forward.bats` (new)
- `scripts/tests/bin/hub_new.bats`
- `scripts/tests/bin/hub_cutover.bats`
- `docs/howto/m5-hub-migration.md`
- `docs/howto/hub-rebuild-from-gitops-vault.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: bin/launchd-reload bootstraps only after launchctl print reports the label gone, and succeeds when the label was not loaded (bootout exit 3)
  - id: M2
    text: all five install-*-port-forward targets reload through bin/launchd-reload
  - id: M3
    text: make hub-migrate HUB_OLD_HOST=<h> runs hub-new then hub-cutover with that host; hub-cutover does not run when hub-new fails
  - id: M4
    text: hub-cutover resolves the old host from HUB_OLD_HOST or the passing hub-new report's old_host, records it, and --verify/--forwards/--rollback reuse the recorded host
  - id: M5
    text: with HUB_FORWARD_OVERWRITE=1, install-hub-*-port-forward overwrites a cutover plist
must_not:
  - id: N1
    text: bin/launchd-reload never runs bootstrap while print still reports the label loaded, and exits non-zero after the retry budget
  - id: N2
    text: install-hub-pushgateway-port-forward / install-hub-loki-port-forward never modify a plist that has a .pre-cutover backup unless HUB_FORWARD_OVERWRITE=1
  - id: N3
    text: hub-new and hub-cutover never fall back to a hard-coded old host; with no host from any source they exit non-zero before ssh, kubectl or launchctl is called
  - id: N4
    text: hub-cutover refuses when HUB_OLD_HOST and the report's old_host differ
  - id: N5
    text: hub-cutover has no make prerequisite on hub-new (rerunning make hub-cutover never runs hub-new)
  - id: N6
    text: tests never call the real launchctl, ssh, kubectl or write under the real ~/Library/LaunchAgents; fixtures assert a scratch HOME and stubbed PATH first
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    text: BATS with a launchctl stub using the captured exit codes (bootout 3 when unloaded, print 113 when unloaded, bootstrap 5 while lingering); lingering N prints then gone; never gone; not loaded
  - id: E2
    proves: [M2, M5, N2]
    kind: offline
    text: BATS running each install target with scratch HOME and stubbed launchctl/kubectl; plist with and without .pre-cutover; with and without HUB_FORWARD_OVERWRITE=1 (paired positive control)
  - id: E3
    proves: [M3, M4, N3, N4, N5]
    kind: offline
    text: BATS for hub-new/hub-cutover host resolution and make hub-migrate ordering with stubbed bin scripts; make -p shows hub-cutover has no hub-new prerequisite
  - id: E4
    proves: [M1, M2]
    kind: live
    text: operator runs make install-hub-pushgateway-port-forward on the M5 with the forward running; it reloads without error 5 and 19094 answers; Claude confirms launchctl print state = running
  - id: E5
    proves: [N2]
    kind: live
    text: Claude runs make install-hub-pushgateway-port-forward on the M4 (cut-over, has .pre-cutover) and sees the refusal; the tunnel plist is byte-identical before and after
interface:
  - bin/launchd-reload <label> <plist>; env LAUNCHD_RELOAD_TRIES, LAUNCHD_RELOAD_WAIT
  - make install-{vault,prometheus,hub-pushgateway,hub-loki,alertmanager}-port-forward; env HUB_FORWARD_OVERWRITE
  - make hub-migrate / hub-new / hub-cutover / hub-cutover-verify / hub-cutover-forwards / hub-cutover-rollback; env HUB_OLD_HOST, HUB_NEW_STATE_DIR, HUB_CUTOVER_STATE_DIR
  - files hub-new-report.json (old_host), $HUB_CUTOVER_STATE_DIR/old-host
```

Test controls:
- N1 is paired with a job that lingers 2 prints and then goes, which does bootstrap.
- N2 is paired with M5 (`HUB_FORWARD_OVERWRITE=1` does overwrite) and with a plist without a backup, which installs.
- N3 is paired with a run where `HUB_OLD_HOST` is set, which reaches the first stage.
- The launchctl stub's exit codes come from the m4-air capture above; put the host and date in a comment.

## Definition of Done

- [ ] R1–R5 implemented; shellcheck on `bin/launchd-reload`, `bin/hub-new`, `bin/hub-cutover`; the four BATS files
  above pass; paste the counts
- [ ] Each must_not test shown red against the pre-fix code
- [ ] Commit `fix(hub): race-free port-forward reloads, cutover-tunnel guard, hub-migrate and required old host` on
  `k3d-manager-v1.43.12`, pushed, SHA reported

## What NOT to Do

- Do not create a PR, skip hooks (`--no-verify`), or commit to `main`.
- Do not modify files outside the Files list; do not touch `scripts/lib/foundation/`.
- Do not change `bin/hub-cutover`'s python `reload()` or the `uninstall-*` targets.
- Do not make `hub-cutover` depend on `hub-new` as a make prerequisite.
- Do not remove either typed confirmation.
- Do not call the real launchctl, ssh or kubectl from tests, or write under the real `~/Library/LaunchAgents`.
