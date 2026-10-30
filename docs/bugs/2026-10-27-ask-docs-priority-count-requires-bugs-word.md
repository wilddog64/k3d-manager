# Bug: ask-docs misses an explicit priority count without the word bugs

**Status:** OPEN — Luna count and tally follow-up independently verified offline; operator reload and live verification pending
**Fix commit:** 67c26bdf0f8aa7c6340a422891a0247f3145abb8
**Previous fix commit:** b6704d68e04da578bc060cda96e19fe0ae94e5f2 (rolled back by 2d88c7be)
**Priority:** P2
**Deferred:** 2026-10-30, operator: no more matcher vocabulary. Wording gaps ("how many P1 open", "what are / list open P2 bugs") wait for `docs/plans/v1.45.1-bug-count-query-translation.md`, where the model writes the query and the tally counts. Workaround: start with "how many … bugs".
**Filed:** 2026-10-27
**Branch:** `k3d-manager-v1.43.9`
**Related:** `docs/plans/v1.45.1-bug-count-query-translation.md`; `docs/bugs/2026-10-10-ask-docs-bug-count-ignores-release-range.md`

`ask-docs how many P1 open for v1.43.5` returns unrelated documentation
excerpts and cannot answer the count. The deterministic matcher requires the
literal noun bugs; adding it selects the correct release/priority/state query.
This degrades the question interface. Adding "bugs" selects the tally route, but a working live rephrasing workaround has not been established: that route timed out during the later verification.

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
- `scripts/bug-tally.py`
- `scripts/tests/bin/test_bug_tally.py`
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

## After operator reload: tally timeout, still OPEN

NewwebhookPID43179startOct28 19:22:14/runningconfirmed. Exactcountquestion
nowselectsdeterministicpathbutjob6f069edfreportsCouldnotcountbugs—tallyfailed
(timeout), at02:24:14ZOct29. Semanticmatcherfixloaded; countnotverified. Local
actualtally5.137s andsameposixspawnlauncherfromthread3.632s bothsucceed, so
newlive30srootcauseunconfirmed. No blinddeadlineincrease/speculativecache.
Processancestrytraceonnextoperatorrepeat needed; fullactualoutputinexisting
livefailureissue. No needanotherrestart solelyforroot-adviceoutputfix.

## Operator-directed rollback

Operator requested lastknownlivegood ask-docs only. ask_docs.py and
bug_count.py restored byte-for-byte from ee456c83 (Oct22 generic tally live
pass). Original missing-noun bug is again present and remains OPEN; old30s
count timeout/history remains too. Shared webhook/tally script not reverted.
Focused87tests pass with cases retained and explicitly historical expectations;
full actual output/removed formatting+source detail and recommended next scope
in [rollback evidence](../issues/2026-10-28-ask-docs-live-count-and-thread-failure.md).
No live restart performed.

## Updated P2 scope — 2026-10-28

Operator requested this existing bug be updated with the count failure. It
now tracks both related acceptance gaps:

1. The exact priority/state/release question without the noun "bugs" falls
   through to semantic search and can return no count. The earlier matcher
   fix b6704d68 routed it correctly offline, but was rolled back in 2d88c7be
   at operator request after live tally timeouts.
2. During live verification of that matcher, the deterministic tally failed
   at its 30-second subprocess deadline. A live trace saw a Git child for at
   least22s without command arguments. A disposable background profile took
   38.562s total, including28.523s on added-document history and5.904s on
   fixed-history scanning. This is evidence of costly work, not proof of the
   exact cause of the live timeout. Post-rollback explicit-bugs phrasing has
   not been live-verified as a working workaround.

The original count problem is already this P2, so no duplicate bug filed.
The timeout is an additional observed failure of its intended count path; it
may affect other tally consumers, but broader impact has not been established.
General model-summary latency is separate enhancement work unless an agreed
latency requirement establishes a defect. The one measured semantic-search
response took approximately81.6s from job creation to delivery record, with
45.568s in the agy candidate/CLI loop; these are single-sample observations,
not a diagnosed general latency regression.

### Updated acceptance for a future fix

- The exact missing-noun P1/open/v1.43.5 question selects a correct deterministic
  count; explicit-bugs questions retain correct behavior, and unrelated pod,
  PR, alert and release-plan questions do not get misclassified.
- The count path returns complete, accurate release/priority/status results
  for tagged and branch/fallback documents. Any unavailable or incomplete
  result is reported as a failure; search excerpts or a model do not invent
  totals. Preserve existing tally consumers and fixed-release semantics.
- Reproduce and measure the expensive path under representative scheduling
  and history. Demonstrate a bounded count path with meaningful equivalence
  and failure tests; do not merely extend the deadline, skip evidence, or
  treat one favorable local timing as a live pass.
- Independently review the implementation and test output; after operator
  rollout, verify one live Slack question and the delivered correct count
  against the same source revision. Keep the bug OPEN until live acceptance.

This documentation update authorizes no implementation, new model selection,
service restart or live test. User asked to communicate before scope changes;
review the proposed implementation before dispatch. Existing authorization
for the earlier narrow Luna matcher task does not by itself cover shared
tally performance changes. No new plan or duplicate bug created.

[Actual trace, rollback and live output](../issues/2026-10-28-ask-docs-live-count-and-thread-failure.md).

## Authorized Luna follow-up — 2026-10-28

Operator explicitly requested dispatch of this updated P2 to GPT-6-Luna.
Task `ask-docs-count-tally-luna`: implement the updated acceptance above in
an isolated worktree. This supersedes the earlier narrow Files list only by
adding `scripts/bug-tally.py` and `scripts/tests/bin/test_bug_tally.py`, as
listed under Files. Do not change `ask_docs.py` or general model summarization
unless a specific necessity is reported to coordinator first. No dashboard,
new plan, external service, dependency, credential, production action, restart,
Slack message, staging/commit/push/PR or memory/spec edits by worker.

Retain complete tally output/CLI contract and `fixed_in` for existing
consumers; any optimized count path must preserve all release attribution,
status/priority totals, source refs, missing metadata and error behavior.
Do not blindly raise 30s timeout, cache mutable state without validation,
remove fixed-in fields for existing consumers, or use semantic/model output
as a count. Prove equivalence to existing full tally on realistic fixture Git
histories including branch/tag attribution, missing metadata and status
transitions. Regression tests must demonstrate real reduction in unnecessary
work for count requests, not timing-only flaky checks or implementation-mirror
assertions. Run focused `test_bug_tally.py`, `test_bug_count.py`,
`test_ask_docs.py`, and relevant existing tests under offline tripwire, Ruff,
syntax and diff checks. Record representative performance under appropriate
bounded conditions and limitations; no fake live verification.

Prior live process trace/Git profile evidence and rollback are in linked
issue. Coordinator independently reviews and performs normal gates/landing;
operator separately reloads and tests Slack after offline approval. User asked
to handle one P2 at a time; general model-summary latency remains separate.

## Luna follow-up landed — live verification pending

GPT-6-Luna taskask-docs-count-tally-luna supersedes the rolled-back earlier
task. Independentfocused227pytestPASS/noskips with existingnativepromtool,
Ruff/audit/hooks and native landing testsPASS; fix67c26bdf pushed. Count-only
path avoids fixedhistory and unnecessaryexplicit-branch tag attribution while
preservingdefaultCLI/fallbackrelease semantics; boundedintent restored.
Independentbackgroundwarmcount3.093s; Luna variable11.765–26.048s, so no
liveSLAclaim. Fullactualresults and gatehistory in
[verification issue](../issues/2026-10-28-ask-docs-count-tally-luna-verification.md).
Operatorreload andlivecount/threadverification required; P2 remainsOPEN.

## Live check failed after 67c26bdf

Operatorreloadedwebhook PID35701start20:25:11PDT afterfixcommit20:21:20.
Slackjobcc203d78 at03:26:27ZOct29deliveredthreadreply `Could not count bugs —
tally failed (timeout). Sources: none`. This is not a live pass. A separate
warmbackgroundcount13.486s confirms variability, notlivecause. ExistingP2
remainsOPEN; Luna follow-up specified in
[verification issue](../issues/2026-10-28-ask-docs-count-tally-luna-verification.md).
No furtheroperatorretry before independentlyreviewed solution.

## Root-cause measurement — 2026-10-29 (Claude)

The same `bug-tally.py --json --counts-only --ref HEAD` takes 1.8 s at normal priority and 13.0 s / 58.6 s under `taskpolicy -b` on the M4. The webhook LaunchAgent sets no `ProcessType`, so launchd applies its default CPU and I/O throttle to the webhook and its Git children. Next step: Phase 0 in [`v1.43.11-ask-docs-count-performance.md`](../plans/v1.43.11-ask-docs-count-performance.md) (`ProcessType Interactive` on the webhook only, then 20 live measurements) before any snapshot design. Status stays OPEN.

### Phase 0 deployed — 2026-10-29 16:0x PDT

The operator added `ProcessType Interactive` to the installed plist and ran `make restart-webhook` from the M4 tmux pane. Claude confirmed with read-only `launchctl print`: `spawn type = interactive (4)` (was `daemon (3)`), on new pid 87282. Remaining for closure: at least 20 live Slack count questions over a day of ordinary load, with timings and an answer comparison (plan E3). Status stays OPEN.

### E3 samples (Claude, read from job directories)

Response time = job directory created → `output` written (excludes the Slack post). The webhook log's
`duration_ms` is only the 202 accept, so it is not used. Count-route samples so far:

| When (PDT) | Job | Route | Time | Note |
|---|---|---|---|---|
| 2026-10-30 04:45 | `1c3b1e84` | count | 3 s | v1.43.5 P1 |
| 2026-10-30 11:01 | `a2edbce3` | count | 5 s | current release P2; first after the 10:57 restart |

2 of 20. Both under the 30 s deadline; the 5 s sample is over the 3 s p95 target, so keep collecting
before deciding. Search-route answers (typos, "list", "what are") took 39–48 s; that is the model, not
the tally, and does not count toward E3.
