# Bug: cluster-status test rewrites the operator's real Alertmanager launch agent

**Status:** OPEN — child C3 of `docs/bugs/2026-11-09-offline-test-all-red-on-m4-four-root-causes.md`; spec written
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-09
**Introduced by:** unknown (the restore call in `bin/cluster-status:431` and the test predate this audit; not bisected)
**Should have been caught by:** review
**Prior art:** none above threshold — exact-slug glob empty; `make find-similar-docs` not run to a result (vector
store unreachable from the M4, 2026-11-09). Grep of `docs/bugs/` for launch agent and tripwire found only unrelated
LaunchAgent-template bugs and `2026-10-24-ci-promql-tests-blocked-by-tripwire-docker.md` (C2's area).
**Severity:** medium-high — a test has already changed a real file on the operator's host; only the tripwire stopped the
`launchctl` calls that would have loaded it
**Approval:** operator, 2026-11-09 (parent bug: one P2 parent with a child per root cause)
**Intent approved:** not yet
**Filed:** 2026-11-09
**Detected by:** Claude, 2026-11-09, tripwire report in the P=1 parallel run; the file write was found later while
writing this spec
**Release:** v1.43.16 (bug-only)
**Branch:** filed on `k3d-manager-v1.43.15`; fix goes on `k3d-manager-v1.43.16`

## Symptom

`scripts/tests/bin/cluster_status_app_cluster_registration.bats` fails all 3 cases under `make test-bin`. The tripwire
blocks 30 `launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist` calls
and 3 `bootout` calls.

The tripwire shims only commands. It did not stop the file write that comes before them. On the M4 (`m4-air`),
captured 2026-11-09:

- `~/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist` was modified at 2026-11-09 18:18:04, during
  the test runs. Its kubectl path is now `/tmp/bats-run-5P6b9w/test/3/bin/kubectl`, the test's stub, which no longer
  exists.
- The agent is not loaded on the M4 (`launchctl print` gives "Could not find service"), so nothing is broken now.
  On a host where it gets loaded again (a reboot, or `make platform-ops`), the Alertmanager port-forward would run a
  missing kubectl and port 19093 would stay down.
- The sibling `com.k3d-manager.alertmanager-auth-proxy.plist` (2026-10-29) is unchanged: the run stopped at the first
  bootstrap failure, before reaching the auth proxy install.

## Root cause

`bin/cluster-status:431` runs `_observability_restore_alertmanager_access_layer` (`scripts/plugins/observability.sh:589`)
in full mode. On macOS, with `launchctl` and `kubectl` on PATH, it reinstalls the access layer when either plist is
missing or port 19093 or 9093 is not listening (`lsof`). On the M4 the ports are not listening, so it runs
`_observability_install_alertmanager_port_forward` (`:273`). That function writes `${HOME}/Library/LaunchAgents/…plist`
with `sed > file` and then calls `_observability_launchd_reload`.

The test stubs `kubectl`, `aws` and `curl`, but not `launchctl`, and it does not isolate `HOME`. So the write targets the
real home, and the reload targets the real launchd domain. The other five `cluster_status_*.bats` files only grep the
script and are not affected. `cluster_status_summary.bats` sets `HOME="${TMP_DIR}"` per call and runs only
`--mode json|summary`, which never reaches line 431.

The tripwire (`scripts/tests/tripwire.sh`) has a gap: it catches a blocked command but not a write to the operator's
real files.

## Fix

1. **Test isolation** (`scripts/tests/bin/cluster_status_app_cluster_registration.bats`): in `setup`, set `HOME` to a
   directory under `BATS_TEST_TMPDIR`, and add a `launchctl` stub that logs its arguments to a file in that directory
   and exits 0. Do not stub out the restore call. The test keeps exercising the real `bin/cluster-status`.
2. **Tripwire write check** (`scripts/tests/tripwire.sh`): before the command runs, record the path, size and mtime of
   every `com.k3d-manager.*.plist` in the real `$HOME/Library/LaunchAgents`. Afterwards, compare. Any file created,
   changed or removed fails the run (exit non-zero even if the command passed), and stderr names each file. When the
   directory does not exist (Linux CI, `fast_gate.sh`), the check is a no-op. For tests of the check itself, the
   directory comes from `K3DM_TRIPWIRE_WATCH_DIR`, defaulting to `$HOME/Library/LaunchAgents` as `HOME` was when the
   tripwire started.
3. Production behaviour of `bin/cluster-status` and `observability.sh` is unchanged.

Out of scope: repairing the M4 plist (operator decision, below); any change to `_observability_restore_alertmanager_access_layer`.

## Contract readers

`scripts/tests/tripwire.sh` is shared. Every reader now also gets the write check:

| Reader | Changes? |
|---|---|
| `Makefile:1408` (`test`), `:1415` (`test-bin`), `:1431` (`test-python` per file), `:1553` (`test-metrics` python) | Behaviour: a run that changes a real k3dm plist now fails. Recipes unchanged. |
| `scripts/ci/fast_gate.sh:47`, `:51` | No: runs on Linux CI, where the directory does not exist, so the check is a no-op. Must stay green (E5). |
| `scripts/tests/bin/test_test_tripwire.py:16`, `:40` | Gains the new cases (E3); existing assertions unchanged. |
| `scripts/tests/lib/fast_gate.bats:9` | Copies the file into a fixture; must still pass (E5). |

## Operator decision needed now (not part of the dispatch)

The M4's port-forward plist is contaminated. Choose one:

- **Remove it** (recommended). The M4 is no longer the hub and the agent is not loaded. A later `make platform-ops`
  or observability install recreates it from the template if it is ever needed.
- **Regenerate it** from `scripts/etc/launchd/com.k3d-manager.alertmanager-port-forward.plist.tmpl` with the real kubectl
  path.

Please also run this on the M5 hub, to confirm the hub's plists were not hit:
grep -l bats-run ~/Library/LaunchAgents/com.k3d-manager.*.plist
No output means clean. The hub was probably protected, because there both plists exist and the ports listen, so the
restore returns early.

## Acceptance

```yaml
must:
  - id: M1
    text: cluster_status_app_cluster_registration.bats passes all its cases under make test-bin (inside the tripwire),
      with the tripwire reporting zero blocked calls from this file.
  - id: M2
    text: the restore path still runs in the test; the launchctl stub records a bootstrap whose plist path is under
      the test's own HOME, not the real one.
  - id: M3
    text: scripts/tests/tripwire.sh fails the run, naming the file, when a com.k3d-manager.*.plist in the watched
      LaunchAgents directory is created, modified or removed during the command, even if the command exited 0.
must_not:
  - id: N1
    text: running the test file must not create, modify or remove any file under the HOME it inherited.
  - id: N2
    text: the tripwire write check must not fail a run in which nothing in the watched directory changed, and must be
      a no-op when the directory does not exist.
  - id: N3
    text: no case is deleted, skipped or weakened, and the restore call at bin/cluster-status:431 is not removed,
      guarded off, or bypassed by an env var.
evidence:
  - id: E1
    proves: M1, M2
    kind: offline
    intent: The cluster-status test passes under the normal test-bin run, and its fake launchctl shows the restore
      still runs, pointed at a throwaway home.
  - id: E2
    proves: N1
    kind: offline
    intent: Run the test with HOME set to a sentinel folder; before the fix the sentinel gains a plist (red), after
      the fix it is byte-for-byte unchanged (green). Your real home is never used.
  - id: E3
    proves: M3, N2
    kind: offline
    intent: The tripwire goes red when a command touches a plist in a sentinel watch folder, stays green when it does
      not, and stays green when the folder is missing.
  - id: E4
    proves: M1, N1
    kind: live
    intent: Claude runs make test-bin on the M4 and shows the mtimes of every k3dm plist in your real LaunchAgents are
      the same before and after.
  - id: E5
    proves: N2
    kind: offline
    intent: fast_gate.bats and the CI fast gate stay green, so Linux CI is unaffected.
interface:
  - bin/cluster-status
  - scripts/tests/bin/cluster_status_app_cluster_registration.bats
  - scripts/tests/tripwire.sh (K3DM_TRIPWIRE_WATCH_DIR)
  - make test-bin
```

N1 and N3 are shown red against the pre-fix code by E2 (sentinel HOME gains a plist) and by a mutation that deletes
line 431 (M2's stub log goes empty).

## Worker definition of done

- E1, E2, E3 and E5 run and pass; paste each command, rc and the proving line.
- E2's red run against the pre-fix test is shown, using only a sentinel HOME under the scratch directory. Never run the
  pre-fix test with the real HOME.
- `git diff --stat` touches only the two files in Fix, plus new tests.
