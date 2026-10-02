# Bug: a substrate rollout failure tears down the vCluster with no pod state saved

**Status:** FIXED (pending)
**Branch:** `k3d-manager-v1.40.0`
**File:** `scripts/plugins/e2e.sh`
**Tests:** `scripts/tests/plugins/e2e.bats`

## Symptom

`make e2e` run `1790959569-5392` (2026-10-02) failed with:

```
error: timed out waiting for the condition
ERROR: e2e: kubectl -n shopping-cart-apps rollout status deployment/product-catalog --timeout=300s failed
```

`product-catalog` is the first **private GHCR image** in the rollout order (postgres, redis and
rabbitmq are public and came up). The cause could be `ImagePullBackOff`, a crash loop, or a
failing probe, and nothing can tell them apart: the EXIT trap writes a summary with
`failure_details: []` and deletes the vCluster. The pods, their events and their logs are gone
before anyone can look, and a rerun costs another ~10 minutes just to get to the same point.

## Fix

### 1 — new function, placed directly above `function _e2e_exit_trap()`

```bash
function _e2e_dump_substrate_diagnostics() {
  local name="${1:-}" run_id="${2:-unknown}"
  [[ -z "$name" ]] && return 0
  local kubeconfig out deploy
  kubeconfig="$(_vcluster_kubeconfig_path "$name")"
  out="${_E2E_REPORT_DIR:-$E2E_REPORT_DIR}/${run_id}.substrate.txt"
  (
    umask 077
    {
      echo "### pods"
      KUBECONFIG="$kubeconfig" _run_command --no-exit -- kubectl -n "$E2E_NAMESPACE" \
        --request-timeout=10s get pods -o wide
      echo "### warning events"
      KUBECONFIG="$kubeconfig" _run_command --no-exit -- kubectl -n "$E2E_NAMESPACE" \
        --request-timeout=10s get events --field-selector type=Warning --sort-by=.lastTimestamp
      for deploy in postgres redis rabbitmq product-catalog basket order keycloak payment; do
        echo "### logs deployment/${deploy}"
        KUBECONFIG="$kubeconfig" _run_command --no-exit -- kubectl -n "$E2E_NAMESPACE" \
          --request-timeout=10s logs "deployment/${deploy}" --all-containers --tail=40
      done
    } > "$out" 2>&1
  )
  _warn "[e2e] substrate deploy failed; pods, warning events and logs saved to ${out}"
  awk '/^### warning events/{p=1;next} /^### /{p=0} p' "$out" | tail -n 15 >&2 || true
}
```

### 2 — `_e2e_exit_trap`: dump before teardown, only for substrate failures

Old:
```bash
  _e2e_teardown "${_E2E_ACTIVE_NAME:-}" || true
  [[ -n "$publish_run_id" ]] && { _e2e_write_result_event "$publish_run_id" || true; }
```
New:
```bash
  if (( rc != 0 )) && [[ "${_E2E_ACTIVE_PHASE:-}" == "deploying-substrate" ]]; then
    _e2e_dump_substrate_diagnostics "${_E2E_ACTIVE_NAME:-}" "${_E2E_RUN_ID:-unknown}" || true
  fi
  _e2e_teardown "${_E2E_ACTIVE_NAME:-}" || true
  [[ -n "$publish_run_id" ]] && { _e2e_write_result_event "$publish_run_id" || true; }
```

The output file goes in the report dir next to the summary JSON, which teardown keeps (it only
removes the per-run log and kubeconfig). `umask 077` because app logs are not reviewed for secrets.

## Tests (append to `scripts/tests/plugins/e2e.bats`, using its existing `_run_command` / `RUN_LOG` stubs)

1. **`substrate diagnostics capture pods, events and per-deployment logs`** — set
   `_E2E_REPORT_DIR="$BATS_TEST_TMPDIR"`, stub `_vcluster_kubeconfig_path` to echo a path, call
   `_e2e_dump_substrate_diagnostics e2e-x run-1`. Assert `$BATS_TEST_TMPDIR/run-1.substrate.txt`
   exists, its mode is `600` (`stat -f %Lp` on macOS / `stat -c %a` on Linux — accept either),
   and `$RUN_LOG` contains `get pods`, `--field-selector type=Warning`, and
   `logs deployment/product-catalog`.
2. **`substrate diagnostics no-op without a vCluster name`** — call with an empty name; assert
   status 0 and `$RUN_LOG` has no `get pods`.
3. **`exit trap dumps diagnostics before teardown`** — structural: take
   `declare -f _e2e_exit_trap`, assert the line number of `_e2e_dump_substrate_diagnostics` is
   lower than that of `_e2e_teardown`, and that the guard line contains `deploying-substrate`.

**Mutation check (must report):** delete the guarded call from the trap → test 3 red. Remove the
`--field-selector type=Warning` command → test 1 red. Restore, all green.

## Rules

- `shellcheck scripts/plugins/e2e.sh` — zero new warnings.
- `bats scripts/tests/plugins/e2e.bats` — all green; paste the summary line.
- No secret values in argv or in the new `_warn`.

## Definition of Done

- [ ] Fixes 1–2 applied exactly as written
- [ ] Tests 1–3 added and green; mutation results reported
- [ ] Commit message: `fix(e2e): save pod state, warning events and logs when the substrate fails`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report the SHA from `git rev-parse origin/k3d-manager-v1.40.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the two listed above (plus this doc's Status line)
- Do NOT commit to `main`
- Do NOT add a keep-vCluster-on-failure mode — teardown order stays as is
