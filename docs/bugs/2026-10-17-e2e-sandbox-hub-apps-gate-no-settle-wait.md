# e2e-sandbox hub-apps gate fails on a single poll while an Application is still converging

**Status:** REOPENED (recurrence, 2026-10-17) — the retry path is live-proven, but the 180s default is shorter than one ArgoCD reconcile; fix F3–F5 below, dispatched to Codex. The first fix `45412d26` stays.
**Priority:** P2
**Severity:** Medium — a `make e2e-sandbox` run started right after `make up` fails before Playwright; rerunning a few minutes later passes
**Found by:** Claude, live run `1792200825-26862` (2026-10-17), branch `k3d-manager-v1.43.4`
**Approval:** explicit 2026-10-17 "can you write a spec for hub-apps check and dispatch to codex?" (operator)
**Related:** `docs/bugs/2026-10-17-e2e-sandbox-hub-apps-gate-trips-on-own-namespace-apply.md`
(fixed the self-inflicted drift; its Recurrence section names this bounded wait as the remaining fix)

## Symptom

```
ERROR: [e2e] hub Applications for ubuntu-k3s are not all Synced and Healthy: ubuntu-k3s-data-layer OutOfSync Healthy;
```

The run started right after `make up` finished. A read a few minutes later showed `ubuntu-k3s-data-layer`
`Synced`: the last operation had `Succeeded` and no resources were out of sync.

## Cause

`_e2e_sandbox_hub_apps_ready` (`scripts/plugins/e2e.sh:173`) reads the Applications once and fails on
any non-`Synced`/`Healthy` row. ArgoCD keeps reconciling for a few minutes after `make up`, so one poll
can't tell a transient state from a persistent one.

## Fix

**F1.** In `scripts/plugins/e2e.sh`, replace the body of `_e2e_sandbox_hub_apps_ready`. An empty
listing still fails at once, because the sandbox isn't registered and waiting won't change that.
Otherwise it re-polls until every row is `Synced Healthy` or the deadline passes, and fails with the
last poll's rows.

Old:
```bash
function _e2e_sandbox_hub_apps_ready() {
  local ns="${E2E_HUB_ARGOCD_NAMESPACE:-cicd}" listing bad
  listing="$(_e2e_hub_kc -n "$ns" get applications.argoproj.io \
    -o 'jsonpath={range .items[?(@.spec.destination.name=="ubuntu-k3s")]}{.metadata.name}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}{end}')"
  if [[ -z "$listing" ]]; then
    _err "[e2e] hub Applications: none target ubuntu-k3s in ${ns}; cluster-up registers the sandbox with the hub — rerun make up with the k3s-aws provider"
    return 1
  fi
  bad="$(awk '$2 != "Synced" || $3 != "Healthy"' <<< "$listing")"
  if [[ -n "$bad" ]]; then
    _err "[e2e] hub Applications for ubuntu-k3s are not all Synced and Healthy: $(tr '\n' ';' <<< "$bad")"
    return 1
  fi
  _info "[e2e] hub Applications for ubuntu-k3s: $(wc -l <<< "$listing" | tr -d ' ') Synced and Healthy"
}
```

New:
```bash
function _e2e_sandbox_hub_apps_ready() {
  local ns="${E2E_HUB_ARGOCD_NAMESPACE:-cicd}" listing bad
  local timeout="${E2E_HUB_APPS_TIMEOUT:-180}" interval="${E2E_HUB_APPS_INTERVAL:-10}" deadline
  deadline=$(( SECONDS + timeout ))
  while :; do
    listing="$(_e2e_hub_kc -n "$ns" get applications.argoproj.io \
      -o 'jsonpath={range .items[?(@.spec.destination.name=="ubuntu-k3s")]}{.metadata.name}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}{end}')"
    if [[ -z "$listing" ]]; then
      _err "[e2e] hub Applications: none target ubuntu-k3s in ${ns}; cluster-up registers the sandbox with the hub — rerun make up with the k3s-aws provider"
      return 1
    fi
    bad="$(awk '$2 != "Synced" || $3 != "Healthy"' <<< "$listing")"
    [[ -z "$bad" ]] && break
    if (( SECONDS >= deadline )); then
      _err "[e2e] hub Applications for ubuntu-k3s are not all Synced and Healthy after ${timeout}s: $(tr '\n' ';' <<< "$bad")"
      return 1
    fi
    _info "[e2e] hub Applications for ubuntu-k3s still converging: $(tr '\n' ';' <<< "$bad") — rechecking in ${interval}s"
    sleep "$interval"
  done
  _info "[e2e] hub Applications for ubuntu-k3s: $(wc -l <<< "$listing" | tr -d ' ') Synced and Healthy"
}
```

**F2.** In `scripts/tests/plugins/e2e.bats`, keep the existing test "hub Applications require Synced
and Healthy" passing. Set `E2E_HUB_APPS_TIMEOUT=0` in it, because its unhealthy cases must still fail
at once. Add three tests. Each sets `E2E_HUB_APPS_INTERVAL=0` and stubs `sleep() { :; }` so nothing
really waits:

1. **Converges.** `_e2e_hub_kc` returns `app OutOfSync Healthy` on its first two calls and
   `app Synced Healthy` on the third. Count the calls in a file under `$BATS_TEST_TMPDIR`. Expect
   status 0, exactly 3 calls, and the "still converging" line in the output.
2. **Persists.** It always returns `app OutOfSync Healthy`, with `E2E_HUB_APPS_TIMEOUT=0`. Expect
   status ≠ 0 and output containing `after 0s` and `app OutOfSync Healthy`.
3. **Empty fails without waiting.** It returns an empty listing with `E2E_HUB_APPS_TIMEOUT=180`.
   Expect status ≠ 0, exactly 1 call, and output containing `none target ubuntu-k3s`.

**Mutation checks** (run on a temporary copy, not the tree; report each as caught):
- removing the `break` → test 1 fails, because it never returns 0;
- moving the empty-listing check below the deadline check → test 3 fails, because the call count
  is greater than 1 or the message is wrong.

## Files

- `scripts/plugins/e2e.sh`
- `scripts/tests/plugins/e2e.bats`

## Rules

- `shellcheck -S warning scripts/plugins/e2e.sh` is clean.
- `bats scripts/tests/plugins/e2e.bats` is fully green; paste the summary line.
- Use bash's `SECONDS`, no `date` calls. Use plain `sleep` in the plugin, as other plugins do. Tests
  must stub it.

## Definition of Done

- [ ] F1 and F2 applied exactly; shellcheck and BATS green (paste the output).
- [ ] Mutation checks reported.
- [ ] Commit message: `fix(e2e): re-poll hub Applications before failing the sandbox gate`.
- [ ] Report the SHA.

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT modify files outside `## Files`. That includes `memory-bank/` and this doc: Claude
  updates them after landing.
- Do NOT run `make e2e-sandbox`, `make up`, or any command against a live cluster.
- Do NOT change the gate's position in `e2e_verify_sandbox`, or the error text of the empty-listing
  case.

## Live proof

`make e2e-sandbox` started straight after `make up` passes `checking-hub-apps`, possibly after one or
more "still converging" lines, and the log shows the gate's final `Synced and Healthy` line.

## Landed (2026-10-17)

`45412d26` on `k3d-manager-v1.43.4`, via `bin/k3dm-codex-dispatch` (task `hub-apps-settle-wait`).
Claude checked it independently:
- **Diff:** matches F1/F2 exactly, and only the two `## Files` paths changed.
- **Gates:** `shellcheck -S warning` is clean and `bats scripts/tests/plugins/e2e.bats` passes 77/77.
- **Mutations, on temporary copies:**
  - removing the `break` makes the converge test hang, killed at 60s;
  - moving the empty-listing check below the deadline check fails "empty hub Applications fail
    without waiting".

Live proof is still pending (see above).

**First live run (2026-10-17, run `1792204737-19253`, commit `56b7add7`).** The gate passed on its
first poll ("15 Synced and Healthy"), so the new code causes no regression on a settled hub. The
retry path was not exercised, because nothing was converging. Live proof of the retry still waits
for a run started straight after `make up`. The run was 3/4; the one failure is the deferred Stripe
402 (`docs/bugs/2026-10-17-stripe-placeholder-key-sticks-in-vault.md`).

## Recurrence — 180s is shorter than an ArgoCD reconcile (2026-10-17)

**Approval:** explicit 2026-10-17 "go for those" (operator), on Claude's write-up of this run.

**Live run `1792235425-21547`** (commit `5ab6b236`) was started straight after `make up`. It exercised the
retry path for the first time. Every converging Application but one settled within the window
(`acg-kube-prometheus-stack`, `istio-base-ubuntu-k3s`, `ubuntu-k3s-data-layer`, and the frontend and payment
apps), and the gate logged each "still converging" line as specified. The retry path is therefore
**live-proven**. But the run still failed:

```
ERROR: [e2e] hub Applications for ubuntu-k3s are not all Synced and Healthy after 180s: acg-trivy-operator OutOfSync Healthy;
```

`acg-trivy-operator`'s four `ClusterComplianceReport`s (`k8s-cis-1.23`, `k8s-nsa-1.0`,
`k8s-pss-baseline-0.1`, `k8s-pss-restricted-0.1`) stayed OutOfSync after the sync operation had
`Succeeded` at 11:12:36Z. Their live spec matched the hub's own `trivy-operator`, which is `Synced`. The app
went `Synced` on its own at 11:18:28Z, with nobody touching it — about six minutes after the sync, at the next
reconcile. The rerun (`1792235987-31168`) then passed the gate on its first poll.

**Cause.** The gate's window equals ArgoCD's default reconcile period (`timeout.reconciliation`, 180s, plus
jitter). A diff that only clears at the next reconcile can outlast a 180s window that starts while the sync is still running. The window must cover at least two
reconcile periods. Why these four reports need a second reconcile is not established (one guess: they are
diffed before the CRD the same sync installs is cached). F3 works either way.

### Fix

**F3.** In `scripts/plugins/e2e.sh`, `_e2e_sandbox_hub_apps_ready`, raise the default from 180s to 420s
(two reconcile periods plus a minute of jitter).

Old:
```bash
  local timeout="${E2E_HUB_APPS_TIMEOUT:-180}" interval="${E2E_HUB_APPS_INTERVAL:-10}" deadline
```

New:
```bash
  local timeout="${E2E_HUB_APPS_TIMEOUT:-420}" interval="${E2E_HUB_APPS_INTERVAL:-10}" deadline
```

**F4.** In `scripts/tests/plugins/e2e.bats`, add this test directly after "empty hub Applications fail without
waiting". It pins the default without waiting: the `sleep` stub advances bash's `SECONDS` instead of sleeping.

```bash
@test "hub Applications default window outlasts two ArgoCD reconciles" {
  local calls="$BATS_TEST_TMPDIR/hub-apps-default-calls"
  : > "$calls"
  _e2e_hub_kc() {
    printf '%s\n' call >> "$calls"
    printf '%s\n' "app OutOfSync Healthy"
  }
  sleep() { SECONDS=$(( SECONDS + $1 )); }
  unset E2E_HUB_APPS_TIMEOUT E2E_HUB_APPS_INTERVAL
  run _e2e_sandbox_hub_apps_ready
  [ "$status" -ne 0 ]
  [[ "$output" == *"after 420s"* ]]
  [[ "$output" == *"rechecking in 10s"* ]]
  [ "$(wc -l < "$calls")" -ge 40 ]
}
```

**Mutation checks** (on a temporary copy, not the tree; report each as caught):
- reverting the default to `180` → the new test fails (`after 180s`, about 19 calls);
- changing the interval default from `10` to `0` → the new test fails (`rechecking in 0s`).

**F5.** In `docs/guides/vcluster-e2e-harness.md`, Tier 2 intro paragraph, document the gate's knobs.

Old:
```markdown
Tier 2 checks the hub's `ubuntu-k3s` Applications, sets
```

New:
```markdown
Tier 2 waits for the hub's `ubuntu-k3s` Applications to be `Synced Healthy` (re-polling every
`E2E_HUB_APPS_INTERVAL`, default 10s, for up to `E2E_HUB_APPS_TIMEOUT`, default 420s — two ArgoCD
reconciles, since a fresh sandbox can need a second one), sets
```

### Files

- `scripts/plugins/e2e.sh`
- `scripts/tests/plugins/e2e.bats`
- `docs/guides/vcluster-e2e-harness.md`

### Rules, Definition of Done, What NOT to Do

As for F1/F2 above (with the third file added to `## Files`), except:
- Commit message: `fix(e2e): give the hub Applications gate two ArgoCD reconciles by default`.
- The new test must finish in under 5 seconds; paste its timing from `bats --timing`.

### Live proof

A `make e2e-sandbox` started straight after `make up` passes `checking-hub-apps` even when an Application
needs a second reconcile.

### Landed — F3–F5 (2026-10-17)

`2de544dc` on `k3d-manager-v1.43.4`, via `bin/k3dm-codex-dispatch` (task `hub-apps-timeout-two-reconciles`).
Claude checked it independently: the diff matches F3–F5 exactly (three files); `shellcheck -S warning` is
clean; `bats scripts/tests/plugins/e2e.bats` passes 78/78; the new test runs in about 0.3s. Mutations, on a
temporary copy: a default of `180` fails `after 420s`; an interval default of `0` fails `rechecking in 10s`
(after spinning the real 420s, since the stub then never advances `SECONDS`). Live proof still pending.

**First live run with 420s (2026-10-17, run `1792239012-26194`, commit `6b4ca6b1`).** On a settled hub the
gate passed on its first poll ("15 Synced and Healthy"): no regression. The longer window itself waits for
a run started straight after a fresh `make up`.
