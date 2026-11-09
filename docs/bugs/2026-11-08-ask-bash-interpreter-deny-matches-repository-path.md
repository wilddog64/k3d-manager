# Bug: ask-bash refuses a read when the repository path contains an interpreter name

**Status:** VERIFIED — `b98cff7e`, independent verifier from Acceptance only, 2026-11-09
**Priority:** P3
**Introduced by:** f68bdee1 (2026-08-03, the interpreter deny line)
**Should have been caught by:** offline test
**Prior art:** not run (`make find-similar-docs` could not reach its vector store from the M4, 2026-11-08); exact-slug glob found nothing; read `docs/bugs/2026-10-08-ask-bash-shell-string-bypasses-path-scope.md`, a different defect in the same file
**Severity:** low — tests only in practice; `/ask` runs from the main checkout, whose path has no such word
**Approval:** operator, 2026-11-08 ("go ahead to file a P3 bug and dispatch to Luna")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** Claude, comparing wide test suites for the alert_delivery fix, 2026-11-08
**Affected:** `bin/k3dm-ask-bash`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

`scripts/tests/bin/ask_bash_scope.bats` tests 2 and 4 fail in a dispatch worktree whose slug contains `python`, such as
`...-probe-uses-python-without-pyyaml`. The command `cat <repo>/README.md` is refused with `Blocked`.

Measured on the M4, 2026-11-08, running `bin/k3dm-ask-bash -c "cat <dir>/README.md"` with `K3DM_REPO_ROOT=<dir>`:
a 123-character path with no keyword exited 0; an 82-character path containing `uses-python-without` exited 1.

## Root cause

`bin/k3dm-ask-bash:91` matches `\b(python[0-9.]*|perl|ruby|node|...)\b` against the whole command string, so an
interpreter name inside the trusted repository path counts as running that interpreter. `\b` treats `-` and `/` as
boundaries.

## Fix

In `bin/k3dm-ask-bash`, on the interpreter deny check at line 91 only, match against a copy of `CMD` with each trusted
root removed:

    _interp_scan="${CMD//"${K3DM_REPO%/}/"/}"
    _interp_scan="${_interp_scan//"${SHOPPING_CARTS_ROOT%/}/"/}"

Then test `_interp_scan` in place of `$CMD` on that line. Keep the trailing `/` and the quotes on the pattern:

- The trailing `/` means a sibling path that only starts with the root is not stripped: with root `/a/python`, the
  program `/a/python3` still reads `python3` and is denied.
- The quotes make the root a literal, so a `*` in it is not a glob.
- Only the root prefix goes. `<repo>/venv/bin/python` still reads `/venv/bin/python` and is denied.

Tests go in `scripts/tests/bin/ask_bash_scope.bats`. Set `K3DM_REPO_ROOT` to a directory under `TEST_ROOT` whose name
contains `python`, so the tests do not depend on where the checkout lives.

## Files

- `bin/k3dm-ask-bash`
- `scripts/tests/bin/ask_bash_scope.bats`

## Do not

- Change the interpreter list or any other deny pattern. The destructive-command and editor checks have the same
  whole-string behaviour; leave them alone.
- Remove or weaken the `sandbox-exec` path or the per-argument scope checks.
- Try to detect "command position" in the string. Shell strings make that unreliable, and this is a security check.
- Use an unquoted pattern, or drop the trailing `/`.

## Contract readers

No shared contract changes: the script's arguments, environment and exit codes stay the same. Callers found by
`git grep k3dm-ask-bash`: `bin/k3dm-webhook` and `scripts/lib/webhook/agent.py`, neither changes.

## Proof of external behaviour

The script runs under `#!/bin/bash`, which is bash 3.2 on macOS. Probed on the M4, 2026-11-08, GNU bash 3.2.57:
`R="/a/py*thon"; C="cat /a/py*thon/x /a/pyZthon/y /a/py*thon3"; P="${R%/}/"; echo "${C//"$P"/}"` printed
`cat x /a/pyZthon/y /a/py*thon3`, so the quoted pattern is literal and a sibling path is left alone.

## Acceptance

```yaml
must:
  - id: M1
    text: "with K3DM_REPO_ROOT at a directory whose name contains python, reading a file inside it through ask-bash exits 0 and prints the file"
  - id: M2
    text: "the same holds for a file under K3DM_SHOPPING_CARTS_ROOT at a directory whose name contains node"
must_not:
  - id: N1
    text: "with that same K3DM_REPO_ROOT, a command that runs python3 is allowed (paired with M1)"
  - id: N2
    text: "a program inside the root named python3, given by its full path, is allowed"
  - id: N3
    text: "a program beside the root whose path merely starts with the root's text (root /x/python, program /x/python3) is allowed"
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    intent: "tests run the real ask-bash against scratch repositories with interpreter names in their folder names: reading a file there now works, while running python, directly or from a path inside or beside that folder, is still refused"
interface:
  - "bin/k3dm-ask-bash -c COMMAND, with HOME, K3DM_REPO_ROOT and K3DM_SHOPPING_CARTS_ROOT set by the caller"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (for N3, drop the trailing `/`), run its test, show it
   red, then restore the guard and show it green. List any `must_not` whose test stayed green with the guard broken.
3. Where the spec allows a read-only run against real data, run the changed code once that way and paste what it
   printed. Otherwise say "no read-only real-data run possible" and why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## Notes

- No live evidence: the change is covered by running the real script, and `/ask` from the main checkout is unaffected.
- `ask_bash_scope.bats` test 1 also fails when the checkout lives in the scratchpad. That was not traced and is out of
  scope here.
