# Copilot review findings — PR #50

**PR:** [#50](https://github.com/wilddog64/lib-foundation/pull/50) — `fix(acg): dead identity host, profile split-brain, and a destructive STS probe`
**Date:** 2026-09-12
**Findings:** 1 (valid)

## Finding 1 — `CHANGE.md`: malformed block reintroducing a disproven root cause

**Flagged:** `CHANGE.md:88`, Copilot comment `3997325491`.

Copilot reported two problems in one block, and both were real:

1. An unbulleted paragraph beginning `stop reporting \`ACG_SESSION_OK\` for a signed-out
   session.` ran on from the end of the preceding bullet, so it rendered as a continuation of
   the `sandbox.js` entry instead of its own list item.
2. Its text asserted the `Cloud Sandboxes` / `Open Sandbox` false-green explanation that the
   same section already documents as **disproven**, contradicting the CORRECTION note carried
   in the bullet at lines 17–31.

### Root cause

Not an authoring mistake — **rebase damage**. The block is the pre-correction wording of the
signed-out-detection entry, which existed only in `308bb3c` and was rewritten out in
`e547147` (`docs(bugs): correct false-green root cause`).

`fix/acg-prism-monogram-selector` was rebased onto `main` after PR #49 merged. Six of the ten
commits touch `CHANGE.md`, so the `[Unreleased]` collision recurred at **four** separate
rebase stops, each resolved by hand. One of those resolutions reinstated the superseded
`308bb3c` text and dropped both its `- ` bullet marker and the blank line before the
following `### Security` heading. The later correction commit's removal then had nothing left
to remove.

### Fix

Deleted the 12 resurrected lines and restored the blank line before `### Security`. The topic
remains covered — correctly, and with its CORRECTION — by the existing bullet at lines 17–31.

### Process note

The post-rebase "nothing was lost" check was:

```
git diff --stat backup/prism-pre-rebase HEAD -- . ':(exclude)CHANGE.md'
```

It **excluded the only file that was hand-resolved**, so it could not have caught this by
construction. A conflict-resolution audit must diff the conflicted file too, and assert the
delta equals exactly what the new base contributed:

```
git diff backup/<pre-rebase-ref> HEAD -- CHANGE.md   # expect ONLY the merged PR's own entry
```

Run that as a positive assertion, not as a scan for surprises. Excluding a file because it
was expected to change is how an unexpected change inside it stays invisible.
