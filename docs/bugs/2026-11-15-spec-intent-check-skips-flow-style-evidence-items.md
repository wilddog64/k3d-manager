# Bug: spec-intent gate never checks evidence items written in YAML flow style

**Status:** LANDED — d09d98f2 on k3d-manager-v1.44.1, 2026-11-16 (Flash, one correction for the `- E1: {…}` shape found by a whole-corpus run; Claude verified: 11 tests red pre-fix, 29/29 green; corpus diff shows only the two map-style plans newly refused, the accepted fail-closed case)
**Priority:** P2 (raised from P3 at grooming 2026-11-15: a gate that silently passes; no wrong dispatch known)
**Introduced by:** unknown (`scripts/lib/spec_intent.py`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** scheduled run — since 2026-11-16 (next codex-dispatch start of a flow-style spec)
**Branch:** k3d-manager-v1.44.1
**Triage:** patch → v1.44.1; Priority raised P3 → P2 (Argon P2 accepted: a safety-gate gap) — operator grooming 2026-11-15 ("Accept as shown")
**Prior art:** exact-slug pass, no match; `find-similar-docs` not run (needs context k3d-k3d-cluster) — none known

## What happened (Claude, 2026-11-15)

`scripts/lib/spec_intent.py:50` splits evidence items on `^\s*-\s+id\s*:` (block style). Items written as flow
mappings (`  - {id: E1, proves: [...], kind: offline, intent: "..."}`, used by many specs, for example
`docs/bugs/2026-11-10-ci-job-named-lint-runs-the-full-test-suite.md`) never match, so a flow-style item with no
`intent` passes the gate. Found while dispatching the ESO spec; that spec was converted to block style.

Also: the header regex at `:72-74` requires the `**Intent approved:**` line to end at the date, so a trailing note
(`operator, 2026-11-15 ("approved")`) is refused with "missing header", a misleading message.

## Fix direction

Parse the Acceptance block as YAML (or accept both item styles) and check `intent` on every evidence item; name the
trailing-text case in the refusal message. Test with a flow-style item lacking intent (red on today's code).

## Reproduction (Claude, 2026-11-16, M4, HEAD 8d2af9eb, python3 stdlib only)

Scratch specs in `/private/tmp/claude-501/-Users-cliang-src-gitrepo-personal-k3d-manager/9ef41df1-0c89-4d16-9ed3-63c5d0c3a8a5/scratchpad/si/`
(each: `**Filed:** 2026-11-16`, `**Intent approved:** operator, 2026-11-16`, an Acceptance block, `evidence:` plus the item shown).
Command: `python3 scripts/lib/spec_intent.py <scratch>/<name>.md`

| scratch spec, evidence item | rc today | wanted |
|---|---|---|
| block `- id: E1` / `kind: offline` (positive control) | 1, "evidence item E1 is missing intent" | 1 |
| flow `- {id: E1, proves: [M1], kind: offline}` | 0 OK | 1 |
| flow `- {..., intent: ""}` | 0 OK | 1 |
| flow multi-line `- {id: E1,` / `proves: [M1],` / `kind: offline}` | 0 OK | 1 |
| flow without id `- {proves: [M1], offline: true}` | 0 OK | 1 |
| mixed: block E1 with intent plus flow E2 `kind: live`, no intent | 0 OK | 1 (names item 2) |
| flow, no intent key, `text: "the intent: is shown"` | 0 OK | 1 |
| flow with `intent: "You will see a result."` | 0 OK | 0 |

No YAML parser exists: `python3 -c "import yaml"` fails on the M4, `scripts/tests/bin/test_spec_intent.py:83-119`
(`test_checker_subprocess_without_yaml_dependency`) forbids importing it, and the dispatcher runs the checker with
bare `python3`. So the fix is a stdlib scanner, not a YAML parse.

## Fix

All edits in `scripts/lib/spec_intent.py`. No comments in the new code (CLAUDE.md style).

1. After line 14 (`INTENT_RULE_DATE = dt.date(2026, 11, 8)`) add the helpers below. `_flow_fields(text)` finds the first `{`,
   scans to its matching `}` tracking `{[` depth, single and double quotes (and `\"` inside double quotes), splits on commas at
   depth 1 only, and returns `{key: raw value}` (key = text before the first `:` with quotes stripped); `None` when the
   braces never close. `_evidence_items(section)` drops blank lines, takes the smallest indent among lines matching
   `^\s*-\s` as the item indent (deeper `- M1` lines inside `proves:` are not items), and returns one `(id, intent_present)`
   per item, or `None` when no line matches. Per item: a first token starting `{` joins the item's lines and uses
   `_flow_fields`; otherwise the existing block logic (lines 52-69, moved verbatim into `_block_has_intent(item)`) runs on the
   item with its leading `- ` replaced by spaces, so `- intent: x` on the dash line also counts. Flow intent is present
   when `value.strip("'\" \t")` is not empty and not `null` or `~`. The id is the `id` field or block `id:` value, else the
   1-based index. An item that is neither a flow mapping nor a `key:` mapping, or a flow mapping that never closes, yields
   a gap `evidence item <id> is not a mapping the checker can read` (fail closed, never skip).

2. Replace lines 49-71, verbatim:

```
    if evidence:
        items = re.split(r"(?m)^\s*-\s+id\s*:\s*", evidence.group(1))
        for index, item in enumerate(items[1:], 1):
            item_id = item.splitlines()[0].strip() or str(index)
            intent = re.search(r"(?m)^([ \t]+)intent[ \t]*:[ \t]*(.*)$", item)
            has_intent = False
            ...
            if not has_intent:
                gaps.append(f"evidence item {item_id} is missing intent")
```

   (lines 50-70 are the existing body, unchanged in meaning) with:

```
    if evidence:
        items = _evidence_items(evidence.group(1))
        if items is None:
            gaps.append("evidence section has no list items the checker can read")
        for item_id, state in items or []:
            if state == "unreadable":
                gaps.append(f"evidence item {item_id} is not a mapping the checker can read")
            elif state != "intent":
                gaps.append(f"evidence item {item_id} is missing intent")
```

   with `_evidence_items` returning `state` of `"intent"`, `"missing"` or `"unreadable"`. The `evidence:` regex at lines 46-48
   and `evidence: []` (no match, no gap) stay as they are.

3. Lines 72-75, the header check, keep the same regex and the same message when no `**Intent approved:**` line exists
   (the existing tests assert it). Add before it: when a line `^\*\*Intent approved:\*\*.*\d{4}-\d{2}-\d{2}.+$` exists but the
   strict regex fails, the gap is `**Intent approved:** line must end at the date (operator, YYYY-MM-DD); put any note on another line`.
   `bin/k3dm-vectordb-metrics:312` keeps the strict regex unchanged.

4. Tests in `scripts/tests/bin/test_spec_intent.py`, after line 80, using `_spec(...)` (fixture already asserts its scratch
   root): one test per row of the Reproduction table (the eight rows, with the block control first), plus the trailing-note
   header case and a `pending` header case (keeps the old message). One dispatcher test via `_run_dispatch` (line 204) with a flow
   item lacking intent and a valid header: refused, output contains `evidence item E1`, `not marker.exists()`; its
   control uses the flow item with an intent and reaches `could not fetch origin/` (as the test at line 248).

## Files

- `scripts/lib/spec_intent.py`
- `scripts/tests/bin/test_spec_intent.py`

## Contract readers

Grep `spec_intent\|check-spec-intent` and `Intent approved` over `bin scripts/lib scripts/ci .githooks Makefile .github`
(2026-11-16, HEAD 8d2af9eb):

- `bin/k3dm-codex-dispatch:920-928` — reader (runs `spec_intent.py`, rc 1 refuses, other rc errors). Unchanged: rc and
  stderr contract stay; only more specs now get rc 1.
- `Makefile:1601-1604` `check-spec-intent` — reader, unchanged.
- `bin/k3dm-vectordb-metrics:312` — duplicate strict header regex (reader of the `**Intent approved:**` format). Unchanged,
  the strict regex does not change.
- `bin/k3dm-dispatch-metrics:91-101` — reader of the Acceptance format (counts items with `^\s+-\s+id\s*:`, live items with
  `^\s+kind:\s*live`); flow items are undercounted there. Not changed (metrics only, does not gate dispatch); filed as a
  follow-up, not this fix.
- `scripts/tests/bin/test_spec_intent.py:9-10,83-119,122-144,147-262` — reader/test; the no-yaml test and the
  c5d28596 exemption test must stay green.
- No writer: nothing generates Acceptance blocks (`grep -rn "must_not" bin scripts/lib scripts/ci` finds only the two readers above).
- Specs in flow style or `E1: {...}` map style that are dated 2026-11-08 or later and lack intent now refuse at dispatch
  (intended). Older ones stay exempt by date, pinned by `test_all_existing_specs_are_exempt_as_of_this_commit`.

## Worker definition of done

- `python3 -m pytest -q scripts/tests/bin/test_spec_intent.py` green; `make test-pytest` green.
- Run the new tests against the pre-fix checker (`git show 8d2af9eb:scripts/lib/spec_intent.py` copied to a scratch dir and
  imported there) and paste which fail: every flow, mixed, multi-line and no-id case red, the block control and the
  intent-present flow control green.
- `python3 scripts/lib/spec_intent.py` on every scratch spec in the Reproduction table gives the "wanted" column.
- No new imports beyond the stdlib already used (`re`); `import yaml` stays absent. Commit and push to the release branch.

## Acceptance

```yaml
must:
  - id: M1
    text: a flow-style evidence item (single-line or multi-line, with or without id) that has no intent, or an empty intent, is refused with "evidence item <id> is missing intent", and the dispatcher refuses before any agent launch
  - id: M2
    text: in a mixed block-and-flow evidence list every item is checked, and the gap names the right item
  - id: M3
    text: block-style items and flow items that carry a non-empty intent still pass (positive controls)
  - id: M4
    text: an **Intent approved:** line with trailing text after the date is refused with a message that says the line must end at the date; an absent line keeps the old message
must_not:
  - id: N1
    text: a flow item without intent passes the gate (rc 0) — red today (rc 0 on flow_no_intent)
  - id: N2
    text: a flow item with intent only inside another field's quoted text (text "the intent: is shown") counts as having intent — red today
  - id: N3
    text: an evidence item the checker cannot read is skipped silently — red today (unreadable items are never seen)
  - id: N4
    text: the checker imports yaml or any non-stdlib module — red only if added; guarded by test_checker_subprocess_without_yaml_dependency
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    command: python3 -m pytest -q scripts/tests/bin/test_spec_intent.py (scratch specs in tmp_path; fixture asserts its scratch root first)
    intent: A spec whose evidence is written in the compact one-line style but has no plain-English "what you will see" line is now stopped at dispatch, the same as one in the long style.
  - id: E2
    proves: [M1]
    kind: offline
    command: the dispatcher test via _run_dispatch with a stub agent that writes a marker file; positive control with an intent reaches the offline fetch failure
    intent: A spec that is stopped for missing intent never starts the agent, and a complete spec still gets past this gate.
  - id: E3
    proves: [M4]
    kind: offline
    command: pytest cases for a trailing note, a pending header and an absent header
    intent: When you add a note after the approval date the refusal tells you to move the note, instead of saying the header is missing.
  - id: E4
    proves: [N4, M3]
    kind: offline
    command: test_checker_subprocess_without_yaml_dependency and test_all_existing_specs_are_exempt_as_of_this_commit stay green
    intent: The gate keeps running on a bare machine with no extra tools, and no spec already in the repo is newly blocked.
interface:
  - python3 scripts/lib/spec_intent.py <spec> (rc 0 OK, 1 gaps on stderr, 2 unreadable)
  - make check-spec-intent SPEC=<spec>
  - bin/k3dm-codex-dispatch start --spec <spec>
```

**Intent approved:** operator, 2026-11-16
**Approval note:** ("Approve all 9")
**Operator decision (2026-11-16, accepted Claude default):** map-style evidence fails closed.
