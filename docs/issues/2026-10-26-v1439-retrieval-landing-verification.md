# v1.43.9 retrieval landing verification

**Date:** 2026-10-26
**Status:** Scoped gates passed; broad runs failed for the reasons below, focused rechecks passed.
**Implementation:** `b133f53e61d0b64aa55bb805bb369f91f2babffe`
**PR URL:** none (no PR created).

## What was attempted

Reviewed the exited worker on m4-air, corrected the unused import and the bare-negation
assertion in the touched BATS suite, added index-refresh failure-isolation coverage,
ran the scoped gates, exercised the C2 mutation, and ran the curated full BATS bundle
twice. Live store/embeddings/cluster verification was skipped as specified by E2 ownership.

## Actual initial lint output

```text
F401 [*] `hermes.prior_art.search` imported but unused
  --> scripts/tests/bin/test_find_similar_docs.py:18:59
Found 1 error.
[*] 1 fixable with the \`--fix\` option.
```

Root cause: the worker moved live ranking but left its old import. Removed it.
Final Ruff output: `All checks passed!`

## Full bundle, default Python 3.15

Command: `PATH=/opt/homebrew/bin:$PATH ./scripts/k3d-manager test all`

Failure excerpts verbatim; counts computed from the retained full TAP log:

```text
running under bash version 5.3.20(1)-release
1..1884

not ok 63 no bare '! cmd' assertions in BATS suites (set -e ignores them)
# (in test file scripts/tests/lib/bats_negation_lint.bats, line 6)
#   `[ "$status" -ne 0 ]' failed
not ok 470 smoke test ESO wiring samples app and hub through helper
# (in test file scripts/tests/lib/webhook_hub_eso.bats, line 155)
#   `[ "$status" -eq 0 ]' failed
not ok 957 dispatch refuses to run and never falls back locally when preflight fails
# (in test file scripts/tests/plugins/e2e_remote.bats, line 306)
#   `[[ "$output" == *"status=busy"* ]]' failed
not ok 969 dispatch returns the remote exit code unchanged
# (in test file scripts/tests/plugins/e2e_remote.bats, line 521)
#   `[ "$status" -eq 7 ]' failed
not ok 993 dispatch refuses and never falls back locally when the lock is held
# (in test file scripts/tests/plugins/e2e_remote.bats, line 838)
#   `[[ "$output" == *"busy"* ]]' failed
not ok 994 dispatch chains publish-back after the E2E and preserves the exit code
# (in test file scripts/tests/plugins/e2e_remote.bats, line 851)
#   `[ "$status" -eq 0 ]' failed
Recorded ok lines: 1878
Recorded not ok lines: 6
```

## Full bundle, Python 3.14 on PATH

Command: `PATH=/private/tmp/k3dm-v1439-python314:/opt/homebrew/bin:$PATH ./scripts/k3d-manager test all`

```text
running under bash version 5.3.20(1)-release
1..1884

not ok 957 dispatch refuses to run and never falls back locally when preflight fails
# (in test file scripts/tests/plugins/e2e_remote.bats, line 306)
#   `[[ "$output" == *"status=busy"* ]]' failed
not ok 969 dispatch returns the remote exit code unchanged
# (in test file scripts/tests/plugins/e2e_remote.bats, line 521)
#   `[ "$status" -eq 7 ]' failed
not ok 993 dispatch refuses and never falls back locally when the lock is held
# (in test file scripts/tests/plugins/e2e_remote.bats, line 838)
#   `[[ "$output" == *"busy"* ]]' failed
not ok 994 dispatch chains publish-back after the E2E and preserves the exit code
# (in test file scripts/tests/plugins/e2e_remote.bats, line 851)
#   `[ "$status" -eq 0 ]' failed
Recorded ok lines: 1880
Recorded not ok lines: 4
```

Root causes:
- The old VectorDB assertion used bare `! grep`, rejected by the repository lint.
  Corrected within the touched suite; guard plus VectorDB recheck passed 18/18.
- Python 3.15 removed `SourceFileLoader.load_module`, still used by the unrelated
  webhook ESO test. Actual output:

```text
AttributeError: 'SourceFileLoader' object has no attribute 'load_module'. Did you mean '.exec_module' instead of '.load_module'?
```

  Python 3.14 recheck passed 6/6 without changing webhook code.
- Four remote-dispatch tests require a pushed HEAD, so their preflight failed on
  the unpushed task commits. Reproduced on the release checkout before synchronization:

```text
1..4
not ok 1 dispatch refuses to run and never falls back locally when preflight fails
# (in test file scripts/tests/plugins/e2e_remote.bats, line 306)
#   `[[ "$output" == *"status=busy"* ]]' failed
# Last output:
# ERROR: [e2e-remote] HEAD 2a729c118145dc4aa31df4429500b89ec5a764a6 is not pushed; push the branch first
not ok 2 dispatch returns the remote exit code unchanged
# (in test file scripts/tests/plugins/e2e_remote.bats, line 521)
#   `[ "$status" -eq 7 ]' failed
# Last output:
# ERROR: [e2e-remote] HEAD 2a729c118145dc4aa31df4429500b89ec5a764a6 is not pushed; push the branch first
not ok 3 dispatch refuses and never falls back locally when the lock is held
# (in test file scripts/tests/plugins/e2e_remote.bats, line 838)
#   `[[ "$output" == *"busy"* ]]' failed
# Last output:
# ERROR: [e2e-remote] HEAD 2a729c118145dc4aa31df4429500b89ec5a764a6 is not pushed; push the branch first
not ok 4 dispatch chains publish-back after the E2E and preserves the exit code
# (in test file scripts/tests/plugins/e2e_remote.bats, line 851)
#   `[ "$status" -eq 0 ]' failed
# Last output:
# ERROR: [e2e-remote] HEAD 2a729c118145dc4aa31df4429500b89ec5a764a6 is not pushed; push the branch first
```

  The shared release branch had diverged. Initial push output:

```text
 ! [rejected]          k3d-manager-v1.43.9 -> k3d-manager-v1.43.9 (non-fast-forward)
error: failed to push some refs to 'github.com:wilddog64/k3d-manager.git'
```

  Fetched and merged both histories without rewriting the shared branch, then pushed.
  Recheck on pushed release HEAD:

```text
1..4
ok 1 dispatch refuses to run and never falls back locally when preflight fails
ok 2 dispatch returns the remote exit code unchanged
ok 3 dispatch refuses and never falls back locally when the lock is held
ok 4 dispatch chains publish-back after the E2E and preserves the exit code
```

Full terminal logs remain on m4-air at
`/private/tmp/v1439-retrieval-test-all.log` and
`/private/tmp/v1439-retrieval-test-all-py314.log`.
Expected BATS BW02 minimum-version warning also appeared in the sandbox-preflight suite;
it did not fail a case.

## Follow-up

Modernize the legacy webhook loader in a separate scoped change for Python 3.15.
Run the full bundle from a pushed release HEAD for a single clean full-run result;
the successful focused rechecks above are not a clean full rerun.
Complete live E2 after deployment: operator dashboard screenshot plus Claude's opt-in live pytest.
