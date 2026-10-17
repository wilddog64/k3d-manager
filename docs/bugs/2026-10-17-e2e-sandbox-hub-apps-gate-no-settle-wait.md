# e2e-sandbox hub-apps gate fails on a single poll while an Application is still converging

**Status:** FIXED (`45412d26`), awaiting live proof — dispatched to Codex and landed 2026-10-17
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
