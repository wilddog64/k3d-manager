# Bug fix: land writes the plan's Status; pre-commit refuses a DRAFT plan with approved intent

**Filed:** 2026-11-19
**Status:** VERIFIED — ffe30f17, 2026-11-19 (Sonnet Acceptance verifier + Claude: 38 bats + 11 pytest, pre-fix 6 red, 6/6 mutants red). Offline-only; first live use is the next land after a promote.
**Bug:** `docs/bugs/2026-11-19-plan-status-goes-stale-after-review-and-land.md` (P3)
**Branch:** `k3d-manager-v1.45.0` (operator promoted it out of the P3 batch; lands with the open release)
**Risk:** low-medium — touches `land`; the new write happens only after a successful merge and never blocks the land
**Implementer:** Luna (Codex). **Verifier:** Claude.
**Intent approved:** operator, 2026-11-19
Intent note: Claude proposed "1: dispatch tool writes the status; 2: commit check for impossible combinations"; operator replied "file one and go with your suggestion".

## Change

### 1. `land` writes the plan's Status (`bin/k3dm-codex-dispatch`, `_dispatch_land`)

Add `_dispatch_mark_plan_landed "$run" "$land_commit" "$repo_path"` and call it as the **last** step of `_dispatch_land`,
after `: >"$run/landed"` (`:1551`) and before the `echo "landed: $slug"` line, as `_dispatch_mark_plan_landed … || true`.
The land is complete before it runs; nothing in it may change the exit status of `land`.

Skip silently (no output, no change) when any of these holds:
- `--review-pending` was passed. `bin/k3dm-codex-land-pending` writes its own `LANDED — Claude review pending` line
  (`_lp_mark_status`, `bin/k3dm-codex-land-pending:22-31`) from `git rev-parse --short HEAD` after land (`:97`); an extra
  commit from land would make it record the docs commit instead of the code commit.
- the run is a review or verify child (`role` recorded as `review` or `verify` for the slug in the ledger `start`/`link`
  events; use the same lookup as the existing ledger reader at `:497-499`).
- `$run/spec` is not a direct child of `docs/plans/` with suffix `.md` (bug docs used as specs and review briefs are out
  of scope).

Otherwise, with `root="$_dispatch_repo_root"` (`:7-8`, the k3d-manager checkout; land is run from it) and
`spec="$(<"$run/spec")"`:
1. `git -C "$root" ls-files --error-unmatch -- "$spec"` must succeed, else print
   `land: plan status not updated (spec not tracked in <root>); set it by hand` and return 0.
2. Refuse (same message shape, reason named) when `git -C "$root" diff --quiet -- "$spec"` or
   `git -C "$root" diff --cached --quiet -- "$spec"` fails, or any of `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `rebase-merge`,
   `rebase-apply` exists under `git -C "$root" rev-parse --git-dir`.
3. Find the first `**Status:**` line before the first `## ` heading. None → return 0, no output (the BATS fixture spec
   `scripts/tests/bin/codex_dispatch_helpers.bash:31-44` has none, so existing land tests see no new commit).
4. Match the value case-insensitively against
   `^(DRAFT|PLANNED|PLAN|PROPOSED|READY|APPROVED|IN PROGRESS|IN-PROGRESS|DISPATCHED|QUEUED)(\s+(rev\s*)?v?\d+)?\s*([—–:.-]\s*)?`.
   On a match, the new value is `LANDED — <ref> (auto: land <YYYY-MM-DD>; verify pending)` followed by `; ` and the
   unmatched remainder if non-empty. `<ref>` is the 8-character land commit; for a `--repo` dispatch,
   `<repo-name>@<ref>` (repo name from `$run/repo-name`).
   - A value already starting `LANDED — ` and containing `(auto: land ` is rewritten the same way (new ref and date,
     remainder after the old `)` kept), so a superseding land replaces the old SHA.
   - Any other value: print `land: plan status left as <first word>` and return 0.
5. Write the file, then `git -C "$root" commit -q --only -m "docs(plans): $slug landed <ref>" -- "$spec"`: single-line
   message, no trailer, normal hooks. If the commit fails, restore the file with
   `git -C "$root" checkout -- "$spec"` and print `land: plan status not updated (commit failed); set it by hand`.
   No push. On success print `land: plan status set LANDED in <spec>`.

### 2. Pre-commit refuses a DRAFT plan with approved intent (new `scripts/check-plan-status.py`, `.githooks/pre-commit`)

Mirror `scripts/check-bug-status.py` and its hook block (`.githooks/pre-commit:88-103`) for staged plan docs, bypass
`K3DM_SKIP_PLAN_STATUS=1`, hook pathspec `':(glob)docs/plans/*.md'` (direct children only).

`check-plan-status.py` normalises each argument to a path relative to `git rev-parse --show-toplevel` and ignores anything
that is not a direct child of `docs/plans/` with suffix `.md`. It reads the header (text before the first `## `):
- Status: the first `**Status:**` value; first word compared case-insensitively.
- Intent approved: true when the header matches
  `(?mi)^\*\*Intent approved:\*\*\s*(?!no\b|pending\b)[^,\n]+,\s*\d{4}-\d{2}-\d{2}\b` (the shape
  `scripts/lib/spec_intent.py:259` accepts).

Refuse when the Status first word is `DRAFT` and intent is approved, unless HEAD has the same (first word, intent approved)
pair for that path (so existing stale files do not block unrelated edits): message
`<path>: Status DRAFT but intent is approved; a reviewed, approved spec starts READY (or IN PROGRESS / LANDED)`.

No rule on the word "landed": umbrella plans legitimately say `IN PROGRESS — Part 1 landed …`
(`docs/plans/v1.45.0-remote-promote-approval.md:3`).

## Files

- `bin/k3dm-codex-dispatch`
- `scripts/check-plan-status.py` (new)
- `.githooks/pre-commit`
- `scripts/tests/bin/codex_dispatch_land.bats`
- `scripts/tests/bin/test_check_plan_status.py` (new)
- `docs/process/rules.md` (one line under the Status-first-word rule: land writes plan Status; pre-commit guards DRAFT+approved)

## Contract readers

- Plan `**Status:**` first word:
  - `bin/k3dm-vectordb-metrics:264` (`_plan_state`), `:388-393` (spec blocker), `:511-536` (blockers; `LANDED` makes the
    plan `implemented`, not dispatchable, and satisfies dependents at `:520`). Intended; no change.
  - `bin/k3dm-dispatch-metrics:346-415` (`_verified_specs`) counts `+**Status:**` transitions to `LANDED` in
    `git log -p -- docs/plans` as unverified closures. The auto line says `verify pending`, which is accurate; no change.
- Writer: `bin/k3dm-codex-land-pending:22-31,95-105` (`_lp_mark_status` after `land --review-pending`). Unchanged; land
  skips its own write under `--review-pending`, so land-pending still records the code commit.
- `scripts/lib/spec_intent.py:251-261` reads `**Intent approved:**`; read only.
- `codex-dispatch start` records `spec-sha256` at start; a landed run cannot be resumed, so the post-land rewrite does
  not trip it.

## What NOT to Do

- Do not let any plan-status step fail, undo, or reorder the land; it runs after `$run/landed` exists.
- Do not push from land, and do not commit any file other than the one spec.
- Do not touch `bin/k3dm-vectordb-metrics`, `bin/k3dm-dispatch-metrics` or `bin/k3dm-codex-land-pending`.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "land of a dispatch whose docs/plans spec Status is 'DRAFT v5 — notes' or 'ready — notes' rewrites it to 'LANDED — <8-char sha> (auto: land <date>; verify pending); notes' in one commit touching only that spec, after the landed marker exists, and prints 'landed: <slug>'"
  - id: M2
    text: "land with Status LANDED (not auto), VERIFIED or SUPERSEDED leaves the file unchanged and prints 'plan status left as <word>'; an auto LANDED line is rewritten with the new sha (superseding)"
  - id: M3
    text: "spec dirty in worktree, dirty in index, untracked, or commit failing (hook stub exits 1): prints 'land: plan status not updated (<reason>); set it by hand', land exits 0, task merged, worktree removed, landed marker present, and the spec file is clean afterwards"
  - id: M4
    text: "a --repo dispatch writes '<repo-name>@<sha>' and commits in the k3d-manager checkout; the target repo gets no extra commit"
  - id: M5
    text: "land --review-pending, a review/verify child, a docs/bugs spec, and a spec without a Status line each produce no status commit and no status output (existing land tests keep HEAD == task head)"
  - id: M6
    text: "pre-commit refuses a staged new plan with Status DRAFT and '**Intent approved:** operator, 2026-11-19'; refuses an existing DRAFT plan whose commit adds that approval; accepts the same file with Status READY (positive control); accepts an edit to a file whose HEAD already had DRAFT+approved; ignores 'pending' and 'no — reason'; K3DM_SKIP_PLAN_STATUS=1 bypasses"
must_not:
  - id: N1
    text: "land leaves an approved docs/plans spec's DRAFT/READY Status unchanged (red on 490d8cd2: no status write exists)"
  - id: N2
    text: "pre-commit accepts a new DRAFT plan with approved intent (red on 490d8cd2: no plan check exists)"
  - id: N3
    text: "pre-commit refuses an umbrella edit 'IN PROGRESS — Part 1 landed …' with approved intent (paired with N2's refusal)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N3]
    kind: offline
    command: "bats scripts/tests/bin/codex_dispatch_land.bats scripts/tests/bin/codex_dispatch_cross_repo.bats scripts/tests/bin/codex_land_pending.bats; python3 -m pytest scripts/tests/bin/test_check_plan_status.py; new tests red on 490d8cd2; mutants red: remove the call (N1), drop '|| true' and make the commit fail (M3), drop the restore after a failed commit (M3 clean), drop the --review-pending skip (M5 / land-pending sha), drop the intent condition (M6), drop the HEAD-pair comparison (M6 existing-file case); shellcheck clean"
    intent: When a dispatch lands, its plan flips to LANDED by itself, and you can no longer commit a plan marked draft after you approved it, so the dashboard stops showing finished or approved plans as unreviewed.
interface:
  - "land: plan status not updated (<reason>); set it by hand"
  - "land: plan status left as <word>"
  - "land: plan status set LANDED in <spec>"
  - "LANDED — <ref> (auto: land <YYYY-MM-DD>; verify pending)"
  - "K3DM_SKIP_PLAN_STATUS=1"
```
