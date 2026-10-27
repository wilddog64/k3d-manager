# Webhook doctor handles recurring Keychain access failures

## Request and scope

Operator requested that the doctor account for frequent login-Keychain locks,
after confirming unlock changed the reader lookup exit from36 to0. A generic
auth_unavailable did not explain this expected operational condition.

Implementation `1ff3b09b2bda92fc20125253f5c7b365db320e46` adds bounded
credential facts and an action hint while keeping the command read-only.
No lock settings, credential storage, ACLs or services were changed.

## Resulting behavior

- Keychain exit36: classification keychain_interaction_required, credential
  status interaction_required. The hint explains the login Keychain may be
  locked or the session cannot request access and gives the interactive
  unlock command. It does not claim every interaction restriction is a lock.
- Missing reader item (exit44): auth_unavailable with credential status missing
  and an existing-reader-configuration hint, distinct from unlock advice.
- Lookup timeout, unavailable command, output cap, empty value and other
  failure retain separate bounded credential statuses.
- Environment reader credential bypasses Keychain; successful Keychain lookup
  reports available. No token or raw error/command output enters public JSON.
- Without a credential, HTTP is not probed and health stays auth_unavailable.
  Credential access failure alone cannot recommend a webhook restart.
  recovery_action is null unless independent local evidence warrants it.
- Every run reads current state; fixture transition from locked to unlocked
  is observed on the next check without a cached token or service restart.
  No auto-unlock, password prompt/collection, lock-policy change or recovery
  operation is performed by the doctor.

## Pre-fix regression output

Four new tests were run against the preceding generic-auth implementation:

```text
FFFF                                                                     [100%]
=================================== FAILURES ===================================
______ test_locked_keychain_reports_access_action_without_http_or_restart ______

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x10b546060>
tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1886/test_locked_keychain_reports_a0')

    def test_locked_keychain_reports_access_action_without_http_or_restart(monkeypatch, tmp_path):
        _stub_local_facts(monkeypatch, tmp_path)
        calls = []
        def lookup(argv):
            calls.append(argv)
            return {"returncode": 36, "stdout": "User interaction is not allowed. private-fixture-value",
                    "timed_out": False, "output_limited": False}
        monkeypatch.setattr(doctor, "_run", lookup)
        result = doctor.diagnose(check=True)
>       assert result["classification"] == "keychain_interaction_required"
E       AssertionError: assert 'auth_unavailable' == 'keychain_int...tion_required'
E         
E         - keychain_interaction_required
E         + auth_unavailable

scripts/tests/bin/test_webhook_doctor.py:358: AssertionError
__________ test_missing_reader_is_distinct_from_keychain_access_block __________

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x10b28c640>
tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1886/test_missing_reader_is_distinc0')

    def test_missing_reader_is_distinct_from_keychain_access_block(monkeypatch, tmp_path):
        _stub_local_facts(monkeypatch, tmp_path)
        monkeypatch.setattr(doctor, "_run", lambda _args: {"returncode": 44, "stdout": "item missing private-fixture-value"})
        result = doctor.diagnose(check=True)
        assert result["classification"] == "auth_unavailable"
>       assert result["credential"]["status"] == "missing"
               ^^^^^^^^^^^^^^^^^^^^
E       KeyError: 'credential'

scripts/tests/bin/test_webhook_doctor.py:374: KeyError
___ test_keychain_statuses_are_bounded_and_never_return_partial_credentials ____

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x10b3344d0>

    def test_keychain_statuses_are_bounded_and_never_return_partial_credentials(monkeypatch):
        cases = [
            (None, "command_unavailable"),
            ({"returncode": -15, "stdout": "private", "timed_out": True}, "command_timeout"),
            ({"returncode": -15, "stdout": "private", "output_limited": True}, "command_output_limit"),
            ({"returncode": 51, "stdout": "private"}, "lookup_failed"),
            ({"returncode": 0, "stdout": ""}, "empty"),
        ]
        for command, expected in cases:
            monkeypatch.setattr(doctor, "_run", lambda _args, command=command: command)
>           token, facts = doctor._keychain_reader_credential()
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
E           AttributeError: module 'webhook_doctor' has no attribute '_keychain_reader_credential'. Did you mean '._keychain_reader_token' instead of '._keychain_reader_credential'?

scripts/tests/bin/test_webhook_doctor.py:392: AttributeError
_________ test_reader_environment_bypasses_keychain_and_is_not_exposed _________

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x10b30ae00>
tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1886/test_reader_environment_bypass0')

    def test_reader_environment_bypasses_keychain_and_is_not_exposed(monkeypatch, tmp_path):
        _stub_local_facts(monkeypatch, tmp_path)
        monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "private-env-fixture")
        monkeypatch.setattr(doctor, "_run", lambda *_args: (_ for _ in ()).throw(AssertionError("Keychain lookup")))
        monkeypatch.setattr(doctor, "_health_probe", lambda token, **_kwargs: {"status": "healthy_http", "http_responsive": True, "all_ok": True})
        result = doctor.diagnose(check=True)
>       assert result["credential"] == {"source": "environment", "status": "available"}
               ^^^^^^^^^^^^^^^^^^^^
E       KeyError: 'credential'

scripts/tests/bin/test_webhook_doctor.py:404: KeyError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_webhook_doctor.py::test_locked_keychain_reports_access_action_without_http_or_restart
FAILED scripts/tests/bin/test_webhook_doctor.py::test_missing_reader_is_distinct_from_keychain_access_block
FAILED scripts/tests/bin/test_webhook_doctor.py::test_keychain_statuses_are_bounded_and_never_return_partial_credentials
FAILED scripts/tests/bin/test_webhook_doctor.py::test_reader_environment_bypasses_keychain_and_is_not_exposed
4 failed, 26 deselected in 0.26s
```

## Final actual focused gate output

```text
...............................                                          [100%]
31 passed in 0.96s
1..5
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook fails after five bootstrap attempts and skips cloud bridge
All checks passed!
{"mode": "dry-run", "probes": ["launchd job state and last exit code", "webhook process PID", "configured webhook TCP listener (default 7443)", "bounded redacted log summary", "reader-authenticated loopback /api/v1/health?quick=1"], "recovery": "No recovery is performed. Operator may run make restart-webhook once only when local evidence warrants it; it also restarts cloud-bridge.", "timestamp_utc": "2026-10-27T22:41:18.455906+00:00"}
```

Commands: pytest on test_webhook_doctor.py; BATS restart_webhook.bats; Ruff on
the doctor and its Python test; direct --dry-run and git diff --check.
Staged _agent_lint/_agent_audit and normal checkpoint hooks passed. All new
helpers/classification remained within the8-if budget. ShellCheck is not
applicable because no production shell file was touched.

This is offline verification of locked-state fixtures, not a claim that the
operator's live Keychain was locked again. We did not relock the Keychain or
change a credential to demonstrate the feature. Existing whole-repository
regression failures are separately documented in the six-bug batch; the full
suite was not repeated for this bounded doctor change.

## Next single operator live check

Run bin/k3dm-webhook-doctor --check in the unlocked session. Available reader
credential and authenticated current health should be reported; a future
blocked access will have the explicit category/hint rather than a generic
credential failure. No restart is requested. GHCR runtime auth/scan and the
remaining batch live items are still pending.
