# Bug: Hermes' "Hub code behind" check compares the hub checkout with the newest release branch, not `deploy/hub`

**Status:** OPEN
**Priority:** P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (Only a non-alerting Grafana dashboard tile is misleading after `deploy/hub` auto-sync, with `make hub-promote-status` and `make hub-sync` available as a workaround); Claude proposed P3. Agreed.
**Triage:** carry → v1.44.0 (deploy/hub batch) — grooming 2026-11-12, operator.
**Waiting on:** dispatch — since 2026-11-12
**Introduced by:** `897cfe72` (v1.43.15 hub deploy-ref change: the hub reads `deploy/hub`); shows once `checkout-auto-sync` is installed on the hub
**Should have been caught by:** spec (the deploy-ref plan's Contract readers did not list `bin/k3dm-hermes:624-733`)
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run (vector store context missing on the M4, 2026-11-10). Related: `docs/bugs/2026-11-06-hub-code-lag-invisible-and-no-catch-up-step.md` (added this check, before deploy/hub existed); `docs/bugs/2026-11-07-hub-code-behind-tile-unknown-matcher-crashes-bugs-dashboard.md` (tile rendering, different root cause)
**Severity:** a misleading dashboard tile, no alert reads it. Once the hub's checkout follows `origin/deploy/hub`
(`checkout-auto-sync` A1), the tile counts commits on the release branch that are not promoted yet and says the hub is
"behind", and on a newer release it says "older release". Neither is a fault: the hub waits for `make hub-promote` by
design. Workaround: read `make hub-promote-status`, and the promote backlog that `make hub-sync` prints.
**Approval:** Claude, 2026-11-10 (found while landing `checkout-auto-sync`; reader of a contract the operator set on 2026-11-07)
**Intent approved:** operator, 2026-11-10 ("approve P3 intents")
**Filed:** 2026-11-10
**Detected by:** Claude, contract-reader search while landing `checkout-auto-sync`, 2026-11-10
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, 2026-11-10)

- `bin/k3dm-hermes:553-561` `_index_ref()`: the reference is the checkout's `@{upstream}` (today
  `origin/k3d-manager-v1.43.15` on m5-air, read over SSH 2026-11-10), unless `K3DM_INDEX_REF` is set.
- `:697-705`: when a newer `k3d-manager-vX.Y.Z` branch exists, it switches the compared ref to it.
- `:624-640` `_push_checkout_lag`: pushes `k3dm_hub_checkout_code_commits_behind{branch}` (`HEAD..<that ref>`, code
  paths only) and `k3dm_hub_checkout_on_newest_release{newest_branch}`.
- Readers: only the "Hub code behind" stat, `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml:385-392`
  (`git grep`, 2026-11-10). No PrometheusRule reads either metric.
- `checkout-auto-sync` A1 fast-forwards the hub checkout to `origin/deploy/hub` without switching branches, so its
  upstream stays the release branch and the count above becomes "commits not promoted yet".

## Fix

Compare the hub checkout with `origin/deploy/hub`: the lag count becomes `HEAD..origin/deploy/hub` on code paths (what
the checkout has not pulled of what is promoted). Drop the newest-release switch from the lag metric and push no
`k3dm_hub_checkout_on_newest_release` (the promote backlog belongs to `make hub-promote-status`). Update the tile's
description and value mapping to match. The document index keeps its own ref logic: change only the lag metric.

## Contract readers

- `k3dm_hub_checkout_code_commits_behind`, `k3dm_hub_checkout_on_newest_release`: writer `bin/k3dm-hermes:624-640`;
  reader the tile at `grafana-dashboard-bugs.yaml:385-392`, which changes with the fix. Nothing else reads them.
- The `branch` label changes from a release branch name to `deploy/hub`.
- Hermes' document index ref (`state["index_ref"]`): unchanged.

## Acceptance

```yaml
must:
  - id: M1
    text: "On the hub, the lag count is the number of code commits in origin/deploy/hub that the checkout's HEAD does not have."
  - id: M2
    text: "Commits on the release branch that are not promoted do not raise the lag count."
must_not:
  - id: N1
    text: "The tile never tells the operator to run make hub-sync BRANCH=."
  - id: N2
    text: "The document index ref does not change."
evidence:
  - {id: E1, proves: [M1, M2], kind: offline, intent: "You will see a test with a scratch origin where the release branch is 3 code commits ahead of deploy/hub and the checkout equals deploy/hub: the count is 0; then deploy/hub moves 2 commits ahead and the count is 2. Against today's code the first case reports 3."}
  - {id: E2, proves: [N1, N2], kind: offline, intent: "You will see the dashboard test find no BRANCH= text in the tile, and a test showing the index ref is the same before and after."}
  - {id: E3, proves: [M1], kind: live, intent: "After the hub checkout follows deploy/hub, Claude shows the tile reading 0 while the release branch has unpromoted commits."}
interface:
  - "bin/k3dm-hermes index refresh (_refresh_index, _push_checkout_lag)"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml panel 19"
```

## Worker definition of done

- Change only `bin/k3dm-hermes`, its tests, and panel 19 of the bugs dashboard (after `checkout-auto-sync` lands, which
  edits the same panel's description). Show E1's first case red against today's code, then green. Paste command, rc
  and proving lines. Leave changes uncommitted; Claude reviews and lands.
