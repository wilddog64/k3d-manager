# Bug: Hermes never publishes its status ConfigMap, and nothing says why

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-29 by Claude (cloud session), from the operator's report that the Hermes Status
dashboard is empty
**Status:** FIXED and verified live 2026-09-29 — `1f495ab0`; operator saw `published: True` and `platform-ops/hermes-status` created on the hub
**Files:** `bin/k3dm-hermes` (`_publish_status`), `scripts/tests/hermes/test_publish_status.py`,
`scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`

## Evidence (2026-09-29, operator on the M4)

- `launchctl list | grep hermes` — running, last exit 0. The Hermes log shows recent polls.
- `kubectl --context k3d-k3d-cluster -n platform-ops get cm -l k3dm.k3.io/hermes-status=true` →
  `No resources found in platform-ops namespace.`
- The Hermes Status dashboard (hub): `Minutes since last poll`, `Current Hermes findings` and
  `Sensor status history` show No data. The three green `0` tiles are fallbacks
  (`or vector(0)` / counts over nothing), not readings.

## Mechanism

Hermes (on the M4) writes `platform-ops/hermes-status` with three `kubectl` calls — `create
--dry-run`, `apply`, `label`. The `vulnerability-inventory-exporter` on the hub reads it and emits
`hermes_*` series. With no ConfigMap the exporter emits only `hermes_incident_active 0`.

Two layers hid the failure:

1. `_publish_status` returned `False` at every failing step and discarded `kubectl`'s stderr.
2. The exporter's `refresh_hermes_status` wraps its read in `except Exception: pass`.

So Hermes polled, paged and filed normally while its dashboard stayed empty, and no log line
anywhere named a cause.

## Candidate causes (unconfirmed — the new log line will name the real one)

- The launchd job sets `PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin` and no `KUBECONFIG`,
  so `kubectl` sees only `~/.kube/config`. If `k3d-k3d-cluster` lives only in another kubeconfig
  file, every call fails with a missing-context error.
- `kubectl apply` stores the whole object in the `last-applied-configuration` annotation, and
  annotations are capped at 256 KiB in total. A large `records` payload would be rejected at `apply`.
- `kubectl` not on the launchd `PATH` (would log as `exec … FileNotFoundError`).

## Change landed (diagnostic only)

`_publish_status` now logs one line to the Hermes log on failure:

```
[k3dm-hermes] status publish failed at <create|apply|label|exec> (context=… namespace=… bytes=N): <kubectl stderr>
```

The detail is whitespace-collapsed, passed through `scrub_credentials`, and cut to 400 characters.
`bytes=` is included so the annotation-size candidate can be confirmed or ruled out from the same
line. Success and the two intentional skips (no records, `K3DM_HERMES_PUBLISH_STATUS` ≠ `1`) stay
silent. Hermes is started fresh by launchd every 300 s, so a `git pull` is enough — no restart.

Tests: `scripts/tests/hermes/test_publish_status.py` (7). Silencing the `apply` failure, dropping
the scrub/bound, and silencing the `exec` failure each went red.

## Next step

Operator: after pulling, wait one poll (≤ 5 min), then
`grep 'status publish failed' ~/Library/Logs/k3dm-hermes.log | tail -3`. The fix follows from that
line. Out of scope until then: the exporter's `except Exception: pass`, which should count read
failures in a metric rather than swallow them.

## Root cause (2026-09-29, from the new log line)

The operator ran `_publish_status` once under the launchd environment:

```
[k3dm-hermes] status publish failed at apply (context=k3d-k3d-cluster namespace=platform-ops bytes=111):
error: unable to decode "STDIN": json: cannot unmarshal string into Go struct field
ObjectMeta.metadata.labels of type map[string]string
```

The label was spliced into the dry-run YAML as `k3dm.k3.io/hermes-status=true` (the `kubectl label`
`key=value` form), so `metadata.labels` parsed as a **string**, not a map, and the API server
rejected every apply. This has been true since the feature shipped in `978ea60f` (2026-09-17): the
Hermes Status dashboard has never had data. Both kubeconfigs resolved `k3d-k3d-cluster` to the same
server (`https://127.0.0.1:52888`), and the candidate causes listed above were all ruled out.

## Fix

`create --dry-run=client -o json`, set `metadata.labels[key] = value` on the parsed object, apply the
JSON. No string surgery on YAML. Tests: `test_applied_manifest_labels_are_a_map` (stdlib `json`, so it
cannot be skipped the way a PyYAML-based check was on this runner) and
`test_label_step_keeps_kubectl_key_equals_value`. Mutations: the original string-label shape and
dropping the label each went red.
