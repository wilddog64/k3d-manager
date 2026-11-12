# Bug: pre-commit Priority check rejects large new bug docs that carry a valid Priority line

**Status:** OPEN — captured 2026-11-12
**Priority:** P3
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (The pre-commit hook falsely blocks committing large new bug documentation files with a valid Priority line due to SIGPIPE under `pipefail`, degrading the commit workflow with a two-step commit workaround.)
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** `edfc9a5c` (2026-10-11, the Priority check in `.githooks/pre-commit`)
**Should have been caught by:** offline test
**Prior art:** none above threshold — exact-slug glob empty; grep of `docs/bugs/` for pre-commit plus pipefail found only unrelated docs; `make find-similar-docs` not run
**Approval:** none (captured only)
**Filed:** 2026-11-12
**Detected by:** Claude, 2026-11-12, committing the two wave 1 batch specs

## Symptom

`git commit` of a new `docs/bugs/*.md` fails with
`Pre-commit hook: <doc> needs **Priority:** P0/P1/P2/P3` although line 4 is `**Priority:** P2`.
Seen on the deploy/hub batch spec (27,248 bytes) and the test-hygiene batch spec (42,977 bytes).

## Evidence

M4 laptop, 2026-11-12, run 5 times per file, each rc 141 (SIGPIPE):

    bash -c 'set -o pipefail; git show ":<doc>" | /usr/bin/grep -Eq "^\*\*Priority:\*\* P[0-3]\b"; echo $?'

The same pipe without `pipefail`, or `grep -Ec` (which reads to the end), returns a match.

## Root cause

`.githooks/pre-commit:14` runs `git show ":${bug_doc}" | grep -Eq ...` under `set -euo pipefail` (line 2). `grep -q`
exits at the first match near the top of the file; `git show` is still writing, dies of SIGPIPE, and `pipefail`
makes the pipeline fail, so the `if !` branch reports a missing Priority. Small docs fit in one write and pass.

## Workaround

Commit the new doc's header first (small enough to pass), then the full text as a modification: the check only
looks at added files (`--diff-filter=A`). Used for the two wave 1 batch specs on 2026-11-12.
