# Bug: bug tally counts IMPLEMENTED and DEFERRED bugs as open

**Filed:** 2026-10-22 (Claude, from the operator's Slack screenshot at 18:11 PDT)
**Status:** OPEN
**Priority:** P3 — wrong counts in Slack and one dashboard metric; the per-bug dashboard rows are correct
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "yes" to dispatching to Luna after bugs-table-title-filter
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/lib/hermes/prior_art.py` (`_CLOSED_RE`, `doc_meta`); `scripts/bug-tally.py`; `scripts/lib/webhook/bug_count.py`
**Related:** `docs/bugs/2026-10-10-ask-docs-bug-count-ignores-release-range.md`

## Symptom

The Slack bug count for v1.43.0 reported "3 open". The three docs it listed are:

| Doc | Status line starts with |
|---|---|
| `2026-10-09-hub-recovery-node-map-hardcoded-stale-after-rebuild.md` | `DEFERRED` |
| `2026-10-09-secret-store-data-puts-value-in-security-argv.md` | `IMPLEMENTED` |
| `2026-10-10-secret-store-data-reports-success-on-failed-keychain-write.md` | `IMPLEMENTED` |

None of them is open work.

## Root cause

`doc_meta` returns `closed` only when the Status value matches `_CLOSED_RE`, which lists
FIXED, CLOSED, RESOLVED, DONE, WONTFIX, SUPERSEDED, DUPLICATE, VERIFIED and LIVE-VERIFIED, but not
`IMPLEMENTED`. Every other value, `DEFERRED` included, falls through to `open`.

`doc_status` (used for the dashboard's per-bug rows) already handles both: it checks
`DEFERRED` first and treats `IMPLEMENTED` as fixed. But `doc_meta` feeds:

- `scripts/bug-tally.py:142`, which builds the per-release open/closed counts and `open_paths`
  that `scripts/lib/webhook/bug_count.py` prints in Slack;
- `bin/k3dm-vectordb-metrics` `_bug_metrics`, which publishes `k3dm_bug_docs{state=...}`.

So both report IMPLEMENTED and DEFERRED docs as open.

## Fix

- **F1.** Add `IMPLEMENTED` to `_CLOSED_RE` in `scripts/lib/hermes/prior_art.py`. `doc_status` is
  unchanged in result: it already returns `fixed` for IMPLEMENTED and checks DEFERRED first.
- **F2.** DEFERRED stays in the open bucket for counting (it is unfinished work), but is labelled.
  In `scripts/bug-tally.py`, add `"status": doc_status(raw)[1]` to each `open_paths` item. In
  `scripts/lib/webhook/bug_count.py`, print `Deferred:` instead of `Open:` for items whose
  `status` is `deferred`, and add the deferred count to the summary line
  (`N open (M deferred)`). No other JSON keys change.
- **F3.** Tests in `scripts/tests/bin/test_bug_tally.py` (and the existing bug_count test file if
  one exists, else in `test_bug_tally.py`): an IMPLEMENTED doc counts closed; a DEFERRED doc
  stays in `open_paths` with `status: deferred` and prints as `Deferred:`; a plain OPEN doc is
  unchanged.
- **F4.** `CHANGELOG.md` entry.

## Files

- `scripts/lib/hermes/prior_art.py`
- `scripts/bug-tally.py`
- `scripts/lib/webhook/bug_count.py`
- `scripts/tests/bin/test_bug_tally.py`
- `scripts/tests/bin/test_prior_art.py` (added at review: its doc_meta expectations pinned IMPLEMENTED as open)
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A bug doc whose Status starts with IMPLEMENTED counts as closed in bug-tally output and in k3dm_bug_docs.
  - id: M2
    text: A DEFERRED doc stays counted as open but is marked status deferred in open_paths, and the Slack reply lists it as "Deferred:" with a deferred count in the summary.
  - id: M3
    text: doc_status returns the same result as before for every Status value (open, fixed, deferred, unknown).
must_not:
  - id: N1
    text: An IMPLEMENTED doc must not appear in open_paths or the open count (red on the pre-fix code).
  - id: N2
    text: A DEFERRED doc must not be printed with the "Open:" label (red on the pre-fix code).
  - id: N3
    text: No existing bug-tally JSON key is removed or renamed; scripts/tests/bin/test_vectordb_bug_metrics.py stays green.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3]
    text: pytest scripts/tests/bin/test_bug_tally.py scripts/tests/bin/test_vectordb_bug_metrics.py; N1 and N2 red on the pre-fix code.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: After make restart-webhook, the operator asks the Slack bot for the v1.43.0 bug count; it reports 0 open IMPLEMENTED docs and lists the hub-recovery doc as Deferred.
interface:
  - scripts/lib/hermes/prior_art.py doc_meta(text), doc_status(text)
  - scripts/bug-tally.py --json --ref REF
  - scripts/lib/webhook/bug_count.py reply(query)
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 and N2 shown red against the pre-fix code.
- [ ] `pytest scripts/tests/bin` green.
- [ ] Commit: `fix(bugs): count IMPLEMENTED as closed and label DEFERRED in the bug tally`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT edit any bug doc's Status line to make the count right.
- Do NOT change `doc_status` behaviour or the dashboard row logic.
