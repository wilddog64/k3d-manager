# Offline Python-stage follow-up

Status: partial; focused repair verified, fresh full operator run pending.

The operator full run `/tmp/k3dm-test-all-1793222885.log` passed the main
1913-case BATS stage (20 skips) and all 623 bin BATS cases, then failed four
Python tests: dashboard producer-series matching, dispatch by-model PromQL,
OrbStack rules, and upgrade annotations. Each attempted Docker promtool fallback
because native promtool was absent from PATH. The unchanged tripwire blocked
those four container calls. It also blocked four `orbctl update --check` calls
from Hermes poll fixtures missing the optional OrbStack hooks. Nothing reached
a real Docker/OrbStack binary. Full actual operator output:
[terminal log](../assets/2026-10-28-test-all-1793222885.txt).

The shared poll fixture now mocks `_publish_orbstack_metrics` and
`_orbstack_notice`; its safety regression installs raising sentinels first and
proves the fixture replaces both. The autouse fixture also directs the OrbStack
Pushgateway URL to the same closed local port as other publishers. Production
code, tripwire policy and semantic assertions are unchanged.

An existing native promtool is available at
`/private/tmp/k3dm-prometheus-review/prometheus-3.2.1.darwin-arm64/promtool`.
Putting its directory on PATH exercises the actual semantic checks without
Docker. No installation or container execution was needed. `PROMTOOL` alone is
insufficient for helpers which resolve the executable from PATH.

## Actual red/green and verification output

Two initial verifier commands used the environment's `python3 -m pytest`, but
that interpreter has no pytest module. These are command mistakes, not test
results; the existing `pytest` CLI runs Python 3.13.6 with dependencies.

### Initial red command

```text
/Users/cliang/src/gitrepo/personal/.direnv/python-3.13/bin/python3: No module named pytest
```

### Initial green command

```text
/Users/cliang/src/gitrepo/personal/.direnv/python-3.13/bin/python3: No module named pytest
```

### Valid red regression

```text
============================= test session starts ==============================
platform darwin -- Python 3.13.6, pytest-9.1.1, pluggy-1.6.0
rootdir: /Users/cliang/src/gitrepo/personal/k3d-manager
collected 86 items / 85 deselected / 1 selected

scripts/tests/hermes/test_hermes.py F                                    [100%]

=================================== FAILURES ===================================
________ test_status_poll_fixture_blocks_optional_orbstack_side_effects ________

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x10a3e4c30>
tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1965/test_status_poll_fixture_block0')

    def test_status_poll_fixture_blocks_optional_orbstack_side_effects(monkeypatch, tmp_path):
        def unexpected(*_args, **_kwargs):
            raise AssertionError("poll fixture reached a real OrbStack integration hook")
    
        monkeypatch.setattr(k3dm_hermes, "_publish_orbstack_metrics", unexpected)
        monkeypatch.setattr(k3dm_hermes, "_orbstack_notice", unexpected)
        calls, runner = _stub_status_poll(monkeypatch, status_payload("healthy"))
>       k3dm_hermes._poll({}, tmp_path / "state.json", now=10000, status_runner=runner)

scripts/tests/hermes/test_hermes.py:422: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
bin/k3dm-hermes:893: in _poll
    return _poll_cycle(state, state_path, now, status_runner)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
bin/k3dm-hermes:878: in _poll_cycle
    _publish_orbstack_metrics(state, now)
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

_args = ({'debounce': {'status_checks': 0}, 'correlation_history': [[]], 'repair_debounce': {'r1': 0}, 'pending_repairs': {}, ...}, 10000)
_kwargs = {}

    def unexpected(*_args, **_kwargs):
>       raise AssertionError("poll fixture reached a real OrbStack integration hook")
E       AssertionError: poll fixture reached a real OrbStack integration hook

scripts/tests/hermes/test_hermes.py:417: AssertionError
----------------------------- Captured stderr call -----------------------------
Hermes heartbeat push skipped (non-fatal): <urlopen error [Errno 1] Operation not permitted>
=========================== short test summary info ============================
FAILED scripts/tests/hermes/test_hermes.py::test_status_poll_fixture_blocks_optional_orbstack_side_effects
======================= 1 failed, 85 deselected in 0.30s =======================
```

### Valid green regression

```text
============================= test session starts ==============================
platform darwin -- Python 3.13.6, pytest-9.1.1, pluggy-1.6.0
rootdir: /Users/cliang/src/gitrepo/personal/k3d-manager
collected 86 items / 85 deselected / 1 selected

scripts/tests/hermes/test_hermes.py .                                    [100%]

======================= 1 passed, 85 deselected in 0.15s =======================
```

### Previously skipped E2E semantic BATS with native promtool

```text
1..2
ok 1 e2e staleness is fresh if any runner passed recently
ok 2 E2EResultsMissing fires only when the hub has no e2e results
```

The full `make test-python` stage under the unchanged tripwire and native
promtool PATH passed: **1661 passed, 2 skipped**. Full unittest/pytest/tripwire
output is preserved in the [stage transcript](../assets/2026-10-28-python-offline-final.txt).
Eight attempted read-only security/kubectl calls remained blocked; no unsafe
Docker or OrbStack call was observed. The report-mode hermetic-guard test
intentionally records its sentinel violation. Two skips remain in the actual
pytest output; this is not a claim of zero skips.

Ruff: `All checks passed!`; `git diff --check`: no output. No shell production
file changed, so ShellCheck is not applicable to these Python-only edits.
The two focused BATS semantic tests passed without skips (output above).
These separate stage results do not establish a fresh full `test-all` run or
published complete=1. Keep the P2 open. Operator next command:

```bash
PATH="/private/tmp/k3dm-prometheus-review/prometheus-3.2.1.darwin-arm64:$PATH" make test-all
```
