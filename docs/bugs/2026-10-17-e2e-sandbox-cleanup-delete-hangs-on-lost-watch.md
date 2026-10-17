# e2e-sandbox exit cleanup hangs forever when kubectl delete loses its watch

**Status:** FIXED (`d9585858`) — live proof pending
**Priority:** P3
**Severity:** Low — the run's verdict and summary are already written; but `make e2e-sandbox` never
exits, holds the operator's pane, and blocks anything waiting for the run to end
**Found by:** Claude, run `1792236389-10503` (2026-10-17), branch `k3d-manager-v1.43.4`
**Approval:** explicit 2026-10-17 "go for those" (operator) covers filing this run's findings; the
fix needs its own go
**Related:** `scripts/plugins/e2e.sh` `_e2e_sandbox_cleanup`

## Symptom

The run wrote its summary (`exit_code=1`, 04:28) and the log's last line is

```
externalsecret.external-secrets.io "e2e-keycloak-credentials" deleted from shopping-cart-apps namespace
```

Twenty-four minutes later `make e2e-sandbox` was still running. Its only live descendant was

```
kubectl --context ubuntu-k3s -n shopping-cart-apps delete externalsecret e2e-keycloak-credentials --ignore-not-found
```

and `kubectl get` returned `NotFound` for the object. The deletion had finished; kubectl was still
waiting for it.

## Cause

`kubectl delete` defaults to `--wait=true`: after the API accepts the delete it watches until the object
is gone. If that watch stream drops without the DELETE event (here, over the sandbox API path), kubectl
waits forever, because `--timeout` defaults to 0 (unbounded). The cleanup line has neither flag:

```bash
  _run_command --soft -- kubectl --context ubuntu-k3s -n shopping-cart-apps delete externalsecret e2e-keycloak-credentials --ignore-not-found || true
```

`|| true` covers failure, not a hang.

## Fix

**F1.** In `scripts/plugins/e2e.sh`, `_e2e_sandbox_cleanup`: don't wait on the deletion. The cleanup only
needs the API to accept it.

Old:
```bash
  _run_command --soft -- kubectl --context ubuntu-k3s -n shopping-cart-apps delete externalsecret e2e-keycloak-credentials --ignore-not-found || true
```

New:
```bash
  _run_command --soft -- kubectl --context ubuntu-k3s -n shopping-cart-apps delete externalsecret e2e-keycloak-credentials --ignore-not-found --wait=false --request-timeout=30s || true
```

**F2.** In `scripts/tests/plugins/e2e.bats`, add a test that stubs `_e2e_sandbox_clear_profile` and
`_run_command` (record `$*` to a file under `$BATS_TEST_TMPDIR`), runs `_e2e_sandbox_cleanup`, and asserts
the recorded delete carries the tokens `--wait=false` and `--request-timeout=30s` (tokens, not the whole line).

**Mutation check** (temp copy): drop `--wait=false` → F2 fails.

## Files

- `scripts/plugins/e2e.sh`
- `scripts/tests/plugins/e2e.bats`

## Rules

`shellcheck -S warning scripts/plugins/e2e.sh` clean; `bats scripts/tests/plugins/e2e.bats` fully green.

## Definition of Done

- [ ] F1/F2 applied; gates green (paste output); mutation check reported.
- [ ] Commit message: `fix(e2e): don't wait on the cleanup delete's watch`.

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks. Do NOT touch files outside `## Files`.
- Do NOT run `make e2e-sandbox` or any command against a live cluster.

## Live proof

The next `make e2e-sandbox` exits within seconds of `Summary written`.

## Landed (2026-10-17)

`d9585858` on `k3d-manager-v1.43.4`, via `bin/k3dm-codex-dispatch` (task `e2e-cleanup-delete-no-wait`).
Claude checked it independently: the diff matches F1/F2 (two files); `shellcheck -S warning` is clean;
`bats scripts/tests/plugins/e2e.bats` passes 79/79; on a temporary copy, dropping `--wait=false` fails the
new test.

**First live run (2026-10-17, run `1792239012-26194`, commit `6b4ca6b1`).** `make e2e-sandbox` exited at
05:12:04; the log's last write (the cleanup's `deleted` line) was 05:11:58, so it exited within one 5s poll
of the cleanup. No hang. The original hang was a lost watch, which is intermittent, so this shows the fix
working rather than proving every case.
