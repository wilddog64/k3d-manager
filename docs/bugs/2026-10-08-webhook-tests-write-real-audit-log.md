# Webhook pytest suite appends fake entries to the real remote-operator audit log

**Filed:** 2026-10-08, Claude
**Branch:** k3d-manager-v1.42.0
**Status:** OPEN — spec ready for Codex
**Priority:** P2 — the security audit trail is polluted; there is no data loss and the entries are tell-able by `actor:"test"`
**Severity:** Medium
**Component:** `scripts/tests/bin/test_webhook_cluster_status_thread.py`, `scripts/tests/conftest.py`

## Symptom

`~/.local/share/k3d-manager/audit/remote-operator.jsonl` holds **72** entries with
`"actor":"test","role":"admin","allowed":true,"source_command":"direct-api"`, dating from
2026-10-02. They come in bursts of three, one per pytest run:

```text
{"ts":"2026-10-08T22:55:51.746462+00:00","path":"/api/v1/cluster-status","action":"cluster-status","actor":"test","role":"admin","allowed":true,...}
{"ts":"2026-10-08T22:55:51.785503+00:00","path":"/api/v1/argocd-upgrade","action":"argocd-upgrade","actor":"test","role":"admin","allowed":true,...}
{"ts":"2026-10-08T22:55:51.789402+00:00","path":"/api/v1/make","action":"make:test-all","actor":"test","role":"admin","allowed":true,...}
```

This is the trail the operator relies on for the webhook security audit
(see the webhook-server security concern). Fake admin "allowed" rows for `argocd-upgrade` and
`make` make real admin activity harder to read, and they train the reader to ignore admin rows.

## Root cause

Three tests drive the real `_Handler.do_POST`, with `_request_actor` patched to `"test"`:
- `test_cluster_status_route_passes_channel_id`
- `test_argocd_upgrade_api_requires_infra_confirmation`
- `test_top_level_make_job_creates_a_slack_thread`

None of them patches `_audit_remote_action` or `webhook.policy.AUDIT_DIR`. `AUDIT_DIR` is
`Path.home() / ".local/share/k3d-manager/audit"` (`scripts/lib/webhook/config.py:30`) and pytest
does not isolate `HOME`, so every run writes to the live file. `webhook.bats` is safe: it sets
a temp `HOME`. Other pytest files patch the function (`test_role_capabilities.py:80`) or the dir
(`webhook_policy.py:284`), but only file by file. Nothing prevents the next test from leaking.

## Fix (spec for Codex)

1. `scripts/tests/conftest.py`: add an autouse fixture that redirects the audit dir for every
   test, so no individual test has to remember:

   ```python
   @pytest.fixture(autouse=True)
   def _k3dm_isolated_audit_dir(tmp_path_factory, monkeypatch):
       policy = sys.modules.get("webhook.policy")
       if policy is None:
           return
       monkeypatch.setattr(policy, "AUDIT_DIR", tmp_path_factory.mktemp("audit"))
   ```

   `sys.modules` lookup, not an import, so conftest gains no import side effects. Test modules
   that load the webhook do so at collection time, before any fixture runs. Add `import sys` if
   it is missing.
2. Do **not** change `config.py`. Do not add an env override for the audit path, because a
   relocatable security audit log is a weakness. `webhook.bats` greps that line as it is.

## Tests

`scripts/tests/bin/test_webhook_cluster_status_thread.py`: add one test that imports
`webhook.policy`, calls `policy._audit_remote_action("/api/v1/x", "x", "test", "admin", True)`,
and asserts:
- `Path(policy.AUDIT_DIR) != Path.home() / ".local/share/k3d-manager/audit"`;
- the line landed in `policy.AUDIT_DIR / "remote-operator.jsonl"`.

Show RED without the conftest fixture, on a temp copy. Run it against a **copy** of the test,
with `HOME` set to a temp dir, so the RED run itself does not write to the real log.

## Cleanup (operator, after the fix lands)

The 72 existing rows stay. The audit log is append-only by intent, so do not rewrite it.
Readers can filter with `actor != "test"`. Record that filter in
`docs/guides/` next to the audit log description, if one exists.
