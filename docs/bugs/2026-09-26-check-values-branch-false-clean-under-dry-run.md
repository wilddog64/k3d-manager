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
