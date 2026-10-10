# Bug: `make appsets-reapply` switches the hub and Hostinger in one step

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0` (spec); implement after
`2026-10-09-appsets-reapply-confirms-before-controller-regenerates.md`, which edits the same function
**Status:** OPEN — spec ready for Codex
**Priority:** P2 — blast radius on the persistent clusters; no incident yet, but the istio-cni one
came in through this path
**Severity:** medium

## Symptom

`make appsets-reapply` applies all 13 ApplicationSets in one pass. The ones that target app-clusters
(Hostinger) re-render at the same moment as the hub's own. A config regression in a release branch
reaches the hub and Hostinger together, and the only check afterwards is the values-branch pin. That
check does not look at health.

The 6-day istio-cni stall (`2026-10-09-hostinger-istio-cni-generic-dirs-after-hub-rebuild-and-no-alert.md`)
entered through an ApplicationSet apply, not through code. The pre-merge vCluster and ACG tiers test
code, so they could not have caught it.

## Cause

`deploy_argocd_applicationsets` (`scripts/plugins/argocd.sh`) loops over every file in
`scripts/etc/argocd/applicationsets/` in glob order. It has no notion of which clusters a set can
reach, and no gate between them.

## Fix

Roll out in two stages, gated on the hub. This is not new environments.

1. Label every ApplicationSet manifest with
   `metadata.labels["k3dm.k3d.io/rollout-stage"]: hub | app-cluster`. The rule is that a set whose
   Applications can land on any cluster other than the hub is `app-cluster`.

   | Stage | Sets |
   |---|---|
   | hub | `demo-rollout`, `grafana-dashboards-hub`, `observability`, `platform-ops`, `vectordb` |
   | app-cluster | `data-git`, `eso`, `services-git`, `istio-ambient`, `observability-acg`, `hostinger-cve-inventory-reader`, `platform-helm` (unrestricted cluster generator), `grafana-dashboards-acg` (app-cluster selector) |

   Codex confirms each assignment from the generator and destination before labelling, and stops to
   report any set that does not fit the rule.
2. `deploy_argocd_applicationsets` applies the `hub` stage first. It then runs the confirmation for
   the hub Applications only: the values-branch pin, plus none `Degraded`, using the bounded wait from
   the confirm-wait bug. Only if that passes does it apply the `app-cluster` stage and confirm again.
   - If the hub stage fails, it stops: `[argocd] hub stage failed — app-cluster ApplicationSets NOT applied`.
     It returns 1.
   - A set with no label, or an unknown stage, aborts **before anything is applied**.
3. `APPSETS_STAGE=hub` (Makefile var → `K3DM_APPSETS_STAGE`) stops after the hub stage, so the
   operator can soak before running again with `APPSETS_STAGE=all` (the default).

## Tests

- New `scripts/tests/plugins/argocd_appset_rollout_stage.bats`:
  - every file in `applicationsets/` has a valid stage label (a coverage test, so a new set cannot
    skip it);
  - with `kubectl` stubbed, hub sets apply before any app-cluster set;
  - a failing hub confirmation means no app-cluster apply;
  - `K3DM_APPSETS_STAGE=hub` applies only hub sets;
  - an unlabelled fixture set aborts with zero applies.
- Mutation check: drop the stage gate. The "no app-cluster apply" test must go red.

## Docs

- `docs/howto/makefile.md`: the `appsets-reapply` row and `APPSETS_STAGE`.
- `CLAUDE.md` "Reapply the ApplicationSets on every release" rule: add a mention of the
  two stages. Claude makes that edit itself when verifying; it is not Codex's job.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/applicationsets/*.yaml` | `k3dm.k3d.io/rollout-stage` label on every set |
| `scripts/plugins/argocd.sh` | staged apply + per-stage confirmation in `deploy_argocd_applicationsets` / `_argocd_deploy_applicationsets` |
| `Makefile` | `APPSETS_STAGE` → `K3DM_APPSETS_STAGE` on `appsets-reapply` |
| `scripts/tests/plugins/argocd_appset_rollout_stage.bats` | new |
| `scripts/tests/plugins/argocd_appset_reapply_confirm_wait.bats` | adjust only if the staged flow changes how the confirmation is called |
| `docs/howto/makefile.md` | `appsets-reapply` row |

`CLAUDE.md` is not in this table: Claude edits it after verification.

## Rules

- `scripts/plugins/argocd.sh` must stay under the agent audit's if-count limit of 8 per function.
  Put the stage logic in new helpers, not inside an existing function.
- `shellcheck scripts/plugins/argocd.sh`: no new warnings.
- `bats scripts/tests/plugins/argocd_appset_rollout_stage.bats scripts/tests/plugins/argocd_appset_reapply_confirm_wait.bats scripts/tests/plugins/argocd.bats`: all green. Paste the output.
- Do not commit. `.git` is read-only in the sandbox.

