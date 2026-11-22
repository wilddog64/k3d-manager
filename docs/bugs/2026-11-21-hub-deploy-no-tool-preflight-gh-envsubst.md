# hub-deploy has no tool preflight; a missing gh or envsubst surfaces late and misattributed

**Status:** OPEN — captured 2026-11-21, not triaged.
**Priority:** P3
**Introduced by:** v1.44.0 (46ec5b36, bin/k3dm-hub-deploy added)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Diagnostic hygiene gap where `bin/k3dm-hub-deploy` lacks an upfront PATH preflight check for `gh` and `envsubst`, causing misleading late errors in non-interactive shells.)
**Waiting on:** operator decision — since 2026-11-21
**Prior art:** not run (find-similar-docs: vector store unavailable, context k3d-k3d-cluster missing); exact-slug glob found none. Related, different root cause: `docs/bugs/2026-11-19-hub-deploy-runs-stale-checkout-copy-of-itself.md`.

## Symptom

`make hub-deploy REF=74ff9a6f` on m5-air, 2026-11-21, from shells without `/opt/homebrew/bin` on PATH:

1. Non-interactive ssh: `gh: not found in PATH`, `[hub-promote] ERROR: GitHub check-runs lookup failed`, stopped at `promote`.
2. Operator's ssh login shell: every hub ApplicationSet printed `env: envsubst: No such file or directory`, then
   `ERROR: [argocd] 6 of 6 hub ApplicationSet(s) did not apply`, stopped at `appsets-reapply`. It read as a cluster
   failure; the cluster was healthy (same context, nodes Ready, the same step applied 6/6 with envsubst on PATH).

No state changed in either case, but diagnosis took several round trips.

## Cause

`bin/k3dm-hub-deploy` does not check its external tools before starting. `_argocd_deploy_applicationsets`
(`scripts/plugins/argocd.sh`, the `env ... envsubst ... | _kubectl apply -f -` pipe) counts a missing `envsubst` as a
per-file apply failure, because kubectl receives empty input. `scripts/plugins/vault.sh:1063` already has the pattern
(`command -v envsubst ... || _err "... (brew install gettext)"`).

## Fix sketch

At the start of `bin/k3dm-hub-deploy`, after `require-role`: `command -v` each of `gh`, `envsubst`, `kubectl`, `git`, `jq`;
on a miss, stop with `hub-deploy: stopped at preflight: <tool> not on PATH (PATH=<value>)` before any promote. In
`_argocd_deploy_applicationsets`, check `envsubst` once before the loop and return 1 with one clear error instead of
N per-file failures. Offline test: PATH without the tool, stop at preflight, positive control with the tool present.
