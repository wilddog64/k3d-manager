# Bug: Hermes has no sensor for a sealed Vault

**Filed:** 2026-10-12
**Branch:** `k3d-manager-v1.44.2`
**Status:** LANDED on `k3d-manager-v1.44.2` 2026-11-17 (fadf8438); verified offline by Claude
**Priority:** P2 — raised 2026-11-17 (operator): without it Hermes misreads a seal as many problems and offered the wrong repair (`2026-11-17-hermes-r7-signing-restore-offered-when-vault-sealed.md`)
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (Hermes status observability is degraded by not surfacing sealed Vault state on the dashboard, with a workaround of inspecting the `vault-sealed` pod label directly or observing downstream ExternalSecrets status); Claude proposed P3. Higher stands until the operator decides.
**Triage:** patch → v1.44.2 (P2), prerequisite of `2026-11-17-hermes-r7-signing-restore-offered-when-vault-sealed.md` (operator, 2026-11-17: "go ahead"). Earlier: passed over, 1st — grooming 2026-11-12.
**Waiting on:** operator decision — since 2026-11-17 (dashboard row live-verified 14:28Z; the 15:01Z pod-restart run unsealed inside one Hermes cycle, so E5/E2 need a longer seal: pause the watchdog or wait for a real outage; see `docs/plans/hermes-vault-sealed.md`)
**Approval:** explicit 2026-10-12 "let's get those two to v1.46.0" (operator, to "should I file them, and for v1.43.2 or v1.44?")
**Severity:** low

## Symptom

After the 2026-10-12 OrbStack upgrade restarted the hub, Vault was sealed for about five minutes.
The Hermes Status dashboard showed nothing about it. If the unseal watchdog had failed, the first
visible signal would have been ExternalSecrets going stale, which points away from the cause.

## Root cause

`scripts/lib/hermes/sensors.py` has no Vault sensor. The data already exists: the hub's Vault pod
carries the service-registration labels `vault-sealed`, `vault-initialized` and `vault-active`
(read on 2026-10-12: `vault-sealed=false`, `vault-initialized=true`, `vault-active=true`).

## External behaviour proof

The labels come from Vault's Kubernetes service registration, not from this repo:
- Upstream `hashicorp/vault-helm` at tag `v0.30.1` (the pin, `scripts/plugins/vault.sh:9`), read
  2026-11-17 via `gh api`: `values.yaml:930` puts `service_registration "kubernetes" {}` in the
  `server.ha.raft.config` default; `templates/server-statefulset.yaml:39-41` sets pod labels
  `app.kubernetes.io/name: vault` and `component: server`.
- The hub deploys `server.ha.enabled: true` with `raft.enabled: true`
  (`scripts/plugins/vault.sh:938-943`) in namespace `secrets` (`VAULT_NS_DEFAULT`, line 7), so that
  default applies.
- Live read on the hub, 2026-10-12: `vault-sealed=false`, `vault-initialized=true`,
  `vault-active=true` on `vault-0`. The M4 has no `k3d-k3d-cluster` context (checked 2026-11-17);
  live evidence E5 in `docs/plans/hermes-vault-sealed.md` re-proves it on the hub.

## Fix

1. `scripts/lib/hermes/sensors.py`: new `vault_seal(run, state, context=None, threshold=2)`, shaped
   like `hostnet_drift`.
   - Context: `context or os.environ.get("K3DM_HERMES_JOB_CONTEXT", "k3d-k3d-cluster")`.
   - Read, with exactly this argv: `["kubectl", "--context", <ctx>, "-n", "secrets", "get", "pods", "-l",
     "app.kubernetes.io/name=vault,component=server", "-o", "json", "--request-timeout=10s"]`.
     Use each pod's `metadata.labels` only. Never exec into a pod, never call the Vault API and never
     read a Secret.
   - No pods, or any pod missing the `vault-sealed` label → `unknown`,
     `vault seal state unavailable`.
   - Any pod with `vault-sealed=true`, debounced exactly like `hostnet_drift`
     (`_debounced("vault_seal", True, max(0, threshold - 1), state)`; `_debounced` returns
     `count > threshold`, so with the default `threshold=2` the second sealed cycle is the first
     `degraded` one) → `degraded`, evidence `sealed: <pod names>` (at most 3).
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
   reads pod labels, and has no repair, and why. (The component table row was already corrected; do
   not touch it.)

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/sensors.py` | `vault_seal` |
| `bin/k3dm-hermes` | import + sensor list |
| `scripts/tests/hermes/test_hermes.py` | tests below |
| `docs/guides/hermes.md` | sensor entry |
| `scripts/tests/hermes/test_app_health.py` | stub `vault_seal` in the `_run_cycle` test (line 164) |

`CHANGELOG.md` is written by Claude at land (shared with the webhook dispatch).

Existing `_run_cycle` tests stub every sensor by name. Add `"vault_seal"` to the stub loops at
`scripts/tests/hermes/test_hermes.py:287, 311, 333, 385` and `scripts/tests/hermes/test_app_health.py:164`;
without it `test_unknown_status_poll_never_pages_or_files_and_preserves_open_groups` (`test_hermes.py:561`)
calls a real `kubectl`, gets `unknown` seven times, and `pager.health_events` pages "vault_seal check
unknown 30+ min".

## Tests

`scripts/tests/hermes/test_hermes.py`, with a stub `run` returning canned pod JSON. No test may call
a real `kubectl`. Every pod fixture carries all three labels (`vault-sealed`, `vault-initialized`,
`vault-active`) unless the test says otherwise. Use these test names exactly (the Acceptance `-k`
filters select on them):

1. `test_vault_seal_unsealed_is_healthy`: one pod, `vault-sealed=false`, `vault-initialized=true`,
   `vault-active=true` → `healthy`, evidence `unsealed: 1 pod(s)`.
2. `test_vault_seal_sealed_degrades_on_second_cycle`: one pod `vault-0`, `vault-sealed=true`,
   `vault-initialized=true`, two cycles with the same `state` → first `healthy`, second `degraded` with
   `sealed: vault-0`.
3. `test_vault_seal_no_pods_is_unknown`: empty item list → `unknown`.
4. `test_vault_seal_missing_label_is_unknown`: pod with `vault-initialized` and `vault-active` but no
   `vault-sealed` → `unknown`.
5. `test_vault_seal_kubectl_error_is_unknown`: `run` returns code 1 → `unknown`.
6. `test_vault_seal_argv_is_read_only`: the argv the stub receives equals the exact list in Fix 1
   (compare the whole list; no substring checks, since `-n secrets` contains "secret").
7. `test_vault_seal_data_is_boolean`: test 1's fixture → `data["pods"][0] == {"name": "vault-0",
   "sealed": False, "initialized": True, "active": True}`.
8. `test_vault_seal_no_repair_can_unseal`: for every `REPAIRS` entry,
   `inspect.getsource(entry["build_command"])` contains neither `unseal` nor `vault operator`, and the
   only entry whose `reads` includes `vault_seal` is r7, where it can only block the repair.
9. `test_vault_seal_run_cycle_includes_record`: with every sensor stubbed, `k3dm_hermes._run_cycle`
   returns a record whose `sensor` is `vault_seal`.

Mutations (each must turn a test red): treat a missing label as healthy (test 4); drop the debounce
(test 2); read `vault-initialized` instead of `vault-sealed` (test 1 and test 7); drop the sensor from
`_run_cycle` (test 9).

Gates: `pytest scripts/tests/hermes`, `make test-pytest`.

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
