# Bug: promtool tests fail or skip on every Mac because only CI installs promtool

**Status:** LANDED (6f7187ab, 42fe44fa, 0a9e053c on k3d-manager-v1.44.0) — child C2 of `docs/bugs/2026-11-09-offline-test-all-red-on-m4-four-root-causes.md`
**Part A:** done upstream — `_install_promtool` merged in lib-foundation #83 (`5d301c1`), released v0.5.5 (#84) and subtree-pulled here in `5f832339` (Claude, 2026-11-14). Part B (k3d-manager) remains.
**Priority:** P2
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (Test-only issue where `promtool`-dependent tests fail or skip on local Macs while CI still runs them and runtime behavior is unaffected); Claude proposed P2. Claude's higher P2 stands until the operator decides.
**Triage:** carry → v1.44.0 (test-hygiene batch) — grooming 2026-11-12, operator. Priority: operator kept Claude's P2 over Argon's P3.
**Waiting on:** live check — since 2026-11-14 (machine-setup on the M5 and M2; CI run on the pushed head)
**Introduced by:** `docs/bugs/2026-10-24-ci-promql-tests-blocked-by-tripwire-docker.md` fix (v1.43.5), which
installed promtool in the CI `lint` job only
**Should have been caught by:** spec (the 2026-10-24 fix covered one environment; its 2026-10-30 Recurrence named
this and was not scheduled)
**Prior art:** `docs/bugs/2026-10-24-ci-promql-tests-blocked-by-tripwire-docker.md` (found by grep, not scored) —
read, same root cause: this is its local recurrence. Filed as a new child, not appended, because the fix now spans
lib-foundation, machine setup, CI and ten test files; a pointer is appended to that doc's Recurrence section.
`make find-similar-docs` not run to a result (vector store unreachable from the M4, 2026-11-09).
**Severity:** medium — 4 cases red on the M4, and real PromQL evaluation silently skipped in six more files on every
Mac, so a broken alert rule or dashboard query is caught only by CI
**Approval:** operator, 2026-11-09 (parent bug); install approach set by the operator 2026-11-09: "anything that we
need to have brew install should turn into _install_* from lib-foundation … make sure that control node will have it"
**Intent approved:** operator, 2026-11-09
**Filed:** 2026-11-09
**Detected by:** Claude, 2026-11-09, serial `make test-python` baseline on the M4
**Release:** v1.43.16 (bug-only)
**Branch:** lib-foundation change first (upstream), then `k3d-manager-v1.43.16`. Part A spec: `docs/plans/lib-foundation-v0.5.5-install-promtool.md`

## Symptom

No Mac in the fleet has `promtool` (M4: `command -v promtool` empty, 2026-11-09). Tests resolve it three ways, and
on a Mac every way fails or hides:

| File | Without promtool |
|---|---|
| `scripts/tests/bin/test_dashboard_queries.py:214` | falls back to `docker run`, tripwire blocks it (rc 97): **red** |
| `scripts/tests/bin/test_dispatch_metrics.py:1391` | same: **red** |
| `scripts/tests/bin/test_orbstack_metrics.py:110` | same, 2 cases: **red** |
| `scripts/tests/observability/test_kine_compaction_stalled.py:93` | docker fallback (dead under the tripwire) |
| `scripts/tests/observability/test_cve_fix_available_alert.py:15` | docker fallback, else `pytest.skip` |
| `scripts/tests/bin/test_vectordb_bug_metrics.py:351` | `pytest.skip` |
| `scripts/tests/plugins/grafana_dashboard_pr_checks.bats:183` | `skip "promtool not installed"` |
| `scripts/tests/plugins/e2e_observability.bats:365`, `:418` | `skip "promtool not installed"` |
| `scripts/tests/plugins/grafana_dashboard_appsets.bats:458` | `if command -v promtool` guard, check silently not run |

`scripts/tests/lib/fast_gate.bats` stubs promtool itself and is out of scope.

## Root cause

promtool is installed only by `.github/workflows/ci.yml:91-110`: Prometheus 3.1.0 linux-amd64 tarball, sha256
pinned, into `$HOME/.local/bin`. Machine setup installs nothing for it, and the `brew` formula that ships it
(`prometheus`) floats its version away from the 3.1.0 the tests pin. The docker fallback can never succeed under
`scripts/tests/tripwire.sh`, so it is dead code in every offline run.

## Fix

### Part A — lib-foundation (upstream first)

New `_install_promtool` in lib-foundation `scripts/lib/system.sh`, following the `_install_node_from_release`
pattern (`system.sh:1518`), plus a checksum:

- Version 3.1.0 by default (`PROMTOOL_VERSION`). The sha256 for each supported platform lives in the function. An
  unknown version or platform is refused: nothing is downloaded without a pinned checksum.
- Platforms: darwin-arm64, darwin-amd64, linux-amd64, linux-arm64. Checksums, captured 2026-11-10T03:13:06Z from
  `https://github.com/prometheus/prometheus/releases/download/v3.1.0/sha256sums.txt`:
  - `darwin-amd64` `de958826f9ca20003b30c48fa3f2fcfa67b2a3aebcabd6230e90bb94f92d86e8`
  - `darwin-arm64` `8ebe1d60d8864ae3e10a359c3b543563e972505e5ef6fe1d00586d86a7e813fc`
  - `linux-amd64` `9a9d1e115d1745826b13aec3f1409780b9fcf1d4206746cb4faee46ca5add70c` (matches `ci.yml:96-97`)
  - `linux-arm64` `c12b9e368006873df0c8865771af0434a3edfc8c8eaeea62b73d3974bff7f2a1`
- Installs only `promtool` into `${PROMTOOL_INSTALL_DIR:-$HOME/.local/bin}`. No sudo and no write outside that
  directory and a `mktemp -d` work dir, which is removed on every path. This fits the control node's no-privilege
  rule (`docs/plans/v1.43.15-control-node-linux.md`).
- Idempotent: if the target already reports `promtool, version 3.1.0`, return 0 without downloading.
- Checksum via `shasum -a 256` or `sha256sum`, whichever exists. A mismatch removes the download and returns non-zero.
- BATS tests in lib-foundation with a stubbed `curl` serving a fixture tarball. The real download is a live check.

### Part B — k3d-manager (after the subtree pull)

1. `bin/k3dm-machine-setup` calls `_install_promtool` for the roles that run the offline suite: `control`,
   `console` and `hub`, not `worker`. It reports the result like other setup steps.
2. `.github/workflows/ci.yml:91-110`: the hand-rolled step is replaced by sourcing lib-foundation and calling
   `_install_promtool`, so CI and every host share one pin.
3. Shared resolvers: `scripts/tests/promtool_helper.py` (`resolve_promtool()`) and `scripts/tests/promtool.bash`
   (`k3dm_promtool`). Order: `$PROMTOOL`, then `$HOME/.local/bin/promtool`, then `promtool` on PATH. When none is
   found, the case **fails** with `promtool not found; run make machine-setup (installs promtool 3.1.0)`. No skip,
   and no docker fallback.
4. The ten files above use the resolver. Every docker fallback, `skip` and `if command -v promtool` guard for
   promtool is removed.

Out of scope: upgrading Prometheus or the pinned 3.1.0; `fast_gate.bats`.

## On converting other brew installs (operator's general rule)

Claude's view, for the operator to rule on separately, not part of this dispatch: use `_install_*` where a tool
must be **pinned and verified**, or is needed **where brew is not** (CI, a minimal host). That covers promtool, and
probably bats, helm and kubectl, which already have installers. For everything else, keep the per-role brew lists
in `scripts/etc/machine/brew.*.list`. `k3dm-machine-setup` already installs Linuxbrew on the control node from a
pinned installer (`homebrew-install.linux.pin`), so those lists already reach it. A blanket conversion would
reimplement Homebrew's upgrades and dependencies tool by tool. Recorded as an idea row if the operator wants it
groomed.

## Files

Part B only (Part A is done upstream; `_install_promtool` is in the subtree at `scripts/lib/foundation`, loaded by
`scripts/lib/system.sh`). Added 2026-11-14 by Claude; C1 (`d96547df`) has landed, so the `e2e_observability.bats`
overlap is gone.

- `bin/k3dm-machine-setup` (new `_install_promtool` step for `control`, `console`, `hub`; not `worker`)
- `scripts/tests/bin/machine_setup.bats` (the new step runs for the three roles and not for `worker`, `_install_promtool` stubbed)
- `.github/workflows/ci.yml` (the "Install promtool" step near line 91: source `scripts/lib/system.sh`, call `_install_promtool`, keep appending `$HOME/.local/bin` to `GITHUB_PATH`)
- `scripts/tests/promtool_helper.py` (new, `resolve_promtool()`)
- `scripts/tests/promtool.bash` (new, `k3dm_promtool`)
- `scripts/tests/bin/test_dashboard_queries.py`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/bin/test_orbstack_metrics.py`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `scripts/tests/observability/test_kine_compaction_stalled.py`
- `scripts/tests/observability/test_cve_fix_available_alert.py`
- `scripts/tests/plugins/grafana_dashboard_pr_checks.bats`
- `scripts/tests/plugins/e2e_observability.bats`
- `scripts/tests/plugins/grafana_dashboard_appsets.bats`
- `CHANGELOG.md` (one `### Fixed` bullet)
- Added 2026-11-14 by Claude after review: `scripts/tests/bin/machine_setup_acceptance.bats` (its complete-host fixture needs a promtool), `scripts/tests/bin/test_promtool_helper.py` (Python resolver contract), `scripts/tests/lib/promtool_helper.bats` (new, bash resolver contract); `.github/workflows/ci.yml` also covers the `alertmanager-behaviour` job, which runs the two `observability/` files.

Acceptance items M1, N1, N3 and E1 were proven by Part A upstream (lib-foundation #83); E2 is Claude's live check.
The worker proves M2 (machine-setup half; CI half is E5 on the PR), M3, M4, N2, E3 and E4.

## Contract readers

| Reader | Changes? |
|---|---|
| `.github/workflows/ci.yml:91-110` (installs promtool, adds `$HOME/.local/bin` to `GITHUB_PATH`) | Yes: calls the lib function; must keep adding the dir to PATH. |
| The ten test files in the Symptom table | Yes: use the resolver. |
| `scripts/tests/lib/fast_gate.bats:43` (stubs promtool) | No: its own stub wins. |
| `bin/k3dm-machine-setup` | Yes: new step. |
| `PROMTOOL` env var, read today by `test_vectordb_bug_metrics.py:351` | Kept, now read by the shared resolver. |

## Sequencing

C1 also edits `scripts/tests/plugins/e2e_observability.bats`, so Part B waits until C1 lands (one open dispatch per
file). Part A (lib-foundation) has no overlap and can go first.

## Acceptance

```yaml
must:
  - id: M1
    text: _install_promtool installs promtool 3.1.0 into PROMTOOL_INSTALL_DIR on darwin-arm64, darwin-amd64,
      linux-amd64 and linux-arm64 after verifying the pinned sha256, without sudo.
  - id: M2
    text: k3dm-machine-setup runs _install_promtool for the control, console and hub roles, and CI installs promtool
      through the same function.
  - id: M3
    text: with promtool installed, every case in the ten files runs its real promtool evaluation under make test,
      make test-bin and make test-python, with zero docker calls.
  - id: M4
    text: without promtool, each such case fails with a message naming make machine-setup.
must_not:
  - id: N1
    text: _install_promtool must not install, or leave behind, a binary whose sha256 does not match the pin, and must
      not download for a version or platform without one.
  - id: N2
    text: no case passes or skips when promtool is absent (no silent skip, no vacuous guard).
  - id: N3
    text: _install_promtool writes nothing outside PROMTOOL_INSTALL_DIR and its own temp directory, and never calls
      sudo.
evidence:
  - id: E1
    proves: M1, N1, N3
    kind: offline
    intent: The installer, fed a fake download, installs promtool when the checksum matches, refuses and leaves
      nothing when it doesn't, refuses unknown versions, and touches only its target and temp folders.
  - id: E2
    proves: M1
    kind: live
    intent: Claude runs the real installer on the M4 into a scratch folder and shows promtool 3.1.0 working; the
      control-node VM run happens with the plan's E3.
  - id: E3
    proves: M3
    kind: offline
    intent: With promtool installed, the four red cases go green and the six files that used to skip now run their
      real PromQL checks.
  - id: E4
    proves: M4, N2
    kind: offline
    intent: With promtool hidden, every affected case fails with the setup message. Before the fix, several of them
      pass by skipping, which is the red result.
  - id: E5
    proves: M2
    kind: offline
    intent: CI's lint job is green on the PR with promtool installed by the shared function.
interface:
  - _install_promtool (lib-foundation scripts/lib/system.sh), PROMTOOL_VERSION, PROMTOOL_INSTALL_DIR
  - bin/k3dm-machine-setup
  - scripts/tests/promtool_helper.py (resolve_promtool), scripts/tests/promtool.bash (k3dm_promtool), PROMTOOL
  - make test, make test-bin, make test-python
```

## Worker definition of done

- Part A: lib-foundation BATS for E1 pass. Paste each command, rc and the proving line. No real network download in
  the tests.
- Part B: E3 and E4 run and pass. E4's red run against the pre-fix files is shown.
- No `docker` in any changed test file. `git grep -n "entrypoint=promtool" scripts/tests` is empty.
- The worker does not run the real download (E2) or machine setup on a real host. Those are Claude's.

## Landed 2026-11-14

- Part B landed as `6f7187ab` (Claude), pushed, `offline_tested` marked. `--test` (7 pytest files, 6 bats suites, real promtool 3.1.0): 0 failures. The fast gate was skipped with `K3DM_SKIP_FAST_GATE=1` after two refusals, both outside the fix:
  1. m4-air had no promtool. Claude installed the pinned 3.1.0 into `~/.local/bin` with `_install_promtool` under `/bin/bash` 3.2 (sha256 verified), which also exercises lib-foundation v0.5.6.
  2. N3 misparsed land's run directory, which contains this slug (`docs/bugs/2026-11-14-machine-setup-acceptance-n3-misparses-install-in-path.md`). Fixed in `42fe44fa`.
- The pre-push fast gate then failed on `test_kine_compaction_stalled.py::test_notification_reaches_platform_warning_only`: the suite reuses the notify suite's Alertmanager fixture via `__wrapped__` but not its autouse `require_docker` skip, so under the tripwire (`docker` blocked, 97) it errored. Pre-existing; Part B only made the file touched. Fixed in `0a9e053c` (skip on `notify.docker_reason()`): under the tripwire 1 passed, 1 skipped; with real Docker 2 passed.
- Remaining live: E2 (real download) on the M5 and M2 via `make machine-setup`, and CI green on the pushed head.
