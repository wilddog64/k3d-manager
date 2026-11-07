# Bug: the Bug Tracking dashboard's open counts do not say what to do

**Filed:** 2026-10-12
**Branch:** `k3d-manager-v1.43.14`
**Status:** OPEN — fix landed `6d42c201` (Luna; corrected after Claude's review), independent verify running, live E5 and E6 pending. E4: of 1004 docs, doc_status changes for exactly the four expected. Spec revised 2026-11-06 after review: the first version collided with two existing dashboard guards (see Design limits).
**Priority:** P2 — raised from P3 2026-11-06; a reader cannot tell a stalled bug from a shipped fix waiting for proof, and it misled the operator about seven rows that day
**Approval:** explicit 2026-11-06 "go ahead" (operator, on rewriting this spec and dispatching it to Luna). Originally explicit 2026-10-12 "then maybe we should have same comment or explaination (short one) to present; otherwise this confuse people as we don't know what to do or panic".
**Severity:** medium

## Symptom

2026-10-12: the **Open P1** stat read **1** in orange. The one P1 was a shipped fix waiting for a
natural recurrence. Nothing was down, and the dashboard gave no hint of that.

2026-11-06: the **Bugs** table showed seven P2 rows as Open, some four or five days old. The operator
asked which could be dispatched. None could: two had their fixes in and waited on a live check, one
waited on Sunday's scheduled run, one was running, and the others were investigations or waited on a
decision. The operator: "dashboard seems not able to present what you explain to be as the status is
all open and some of them are 4 or 5 days old".

## Root cause

1. `doc_status` reduces a Status line to `open`, `fixed`, `deferred` or `unknown`. `open` mixes not
   started, running, fix landed awaiting proof, waiting on a schedule and waiting on a person.
2. It reads only the start of the line. `OPEN — machine-setup half landed…` and `FIX IN SUBTREE — …`
   both classify as `open`, and what follows is never read.
3. `_CLOSED_RE` omits `WITHDRAWN`, `OBSOLETE`, `COMPLETE` and `COMPLETED`, and it anchors on the first
   character, so `✅ RESOLVED` and `**WITHDRAWN` do not match a word it does list or should list.
4. Open for counts from the filing date. That is correct, and it cannot separate a bug waiting on a
   known event from one nobody has picked up.

## Why not the 2026-10-12 fix

The earlier version of this spec derived a `phase` from the first word of the Status line. That
repeats root cause 2: `OPEN — machine-setup half landed` would show `not started`, and
`FIX IN SUBTREE` would show `in progress`. It also named `k3dm_bug_open_info` and an "Open bugs" table
that no longer exist; the row is `k3dm_bug_info` and the table is **Bugs**. This rewrite replaces it.

## Fix

### 1. `scripts/lib/hermes/prior_art.py`

Add `WITHDRAWN`, `OBSOLETE`, `COMPLETE` and `COMPLETED` to `_CLOSED_RE`.

In `_status_value`, drop leading characters that are not word characters from a non-empty value,
using `re.sub(r"^[^\w]+", "", value)`. Return `None` where it returns `None` today.

`bin/k3dm-dispatch-metrics` imports `_CLOSED_RE`, so a doc newly marked `WITHDRAWN` or `OBSOLETE` counts as an unverified closure there, as `SUPERSEDED` and `DUPLICATE` already do. Leave that as it is.

Add `doc_waiting_on(text)`, returning `(waiting_on, waiting_since)`:

- It reads the first line in the header block matching `**Waiting on:** <value>`. The header block
  ends at the first line that starts with `## `. A line below that is an example or a quotation, and
  is ignored.
- `<value>` is `<word> — since YYYY-MM-DD` or `<word>`, split on ` — since `.
- `<word>`, lowercased and trimmed, must be one of these six, or the result is `invalid`:
  `dispatch`, `fix running`, `live check`, `scheduled run`, `investigation`, `operator decision`.
- `waiting_since` is the date if it is a real calendar date, else `-`. A bad date does not make a valid
  word `invalid`.
- No such line returns `("not stated", "-")`. An `invalid` word returns `("invalid", "-")`.

The returned strings come only from that fixed set and that date check. Nothing from the line's free
text may reach a label.

### 2. `bin/k3dm-vectordb-metrics`, `_bug_status_metrics`

Add two labels to `k3dm_bug_info`, immediately after `live_evidence`:

- `waiting_on` and `waiting_since` from `doc_waiting_on` when the row's status is `open` or `unknown`.
- `waiting_on="-"` and `waiting_since="-"` for every other status, whatever the doc says. A forgotten
  line on a closed doc must not show.

Do not change the row's value, `sort_key`, `status`, `fix_sha`, any other label, or
`k3dm_bug_status_docs`.

### 3. `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`

**Design limits (Claude's spec error, found in review 2026-11-06).** The first version of this section asked for descriptions on the `Open P*` tiles and two new columns. Both broke guards that exist on purpose: a tile narrower than `w=4` has no description (`2026-10-19-bug-dashboard-verification-tile-labels-clipped`), and the table's widths plus 150 stay within 1350 so it fits a laptop without horizontal scrolling. Those guards stay as they are.

**Bugs** table (the panel titled `Bugs`):

- `renameByName`: `waiting_on` → `Waiting on`.
- `indexByName`: put `waiting_on` immediately after `status`, and move the later columns along by one.
- `excludeByName`: `waiting_since` is true. The label is exported and not shown, because the table has no room for it.
- Overrides: `Waiting on` is filterable, width 130. Reduce `Open for`, `Status` and `Priority` by 10 each, which keeps the total at the limit.
- Append to the panel description: "Waiting on says what an open bug needs next; filter that column to separate live checks and scheduled runs from work nobody has picked up. `not stated` means the doc has no Waiting on line. The Open P0 to P3 tiles count every open doc, including fixes that landed and are waiting for a live check, so read this column before treating a count as an incident."

No change to the tiles: no description, colour, threshold or position change.

### 4. Docs

- `docs/guides/grafana-dashboards/k3dm-bugs.md`: the column, that `waiting_since` is exported but not shown, the six values, the line's format,
  `not stated` and `invalid`, and that Open for still counts from filing.
- `CHANGELOG.md` `[Unreleased]` → `### Fixed`.

Claude, not the worker, adds the convention to `CLAUDE.md` and writes the Waiting on line into the
open docs after landing.

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/prior_art.py` | closed words, status cleanup, `doc_waiting_on` |
| `bin/k3dm-vectordb-metrics` | two labels |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` | column, widths, table description |
| `scripts/tests/bin/test_prior_art.py` | tests |
| `scripts/tests/bin/test_vectordb_bug_metrics.py` | tests |
| `scripts/tests/plugins/grafana_dashboard_bugs.bats` | tests, column index updates |
| `docs/guides/grafana-dashboards/k3dm-bugs.md` | section above |
| `CHANGELOG.md` | entry |

## Tests

Use temp fixtures or injected `texts=` and `now=`. Never push to the real Pushgateway. A test first
asserts it is pointed at its fixture, not the real `docs/bugs/`.

Gates: `pytest scripts/tests/bin/test_prior_art.py scripts/tests/bin/test_vectordb_bug_metrics.py scripts/tests/bin/test_open_for_acceptance.py scripts/tests/bin/test_live_evidence_acceptance.py`,
`bats scripts/tests/plugins/grafana_dashboard_bugs.bats`.

If an existing test pins an old behaviour this spec changes, other than a column index or a whole-label
string gaining the two new labels, stop and report it. Do not remove an assertion.

## What NOT to Do

- Do NOT derive Waiting on from the Status text.
- Do NOT edit any bug doc, `CLAUDE.md` or the memory bank.
- Do NOT change `fix_sha`, Open for, or how any row is sorted.
- Do NOT add a label holding free text.
- Do NOT add a description to a tile, or change the 1350 limit or the tile-description assertion in `grafana_dashboard_bugs.bats`.
- Do NOT read the ledger or any live system to work out a value.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT modify files outside the Files list.

## Acceptance

```yaml
interface:
  - "scripts/lib/hermes/prior_art.py: doc_waiting_on(text) -> (waiting_on, waiting_since); doc_status(text); doc_meta(text); _status_value(text)"
  - "bin/k3dm-vectordb-metrics: _bug_status_metrics(root, ref=None, now=None, tally=None, texts=None, ...), texts maps a path such as docs/bugs/2026-11-01-x.md to the doc text, and it returns exposition text"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml: the panel titled Bugs, and the panels titled Open P0 to Open P3"
must:
  - id: M1
    text: "An open doc with a header line '**Waiting on:** live check — since 2026-11-06' gives a k3dm_bug_info row with waiting_on=\"live check\" and waiting_since=\"2026-11-06\"."
  - id: M2
    text: "Each of dispatch, fix running, live check, scheduled run, investigation and operator decision is accepted, in any letter case, with and without a since date."
  - id: M3
    text: "An open doc with no Waiting on line gives waiting_on=\"not stated\", waiting_since=\"-\"."
  - id: M4
    text: "A word outside the six gives waiting_on=\"invalid\", waiting_since=\"-\". A valid word with an impossible date such as 2026-13-40 keeps the word and gives waiting_since=\"-\"."
  - id: M5
    text: "A doc with no Status line (status unknown) carries waiting_on and waiting_since by the same rules."
  - id: M6
    text: "Status values beginning WITHDRAWN, OBSOLETE, COMPLETE or COMPLETED classify as closed. '✅ RESOLVED 2026-08-28' and '**WITHDRAWN (2026-06-12).**' classify as closed."
  - id: M7
    text: "The Bugs table maps waiting_on to Waiting on, directly after Status, with custom.filterable true; waiting_since is excluded from the table; and the description says the Open tiles include fixes waiting for a live check."
must_not:
  - id: N7
    text: "The dashboard's existing guards hold: no tile narrower than w=4 has a description, and the Bugs table's fixed widths plus 150 are at most 1350. Paired control: Waiting on has its width and is visible."
  - id: N1
    text: "A closed doc, or a deferred one, that still has a Waiting on line shows waiting_on=\"-\" and waiting_since=\"-\"."
  - id: N2
    text: "A '**Waiting on:**' line below the first '## ' heading is ignored: with no header line the row says not stated, and a header line beats it."
  - id: N3
    text: "Free text never reaches a label. A line such as '**Waiting on:** live check\", evil=\"1' gives waiting_on=\"invalid\" and the exposition line still parses with no evil label."
  - id: N4
    text: "The row's value, status, sort_key and fix_sha are unchanged by adding, changing or removing a Waiting on line, for an open doc and a fixed doc."
  - id: N5
    text: "A Status such as 'OPEN — fix landed' stays open, and 'REVERTED' or a non-listed word stays open after the leading-character cleanup."
  - id: N6
    text: "Across the live tree, comparing the parent of the fix with the fix, doc_status changes for exactly the four docs named in E4 and no others, and plan metrics are identical."
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N3, N4, N5]
    kind: offline
    what: "Claude's review run of the Gates in the Tests section on the task branch."
  - id: E2
    proves: [M7, N7]
    kind: offline
    what: "bats scripts/tests/plugins/grafana_dashboard_bugs.bats on the task branch."
  - id: E3
    proves: [M1, M2, M3, M4, M5, M6, M7, N1, N2, N3, N4, N5, N7]
    kind: offline
    what: "Independent verifier's tests, written from this block only, pass on the landed commit and are red on its parent. N1 to N5 and N7 hold by a paired positive control: each negative test sits beside a test of the same fixture that shows the label does appear when the rule permits. Mutants, each red: gate removed so closed docs show the line; header-block limit removed; free text passed through; RESOLVED match anchored without the cleanup; a word dropped from the six; a description added to Open P1; a width raised past the limit."
  - id: E4
    proves: [N6]
    kind: offline
    what: "Claude compares the live tree at parent and fix. Expected flips, open to fixed: 2026-08-28-stage-c-cosign-signing-fails-post-merge, 2026-06-12-cluster-provider-local-registration-and-r*, 2026-09-11-hub-control-plane-readoption, 2026-04-24-argocd-cli-login-plaintext-prompt."
  - id: E5
    proves: [M1, M3]
    kind: live
    what: "Claude: after the docs carry the line and Hermes has polled the updated M5 checkout, hub Prometheus returns k3dm_bug_info rows with waiting_on=\"live check\" and none of the docs given a line reads not stated."
  - id: E6
    proves: [M7]
    kind: live
    what: "Operator: after the dashboard is synced from the release branch, the Bugs table shows the column without horizontal scrolling at laptop width, the narrowed headers are readable, and filtering Waiting on works."
```
