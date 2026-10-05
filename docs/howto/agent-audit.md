# Agent audit and hermetic tests

When a commit is refused by the pre-commit hook, read the file and rule named in the refusal before
changing anything. The hook audits staged content, so the result describes what would be committed,
not an unrelated working-tree file.

The checks are:

| Staged files | Checks |
| --- | --- |
| Python test files | No deleted test function, assertion, or `self.assert…` line; no deleted test file |
| Python files | Staged syntax compiles; non-test code has no `shell=True`, `eval(`, `exec(`, `"sudo"`, or sensitive command flags |
| `*.bats` | No lost `@test` block or assertion |
| `*.sh` | Function `if` count stays within the limit; no bare `sudo`; no tab indentation |
| Any file | No inline credentials in `kubectl exec` |
| `*.yaml`, `*.yml` | No hardcoded IPv4 address outside the allowlist |

A Python file is a `.py` file or an extensionless file whose first line has a Python shebang. A
Python test is selected by the default `*/tests/*`, `test_*.py`, or `*_test.py` patterns. The audit
also has an opt-in AI lint for its configured file globs.

Read a refusal literally: the path identifies the staged file, the rule identifies the check, and
the surrounding message explains the permitted remedy. A deliberate Python exception can be marked
on the same line, with a reason:

```python
subprocess.run(cmd, shell=True)  # agent-audit: allow shell-true fixed command from trusted input
```

The rule names are `shell-true`, `eval`, `exec`, `sudo`, and `sensitive-flag`. A marker without a
reason is not an exemption. Shell code that deliberately uses remote sudo has its separate
`# agent-audit: remote-sudo` marker.

The local `scripts/lib/agent_rigor.sh` is a shim to lib-foundation. Changes to the audit itself go to
lib-foundation first; k3d-manager receives them with a subtree pull. Do not edit the shim or bypass
the hook to hide a finding.

## Hermetic Python tests

Pytest runs with an autouse guard in `scripts/tests/conftest.py`. It has three rules:

1. Calls to real host executables such as `security`, `kubectl`, `gh`, `docker`, `ssh`, and `scp`
   are blocked unless the resolved executable is a test or tripwire stub.
2. Remote Git operations (`fetch`, `pull`, `push`, `clone`, and `ls-remote`) are blocked for remote
   URLs; local temporary repositories remain allowed.
3. IPv4 and IPv6 socket connections must be loopback; Unix sockets are allowed.

The refusal names the test, command, and rule, for example:

```text
hermetic: scripts/tests/bin/test_example.py::test_keychain called real 'security' (executable) — stub it, or put a stub in tmp_path
```

The default is `K3DM_HERMETIC=enforce`. `K3DM_HERMETIC=report` records violations and prints their
node IDs at the end of the run; `K3DM_HERMETIC=off` disables the guard. Use
`@pytest.mark.external(reason="...")` only when the test's purpose is a deliberate live call, and
list that reason in the review. The existing `scripts/tests/tripwire.sh` still supplies PATH shims
for the broader offline suite. Tripwire and the hermetic guard complement each other: the guard also
catches bare pytest runs, absolute executable paths, sockets, and remote Git.

`make lint-python` runs the pinned Ruff pyflakes rules over tracked `.py` files and tracked Python
shebang scripts. `make validate-manifests` runs strict kubeconform validation, including the pinned
custom-resource catalog. CI runs both after the pytest suites.

`--no-verify` is operator-only. An agent must fix the underlying finding and keep the hook active.
