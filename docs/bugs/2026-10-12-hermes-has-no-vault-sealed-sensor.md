# Bug: Hermes has no sensor for a sealed Vault

**Filed:** 2026-10-12
**Branch:** `k3d-manager-v1.44.0`
**Status:** OPEN
**Priority:** P3 — a visibility gap; the watchdog unseals Vault today, but nothing reports when it does not
**Approval:** explicit 2026-10-12 "let's get those two to v1.44.0" (operator, to "should I file them, and for v1.43.2 or v1.44?")
**Severity:** low

## Symptom

After the 2026-10-12 OrbStack upgrade restarted the hub, Vault was sealed for about five minutes.
The Hermes Status dashboard showed nothing about it. If the unseal watchdog had failed, the first
visible signal would have been ExternalSecrets going stale, which points away from the cause.

## Root cause

`scripts/lib/hermes/sensors.py` has no Vault sensor. The data already exists: the hub's Vault pod
carries the service-registration labels `vault-sealed`, `vault-initialized` and `vault-active`
(read on 2026-10-12: `vault-sealed=false`, `vault-initialized=true`, `vault-active=true`).

## Fix

1. `scripts/lib/hermes/sensors.py`: new `vault_seal(run, state, context=None, threshold=2)`, shaped
   like `hostnet_drift`.
   - Context: `context or os.environ.get("K3DM_HERMES_JOB_CONTEXT", "k3d-k3d-cluster")`.
   - Read: `kubectl --context <ctx> -n secrets get pods -l app.kubernetes.io/name=vault,component=server -o json`.
     Use each pod's `metadata.labels` only. Never exec into a pod, never call the Vault API and never
     read a Secret.
   - No pods, or any pod missing the `vault-sealed` label → `unknown`,
     `vault seal state unavailable`.
   - Any pod with `vault-sealed=true`, debounced with `_debounced("vault_seal", …)` → `degraded`,
     evidence `sealed: <pod names>` (at most 3).
   - Otherwise `healthy`, evidence `unsealed: <n> pod(s)`.
   - `data`: `{"pods": [{"name", "sealed", "initialized", "active"}]}` with the label values as
     booleans (`None` when a label is absent).
   - Any exception → `unknown`.
2. `bin/k3dm-hermes`: import it and add `vault_seal(_probe_run, state)` to the sensor list next to
   `hostnet_drift`.
3. The sensor never unseals. No repair is added in `scripts/lib/hermes/repairs.py`; Hermes must not
   hold an unseal shard. Unsealing stays with the in-cluster watchdog
   (`docs/bugs/2026-10-12-vault-unseal-watchdog-gives-up-while-vault-boots.md`).
4. `docs/guides/hermes.md`: add `vault_seal` to the numbered sensor list, stating it is read-only,
   reads pod labels, and has no repair, and why. Fix the stale "The five read-only sensors" row in
   the component table to say the sensor list below.

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/sensors.py` | `vault_seal` |
| `bin/k3dm-hermes` | import + sensor list |
| `scripts/tests/hermes/test_hermes.py` | tests below |
| `docs/guides/hermes.md` | sensor entry + table row |
| `CHANGELOG.md` | `[Unreleased]` → `### Added` |

## Tests

`scripts/tests/hermes/test_hermes.py`, with a stub `run` returning canned pod JSON. No test may call
a real `kubectl`.

1. One pod, `vault-sealed=false` → `healthy`, evidence `unsealed: 1 pod(s)`.
2. One pod, `vault-sealed=true`, two cycles with the same `state` → first `healthy`, second
   `degraded` with `sealed: vault-0`.
3. Empty item list → `unknown`.
4. Pod with no `vault-sealed` label → `unknown`.
5. `run` returns code 1 → `unknown`.
6. The command the stub receives contains `get` and `pods` and does not contain `exec`, `secret` or
   `unseal`.
7. `data["pods"][0]["sealed"]` is a bool.
8. `repairs.py` has no rule that names `vault_seal` (assert by reading the repair table).

Mutations (each must turn a test red): treat a missing label as healthy (test 4); drop the debounce
(test 2); read `vault-initialized` instead of `vault-sealed` (test 2).

Gates: `pytest scripts/tests/hermes/test_hermes.py`, `make test-pytest`.

## Proof it works

The next Hermes cycle after landing shows a `vault_seal` row on the Hermes Status dashboard reading
`unsealed: 1 pod(s)`. On the next hub restart it reads `degraded` while Vault is sealed and returns
to `healthy` once the watchdog unseals it.

## What NOT to Do

- Do NOT add a repair or any unseal path to Hermes.
- Do NOT read Secrets, exec into Vault, or call the Vault HTTP API.
- Do NOT change other sensors, the exporter or the dashboard JSON.
- Do NOT commit, push or create a PR. Claude verifies and commits.
- Do NOT modify files outside the Files list.
