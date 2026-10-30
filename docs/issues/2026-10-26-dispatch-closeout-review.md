# Independent dispatch closeout review

**Status:** Both tasks landed/offline VERIFIED; live verification pending
**Priority:** P2

## Scope

Operator reported the dispatched tasks completed. Both supervisors recorded exit
0, but the P3 worker explicitly reported partial implementation and failing BATS.
Hermes was independently reviewed, tested red on the original implementation,
committed on its task branch, then rebased/tested/landed through the dispatcher.
Implementation `3aae7adc` is pushed; no live fetch/restart/deployment performed.

The original Hermes worker could not run Ruff. Coordinator installed Ruff 0.17.3
in disposable `/private/tmp/k3dm-review-tools`; `--no-cache` avoids writes outside
the coordinator sandbox. Its first broad Python run passed 369 tests with one
PytestCacheWarning (cache write denied); the post-rebase run disables cache and
passes without that warning. ShellCheck is not applicable to the Python/Markdown
Hermes patch. Staged `_agent_audit`, `_agent_lint`, and diff checks passed.

## P3 review findings and model correction

P3 initial report: 36 dashboard BATS passed, 2 failed; pytest 108 passed. Missing
ledger-aware Blocked by reconciliation, missing lifecycle fixtures, and guide
claims without implementation. Coordinator requested completion in the same
session with compatibility-preserving display mapping and original scope.

Dispatcher resume inherited the configured default model instead of the
requested Luna model. The runtime log of resume 2 reads:

```text
model: gpt-6.1-sol
provider: openai
session id: 01a17b2f-6931-7a01-9672-72f648ece226
```

Coordinator stopped only that task's worker descendants, then resumed with a
temporary `K3DM_CODEX_BIN` wrapper that injects `--model gpt-6-luna` into
`codex exec resume`. It preserves all dispatcher sandbox/scope arguments and
does not change repository dispatcher code. Resume 3 confirms:

```text
model: gpt-6-luna
provider: openai
session id: 01a17b2f-6931-7a01-9672-72f648ece226
```

Follow-up outside implementation scope: preserve explicit model selection on
Codex resume in the dispatcher; do not silently rely on the configured default.
P3 implementation/review is still pending at this record's initial creation.

## Recovered coordinator command issues

The previous session's disposable environment no longer exists:

```text
zsh:1: no such file or directory: /private/tmp/k3dm-test-venv/bin/python
```

Used installed `python3` (pytest 9.1.1) instead. A Ruff cache attempt returned:

```text
error: Failed to initialize cache at /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/hermes-launchagent-keychain-ssh/.ruff_cache: Operation not permitted (os error 1)
ruff failed
```

Rerunning with `ruff check --no-cache` passed. One status command was invoked
from a task checkout instead of the required release checkout:

```text
[codex-dispatch] ERROR: current branch 'task/v1.43.9/plans-dispatch-status-reconcile-luna' is not a release branch
```

The corrected status command from the release checkout reported running/in-scope.
A source search used an unmatched Zsh glob:

```text
zsh:5: no matches found: scripts/tests/bin/test_hermes*.py
```

Used `rg --files scripts/tests` to find `scripts/tests/hermes` instead. An
ancillary log read used `test.log`; the dispatcher actually records
`land-test.log`, which was read successfully below.

## Hermes expected pre-fix regression failures

```text
FFF                                                                      [100%]
=================================== FAILURES ===================================
_ test_index_fetch_uses_macos_keychain_without_overriding_caller[darwin-None-/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes] _

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x106a32780>
capsys = <_pytest.capture.CaptureFixture object at 0x106891940>
platform = 'darwin', override = None
expected = '/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes'

    @pytest.mark.parametrize(("platform", "override", "expected"), [
        ("darwin", None, "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes"),
        ("darwin", "ssh -F /tmp/custom-ssh-config", "ssh -F /tmp/custom-ssh-config"),
        ("linux", None, None),
    ])
    def test_index_fetch_uses_macos_keychain_without_overriding_caller(
            monkeypatch, capsys, platform, override, expected):
        import subprocess

        spec = importlib.util.spec_from_loader(
            "hermes_fetch_ssh", SourceFileLoader("hermes_fetch_ssh", str(ROOT / "bin/k3dm-hermes")))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        monkeypatch.setattr(module, "_index_ref", lambda: ("origin/test", "test"))
        monkeypatch.setattr(module, "_push_index_metrics", lambda _metrics: None)
        monkeypatch.setattr(module.sys, "platform", platform)
        monkeypatch.delenv("SSH_AUTH_SOCK", raising=False)
        if override is None:
            monkeypatch.delenv("GIT_SSH_COMMAND", raising=False)
        else:
            monkeypatch.setenv("GIT_SSH_COMMAND", override)
        captured = {}

        def run(argv, **kwargs):
            captured.update(kwargs)
            return subprocess.CompletedProcess(argv, 128, "", "Permission denied (publickey).")

        monkeypatch.setattr(module.subprocess, "run", run)
        assert module._refresh_index({}) is None
>       assert captured["env"].get("GIT_SSH_COMMAND") == expected
               ^^^^^^^^^^^^^^^
E       KeyError: 'env'

scripts/tests/bin/test_retrieval_probe.py:211: KeyError
----------------------------- Captured stderr call -----------------------------
vectordb index refresh skipped: git fetch failed: Permission denied (publickey).
_ test_index_fetch_uses_macos_keychain_without_overriding_caller[darwin-ssh -F /tmp/custom-ssh-config-ssh -F /tmp/custom-ssh-config] _

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x1068948a0>
capsys = <_pytest.capture.CaptureFixture object at 0x106a0b890>
platform = 'darwin', override = 'ssh -F /tmp/custom-ssh-config'
expected = 'ssh -F /tmp/custom-ssh-config'

    @pytest.mark.parametrize(("platform", "override", "expected"), [
        ("darwin", None, "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes"),
        ("darwin", "ssh -F /tmp/custom-ssh-config", "ssh -F /tmp/custom-ssh-config"),
        ("linux", None, None),
    ])
    def test_index_fetch_uses_macos_keychain_without_overriding_caller(
            monkeypatch, capsys, platform, override, expected):
        import subprocess

        spec = importlib.util.spec_from_loader(
            "hermes_fetch_ssh", SourceFileLoader("hermes_fetch_ssh", str(ROOT / "bin/k3dm-hermes")))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        monkeypatch.setattr(module, "_index_ref", lambda: ("origin/test", "test"))
        monkeypatch.setattr(module, "_push_index_metrics", lambda _metrics: None)
        monkeypatch.setattr(module.sys, "platform", platform)
        monkeypatch.delenv("SSH_AUTH_SOCK", raising=False)
        if override is None:
            monkeypatch.delenv("GIT_SSH_COMMAND", raising=False)
        else:
            monkeypatch.setenv("GIT_SSH_COMMAND", override)
        captured = {}

        def run(argv, **kwargs):
            captured.update(kwargs)
            return subprocess.CompletedProcess(argv, 128, "", "Permission denied (publickey).")

        monkeypatch.setattr(module.subprocess, "run", run)
        assert module._refresh_index({}) is None
>       assert captured["env"].get("GIT_SSH_COMMAND") == expected
               ^^^^^^^^^^^^^^^
E       KeyError: 'env'

scripts/tests/bin/test_retrieval_probe.py:211: KeyError
----------------------------- Captured stderr call -----------------------------
vectordb index refresh skipped: git fetch failed: Permission denied (publickey).
_ test_index_fetch_uses_macos_keychain_without_overriding_caller[linux-None-None] _

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x106a77410>
capsys = <_pytest.capture.CaptureFixture object at 0x106a0bed0>
platform = 'linux', override = None, expected = None

    @pytest.mark.parametrize(("platform", "override", "expected"), [
        ("darwin", None, "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes"),
        ("darwin", "ssh -F /tmp/custom-ssh-config", "ssh -F /tmp/custom-ssh-config"),
        ("linux", None, None),
    ])
    def test_index_fetch_uses_macos_keychain_without_overriding_caller(
            monkeypatch, capsys, platform, override, expected):
        import subprocess

        spec = importlib.util.spec_from_loader(
            "hermes_fetch_ssh", SourceFileLoader("hermes_fetch_ssh", str(ROOT / "bin/k3dm-hermes")))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        monkeypatch.setattr(module, "_index_ref", lambda: ("origin/test", "test"))
        monkeypatch.setattr(module, "_push_index_metrics", lambda _metrics: None)
        monkeypatch.setattr(module.sys, "platform", platform)
        monkeypatch.delenv("SSH_AUTH_SOCK", raising=False)
        if override is None:
            monkeypatch.delenv("GIT_SSH_COMMAND", raising=False)
        else:
            monkeypatch.setenv("GIT_SSH_COMMAND", override)
        captured = {}

        def run(argv, **kwargs):
            captured.update(kwargs)
            return subprocess.CompletedProcess(argv, 128, "", "Permission denied (publickey).")

        monkeypatch.setattr(module.subprocess, "run", run)
        assert module._refresh_index({}) is None
>       assert captured["env"].get("GIT_SSH_COMMAND") == expected
               ^^^^^^^^^^^^^^^
E       KeyError: 'env'

scripts/tests/bin/test_retrieval_probe.py:211: KeyError
----------------------------- Captured stderr call -----------------------------
vectordb index refresh skipped: git fetch failed: Permission denied (publickey).
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_retrieval_probe.py::test_index_fetch_uses_macos_keychain_without_overriding_caller[darwin-None-/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8 -o UseKeychain=yes]
FAILED scripts/tests/bin/test_retrieval_probe.py::test_index_fetch_uses_macos_keychain_without_overriding_caller[darwin-ssh -F /tmp/custom-ssh-config-ssh -F /tmp/custom-ssh-config]
FAILED scripts/tests/bin/test_retrieval_probe.py::test_index_fetch_uses_macos_keychain_without_overriding_caller[linux-None-None]
3 failed, 8 deselected in 0.19s
```

## Hermes focused fixed suite

```text
...........                                                              [100%]
11 passed in 0.34s
```

## Hermes BATS

```text
1..17
ok 1 vectordb ApplicationSet is hub-scoped without an app-cluster selector
ok 2 vectordb uses the pinned pgvector pg17 image and not latest
ok 3 vectordb defines no Role, RoleBinding, or ClusterRole
ok 4 vectordb destination and manifests use namespace vectordb, never default
ok 5 vectordb credentials use secretKeyRef and never plaintext trust auth
ok 6 vectordb ExternalSecret uses vault-backend and vectordb/postgres
ok 7 vectordb destination is permitted by the platform AppProject
ok 8 vectordb Application template enables server-side diff
ok 9 vectordb ApplicationSet retains server-side apply and masks no differences
ok 10 the ESO Vault policy grants the prefix the vectordb ExternalSecret reads
ok 11 vectordb Vault seed function is defined
ok 12 bootstrap seeds vectordb before deploying the AppProject
ok 13 vectordb Vault seed checks for an existing secret before putting
ok 14 vectordb Vault seed sends generated credentials on stdin, not argv
ok 15 vectordb Vault seed generates the value from urandom inside remote sh
ok 16 vectordb Vault seed pins the secret KV mount on get and put
ok 17 no bare '! cmd' assertions in BATS suites (set -e ignores them)
```

## Hermes dispatcher landing

```text
scope: in-scope
target moved: +23 commits since dispatch (37eb28211ed95d8e3e179f91336bc595b163f20d..b2d54c581bfeb1daffb0ac12dcb6abae5502dd8b)
Rebasing (1/1)
Successfully rebased and updated refs/heads/task/v1.43.9/hermes-launchagent-keychain-ssh.
tests: passed
landed: hermes-launchagent-keychain-ssh
push: git -C /Users/cliang/src/gitrepo/personal/k3d-manager push origin k3d-manager-v1.43.9
```

## Hermes post-rebase Python and Ruff gates

```text
........................................................................ [ 19%]
........................................................................ [ 39%]
........................................................................ [ 58%]
........................................................................ [ 78%]
........................................................................ [ 97%]
.........                                                                [100%]
369 passed in 19.20s
All checks passed!
```

## Final Plans P3 review and landing

Resume 3 completed on confirmed GPT-6-Luna. The coordinator removed a fixture
test that copied the intended display conditional and added actual Prometheus
engine checks inside the existing test suite. Nine lifecycle cases cover stale
landed proposed/ready/in-progress, current landed implemented, awaiting land,
refused, failed, running, and no-ledger rows, in Auto and Manual modes. Extra
repo/release series must be excluded; expected rows preserve all source labels.
Both query tests fail on the original dashboard and pass on the replacement.

Promtool 3.2.1 was downloaded from the official Prometheus GitHub release into
/private/tmp for isolated evaluation; no live Prometheus connection or service
change. The new engine tests skip explicitly if promtool is unavailable; this
verification supplies PROMTOOL and executes both, with no skips.

Five-file scope remains in-scope. Exporter contract is unchanged. Fixed widths
are 1,312 px; only one Verified column remains. Implementation `608b90a1` landed
through the dispatcher after rebase and passing gates. Current P3 status is
VERIFIED offline; E3 rollout/screenshot remains pending. No PR created.

## Plans focused Python suite

```text
........................................................................ [ 64%]
.......................................                                  [100%]
111 passed in 9.24s
```

## Plans full BATS result

```text
1..38
ok 1 bug dashboard is valid JSON with uid and Prometheus datasource
ok 2 release forecast panels align by version and map dates and states
ok 3 release cadence panel names the median tag gap and explains cadence
ok 4 target state names the blocked milestone and reason
ok 5 remaining releases table shows a not-before column
ok 6 bug dashboard has a release variable
ok 7 bug dashboard has a repo variable and scopes every bug selector
ok 8 bug dashboard has a verified filter
ok 9 bug dashboard defaults to Auto current release and keeps Manual selection
ok 10 Auto bug filtering follows the repo-scoped current-release metric
ok 11 release dropdown and table use version-order labels
ok 12 Auto and Manual modes filter every filed-in bug summary and the table
ok 13 release summary tiles follow mode while repository-wide tiles do not
ok 14 bug dashboard separates filed-in and fixed-in release views
ok 15 every bug metric queried by dashboard is emitted
ok 16 bug dashboard panels have non-overlapping positions inside 24 columns
ok 17 release forecast sits between the plan tiles and the Plans table, and lists only unshipped milestones for the selected release
ok 18 plan names link to the plan doc on the scanned branch, and bug tiles say bugs
ok 19 bug dashboard release plans row shows joined plan state without not-started inference
ok 20 bug dashboard Plans table orders plans numerically and shows dependencies
ok 21 bug dashboard bar charts blank the labels of empty segments
ok 22 bug dashboard pins one colour per priority and state, independent of data order
ok 23 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 24 open bugs table links each title to its doc on the scanned branch
ok 25 bug dashboard separates verified and live-verified summary and table
ok 26 Verified column reads verified, and only Live-verified reads live
ok 27 open bugs table sorts by sort_key before hiding it
ok 28 open bugs table sits in row 22 under the stats, with the time series moved below
ok 29 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 30 open bugs table shows age in days, not a duration that rolls up to weeks
ok 31 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 32 bugs table pairs each verification column with its timestamp
ok 33 Plans Dispatch links to the release in Agent dispatch
ok 34 priority tiles say they count open bugs
ok 35 bugs table columns fit a laptop-width panel without horizontal scrolling
ok 36 plans table columns fit a laptop-width panel without horizontal scrolling
ok 37 remaining releases table shows forecast dates only and fits a laptop-width panel
ok 38 Plans table retains the original single verification column and dispatch labels
```

## Plans dispatcher landing

```text
scope: in-scope
target moved: +3 commits since dispatch (a1ba5bf18748b9c57df2175e371412aa3787b922..459f42d8691447a7d85dbb459711a5fae52bb8c2)
Rebasing (1/1)
Successfully rebased and updated refs/heads/task/v1.43.9/plans-dispatch-status-reconcile-luna.
tests: passed
landed: plans-dispatch-status-reconcile-luna
push: git -C /Users/cliang/src/gitrepo/personal/k3d-manager push origin k3d-manager-v1.43.9
```

## Plans post-rebase gates

```text
........................................................................ [ 64%]
.......................................                                  [100%]
111 passed in 10.81s
All checks passed!
1..38
ok 1 bug dashboard is valid JSON with uid and Prometheus datasource
ok 2 release forecast panels align by version and map dates and states
ok 3 release cadence panel names the median tag gap and explains cadence
ok 4 target state names the blocked milestone and reason
ok 5 remaining releases table shows a not-before column
ok 6 bug dashboard has a release variable
ok 7 bug dashboard has a repo variable and scopes every bug selector
ok 8 bug dashboard has a verified filter
ok 9 bug dashboard defaults to Auto current release and keeps Manual selection
ok 10 Auto bug filtering follows the repo-scoped current-release metric
ok 11 release dropdown and table use version-order labels
ok 12 Auto and Manual modes filter every filed-in bug summary and the table
ok 13 release summary tiles follow mode while repository-wide tiles do not
ok 14 bug dashboard separates filed-in and fixed-in release views
ok 15 every bug metric queried by dashboard is emitted
ok 16 bug dashboard panels have non-overlapping positions inside 24 columns
ok 17 release forecast sits between the plan tiles and the Plans table, and lists only unshipped milestones for the selected release
ok 18 plan names link to the plan doc on the scanned branch, and bug tiles say bugs
ok 19 bug dashboard release plans row shows joined plan state without not-started inference
ok 20 bug dashboard Plans table orders plans numerically and shows dependencies
ok 21 bug dashboard bar charts blank the labels of empty segments
ok 22 bug dashboard pins one colour per priority and state, independent of data order
ok 23 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 24 open bugs table links each title to its doc on the scanned branch
ok 25 bug dashboard separates verified and live-verified summary and table
ok 26 Verified column reads verified, and only Live-verified reads live
ok 27 open bugs table sorts by sort_key before hiding it
ok 28 open bugs table sits in row 22 under the stats, with the time series moved below
ok 29 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 30 open bugs table shows age in days, not a duration that rolls up to weeks
ok 31 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 32 bugs table pairs each verification column with its timestamp
ok 33 Plans Dispatch links to the release in Agent dispatch
ok 34 priority tiles say they count open bugs
ok 35 bugs table columns fit a laptop-width panel without horizontal scrolling
ok 36 plans table columns fit a laptop-width panel without horizontal scrolling
ok 37 remaining releases table shows forecast dates only and fits a laptop-width panel
ok 38 Plans table retains the original single verification column and dispatch labels
```

## Plans actual-query pre-fix regression output

```text
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_vectordb_bug_metrics.py::test_release_plans_query_evaluates_lifecycle_fixtures[0]
FAILED scripts/tests/bin/test_vectordb_bug_metrics.py::test_release_plans_query_evaluates_lifecycle_fixtures[1]
2 failed, 109 deselected in 0.61s
```
