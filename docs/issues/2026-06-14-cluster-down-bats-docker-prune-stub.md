# 2026-06-14 — `cluster_down.bats` needed a Docker stub for sandbox validation

## What was tested

I ran the renamed BATS suites after the `bin/acg-*` → `bin/cluster-*` rename:

- `bats scripts/tests/bin/cluster_up.bats`
- `bats scripts/tests/bin/cluster_down.bats`
- `bats scripts/tests/bin/cluster_sync_apps.bats`

`cluster_up.bats` and `cluster_sync_apps.bats` passed. `cluster_down.bats` initially failed in this sandbox because the `bin/cluster-down` script reaches the Docker prune step and the test harness did not stub `docker`.

## Actual output

Initial failing output from the down suite:

```text
1..5
not ok 1 acg-down keeps the local hub when --keep-hub is set
# (in test file scripts/tests/bin/cluster_down.bats, line 132)
#   `[ "$status" -eq 0 ]' failed
not ok 2 acg-down deletes the local hub by default
# (in test file scripts/tests/bin/cluster_down.bats, line 141)
#   `[ "$status" -eq 0 ]' failed
not ok 3 acg-down removes the ArgoCD browser HTTPS listener
# (in test file scripts/tests/bin/cluster_down.bats, line 156)
#   `[ "$status" -eq 0 ]' failed
not ok 4 acg-down warns and continues when the ArgoCD browser listener is not loaded
# (in test file scripts/tests/bin/cluster_down.bats, line 169)
#   `[ "$status" -eq 0 ]' failed
not ok 5 acg-down removes the Keycloak browser HTTP listener
# (in test file scripts/tests/bin/cluster_down.bats, line 179)
#   `[ "$status" -eq 0 ]' failed
```

Manual reproduction showed the underlying failure came from the Docker prune step in `bin/cluster-down`.

## Root cause

The renamed `cluster_down.bats` suite had no `docker` stub, while `bin/cluster-down` still executes the Docker prune path near the end of the script. In this sandbox, the real Docker socket is unavailable, so the suite exited non-zero before the assertions could complete.

## Recommended follow-up

- Keep the local `docker` stub in `scripts/tests/bin/cluster_down.bats` so the renamed suite stays green in sandboxed validation environments.
- If future test harnesses reuse this suite, ensure the Docker prune path stays isolated from host Docker access.
