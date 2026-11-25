# Cloud bridge loses the response of a queued `sandbox-up` / `sandbox-down`

**Status:** OPEN — captured 2026-11-25
**Priority:** P2 (a cloud lifecycle request runs but its response is lost; workaround: check sandbox state with `cluster-status`)
**Triage:** carry → v1.46.0, fixed inside plan 1b (`docs/plans/v1.46.0-cloud-approval-b-bridge.md`), which rewrites the same path
**Branch:** `k3d-manager-v1.46.0`
**Introduced by:** ef6f48a1 (v1.41.0, `LIFECYCLE_TIMEOUTS` watch timeout)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** none above threshold (exact-slug glob found none; vector store unreachable)
**Detected by:** Astra (codex `gpt-6.2-astra`) blind review of v1.46.0 plan 1, 2026-11-25; confirmed by Claude against the code.

## Symptom

`_watch_entry` (`bin/k3dm-cloud-bridge:492-501`) computes:

```python
target = ACTION_ALLOWLIST[request["action"]][3]
timeout = LIFECYCLE_TIMEOUTS.get(request["action"], MAKE_TARGETS.get(target, {}).get("timeout", 300))
```

The default argument is evaluated eagerly. For `sandbox-up` and `sandbox-down`, `target` is the dict
`{"action": "up"|"down", "provider": "aws"}` (`scripts/lib/webhook/cloud_actions.py:21-22`), so `MAKE_TARGETS.get(target, {})`
raises `TypeError: cannot use 'dict' as a dict key (unhashable type: 'dict')`. Reproduced by Astra by evaluating `_watch_entry`
alone with a queued response.

The call happens in `process_tick` after `_call_webhook` returned (`:652`) and before the outbox write, so the webhook has already
started the lifecycle job when the exception aborts the tick. The request is claimed, so it is not retried; after a bridge restart,
orphan recovery answers it "outcome unknown".

## Fix

Select the timeout explicitly: `LIFECYCLE_TIMEOUTS[action]` when the action is in it, else the `MAKE_TARGETS` lookup. Add a test that a
queued response for each lifecycle action yields a watch entry with the lifecycle timeout (3600 / 1800). The existing test at
`scripts/tests/bin/test_cloud_bridge.py:615` builds the watch entry by hand and never calls `_watch_entry` for a lifecycle action.
