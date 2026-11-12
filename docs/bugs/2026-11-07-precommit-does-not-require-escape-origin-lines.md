# Bug: pre-commit does not require the escape-origin lines on new bug docs

**Status:** OPEN — specced 2026-11-07; queued for a P3 batch under the dispatch WIP limit
**Priority:** P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (Pre-commit lint gap for required metadata lines on new bug documentation is repository hygiene with no runtime or functional impact); Claude proposed P3. Agreed.
**Triage:** passed over (v1.43.16 was not cut; this does not count as a pass-over: it was picked 2026-11-09) — grooming 2026-11-12, operator.
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** pre-existing (the rule is new on 2026-11-07; nothing enforces it yet)
**Should have been caught by:** none
**Severity:** low — without enforcement, the new `Introduced by` and `Should have been caught by` lines will be skipped, and the per-release escape counts in the retro will be incomplete
**Approval:** operator, 2026-11-07 (chose "1 Escape origin" among the rules to adopt; the check was proposed with it as a P3)
**Assigned:** unassigned (P3 batch)
**Filed:** 2026-11-07
**Detected by:** Claude, writing the escape-origin rule into the shared `bug-priority` block of `CLAUDE.md`, `AGENTS.md` and `GEMINI.md`
**Affected:** `.githooks/pre-commit` (new-bug-doc check, `:10-19`)
**Branch:** `k3d-manager-v1.43.16` (operator, 2026-11-09)

## Observed failure

The shared `bug-priority` block now requires every bug filed from 2026-11-07 to carry two lines:
- `**Introduced by:** <commit or release | pre-existing | unknown>`
- `**Should have been caught by:**` one of `spec`, `offline test`, `review`, `deploy step`, `live check`, `none`

`.githooks/pre-commit:10-19` checks only `**Priority:**` on newly added `docs/bugs/*.md`. A new bug doc without the two
lines commits cleanly.

## Root cause

The rule was written on 2026-11-07, and the hook was not extended with it.

## Fix

1. In `.githooks/pre-commit`, inside the existing loop over newly added bug docs (`--diff-filter=A`), also require:
   - a line matching `^\*\*Introduced by:\*\* \S`;
   - a line matching `^\*\*Should have been caught by:\*\* (spec|offline test|review|deploy step|live check|none)\b`.
   A missing or invalid line fails the commit. The message names the file and the line it needs, and lists the six
   allowed values, in the same style as the Priority message.
2. Only newly added bug docs are checked, exactly as for Priority. Edits to existing docs are never blocked.
3. Add tests to `scripts/tests/plugins/precommit_bug_priority.bats` next to the Priority tests.

## Files

- `.githooks/pre-commit`
- `scripts/tests/plugins/precommit_bug_priority.bats`

## What NOT to do

- Do not check docs that are only modified, not added; there are hundreds of legacy bug docs without these lines.
- Do not change the Priority check or its message.
- Do not edit any existing `docs/bugs/` doc.
- Do not run git add, commit or push, and do not touch `memory-bank/`.

## Acceptance

```yaml
must:
  M1: committing a new docs/bugs/*.md without an Introduced by line, or without a valid Should have been caught by line, fails with a message naming the file and the missing line
  M2: a new bug doc with Priority, Introduced by and a valid Should have been caught by value commits
must_not:
  N1: a modified (not added) bug doc without the two lines never fails the hook (paired control for M1)
  N2: a Should have been caught by value outside the six allowed values never passes
  N3: the existing Priority check's behaviour and message never change
evidence:
  E1:
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    intent: >-
      You will see precommit_bug_priority.bats create a scratch git repo with the hook, stage an added bug doc missing
      each line in turn, one with an invalid value, one complete, and a modified legacy doc, and assert the exit code
      and message of each. The M1 and N2 assertions are red on the pre-fix hook.
    what: bats scripts/tests/plugins/precommit_bug_priority.bats
interface:
  - .githooks/pre-commit (run against a scratch repo's staged files)
```
