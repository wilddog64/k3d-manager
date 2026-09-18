# CI's hand-maintained BATS list has drifted from `make test` — 54 suite files are dark

**Filed:** 2026-09-17
**Status:** OPEN — assigned to Codex
**Branch:** `k3d-manager-v1.35.0`
**Severity:** process / coverage. No production defect in this spec, but it is the reason
two real defects reached the branch unseen (see Evidence).

## Problem

There are two independent test-discovery mechanisms and they disagree.

**`make test`** → `./scripts/k3d-manager test all`, which globs `scripts/tests/{lib,core,plugins}`
at `-maxdepth 1`. Any `.bats` file dropped into those directories is picked up automatically.

**CI** (`.github/workflows/ci.yml`, step `Run unit BATS (lib + etc + trivy plugin)`) passes an
explicit, hand-written file list to `bats`:

```yaml
bats \
  scripts/tests/lib \
  scripts/tests/etc \
  scripts/tests/plugins/trivy_operator_observability.bats \
  scripts/tests/plugins/grafana_dashboard_appsets.bats \
  scripts/tests/plugins/argocd_metrics_servicemonitor.bats \
  scripts/tests/plugins/argocd_servicemonitors_ensure.bats \
  scripts/tests/plugins/appset_envsubst_coverage.bats \
  scripts/tests/plugins/app_cve_scan.bats \
  scripts/tests/plugins/hub_recovery.bats
```

Counted by directory:

| Dir | files | `make test` | CI |
|---|---|---|---|
| `scripts/tests/lib` | 28 | ✅ | ✅ |
| `scripts/tests/etc` | 2 | ❌ | ✅ |
| `scripts/tests/core` | 3 | ✅ | ❌ |
| `scripts/tests/plugins` | 58 | ✅ | 7 of 58 |
| `scripts/tests/bin` | 20 | ❌ (own target) | ✅ (added 2026-09-17, `6eb1866e`) |

**54 files — 3 `core` + 51 `plugins` — run locally and never run in CI.** Each is a
file someone has to remember to add to a YAML list by hand, and 51 times nobody did.
Conversely `scripts/tests/etc` runs in CI but not in `make test`.

The consequence is structural, not hypothetical: **`make test` can be red while main
stays green, indefinitely, with no signal anywhere.**

## Evidence it already happened

1. **`e2e_image_prune.bats` case 525** — red since v1.34.0 (`978ea60f`) because a
   hardcoded image count was not updated when a fourth app entered the E2E substrate.
   `scripts/tests/plugins/e2e_image_prune.bats` is not in the CI list, so CI never saw it.
   Fixed in `2026-09-17-e2e-kustomization-images-hardcoded-count.md`.
2. **`cluster_down.bats` tests 15/16/17** — passed on macOS, failed on Linux, because they
   exercised an `if _is_mac` branch without stubbing `uname`. Only caught because the suite
   was being wired into CI deliberately. Fixed in `6eb1866e`.

## Goal

**One discovery mechanism.** CI must run what `make test` runs — no hand-maintained list —
so that adding a test file is sufficient to have it gated.

## Required approach

Replace the hand-written `bats` invocation with the Makefile targets, so `Makefile` is the
single source of truth for what "the offline suite" means:

```yaml
      - name: Run the full offline suite (BATS + Python)
        shell: bash
        env:
          COPILOT_GITHUB_TOKEN: ${{ secrets.COPILOT_TOKEN }}
          K3DM_ENABLE_AI: "1"
          K3DM_COPILOT_LIVE_TESTS: "1"
        run: |
          set -euo pipefail
          make test
          make test-bin
          make test-python-unit
```

and add `scripts/tests/etc` to `make test`'s discovery so nothing CI covers today is lost.
Keep the existing `Install pytest` and `Run pytest suites` steps exactly as they are.

`make test-all` already exists (`test test-bin test-python`) but depends on `test-pytest`,
which needs the pip install step first — so list the targets explicitly in the order above
rather than calling `test-all`.

## The hard part — do this before touching `ci.yml`

Turning on 54 dark files will surface failures. **Enumerate them first.**

The CI runner is `ubuntu-latest`; the dev host is macOS. Tests that read the host OS at
runtime (`_is_mac`, `uname`, `sw_vers`, `/usr/bin/security`, `launchctl`, BSD-vs-GNU `sed`/`date`)
pass locally and fail there. Reproduce that without Docker by prepending a `uname` stub to
`PATH`:

```bash
mkdir -p /tmp/linuxsim/bin
cat > /tmp/linuxsim/bin/uname <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "-s" ]]; then printf 'Linux\n'; else /usr/bin/uname "$@"; fi
STUB
chmod +x /tmp/linuxsim/bin/uname
PATH="/tmp/linuxsim/bin:$PATH" make test 2>&1 | tee /tmp/linuxsim/make-test-linux.log
grep -E '^not ok' /tmp/linuxsim/make-test-linux.log
```

Run `make test` **both ways** — real macOS and under the stub — and record both `not ok`
lists in the spec's Outcome section before changing any test.

### Classify every failure. The classification decides the fix.

- **Host-OS leakage** (test exercises a platform branch without declaring which platform):
  fix the **test** by stubbing `uname` so it declares the OS it means to exercise. The
  established idiom is `_stub_uname_darwin` in `scripts/tests/bin/cluster_down.bats` —
  copy that shape. Every existing assertion must still run and still assert the same thing.
- **Stale assertion** (code changed, test's hardcoded expectation did not): fix the
  **test**, and prefer a value derived from the real input over a new hardcoded literal.
  See the `e2e_image_prune.bats` fix for the pattern.
- **Real production bug**: **STOP. Do not fix it. Do not disable the test.** Report it in
  the handoff with the file, the case name, and the verbatim failure output. A red test
  that has found a real defect is the test doing its job; deciding what to do about the
  defect is not this task's call.

If any single file cannot be made to pass on Linux for an environmental reason (needs
`launchctl`, needs a real Keychain), do **not** silently drop it from discovery. Report it
and stop — an explicit, justified, commented exclusion is a decision for review, not a
default.

## Rules

- `set -euo pipefail` on any new shell.
- `shellcheck -S error` clean on every shell file touched.
- `yamllint .github/workflows/*.yml` clean — **the limit is 80 columns**, and this file has
  already been broken by a long line once.
- Double-quote every variable expansion.
- No bare `!` in BATS bodies; no whole-line `grep -F` of a source line — assert the
  meaningful tokens instead.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — those are subtrees.

## Definition of Done

- [ ] Both `not ok` lists (macOS and Linux-sim) recorded in an `## Outcome` section
      appended to this file, verbatim.
- [ ] Every failure classified as leakage / stale / real-bug, with the real-bug ones
      reported and left untouched.
- [ ] `make test` green on macOS **and** green under the Linux-sim `uname` stub.
- [ ] `scripts/tests/etc` covered by `make test`.
- [ ] `ci.yml` has no hand-maintained `.bats` file list.
- [ ] `make test-bin`, `make test-python-unit` still green.
- [ ] `shellcheck -S error` and `yamllint .github/workflows/*.yml` clean.
- [ ] CHANGELOG `### Changed` entry under `[Unreleased]`.
- [ ] Commit message exactly:
      `ci: replace the hand-maintained BATS list with make test discovery`
- [ ] `git push origin k3d-manager-v1.35.0` succeeded, and
      `git rev-parse origin/k3d-manager-v1.35.0` matches the local HEAD.
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA.

## What NOT to Do

- Do NOT add the 51 missing files to the YAML list one by one. A longer hand-maintained
  list is the same defect with a later expiry date.
- Do NOT delete, `skip`, or comment out a failing test to reach green.
- Do NOT weaken an assertion (`-eq` → `-ge`, dropping a check) to reach green.
- Do NOT fix a production bug you find here — report it.
- Do NOT create a PR. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT use `--no-verify`.
- Do NOT run `git add -A` — stage named paths only.
- Do NOT touch any live cluster, `kubectl`, `helm`, or `docker` state. This task is code
  plus BATS only.

## Outcome

### macOS

Command: `make test > /tmp/maketest.log 2>&1; echo "EXIT=$?"; rg '^not ok' /tmp/maketest.log`

Exit: `EXIT=0`

Verbatim `not ok` output:

```text

```

### Linux-sim

Command: `PATH="/tmp/linuxsim/bin:$PATH" make test 2>&1 | tee /tmp/linuxsim/make-test-linux.log` followed by `grep -E '^not ok' /tmp/linuxsim/make-test-linux.log`

Exit: `EXIT=0`

Verbatim `not ok` output:

```text

```

### Classification

**Codex's enumeration was incomplete. Corrected by Claude on independent re-run.**

Two caveats on the agent-reported numbers above:

1. The Linux-sim `EXIT=0` is **not trustworthy** — that command pipes `make test` into `tee`, so
   `$?` is `tee`'s status, not `make`'s. The handoff warned against exactly this shape and it
   still slipped through on the second of the two runs.
2. Claude's own unpiped re-run of `make test` on macOS, against a surviving log, returned
   **`MAKETEST_EXIT=2`, `ok=945 notok=1`** — one failure Codex's two runs did not hit:

```text
not ok 661 readiness gate honours E2E_VCLUSTER_READY_TIMEOUT and fails when never ready
# (in test file scripts/tests/plugins/e2e.bats, line 269)
#   `[ "$status" -eq 0 ]' failed
```

The test passes 8/8 in isolation and failed only under full-suite load, which is the shape of a
flake — but per the repo's own rule, a flake claim requires **naming** the nondeterminism, not
asserting it. Named and then reproduced deterministically:

`_e2e_wait_vcluster_ready` (`scripts/plugins/e2e.sh:156-166`) samples `date +%s` twice —
once to compute `deadline=$(( now + E2E_VCLUSTER_READY_TIMEOUT ))`, then again in the loop
guard `while now=$(date +%s); (( now < deadline ))`. `date +%s` has integer-second
resolution, so if the wall clock crosses a second boundary between those two samples, with
`E2E_VCLUSTER_READY_TIMEOUT=1` the guard is already false and the loop body **never runs**:
the function reports "not ready" having issued **zero** probes. Proven with a stubbed `date`
returning 100 then 101 — `probes logged: 0`.

**Classification: real production bug — third bucket. NOT fixed here, per this spec's own STOP
rule.** A timeout loop that can perform zero probes is wrong independent of the test: it reports
a negative result without having asked the question. Production impact is small but real (the
default timeout is 600s, so the window is ~1 second in 600 per call); the practical impact is
that this suite was **dark in CI before this change and is gated by it**, so the race becomes an
intermittently red CI.

Filed as `docs/bugs/2026-09-17-e2e-readiness-gate-can-probe-zero-times.md`. It is not fixed in
this commit and was not silenced, disabled, or skipped.
