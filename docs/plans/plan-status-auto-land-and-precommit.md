# Bug fix: land writes the plan's Status; pre-commit refuses a DRAFT plan with approved intent

**Filed:** 2026-11-19
**Status:** READY — operator "file one and go with your suggestion", 2026-11-19; Argon blind review owed before dispatch
**Bug:** `docs/bugs/2026-11-19-plan-status-goes-stale-after-review-and-land.md` (P3)
**Branch:** `k3d-manager-v1.45.0` (operator promoted it out of the P3 batch; lands with the open release)
**Risk:** low-medium — touches `land`; the new write happens only after a successful merge and never blocks the land
**Implementer:** Luna (Codex). **Verifier:** Claude.
**Intent approved:** operator, 2026-11-19
Intent note: Claude proposed "1: dispatch tool writes the status; 2: commit check for impossible combinations"; operator replied "file one and go with your suggestion".

## Change

### 1. `land` writes the plan's Status (`bin/k3dm-codex-dispatch`, `_dispatch_land`)

After the fast-forward merge succeeds and the ledger `land` event is written (after `:1544`), call a new
`_dispatch_mark_plan_landed "$run" "$land_commit"`. Behaviour:

- Spec path: `$run/spec` (relative to the k3d-manager checkout that holds this script, `$K3DM_ROOT` or the script's repo root,
  for same-repo and `--repo` dispatches alike). Missing file → print `land: plan status not updated (spec not found)` and return 0.
- Only when the Status line's first word is one of `DRAFT`, `PLANNED`, `PLAN`, `PROPOSED`, `READY`, `APPROVED`,
  `IN PROGRESS`, `DISPATCHED`: replace the leading word(s) with `LANDED — <short sha> (auto: land <YYYY-MM-DD>; verify
  pending)` and keep the rest of the line after a single space. Any other first word (`LANDED`, `VERIFIED`,
  `LIVE-VERIFIED`, `SUPERSEDED`, …) → leave it, print `land: plan status left as <word>`.
- For a `--repo` dispatch, `<short sha>` is prefixed `<repo-name>@`.
- Commit only that file in the k3d-manager checkout: `git -C <root> commit --only -m "docs(plans): <slug> landed <sha>"
  -- <spec>` with the attribution footer the script already uses for its own commits, if any; otherwise
  `Co-Authored-By` is not added. If the file has uncommitted changes, or the checkout is mid-rebase/merge, or the commit
  fails, print `land: plan status not updated (<reason>); set it by hand` and return 0. No push.
- Every failure in this function is non-fatal: the land itself has already succeeded and must still print `landed:`.

### 2. Pre-commit refuses impossible plan states (new `scripts/check-plan-status.py`, `.githooks/pre-commit`)

Mirror `scripts/check-bug-status.py` and its hook block (`.githooks/pre-commit:88-103`) for staged
`docs/plans/*.md`, bypass `K3DM_SKIP_PLAN_STATUS=1`. Refuse a staged plan when its Status changed from HEAD (or the file is
new) and:

- (a) Status starts `DRAFT` and the file has `**Intent approved:** <name>, YYYY-MM-DD` (any name other than `no`):
  `<path>: Status DRAFT but intent is approved; a reviewed, approved spec starts READY (or IN PROGRESS / LANDED)`.
- (b) Status starts `DRAFT`, `PLANNED`, `READY` or `IN PROGRESS` and the file has a `**Fix commit:**` line or the Status
  text contains `landed` as a word: `<path>: Status says not landed but the file records a landed commit; start it LANDED`.

Also refuse when the file is unchanged in Status but newly gains the `**Intent approved:**` approval in the same commit
(the HEAD comparison is on the pair (Status, Intent approved), not Status alone).

## Files

- `bin/k3dm-codex-dispatch`
- `scripts/check-plan-status.py` (new)
- `.githooks/pre-commit`
- `scripts/tests/bin/codex_dispatch_land.bats`
- `scripts/tests/bin/test_check_plan_status.py` (new)
- `docs/process/rules.md` (one line under the Status-first-word rule: plan Status is written by land; pre-commit guards DRAFT+approved)

## Contract readers

- Plan `**Status:**` first word: `bin/k3dm-vectordb-metrics:264` (`_plan_state`) and `:388-393` (spec blocker) — reads
  `LANDED`, already in the vocabulary; no change. `scripts/lib/spec_intent.py:251-261` reads `**Intent approved:**` — read
  only, no change.
- `codex-dispatch start` (`_dispatch_start`, `:943`) reads the spec and records `spec-sha256`: land runs after, so a Status
  rewrite at land does not affect start; `resume` of a landed run is already refused.
- Existing plan files: grep `^\*\*Status:\*\* DRAFT` in `docs/plans/` with an approved `**Intent approved:**` — the check
  applies only when the pair changes, so existing files do not block unrelated commits.

## What NOT to Do

- Do not make any plan-status failure fail or undo a land.
- Do not push from land, and do not commit any file other than the one spec.
- Do not touch `bin/k3dm-vectordb-metrics`.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "land of a dispatch whose spec Status is 'DRAFT v5 ...' or 'READY ...' rewrites it to 'LANDED — <sha> (auto: land <date>; verify pending) ...' in one commit touching only that spec, and still prints 'landed: <slug>'"
  - id: M2
    text: "land with a spec Status of LANDED/VERIFIED/SUPERSEDED leaves the file unchanged and prints 'plan status left as <word>'"
  - id: M3
    text: "land with the spec file dirty, missing, or the commit failing prints 'plan status not updated (...)', exits 0, and the land is complete (task branch merged, worktree removed, landed marker written)"
  - id: M4
    text: "a --repo dispatch writes '<repo-name>@<sha>' and commits in the k3d-manager checkout, not the target repo"
  - id: M5
    text: "pre-commit refuses a staged plan with Status DRAFT and '**Intent approved:** operator, 2026-11-19'; accepts the same file with Status READY (positive control); K3DM_SKIP_PLAN_STATUS=1 bypasses"
  - id: M6
    text: "pre-commit refuses a staged plan with Status READY and a '**Fix commit:**' line; accepts LANDED"
must_not:
  - id: N1
    text: "land leaves an approved DRAFT/READY spec's Status unchanged (red on 23818ae4: no status write exists)"
  - id: N2
    text: "pre-commit accepts DRAFT with approved intent (red on 23818ae4: no plan check exists)"
  - id: N3
    text: "an unrelated commit is refused because some other plan file in the tree is stale (paired with M5 refusal of the staged file)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N3]
    kind: offline
    command: "bats scripts/tests/bin/codex_dispatch_land.bats; python3 -m pytest scripts/tests/bin/test_check_plan_status.py; new tests red on 23818ae4; mutants red: skip the status call in land, make the status failure fatal (M3), drop the intent condition (M5), drop the Fix-commit condition (M6); shellcheck clean"
    intent: When a dispatch lands, its plan flips to LANDED by itself, and you can no longer commit a plan marked draft after you approved it, so the dashboard stops lying about plan state.
interface:
  - "land: plan status not updated (<reason>); set it by hand"
  - "land: plan status left as <word>"
  - "LANDED — <sha> (auto: land <YYYY-MM-DD>; verify pending)"
  - "K3DM_SKIP_PLAN_STATUS=1"
```
