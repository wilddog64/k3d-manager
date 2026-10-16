# Bug: an e2e run that fails before any test runs is invisible in the failure panels (2026-10-16)

**Status:** IMPLEMENTED — landed `c92c4311` (Codex; Claude verified: BATS 181/181, 3 new tests red on the old code, all 4 mutations red, shellcheck unchanged). Live proof blocked: the hub exporter predates the fix (see Live check)
**Priority:** P3 — the failure shows on the status tiles; only the failure-analysis panels miss it
**Branch:** `k3d-manager-v1.43.2`
**Release:** v1.43.2
**Filed:** 2026-10-16, at operator request
**Approval:** explicit 2026-10-16 "go ahead to file a P3 bug and send to codex" (operator)
**Component:** `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`, `scripts/plugins/e2e.sh`, `scripts/plugins/e2e_remote.sh`
**Related:** `docs/bugs/2026-10-15-e2e-sandbox-argocd-crd-helm-ownership-conflict.md` (the failure that exposed this),
`docs/issues/2026-09-16-live-e2e-failure-groups-empty.md` (an earlier cause of empty detail panels)

## Observed

`make e2e-sandbox` run `1792155966-29279` failed during Argo CD install, before Playwright ran.
On the **E2E Verification** dashboard:

- **Status** shows `local-m4: sandbox/product-catalog/stripe` FAIL, and **Failing runs in window** is 1.
- **Failure trend by service** shows "No data".
- **Failure causes by service** and **Top failing specs** show "No data in response".

The run's summary (`~/.k3dm/e2e/1792155966-29279.json`) has `result: fail`,
`phase: installing-argocd`, `failure_groups: []` and `failure_details: []`.

## Root cause

1. **The failure panels count only test failures.** They query `e2e_failure_group_info`, which
   the exporter emits once per entry in the event's `failure_groups`. A run that fails before any
   test runs has none, so it adds nothing.
2. **The stage is dropped on publish.** Both event writers, the local one
   (`_e2e_write_result_event` in `scripts/plugins/e2e.sh`) and the remote one (`_e2e_publish_build`
   in `scripts/plugins/e2e_remote.sh`), copy neither `phase` nor `exit_code` into `event.json`. The
   hub's ConfigMap for this run has no `phase`, so the exporter cannot say where the run stopped.

**Top failing specs** is correct to stay empty: no spec ran.

## Fix

Work only in the worktree and branch you were launched in. Read the three Component files in full
first, plus `scripts/tests/plugins/e2e.bats`, `scripts/tests/plugins/e2e_remote.bats` and
`scripts/tests/plugins/e2e_observability.bats`.

### 1. Producers: publish the phase

- `scripts/plugins/e2e.sh`, `_e2e_write_result_event`: in the `event` dict, after `"commit"`,
  add `"phase": s.get("phase") or "",`.
- `scripts/plugins/e2e_remote.sh`, `_e2e_publish_build`: `phase` is already required and
  validated by `STR_FIELDS`. In the `event` dict, after `"commit": commit,`, add
  `"phase": vals["phase"],`.

Do not change any validator, ALLOWED/REQUIRED set, ConfigMap name or label.

### 2. Exporter: count an aborted run as one failure group

In `exporter.py` inside `vulnerability-inventory-exporter.yaml`, add a top-level helper beside
`e2e_app_service`:

```python
    def e2e_failure_groups(payload, passed, service):
        groups = payload.get("failure_groups") or []
        if passed or groups or payload.get("failure_details"):
            return groups
        phase = str(payload.get("phase") or "unknown")
        return [{"kind": "aborted at " + phase, "target": phase, "service": service, "count": 1}]
```

In `refresh_e2e_events`, compute `passed` once and use the helper:

- `"passed": str(payload.get("passed", "")).lower() == "true",` uses that `passed` value;
- `"failure_groups": e2e_failure_groups(payload, passed, payload.get("service", "")),`
  replaces `payload.get("failure_groups", [])`.

Nothing else in the exporter changes. A failed run then adds one `e2e_failure_group_info` series
with `kind="aborted at <phase>"`. **Failure trend** and **Failure causes** count it, the causes
legend reads `product-catalog / aborted at installing-argocd`, and **Top failing specs** stays
empty. Events published before this fix have no `phase`, so they read `aborted at unknown`.

Do not change the dashboard, RBAC, the ConfigMap read, or any other metric.

### 3. Docs

- `docs/guides/grafana-dashboards.md`, E2E Verification notes (beside the "Aggregate-only
  events" bullet): one bullet saying that a run which fails before any test runs counts as one
  failure group, `aborted at <phase>`, and that Top failing specs stays empty for it.
- `CHANGELOG.md` `[Unreleased]`: one `Fixed:` entry.

## Files

| File | Change |
|---|---|
| `scripts/plugins/e2e.sh` | item 1 |
| `scripts/plugins/e2e_remote.sh` | item 1 |
| `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml` | item 2 |
| `scripts/tests/plugins/e2e.bats`, `scripts/tests/plugins/e2e_remote.bats`, `scripts/tests/plugins/e2e_observability.bats` | tests below |
| `docs/guides/grafana-dashboards.md`, `CHANGELOG.md` | item 3 |

No other file.

## Tests (each new one shown failing against the pre-change code, on a temp copy)

1. `e2e.bats`: a failed summary with `phase: installing-argocd` publishes an event whose
   `phase` is `installing-argocd`. Extend the existing "failed run publishes passed=false" test
   or add one beside it.
2. `e2e_remote.bats`: the event built by `_e2e_publish_build` carries the summary's `phase`.
3. `e2e_observability.bats`: a **behavioural** test, not a source grep. Load `exporter.py` from
   the YAML, use `ast` to extract only the `e2e_failure_groups` function, exec it alone, and
   assert:
   - a failed payload with no groups or details and `phase: installing-argocd` returns one group:
     kind `aborted at installing-argocd`, target `installing-argocd`, the given service, count 1;
   - with no `phase`, kind is `aborted at unknown`;
   - a passed payload returns `[]`;
   - a failed payload with existing `failure_groups` returns them unchanged;
   - a failed payload with only `failure_details` returns `[]`.
4. The existing `e2e_observability.bats` "compiles cleanly" test stays green.

### Mutations (Claude, at verification)

Each must turn a test red:

- drop `phase` from the local event;
- drop `phase` from the remote event;
- the helper ignores `failure_details` (synthesizes when only details exist);
- the helper synthesizes for a passed run.

## Operational Requirements

| Item | Requirement |
|---|---|
| Resources | At most one extra `e2e_failure_group_info` series per failed, test-less run, within the existing 200-event read cap. |
| Rollback | Revert. The exporter recomputes from ConfigMaps on every refresh, so no stored state changes. |
| Proof it works | After ArgoCD syncs `platform-ops` (exporter restart picks up the ConfigMap), Failure causes by service shows `product-catalog / aborted at unknown` for run `1792155966-29279`. The next failed sandbox run shows its real phase. |

## Definition of Done

- [ ] Items 1–3 exactly as written; `shellcheck scripts/plugins/e2e.sh scripts/plugins/e2e_remote.sh` reports no new warning.
- [ ] `bats scripts/tests/plugins/e2e.bats scripts/tests/plugins/e2e_remote.bats scripts/tests/plugins/e2e_observability.bats` green; paste the summary.
- [ ] Leave the changes **uncommitted**. Claude verifies, commits and lands them with:
  `fix(e2e): count a run that fails before its tests as an aborted failure group`

## What NOT to Do

- Do NOT contact the hub, a runner or any cluster; tests use stubs only.
- Do NOT change the E2E dashboard, the exporter's RBAC, or any other exporter metric.
- Do NOT change the remote validator's ALLOWED, REQUIRED or STR_FIELDS.
- Do NOT create a PR, commit, switch branches, or use `--no-verify`.
- Do NOT modify files outside the Files table, including `memory-bank/`.

## Live check 2026-10-16 — fix not deployed

- The hub's `platform-ops/vulnerability-inventory-exporter` ConfigMap has no `e2e_failure_groups`;
  git at `47e304f1` has it. Prometheus has no `e2e_failure_info` series for the three failed
  sandbox runs (`1792155966-29279`, `1792169623-15778`, `1792169905-3394`), which `e2e_run_info`
  does list.
- Cause: the exporter is applied by `deploy_argocd_platform_ops` (`make platform-ops`), not by
  Argo CD. `hub-platform-ops` syncs only `app-cluster-kubeconfig-externalsecret.yaml`, so
  `make appsets-reapply` never delivers exporter changes. A `rollout restart` alone does not help
  either, because the ConfigMap is still the old one.
- To prove it: operator runs `make platform-ops` (applies the manifest and restarts the exporter),
  then Claude re-queries `e2e_failure_info{run_id="1792169905-3394"}` for
  `aborted at configuring-vault`.
