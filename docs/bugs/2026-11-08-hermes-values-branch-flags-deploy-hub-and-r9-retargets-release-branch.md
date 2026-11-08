# Bug: Hermes flags apps on `deploy/hub` as stale, and its repair r9 would re-target them to the release branch

**Status:** OPEN — filed 2026-11-08
**Priority:** P2
**Waiting on:** fix running — since 2026-11-08
**Introduced by:** `897cfe72` (v1.43.15, hub deploy ref: ApplicationSets pin `deploy/hub`)
**Should have been caught by:** spec
**Severity:** high — one Approve click puts unpromoted release-branch code on the hub, and r9 is marked not reversible;
workaround: Deny every r9 card
**Approval:** operator, 2026-11-08 ("approved the intent")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** operator, Slack `k3dm-notices`, 2026-11-08 09:51 PST (screenshot: "values_branch: 20 apps (21 source
refs) not on k3d-manager-v1.43.15: blackbox-exporter@deploy/hub, hub-grafana-dashboards@deploy/hub,
hub-loki@deploy/hub (+17 more) (2026-11-08T17:51:02Z)"; pending repair `r9-d9add2e2`). Denied on Claude's advice.
**Affected:** `scripts/lib/hermes/sensors.py`, `scripts/lib/hermes/repairs.py`, `scripts/plugins/argocd.sh`
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/plans/v1.43.15-hub-deploy-ref-and-live-write-guard.md` (the change that moved the expected ref; it
does not mention Hermes); `docs/bugs/2026-10-08-hermes-values-branch-counts-sources-as-apps.md` (FIXED, same sensor)

## Symptom

Hermes raised a `values_branch` incident for 20 hub Applications whose k3d-manager sources target `deploy/hub`, and
proposed r9, "Reapply ApplicationSets on the release branch". `deploy/hub` is the correct ref since the hub deploy ref
plan landed. The incident is noise; the repair is harmful.

## Root cause

The 2026-07-24 rule (apps track the release branch) is still encoded in three places:
- `_values_branch_expected` (`sensors.py:114-127`) takes the expected ref from `K3DM_RELEASE_BRANCH` or the checkout's
  `git rev-parse --abbrev-ref HEAD`, so on the hub it expects `k3d-manager-v1.43.15`.
- r9 (`repairs.py:171-182, 247-250`) requires a `k3d-manager-vX.Y.Z` expected ref and runs
  `deploy_argocd_applicationsets --confirm` with `K3D_MANAGER_BRANCH=<that branch>`. That overrides the
  `deploy/hub` default (`scripts/plugins/argocd.sh:1289`), so approving it re-targets every Application to the
  release branch and bypasses `make hub-promote`.
- `argocd_check_values_branch` (`argocd.sh:2055-2063`, called by `bin/cluster-status:290`) falls back to the
  checkout's branch the same way.

Proof of the deployed behaviour: the live Hermes record above (hub, 2026-11-08T17:51Z) shows ArgoCD reporting
`deploy/hub` as the source revision of 20 Applications after the operator's promotes.

## Fix

1. `sensors.py`: the expected ref is the `expected` argument, else `deploy/hub`. Remove the `K3DM_RELEASE_BRANCH` and
   `git rev-parse` lookups (no other reader in the repo), the "not a release branch" skip, and `RELEASE_BRANCH`
   (`sensors.py:20`, no other importer). `values_branch` keeps its signature: `run` stays as an unused positional, so
   `bin/k3dm-hermes:209` and the existing monkeypatches stay valid. `data["expected"]` stays set (now `deploy/hub`);
   r9 reads it. The `expected` argument is a test hook only: r9's precondition rejects any other value.
   `bin/k3dm-hermes:593` and `scripts/lib/hermes/e2e_bugs.py:11` have their own release-branch regexes for other
   purposes; leave them.
2. `repairs.py` r9: the precondition requires expected == `deploy/hub` and a stale reference; the command sets
   `K3D_MANAGER_BRANCH=deploy/hub`. Name, exactly: `Reapply ApplicationSets pinned to deploy/hub`; blast radius:
   `every k3d-manager-sourced Application on the hub and app cluster re-targets deploy/hub and syncs`. `reversible`
   stays `False` on purpose. Update the R9 row of `docs/guides/hermes.md:69` to the same name.
3. `argocd.sh` `argocd_check_values_branch`: default expected ref `${K3D_MANAGER_BRANCH:-deploy/hub}`, not the
   checkout's branch; remove the `rev-parse` and its `|| echo main` fallback (`argocd.sh:2062-2064`). An exported
   `K3D_MANAGER_BRANCH` still overrides it, as in `deploy_argocd_applicationsets`; that is accepted. The fix hint at
   `argocd.sh:2104` and the WARN text at `bin/cluster-status:294` stay as they are: both read right once the expected
   ref is `deploy/hub`.
4. Tests. In `scripts/tests/hermes/test_hermes.py`: delete the two non-release skip tests (`:214`, `:233`) and the
   `K3DM_RELEASE_BRANCH` assertions in `:250`; convert the other `values_branch` tests (`:148-247`) to the
   `deploy/hub` default. In `scripts/tests/hermes/test_repairs.py:145` the r9 command expects
   `K3D_MANAGER_BRANCH=deploy/hub`. In `scripts/tests/plugins/argocd_values_branch_drift.bats` add no-argument cases
   with `K3D_MANAGER_BRANCH` unset and a stub `git` on PATH that records calls.

## Files

- `scripts/lib/hermes/sensors.py`
- `scripts/lib/hermes/repairs.py`
- `scripts/plugins/argocd.sh`
- `docs/guides/hermes.md` (R9 row only)
- `scripts/tests/hermes/test_hermes.py`
- `scripts/tests/hermes/test_repairs.py`
- `scripts/tests/plugins/argocd_values_branch_drift.bats`
- `scripts/tests/bin/cluster_status_values_branch.bats` (only if a change above breaks it; its WARN text is unchanged)

## Do not

- Change `deploy_argocd_applicationsets`, `make hub-promote` or the ApplicationSet manifests.
- Add a way for Hermes to target any ref other than `deploy/hub`.

## Acceptance

```yaml
must:
  - id: M1
    text: "the values_branch sensor reports healthy when every k3d-manager source targets deploy/hub, with the checkout on a release branch"
  - id: M2
    text: "the values_branch sensor reports degraded and names the Application when one k3d-manager source targets k3d-manager-v1.43.15 (paired control for M1)"
  - id: M3
    text: "in the M2 state, Hermes proposes r9 named 'Reapply ApplicationSets pinned to deploy/hub', and its command carries K3D_MANAGER_BRANCH=deploy/hub"
  - id: M4
    text: "argocd_check_values_branch with no argument and K3D_MANAGER_BRANCH unset expects deploy/hub: no drift for sources on deploy/hub, drift for a source on the release branch"
must_not:
  - id: N1
    text: "r9 is proposed when every source targets deploy/hub, or any r9 command carries a ref other than deploy/hub (paired with M3)"
  - id: N2
    text: "the sensor or argocd_check_values_branch takes its expected ref from the checkout's git branch (a stub git or run hook reporting k3d-manager-v1.43.15 must not change the result, and records zero calls)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    intent: "tests feed the Hermes check and the make-status check a set of apps all on deploy/hub and a set with one app on the release branch, with git reporting the release branch; the first is healthy with no repair offered, the second is flagged and the only repair offered pins deploy/hub"
  - id: E2
    proves: [M1]
    kind: live
    intent: "after the hub runs the fixed code, the next Hermes run reports values_branch healthy with every k3d-manager source on deploy/hub, and no r9 card appears in Slack"
interface:
  - "scripts/lib/hermes/sensors.py values_branch(run, argocd_run, state, token=..., expected=None)"
  - "scripts/lib/hermes/repairs.py repairs.propose(records, state) and the r9 entry's precondition and build_command keys"
  - "./scripts/k3d-manager argocd_check_values_branch '' <context>"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## Notes

- Intents approved by the operator on 2026-11-08 ("approved the intent"). The operator pressed Deny on `r9-d9add2e2` the same day.
- Until the fix lands: Deny every r9 card. Approving one undoes the promote gate for all hub apps.
- No overlap with open dispatches (abandon P3: `bin/k3dm-codex-dispatch`; Gemini-ask: `agent.py`, `status.py`,
  `bin/k3dm-webhook`; control-node role: provision-homebrew). WIP is 3/3, so it waits for a slot.
- A P2 introduced in the open release: it blocks the v1.43.15 release PR.
- First-pass trial dispatch (`docs/howto/dispatch-first-pass-trial.md`): DoD added 2026-11-08; spec review by a second agent runs after the intent approval, so an intent it changes goes back to the operator.
- Spec review (Sonnet, 2026-11-08): no blockers; 6 should-fix and 2 nits, all applied: the existing tests to delete
  or convert, `test_repairs.py` and the real bats suite, the guide's R9 row, `run` kept as an unused positional,
  `RELEASE_BRANCH` removed, the `expected` argument as a test hook, the exact r9 name, and a zero-calls control on N2.
  The E1 and E2 intents are unchanged, so the operator's approval stands.
