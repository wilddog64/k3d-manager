# 2026-05-30 — `scripts/tests/test_install_sudoers.bats` repo-root path mismatch

## What was tested

- `bats scripts/tests/test_install_sudoers.bats`

## Actual output

```text
1..4
not ok 1 install-sudoers.sh is executable
# (in test file scripts/tests/test_install_sudoers.bats, line 9)
#   `[[ -x "$SCRIPT" ]]' failed
not ok 2 install-sudoers.sh --help exits 0
# (in test file scripts/tests/test_install_sudoers.bats, line 14)
#   `[ "$status" -eq 0 ]' failed
not ok 3 install-sudoers.sh --dry-run validates sudoers syntax
# (in test file scripts/tests/test_install_sudoers.bats, line 20)
#   `[ "$status" -eq 0 ]' failed
ok 4 install-sudoers.sh rejects unknown arguments

The following warnings were encountered during tests:
BW01: `run`'s command `/Users/cliang/src/gitrepo/personal/bin/install-sudoers.sh --help` exited with code 127, indicating 'Command not found'. Use run's return code checks, e.g. `run -127`, to fix this message.
      (from function `run' in file /opt/homebrew/Cellar/bats-core/1.13.0/lib/bats-core/test_functions.bash, line 420,
       in test file scripts/tests/test_install_sudoers.bats, line 13)
BW01: `run`'s command `/Users/cliang/src/gitrepo/personal/bin/install-sudoers.sh --dry-run` exited with code 127, indicating 'Command not found'. Use run's return code checks, e.g. `run -127`, to fix this message.
      (from function `run' in file /opt/homebrew/Cellar/bats-core/1.13.0/lib/bats-core/test_functions.bash, line 420,
       in test file scripts/tests/test_install_sudoers.bats, line 19)
BW01: `run`'s command `/Users/cliang/src/gitrepo/personal/bin/install-sudoers.sh --bogus-flag` exited with code 127, indicating 'Command not found'. Use run's return code checks, e.g. `run -127`, to fix this message.
      (from function `run' in file /opt/homebrew/Cellar/bats-core/1.13.0/lib/bats-core/test_functions.bash, line 420,
       in test file scripts/tests/test_install_sudoers.bats, line 25)
```

## Root cause

The test harness used `BATS_TEST_DIRNAME/../../..`, which resolves one directory above the repository root in this checkout layout. That pointed `SCRIPT` at `/Users/cliang/src/gitrepo/personal/bin/install-sudoers.sh` instead of the actual repo file.

## Recommended follow-up

- Keep `REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"` in `scripts/tests/test_install_sudoers.bats` for this repository layout.
