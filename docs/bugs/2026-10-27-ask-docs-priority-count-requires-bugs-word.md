# Bug: ask-docs misses an explicit priority count without the word bugs

**Status:** OPEN — operator live count check failed; committed matcher remains offline-verified, running webhook predates fix; controlled reload and retest pending
**Fix commit:** b6704d68e04da578bc060cda96e19fe0ae94e5f2
**Priority:** P2
**Filed:** 2026-10-27
**Branch:** `k3d-manager-v1.43.9`
**Related:** `docs/plans/v1.45.1-bug-count-query-translation.md`; `docs/bugs/2026-10-10-ask-docs-bug-count-ignores-release-range.md`

`ask-docs how many P1 open for v1.43.5` returns unrelated documentation
excerpts and cannot answer the count. The deterministic matcher requires the
literal noun bugs; adding it selects the correct release/priority/state query.
This degrades the question interface with a working rephrasing workaround.

Evidence and exact reproduction:
[Investigation](../issues/2026-10-27-ask-docs-priority-count-misses-bug-noun.md).

The existing v1.45.1 translation plan's `_BUG_RE` gate would also reject this
question. A scoped fix should recognize a bounded priority-count question,
use the deterministic tally, and retain ordinary non-bug count fallback.
Required regressions: this exact wording selects P1/open/v1.43.5 and bypasses
retrieval/model; existing bug wording retains its result; unrelated pod counts
still fall through. No implementation or live deployment is included here.

## Files

- `scripts/lib/webhook/bug_count.py`
- `scripts/tests/bin/test_bug_count.py`
- `scripts/tests/bin/test_ask_docs.py`

## Authorized bounded task

Operator asked to investigate the three open screenshot bugs and dispatch
accordingly. Implement this P2 in an isolated GPT-6-Luna worktree. Recognize
the exact how many P1 open for v1.43.5 question as deterministic bug count
CountQuery(v1.43.5,P1,open), without requiring nounbugs. Use bounded intent:
count phrase + explicit P0-P3 priority + explicit bug-state context with
release when needed to disambiguate. Do not greedily hijack unrelated pod,
PR, issue, release-plan or other object counts merely mentioning priority.
Existing explicit bug/bugs queries, release/current/lastN ranges and state
normalization must retain behavior. Ordinary non-bug questions still fall
through. Reuse deterministic bug-tally; do not count semantic results, add
model/network calls or implement the broader v1.45.1 translation plan.

Regression exact question bypasses retrieval/model and selects correct
priority/state/release; explicitbugs result unchanged; unrelated pod counts
including explicit P1/open context fall through. Include case/word-boundary/
priority validity cases. Show relevant regression red on original matcher,
then focused test_bug_count and test_ask_docs pytest, Ruff/Python syntax and
diffcheck. No arbitrary count from a real mutable corpus asserted in fixtures.

Read instructions/memory-bank first. Edit only Files; no spec/memory edits,
stage/commit/push/PR, live Slack/webhook/cluster/provider/Keychain/network
access, credential changes or restart. Coordinator reviews and runs actual
staged lint/audit before landing/push. Operator live query follows separately.
No new plans or broad refactor; new/refactored functions <=8ifs.

## Independent implementation review

Luna implementation landed and pushed after review follow-up. [Full test output, corrected fixture/gate failures and live limits](../issues/2026-10-27-three-open-bugs-investigation-and-luna.md). Operator live check pending; no production deployment/restart by coordinator.

## 2026-10-28 failed live acceptance

Exactmissingnounquestionfellthroughsemanticsearchagain; job58e47ff3answer
saysdocumentationdoesnotcontaincount andoperatorreportsnothread. LiveFAIL,
notzero-count. RuntimePID4295startedOct25beforeb6704d68Oct27, imports
ask_docs/bug_countatstartup; staleloadedcode stronglysuspected. Freshimport
correctcount0/modelretrievalsentinelsnotcalled;87focusedtestsPASS. Bugreopened
forliveretest, fix/evidencepreserved; notprovennewcoderegression. Threadroute
unknownpendingoperatorinvocation/channelandcontrolledreload. No actual
restart/credentialswrite/Slackmessage.
[Actual output and one next operator step](../issues/2026-10-28-ask-docs-live-count-and-thread-failure.md).
