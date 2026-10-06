# Bug: offline launchd test requires macOS `plutil` on the Ubuntu CI runner

**Filed:** 2026-10-06
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED — use Python `plistlib` and portable `script -c` syntax
**Severity:** medium. The production plist writer is not reached by the CI gate because the test exits before the remaining offline suites run.

## Symptom

The pull request lint job runs `make test-bin` on `ubuntu-latest`. The new
`Hostinger frontend plist has exactly two ProgramArguments` test fails before
it can inspect the generated plist:

```text
not ok 313 Hostinger frontend plist has exactly two ProgramArguments
# (in test file scripts/tests/bin/sandbox_launchd_scope.bats, line 146)
#   `[ "${status}" -eq 0 ]' failed
BW01: `run`'s command `plutil -extract ProgramArguments json -o - /tmp/bats-run-g87WEc/test/313/frontend-browser-http.plist` exited with code 127, indicating 'Command not found'.
make: *** [Makefile:1111: test-bin] Error 1
```

The job is configured with `runs-on: ubuntu-latest`, while `plutil` is a
macOS-only command. The failure is therefore a test portability defect, not a
failure of the generated plist contents.

## Cause and fix

The BATS test used `plutil -extract` to read `ProgramArguments`. It now uses
Python's standard-library `plistlib`, which is already required by the Python
test jobs and is available on the Ubuntu runner. The assertion still requires
the exact two-element value `["/bin/bash", wrapper]`.

The same suite also used BSD/macOS `script` argument ordering in the Keychain
and wrong-context preflight tests. Ubuntu's util-linux `script` requires the
command to be passed with `-c`, while macOS uses the positional command form.
The tests now use a small dialect-detecting helper for both forms.

The follow-up CI failure was:

```text
not ok 150 hub-restore rejects an unreadable Keychain before any make step
not ok 151 hub-restore rejects the wrong Kubernetes context before any make step
make: *** [Makefile:1111: test-bin] Error 1
```

## Validation

Run the focused BATS suites and the complete `make test-bin` suite on the fix
branch. The pull request CI run should then proceed past tests 150, 151, and
313.
