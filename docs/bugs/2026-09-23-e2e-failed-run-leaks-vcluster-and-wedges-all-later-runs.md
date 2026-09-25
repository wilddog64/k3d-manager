# Bug: a failed e2e run leaks its vCluster and wedges every later run (silently, for hours)

**Date:** 2026-09-23
**Branch:** `k3d-manager-v1.37.0`
**Status:** FIXED 2026-09-23 — root cause corrected and measured (see the correction below);
Changes 1–3 implemented, unit-verified and mutation-proven. **Not yet exercised against the
live runner.** Runner verified clear of leaked vClusters at the time of writing (`vclusters`
namespace absent, no helm release, hub ArgoCD free of `cluster-e2e-*` registrations).
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

### CORRECTION 2026-09-23 — why teardown is not reached

The original text above stopped at "is not reached" without naming a mechanism. The
mechanism is now measured, and it is **not** a missing trap. `e2e.sh:101` installs
`trap '_e2e_exit_trap' EXIT` before `vcluster_create`, and that trap **did** fire — the
`Summary written … (exit_code=1)` line in the transcript below can only come from it,
because the failure at `deploying-substrate` means the inline summary call was never
reached.

From `~/.k3dm/e2e/dispatch/m2-20260923T111856Z.log` (run `1790162339-22194`):

```
ERROR: [acg-up] GHCR_PAT not set and no valid PAT in Vault — …
INFO: [e2e] Summary written to /Users/cliang/.k3dm/e2e/1790162339-22194.json (exit_code=1)
running under bash version 5.3.15(1)-release      <- next, unrelated invocation
```

Between the summary and the end of the run there is **no** `Deregistered … from hub
ArgoCD`, **no** `Deleted vCluster`, and **no** `ERROR:` line. Teardown did not fail — it
never ran, and nothing was logged to say so.

The trap body runs summary → result event → teardown. The kill is the middle step:

- `_e2e_write_result_event` ends with `if _kubectl create -f "$manifest_file" >/dev/null 2>&1`.
- `_kubectl` forwards to `_run_command` **without `--no-exit`**, and `_run_command`
  (`scripts/lib/system.sh:1795`) ends a failure with `_err`, which is `exit 1`
  (`system.sh:1731-1734`).
- `exit` inside the EXIT trap terminates the shell immediately. Being inside an `if`
  condition does not contain it, and `|| true` on the caller cannot catch it.
- `2>&1` into `/dev/null` **swallows the `ERROR:` line**, which is why the leak is silent.

On the m2 runner the hub is unreachable by construction (`error: context
"k3d-k3d-cluster" does not exist` appears earlier in the same transcript), so
`_kubectl create` fails on **every** dispatch. Teardown is therefore unreachable on the
runner for every run, pass or fail — the vCluster only survives long enough to be noticed
when the run fails, because a passing run's inline path publishes the event before the
trap.

Neither `_info "[e2e] Published result event …"` nor `_warn "[e2e] could not publish result
event …"` appears in the transcript, which confirms the call neither succeeded nor reached
its `else` — it exited.

### Why the existing test did not catch this

`scripts/tests/plugins/e2e.bats:403` is `failed job -> non-zero exit but vcluster still
torn down (teardown on failure)` — a test written for exactly this scenario, and it is
green. It cannot fail: `setup()` replaces `_run_command` with a stub
(`e2e.bats:22-37`) that logs its arguments and `return`s. The stub has no `_err` and no
`exit`, so the one behaviour that breaks production — a hard exit from inside the trap —
is unreachable under test. The assertion `grep -F "vcluster_destroy e2e-"` passes because
the publish step is harmless in the harness.

This is the "a new test passing ≠ it can fail" trap: the guard was tested against a
substitute that cannot exhibit the defect.

The leak is therefore **permanently self-sustaining**: the first failure that skips teardown
blocks every subsequent run forever, and each blocked run fails too early to clean up.

## Why nobody noticed for two hours

`bin/k3dm-hermes:283` dispatches `e2e_runner_dispatch m2` on a 300s launchd interval
(`com.k3d-manager.hermes.plist` → `StartInterval 300`). Between 03:19 and 04:14 local,
Hermes burned **~17 consecutive dispatches**, all failing identically. Confirmed by
`~/.k3dm/e2e/dispatch/` — one `m2-*.log` triple every ~6–7 minutes.

Hermes did file, but only for the first two failures:

- `docs/bugs/2026-09-23-e2e-harness-deploying-substrate.md` (run `1790154235-20`, `c9d5da06`)
- `docs/bugs/2026-09-23-e2e-harness-creating-vcluster.md` (run `1790154640-13530`, `0c405871`)

Everything after that was **silently deduped**. `scripts/lib/hermes/e2e_bugs.py:163` checks
recurrence with `bug_dir.glob(f"*-{group['slug']}.md")`; once
`…-e2e-harness-creating-vcluster.md` existed, the remaining ~15 identical failures matched it
and filed nothing. The dedup is correct — it is exactly what stops 17 duplicate docs — but it
is **write-once**: the existing doc is never updated with a recurrence count or a last-seen
timestamp, so a defect that fired 17 times is indistinguishable from one that fired once.

The two docs it did file are also weak evidence:

- Counts render as `None passed / None failed / None total` — the run died before any test,
  so the summary has nulls and the template prints them raw.
- "Sample errors" captured five `INFO: [e2e-remote]` lines, **not** the `fatal there is
  already a virtual cluster…` line that states the cause. The sample is the transcript's
  last 5 lines (`bin/k3dm-hermes:288`), and on this failure the useful line is further up.
- Failing tests reads `…and 1 more`, listing nothing.

So the triage hint — "the run did not reach Playwright; read the dispatch transcript" — is
the only accurate content, and it defers to a human.

Two further reasons the scale stayed invisible:

- **No escalation on repetition.** Each run is individually "a failing e2e run", which
  Hermes already reports; 17 identical consecutive failures is not a state it recognises as
  distinct from one.
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

5. **Make Hermes' recurrence check write-through.** `e2e_bugs.py:163` should update the
   matched doc — bump a recurrence count, record last-seen run id and timestamp — instead of
   returning early. The dedup is right; the write-once behaviour is what hid a 17× repeat.
   Separately, widen the sample capture beyond the transcript's last 5 lines so the actual
   `fatal` line is retained, and suppress `None passed / None failed / None total` when the
   run produced no counts.

Options 1 and 4 are independent and both worth doing: 1 stops the wedge, 4 stops the silence.
Option 5 is what would have made the other four unnecessary to discover by hand.

---

## Fix plan (2026-09-23, after the correction above)

Option 3 as originally written — "guarantee teardown on the failure path" — is too vague to
implement, because teardown was already guaranteed by a trap. The defect is that the trap
kills itself before reaching it. Three changes, smallest first.

### Change 1 — the publish step must not be able to hard-exit

`_e2e_write_result_event` and `_e2e_prune_result_events` are best-effort reporting. Both
already branch on failure (`_warn "… dashboards unaffected"`), so the hard exit is plainly
unintended — the `else` was written expecting a return code that `_run_command` never gives
it. Pass `--no-exit` so `_kubectl` returns instead of exiting:

```bash
if _kubectl --no-exit create -f "$manifest_file" >/dev/null 2>&1; then
```

and in `_e2e_prune_result_events`:

```bash
names="$(_kubectl --no-exit -n "$E2E_RESULT_EVENT_NAMESPACE" get configmaps \
```

This alone fixes the observed leak.

### Change 2 — teardown runs before the network step, not after

Change 1 fixes today's exit site. Change 2 makes the trap survive the next one. Reorder
`_e2e_exit_trap` so the only step that frees a shared, contended resource runs before any
step that talks to the network:

```
summary (local file write)  →  teardown (frees the namespace)  →  result event (network)
```

Teardown removes the per-run log and kubeconfig; it does not touch the summary JSON that
`_e2e_write_result_event` reads, so the reorder is safe. On the success path the inline
sequence is unchanged — the reorder applies only to the trap, which is the failure path.

### Change 3 — `vcluster_create` reconciles an occupied namespace (option 1)

Changes 1 and 2 cannot recover a wedge that already exists: a `SIGKILL`ed or panicked run
leaves a vCluster behind with no trap to run at all, and the reproduction below shows the
wedge is permanently self-sustaining once formed. Before `vcluster create`, if the namespace
holds a vCluster that is not the one being created, delete it and log loudly at `_warn` —
an orphan is always a bug, so removing one silently would hide Changes 1 and 2 regressing.

### Testing

The harness gap named above must be closed in the same commit, or these changes get the
same green-but-blind coverage the old test had:

- The `_run_command` stub in `e2e.bats:setup()` cannot exit. A test for Change 2 must use a
  stub that **does** exit on the publish call, and assert teardown still happened.
- A test asserting `--no-exit` is passed on the publish path guards Change 1 against a
  future edit dropping it.
- Mutation-check both: revert each change and confirm the new test goes red.

### Verification (2026-09-23)

- `shellcheck scripts/plugins/e2e.sh scripts/plugins/vcluster.sh` — clean.
- `e2e.bats` 49/0, `vcluster.bats` 27/0, `e2e_remote.bats` 80/0, `e2e_observability.bats`
  15/0, `e2e_image_prune.bats` 10/0 — 181 pass, 0 fail.
- Mutation proofs, each restored byte-identical afterwards (`cmp -s`):
  - Removing the `_vcluster_reconcile_namespace` call → 4 reds (21, 22, 23, 27).
  - Dropping `--no-exit` from the publish and prune calls → 2 reds (46, 47).
  - Restoring the original trap order (publish before teardown) → 1 red (48).
- The ordering test needed a second pass to become a real guard. Its first version stubbed
  `_e2e_wait_job` to fail, which fails **after** the inline summary is written — so the
  trap's publish branch never ran and the test passed under both orderings. Failing at
  `_e2e_deploy_substrate` instead reproduces the production path, where the summary is
  unwritten when the trap fires. Worth recording: the first version was green, and green
  for the wrong reason, which is the same failure mode as the original `e2e.bats:403`.

### Not in this change

Options 4 (health-check visibility, Hermes N-consecutive escalation) and 5 (write-through
recurrence, wider sample capture, `None passed/None failed` rendering) stay open. They stop
the *silence*, not the leak, and belong in their own commit.

Follow-on, noticed while tracing: `_vcluster_ensure_exists` (`vcluster.sh:264-276`) returns
success purely because a kubeconfig file is present, without confirming the vCluster exists.
Six stale kubeconfigs are currently sitting in `~/.kube/vclusters/` on the runner — residue
of the teardowns that never ran — and each one makes `vcluster_destroy` believe a long-gone
cluster is still there. Harmless today (destroy falls back to `helm uninstall` and exits
clean) but it is a lie in a load-bearing predicate.

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
