# ask-docs priority-count routing investigation

## Attempt and actual output

Operator question: `ask-docs how many P1 open for v1.43.5`.
[Question screenshot](../assets/2026-10-27-ask-docs-count-question.png).
The reply states:

> The provided documentation excerpts do not contain information about how many P1 bugs are open for v1.43.5.

[Reply and unrelated semantic sources](../assets/2026-10-27-ask-docs-count-fallback.png).

Read-only local reproduction, with `PYTHONPATH=scripts/lib`:

```text
'how many P1 open for v1.43.5' => None
'how many P1 bugs open for v1.43.5' => CountQuery(release='v1.43.5', priority='P1', state='open')
```

## Root cause and coverage

`webhook.bug_count.match()` requires both a count expression and the literal
word bug/bugs. This question omits that noun. `ask_docs.answer()` therefore
falls through to semantic retrieval and the documentation-only model prompt.
The local source reproduces the observed routing; no production logs were
inspected and no live service was changed.

The fixed 2026-10-10 release-range bug concerns a different failure. Existing
plan `v1.45.1-bug-count-query-translation` covers regex misses generally, but
its item 2 gate also requires `_BUG_RE`, so implementing it verbatim would
leave this exact question unsupported.

## Follow-up

Track the concrete gap in the linked P2 bug. Add bounded priority-count intent
recognition and regression coverage for this exact question, while preserving
non-bug count fallback. Count through bug-tally, never semantic top-k results.
Workaround: `ask-docs how many P1 bugs open for v1.43.5`. Implementation and
live verification remain pending; no new plan document or code fix was made.

## Verification output and evidence-record correction

`python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_bug_count.py -q`:

```text
......................                                                   [100%]
22 passed in 5.11s
```

An initial checkpoint hook correctly rejected trailing explanatory text after
the structured Live evidence IDs in the two dashboard records:

```text
docs/bugs/2026-10-26-plans-table-live-verification-column.md: LIVE-VERIFIED requires a well-formed **Live evidence:** line or a typed **Live investigation evidence:** line
docs/bugs/2026-10-26-vectordb-probe-age-panel-default-red.md: LIVE-VERIFIED requires a well-formed **Live evidence:** line or a typed **Live investigation evidence:** line
```

Removed that trailing text; the evidence links remain in the batch issue.
No bypass was used. BATS and ShellCheck are not applicable to this Markdown/PNG
investigation record; the named Python matcher suite was run above.
