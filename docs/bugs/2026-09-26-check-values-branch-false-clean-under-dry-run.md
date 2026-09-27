# `argocd_check_values_branch` reports a false clean under `--dry-run`

**Filed:** 2026-09-26 (Claude, during the v1.38.0 release ApplicationSet reapply)
**Severity:** medium — the release step's own confirmation gate passes while the drift it
exists to detect is present.
**Status:** OPEN, unfixed. Found by measurement, not by the gate.

## Symptom

`./scripts/k3d-manager deploy_argocd_applicationsets --dry-run` ends with:

```
INFO: [argocd] Confirming values-branch pin (k3d-manager-v1.39.0)
INFO: [argocd] Expected values branch: k3d-manager-v1.39.0
INFO: [argocd] All Applications reference values branch k3d-manager-v1.39.0
```

At that moment **no** Application referenced `k3d-manager-v1.39.0`. A direct read of the hub
showed 24 k3d-manager sources pinned at `k3d-manager-v1.37.0`, six of them `ref: values`:

```
acg-kube-prometheus-stack  k3d-manager-v1.37.0
acg-trivy-operator         k3d-manager-v1.37.0
hub-loki                   k3d-manager-v1.37.0
kube-prometheus-stack      k3d-manager-v1.37.0
loki                       k3d-manager-v1.37.0
trivy-operator             k3d-manager-v1.37.0
```

The dry run did not mutate anything — the pins were still `v1.37.0` afterwards — so this is a
reporting failure, not a partial apply.

## Root cause

`_argocd_values_branch_drift` (`scripts/plugins/argocd.sh:1780`) signals three different
outcomes through the same channel and the caller can only see one of them:

- **no drift** → empty stdout, exit 0
- **unparseable input** → `except ValueError: sys.exit(3)`, empty stdout
- drift → one line per drifted Application on stdout

`argocd_check_values_branch` (`:1749`) then decides on stdout alone:

```bash
_drift="$(printf '%s' "${_apps}" | _argocd_values_branch_drift "${_expected}")"
if [[ -z "${_drift}" ]]; then
   _info "[argocd] All Applications reference values branch ${_expected}"
   return 0
fi
```

The exit status is discarded. Under `--dry-run` `_kubectl` does not execute, so `${_apps}`
holds non-JSON, `json.load` raises, python exits 3 with nothing on stdout, and an empty
`_drift` is read as "clean".

The `checked N values references` line the function prints to stderr is the tell — it is
**absent** from a dry-run transcript, because python exits before reaching it. A gate whose
own progress counter never printed cannot have checked anything.

The detector logic itself is correct: run against the real cluster JSON it flags all six.

## Fix

Separate "nothing to report" from "could not tell".

1. Capture the exit status and fail closed on anything non-zero:
   ```bash
   _drift="$(printf '%s' "${_apps}" | _argocd_values_branch_drift "${_expected}")" || {
      _warn "[argocd] Could not evaluate values-branch drift (parse or query failure)"
      return 2
   }
   ```
2. Assert the checked count is non-zero. Zero `ref: values` sources on a live hub means the
   query or the filter is wrong, not that everything is pinned correctly — the same
   vacuous-pass class as the pytest suites in
   `docs/bugs/2026-09-25-pytest-suites-unreachable-from-make.md`.
3. Skip the confirmation entirely under `--dry-run`, or state that it was skipped. Confirming
   a pin that was never applied is meaningless either way, and printing a clean result is
   worse than printing nothing.

## Secondary finding — the gate checks 6 of 24 references

The detector only inspects sources with `ref: values`. On the live hub that is 6 sources; a
further **18** k3d-manager sources carry `targetRevision: k3d-manager-v1.37.0` with no `ref`
at all (the Applications' own manifest sources — the `ubuntu-hostinger-shopping-cart-*` and
`ubuntu-k3s-shopping-cart-*` sets, `hub-platform-ops`, the dashboard sets).

Those go stale on exactly the same release boundary and for the same reason, since both are
templated from `${K3D_MANAGER_BRANCH}`. A reapply fixes all 24, but the gate only ever
confirms 6 — so a set whose manifest source drifted while its values source did not would
pass. Narrowing to `ref: values` matches the wording of the CLAUDE.md rule, which is about the
`$values` source; the exposure is wider than the wording.

## Process note

The gate was believed for one command before being checked. It was caught only because the
live pins had been measured *before* the dry run, so the "all clean" claim contradicted a
number already in hand. Establishing current state before running a release step is what made
the false clean visible at all — without the baseline, the dry run looked like a clean
no-op confirming there was nothing to do.

Related: `reference_new_test_passing_does_not_mean_it_can_fail`,
`feedback_grep_count_gates_preexisting`.

---

# Implementation spec (dispatched to Codex 2026-09-26)

**Branch:** `k3d-manager-v1.39.0` — work on this branch only, never `main`.
**Files — exactly these four, nothing else:**

- `scripts/plugins/argocd.sh`
- `scripts/tests/plugins/argocd_values_branch_drift.bats`
- `CHANGELOG.md`
- `memory-bank/activeContext.md`, `memory-bank/progress.md`

## Before You Start

1. `git pull origin k3d-manager-v1.39.0`
2. Read `memory-bank/activeContext.md` (top two sections) and this whole bug doc.
3. Read these, in full, before editing:
   - `scripts/plugins/argocd.sh` — `argocd_check_values_branch` (~line 1749),
     `_argocd_values_branch_drift` (~line 1780), and the verify call inside
     `deploy_argocd_applicationsets` (~line 1244)
   - `scripts/tests/plugins/argocd_values_branch_drift.bats` — all 5 existing tests; they must
     keep passing unchanged except where this spec says otherwise
   - `scripts/lib/system.sh:1717` — `_dry_run_active`

## M1 — make the drift detector's outcomes distinguishable

The detector currently signals three different outcomes through one channel (empty stdout), so
the caller cannot tell "no drift" from "could not tell". Give it distinct exit codes.

In `_argocd_values_branch_drift`, replace this:

```python
try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(3)
```

with this:

```python
try:
    doc = json.load(sys.stdin)
except ValueError:
    print("[argocd] values-branch input is not JSON", file=sys.stderr)
    sys.exit(3)
```

and replace this:

```python
print("[argocd] checked {} values references".format(checked), file=sys.stderr)
```

with this:

```python
print("[argocd] checked {} values references".format(checked), file=sys.stderr)
if checked == 0:
    print("[argocd] no values references found — the query or the filter is wrong", file=sys.stderr)
    sys.exit(4)
```

Exit 3 = unparseable input. Exit 4 = parsed, but zero references inspected. Exit 0 = a real
check ran (drift lines, if any, are on stdout as today).

## M2 — make the caller fail closed

In `argocd_check_values_branch`, replace this:

```bash
   _info "[argocd] Expected values branch: ${_expected}"
   _drift="$(printf '%s' "${_apps}" | _argocd_values_branch_drift "${_expected}")"

   if [[ -z "${_drift}" ]]; then
```

with this:

```bash
   _info "[argocd] Expected values branch: ${_expected}"

   local _rc=0
   _drift="$(printf '%s' "${_apps}" | _argocd_values_branch_drift "${_expected}")" || _rc=$?

   case "${_rc}" in
      0) ;;
      4)
         _warn "[argocd] Values-branch gate inspected 0 references — treating as a failure, not a clean result"
         return 2
         ;;
      *)
         _warn "[argocd] Could not evaluate values-branch drift (exit ${_rc})"
         return 2
         ;;
   esac

   if [[ -z "${_drift}" ]]; then
```

The `|| _rc=$?` form is required: a bare assignment from a failing command substitution aborts
under `set -e`, and `if ! _drift=...` would collapse exit 3 and exit 4 into one branch with one
message.

Also add `local _rc` to the existing `local` block at the top of the function if you prefer
declaring it there — either is acceptable, but `_rc` must be local.

## M3 — stop the confirmation from running under `--dry-run`

This is the defect that produced the false clean. In `deploy_argocd_applicationsets`, replace:

```bash
   if (( verify )) && declare -f argocd_check_values_branch >/dev/null 2>&1; then
      _info "[argocd] Confirming values-branch pin (${K3D_MANAGER_BRANCH})"
      argocd_check_values_branch "${K3D_MANAGER_BRANCH}"
   fi
```

with:

```bash
   if (( verify )) && declare -f argocd_check_values_branch >/dev/null 2>&1; then
      if _dry_run_active; then
         _info "[argocd] DRY_RUN: skipping the values-branch confirmation — nothing was applied, so there is nothing to confirm"
      else
         _info "[argocd] Confirming values-branch pin (${K3D_MANAGER_BRANCH})"
         argocd_check_values_branch "${K3D_MANAGER_BRANCH}"
      fi
   fi
```

## M4 — widen the gate to the manifest sources, excluding `HEAD`

The secondary finding above. In the python, replace:

```python
    for src in sources:
        if src.get("ref") != "values":
            continue
        if repo not in src.get("repoURL", ""):
            continue
        checked += 1
```

with:

```python
    for src in sources:
        if repo not in src.get("repoURL", ""):
            continue
        if src.get("targetRevision", "") == "HEAD":
            tracking_head += 1
            continue
        checked += 1
```

Initialise `tracking_head = 0` beside `checked = 0`, and change the counter line to:

```python
print("[argocd] checked {} k3d-manager references ({} tracking HEAD, ignored)".format(
    checked, tracking_head), file=sys.stderr)
```

**`HEAD` must be excluded, not reported as drift.** Two rollout-demo sources deliberately track
`HEAD`; flagging them would make the gate cry wolf on every run. They are counted and named in
the counter line so the exclusion is visible rather than silent.

This widens coverage from 6 references to 24 on the live hub. The existing test
`"chart sources are ignored, only the values ref is checked"` asserts the old counter text and
**must be updated** — chart sources are still ignored (no k3d-manager `repoURL`), so keep the
test's intent and fix its expected string and name.

## Definition of Done

- [ ] M1–M4 applied exactly as written above.
- [ ] `shellcheck scripts/plugins/argocd.sh` — zero **new** warnings versus the pre-change run.
      Capture both runs and compare; do not fix pre-existing warnings.
- [ ] All 5 existing tests in `argocd_values_branch_drift.bats` pass, with the one counter-text
      test updated per M4.
- [ ] Six new tests added to `scripts/tests/plugins/argocd_values_branch_drift.bats`:
      1. unparseable input → status 2, output matches `Could not evaluate`
      2. a valid JSON document with zero k3d-manager references → status 2, output matches
         `inspected 0 references` (this is the vacuous-pass guard)
      3. a source with no `ref` and a stale `targetRevision` → status 1 and the name appears
         (M4 coverage; fails before M4)
      4. a source with `targetRevision: HEAD` → status 0, not reported as drift
      5. the counter line reports both numbers, e.g. `checked 2 k3d-manager references (1 tracking HEAD, ignored)`
      6. `deploy_argocd_applicationsets` under `DRY_RUN=1` prints the skip message and does
         **not** print `All Applications reference` (stub `_argocd_deploy_applicationsets` to
         return 0)
- [ ] **Mutation-check every new test.** For each of the six, revert the single change it covers,
      confirm the test goes RED, restore. Report which change you reverted per test and the red
      output. A new test that passes against the unfixed source proves nothing.
- [ ] `bats scripts/tests/plugins/argocd_values_branch_drift.bats` and
      `bats scripts/tests/plugins/argocd.bats` both green — paste full output.
- [ ] `CHANGELOG.md` `## [Unreleased]` gains a `### Fixed` entry written as prose explaining the
      defect class (one channel signalling three outcomes) and why the fix is correct.
- [ ] Both memory-bank files updated with the commit SHA and status.
- [ ] Commit message verbatim:

```
fix(argocd): values-branch gate can no longer report a clean result it did not verify

_argocd_values_branch_drift signalled three outcomes through one channel: no
drift, unparseable input and zero references inspected all produced empty
stdout, and the caller decided on stdout alone while discarding the exit
status. Under --dry-run the kubectl call never executed, so the detector
exited 3 silently and the gate announced that every Application referenced the
expected branch while 24 sources sat on the previous release.

The detector now exits 3 on unparseable input and 4 on a parse that inspected
nothing, the caller fails closed with return 2 on both, and the confirmation is
skipped outright under DRY_RUN rather than run against a cluster state that was
never read.

Also widens the gate from the 6 sources carrying ref: values to all 24
k3d-manager references, which drift on the same release boundary for the same
reason. Sources deliberately tracking HEAD are excluded and counted separately
so the exclusion is visible.

See docs/bugs/2026-09-26-check-values-branch-false-clean-under-dry-run.md
```

- [ ] `git push origin k3d-manager-v1.39.0`, then report `git rev-parse origin/k3d-manager-v1.39.0`
      and `git show --stat HEAD`.

## What NOT to Do

- Do NOT create a PR, merge, or commit to `main`.
- Do NOT force-push, and do NOT use `--no-verify`.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` — they are subtrees.
- Do NOT run `kubectl`, `helm`, `docker`, `make up`, or
  `deploy_argocd_applicationsets --confirm`. **The sets were already reapplied on 2026-09-26 and
  the hub is correctly pinned; re-running it is a live mutation and is not yours to make.**
- Do NOT change `argocd_check_values_branch`'s signature, its default context
  (`k3d-k3d-cluster`) or its default namespace (`${ARGOCD_NAMESPACE:-cicd}`).
- Do NOT "fix" `_argocd_appset_live_overrides` or the istio-cni dirs — a separate open spec.
- Do NOT refactor anything this spec does not name. No tidying of neighbouring functions.
- Do NOT use a bare `!` or a whole-line `grep -F` in a BATS assertion.
- Do NOT `git add -A`. Stage each file by path.
- Do NOT `git stash`.
