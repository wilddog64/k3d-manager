# Bug: a failed e2e run leaks its vCluster and wedges every later run (silently, for hours)

**Date:** 2026-09-23
**Branch:** `k3d-manager-v1.37.0`
**Status:** OPEN — unassigned
**Affects:** `scripts/plugins/e2e.sh`, `scripts/plugins/vcluster.sh`, `bin/k3dm-hermes`
**Substrate:** m2jump remote runner (`k3d-e2e-runner`), `vclusters` namespace

---

## Symptom

Every Tier 1 dispatch fails within ~15 seconds:

```
fatal  there is already a virtual cluster in namespace vclusters;
       creating multiple virtual clusters inside the same namespace is not supported
ERROR: failed to execute .../vcluster create e2e-1790162027-6638 -n vclusters ...
INFO: [e2e] Summary written to ~/.k3dm/e2e/1790162027-6638.json (exit_code=1)
```

The published result is `result=fail, phase=deploying-substrate` — indistinguishable in Grafana
from a genuine substrate failure.

## Root cause

Two facts combine:

1. **`vcluster create` is not idempotent per namespace.** vCluster 0.32.1 refuses a second
   virtual cluster in a namespace that already has one. `scripts/plugins/vcluster.sh:4` pins
   `VCLUSTER_NAMESPACE="${VCLUSTER_NAMESPACE:-vclusters}"` — one shared namespace — while every
   run gets a unique name (`e2e-<epoch>-<pid>`). So the namespace, not the name, is the
   contended resource.

2. **A run that fails at `deploying-substrate` does not delete its vCluster.** Run
   `1790154235-20` failed at 2026-09-23T09:04:49Z and wrote a terminal summary
   (`exit_code: 1`), but `e2e-1790154235-20` was still `Running` 131 minutes later. The
   teardown path exists (`vcluster.sh:67-76`, with a `helm uninstall` fallback) but is not
   reached on this failure path.

The leak is therefore **permanently self-sustaining**: the first failure that skips teardown
blocks every subsequent run forever, and each blocked run fails too early to clean up.

## Why nobody noticed for two hours

`bin/k3dm-hermes:283` dispatches `e2e_runner_dispatch m2` on a 300s launchd interval
(`com.k3d-manager.hermes.plist` → `StartInterval 300`). Between 03:19 and 04:14 local,
Hermes burned **~17 consecutive dispatches**, all failing identically. Confirmed by
`~/.k3dm/e2e/dispatch/` — one `m2-*.log` triple every ~6–7 minutes.

None of it surfaced:

- **No bug doc was filed.** `docs/bugs/` has no entry dated 2026-09-23 from Hermes, and
  `git status docs/bugs` is clean.
- **No escalation.** Each run is individually "a failing e2e run", which is an expected
  state Hermes already reports; 17 identical consecutive failures is not a state it
  recognises as distinct.
- **`e2e_runner_health` reports `available`.** It checks the lock and the runner cluster,
  not whether the `vclusters` namespace is occupied — so the one command an operator would
  run to triage this says everything is fine.

## Fix options

1. **Preferred — make create self-healing.** Before `vcluster create`, reconcile the
   namespace: if it holds a vCluster whose run is not the current one, delete it. This
   fixes the wedge permanently rather than requiring a clean shutdown every time.
2. **Namespace per run.** `VCLUSTER_NAMESPACE="vcluster-${run_id}"` removes the shared
   contended resource entirely. Larger change: teardown, kubeconfig paths and the hub
   registration cleanup (`vcluster.sh:95-111`) all assume one namespace.
3. **Guarantee teardown on the failure path.** Necessary but **not sufficient on its own** —
   it cannot recover from a wedge that already exists (a SIGKILL'd or panicked run still
   leaks), which is exactly the state observed here.
4. **Make the wedge visible.** Add an occupied-namespace check to `e2e_runner_health` so it
   reports `severity=degraded` instead of `ok`, and teach Hermes to escalate N consecutive
   failures at the same phase as one event rather than N independent ones.

Options 1 and 4 are independent and both worth doing: 1 stops the wedge, 4 stops the silence.

## Reproduction

Confirmed live, not inferred. After clearing the first orphan, run `1790162339-22194` was
dispatched, brought its vCluster up healthy, then failed at `deploying-substrate` on an
unrelated blocker (the runner's GHCR credential — see Gap 3 of
`docs/bugs/2026-08-22-e2e-m2-runner-bootstrap-kubeconfig-and-ghcr-gaps.md`). One minute after
the run exited non-zero:

```
NAME                                     READY   STATUS    AGE
e2e-1790162339-22194-55ff7bc787-nlwsl    1/1     Running   91s
```

**The vCluster leaked again.** So the wedge re-forms on the very next failure — any fix that
only cleans up existing orphans is a one-shot workaround, and fix option 3 (teardown on the
failure path) is required, not optional.

Synthetic reproduction:

```bash
# on the runner, leave a vcluster behind
vcluster create e2e-manual -n vclusters --connect=false
# from the M4
make e2e-remote RUNNER=m2   # fails in ~15s at deploying-substrate
```

## Immediate remediation applied (2026-09-23, operator-approved)

```bash
launchctl bootout gui/$(id -u)/com.k3d-manager.hermes      # stop the 5-min retry loop
ssh m2jump 'vcluster delete e2e-1790154235-20 -n vclusters --wait'
```

`vcluster delete` removed the `vclusters` namespace along with the vCluster; the next
`create` recreated it cleanly (`Creating namespace vclusters`), so namespace removal is not
a problem for the create path.

**Hermes must be reloaded** once Tier 1 work is finished:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.k3d-manager.hermes.plist
```

## Notes

- The ~17 failed runs published `result=fail` to Grafana. Any Tier 1 pass-rate read across
  2026-09-23 03:00–04:20 local is measuring this wedge, not the shopping cart.
- Unrelated but observed in the same Hermes log and already known: the ArgoCD sensor reports
  `credential rejected; re-mint k3dm-hermes-argocd-token`, and `frontend.3ai-talk.org` is
  still failing reachability.
