# dev-hub: every synced pod is forbidden — PriorityClass `preemptionPolicy: Never` conflicts with the pod spec vCluster copies

**Status:** LIVE-VERIFIED — 3e0ee4ac live on m5-air (2026-11-13)
**Priority:** P1 (Claude proposal: no pod inside the dev hub can run, so CoreDNS, Argo CD and Grafana never start; blocks dev-hub plan E2 in the open v1.44.0 release)
**Classified:** pending (Argon, from this doc alone)
**Introduced by:** b2067ad3 (dev-hub Part A, `scripts/etc/dev-hub/priorityclass.yaml`)
**Should have been caught by:** live check (host admission is invisible to offline tests; the first live run stopped earlier, at the coredns schema bug)
**Fix commit:** `3e0ee4ac`
**Prior art:** exact-slug glob, no match; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing); related, different root cause: docs/bugs/2026-11-13-dev-hub-up-fails-vcluster-rejects-top-level-coredns.md
**Approval:** operator, 2026-11-13: "go ahead to have the proposed fix"
**Dispatch go:** operator, 2026-11-13: "go ahead to have the proposed fix"
**Intent approved:** operator, 2026-11-13

## Symptom

On m5-air, 2026-11-13 ~11:00 PST, vCluster 0.32.1, after the coredns fix (8c2bfc5f) let `make dev-hub-up` create the vCluster: inside the vCluster `pod/coredns-7c7ccd6944-m85br` stays Pending, there is no host copy in namespace `dev-hub`, and `make dev-hub-up` hangs at "Release "argocd" does not exist. Installing it now." The event on the virtual pod (read-only capture by the operator):

    Warning  SyncError  pod-syncer  Error syncing to host cluster: create object: pods "coredns-7c7ccd6944-m85br-x-kube-system-x-dev-hub" is forbidden: the string value of PreemptionPolicy (PreemptLowerPriority) must not be provided in pod spec; priority admission controller computed Never from the given PriorityClass name

Quota is not the cause: `dev-hub-budget` shows 1/30 pods, 256Mi/1Gi requests.memory.

## Root cause

`values-dev-hub.yaml` sets `sync.toHost.pods.priorityClassName: k3dm-dev-preemptible`. The syncer swaps the class name but keeps `spec.preemptionPolicy`, which the virtual API server already filled in (`PreemptLowerPriority`, from the virtual pod's own class). The host's Priority admission plugin works out `Never` from `k3dm-dev-preemptible` and rejects any pod whose spec already carries a different value. The control-plane pod `dev-hub-0` gets past this because the host StatefulSet creates it with no preemptionPolicy set, so admission fills it in. Every pod the syncer copies hits the error.

## Proposed fix (approved 2026-11-13)

Remove `preemptionPolicy: Never` from `scripts/etc/dev-hub/priorityclass.yaml`, so the default `PreemptLowerPriority` applies and matches what synced pods carry. At `value: -100` the class can preempt only pods below -100, and the hub has none, so dev-hub pods still give way to hub workloads, which is what the plan wants. Two things must be proved before dispatch, under the prove-external-behaviour rule:
- `preemptionPolicy` on a PriorityClass is likely immutable (upstream `ValidatePriorityClassUpdate`). If so, `dev_hub_up`'s `kubectl apply` fails on the live hub until the old class is deleted. The fix then needs a delete-and-recreate step, or a new class name.
- vCluster 0.32.1 has no setting that drops or rewrites the copied preemptionPolicy (check upstream source at the tag). If one exists, it is the smaller change.

## Proof of external behaviour

Captured by Claude on m4-air, 2026-11-13, with `gh api` against upstream source:
- Kubernetes v1.35.0 `pkg/apis/scheduling/validation/validation.go:63-64` (`ValidatePriorityClassUpdate`): "preemptionPolicy is immutable", via `ValidateImmutableField`. Taking the field out of the manifest makes the API server default it to `PreemptLowerPriority`, which counts as a change from `Never`, so `kubectl apply` on the live hub is refused. The class must be deleted and recreated once.
- vCluster v0.32.1 `pkg/controllers/resources/pods/translate/translator.go:220-225`: when `sync.toHost.pods.priorityClassName` is set and the host pod has no class name, the syncer sets `PriorityClassName` and resets `Priority` to nil. It never touches `PreemptionPolicy`, so the virtual pod's value is copied as is. No setting changes this. `pkg/controllers/resources/priorityclasses/translate.go` deals only with syncing the class objects, which `values-dev-hub.yaml` leaves disabled.
- The live symptom above, captured on m5-air on 2026-11-13, is the read-only capture of the host admission error.

## Fix

1. `scripts/etc/dev-hub/priorityclass.yaml`: delete the `preemptionPolicy: Never` line. Nothing else changes (`value: -100`, `globalDefault: false`, the name and the description all stay).
2. `scripts/plugins/dev_hub.sh` `_dev_hub_apply_host_objects`: before the `apply -f priorityclass.yaml`, read the live `{.preemptionPolicy}` of `k3dm-dev-preemptible` on the host context with a soft, quiet read. If the class exists and its policy is anything but `PreemptLowerPriority`, run `_dev_hub_host_kubectl delete priorityclass k3dm-dev-preemptible`, then apply as today. If the class is absent or already `PreemptLowerPriority`, do not delete. The delete only blocks new pods that name the class for a moment, and the apply right after recreates it. Running pods are not touched.

Recovering the live hub after promote: `make dev-hub-down` then `make dev-hub-up`. The half-built hub from the 11:00 run has no replicated Prometheus Service, so the idempotent path prints that same repair advice.

## Acceptance

```yaml
must:
  - id: M1
    text: priorityclass.yaml has no preemptionPolicy key; name k3dm-dev-preemptible, value -100 and globalDefault false are unchanged
  - id: M2
    text: when the live class reports preemptionPolicy Never, dev_hub_up runs delete priorityclass k3dm-dev-preemptible on the host context before apply -f priorityclass.yaml (order asserted in the call log)
must_not:
  - id: N1
    text: priorityclass.yaml sets preemptionPolicy to any value other than PreemptLowerPriority (red on pre-fix)
  - id: N2
    text: dev_hub_up deletes the class when it is absent or already PreemptLowerPriority (paired with M2 as the positive control)
  - id: N3
    text: any host-context call outside namespace dev-hub other than apply -f priorityclass.yaml, get priorityclass k3dm-dev-preemptible, and delete priorityclass k3dm-dev-preemptible
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    intent: The dev hub's priority class no longer stops vCluster from copying pods to the host, and dev-hub-up swaps out an old class that still says Never exactly once, leaving a correct class alone.
    command: bats scripts/tests/plugins/dev_hub.bats (new M1/N1 and M2 tests red on c8099c47)
  - id: E2
    proves: [M1, M2]
    kind: live
    intent: After a promote, make dev-hub-down then make dev-hub-up on the M5 recreates the class as PreemptLowerPriority, and the CoreDNS pod runs in host namespace dev-hub with a 128Mi memory limit, which also closes the coredns bug's live check.
interface: scripts/etc/dev-hub/priorityclass.yaml; scripts/plugins/dev_hub.sh _dev_hub_apply_host_objects
```

## Contract readers

The PriorityClass name does not change; only its preemption policy does.
- `scripts/etc/vcluster/values-dev-hub.yaml:4` (`controlPlane.statefulSet.scheduling.priorityClassName`) and `:35` (`sync.toHost.pods.priorityClassName`): name only; unchanged.
- `scripts/tests/plugins/dev_hub.bats:246` (apply call), `:427-435` (N1 host-scope allow-list: extended by N3 here to the exact get/delete calls), `:538`, `:567` (values fixtures): name only.
- `docs/plans/v1.44.0-dev-hub-vcluster.md:166-167`: describes `preemptionPolicy: Never`; Claude corrects it after landing.
- writers: `scripts/plugins/dev_hub.sh:129` (`_dev_hub_apply_host_objects`) only.

## Files

- `scripts/etc/dev-hub/priorityclass.yaml`
- `scripts/plugins/dev_hub.sh`
- `scripts/tests/plugins/dev_hub.bats`

## Definition of done (worker)

- Edit text only. Delete exactly one line from `priorityclass.yaml`. In `dev_hub.sh` touch only `_dev_hub_apply_host_objects`. Go through `_run_command` (soft/quiet for the read, `_dev_hub_host_kubectl` for the delete), quote every expansion, and add no inline comments.
- In `dev_hub.bats`, extend the kubectl stub so `get priorityclass k3dm-dev-preemptible` prints `${LIVE_PREEMPTION_POLICY}` and exits 0 when it is set, and exits 1 when it is unset (absent class). Add tests: M1/N1 (parse or grep the manifest by key, with a positive control that the file still has `value: -100`); M2 (`LIVE_PREEMPTION_POLICY=Never`: delete line present and earlier in `CALL_LOG` than the apply line); N2 (unset and `PreemptLowerPriority`: no `delete priorityclass` line, and the apply is still present). Extend the N1 host-scope test's allow-list to the two exact calls and nothing broader. Do not remove or weaken any other test or assert.
- Run, then paste each command, its exit code and the summary line: `bats scripts/tests/plugins/dev_hub.bats` (0 not ok); `shellcheck scripts/plugins/dev_hub.sh`. Then put back `priorityclass.yaml` and `dev_hub.sh` from `git show HEAD:<path>` (keep your test edits), confirm the new M1/N1 and M2 tests are not ok, and restore your fix.
- Do not commit; leave changes in the worktree.

## Review log (Fable side-by-side, 2026-11-13)

- Medium, accepted as pre-existing: under `DRY_RUN=1` the `system_overrides.sh` wrapper prints a preview line to stdout. The policy read captures that line, so the dry run would preview a delete. Nothing is deleted, because the delete is only previewed too. It can't be reached today: `_dev_hub_require_host_context` captures `current-context` the same way and fails first, so a real dev-hub dry run was already broken. The bats stub ignores `DRY_RUN`. Captured as docs/bugs/2026-11-13-dev-hub-dry-run-captures-preview-lines-as-values.md (P3).
- Low, accepted for the same P3: M2 doesn't check that the delete goes to the host context; `[ a ] && [ b ]` at bats :275 fails only because of the line after it; a failed read (timeout or RBAC) counts as "class absent", which is fail-safe but gives a raw immutable-field error.
- Claude's own review overlapped on the code path; the dry-run wrapper behaviour came only from Fable.

## Landed (2026-11-13)

`3e0ee4ac` (Luna, 1 run, no corrections). E1 offline PASS outside the sandbox: `bats scripts/tests/plugins/dev_hub.bats` 58/58, shellcheck clean. On the pre-fix files the new M1/N1 and M2 tests fail and N2 stays green, as expected. Mark offline_tested recorded. E2 live: after promote, the operator runs `make dev-hub-down` then `make dev-hub-up` on the M5.

## Live verification (2026-11-13)

m5-air, operator, after `make hub-promote REF=5c253d1b`, `git pull --ff-only`, `make dev-hub-down`, `make dev-hub-up` (which reached the Grafana `--wait` install): `kubectl --context k3d-k3d-cluster get priorityclass k3dm-dev-preemptible -o jsonpath='{.preemptionPolicy}'` gave `PreemptLowerPriority`. Host namespace `dev-hub` lists 8 pods. Seven were copied from the vCluster (Argo CD x5, Grafana, and `coredns-7c7ccd6944-xfgqv-x-kube-system-x-dev-hub` at a `128Mi` memory limit), plus `dev-hub-0` at 768Mi. Mark live_verified recorded at 3e0ee4ac. Errors seen: none.

**Live evidence:** 2026-11-13 · run operator-m5-dev-hub-up · env hub · scenario synced-pods-admitted-preemptlowerpriority · commit 5c253d1b · proves E2
