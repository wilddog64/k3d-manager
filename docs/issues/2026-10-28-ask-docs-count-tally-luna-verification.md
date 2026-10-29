# Luna ask-docs count and tally follow-up verification

Status: offline verified; live Slack verification pending.

Operator explicitly requested native GPT-6-Luna task ask-docs-count-tally-luna.
In-scope implementation landed/pushed as 67c26bdf0f8aa7c6340a422891a0247f3145abb8;
prior rolled-back task ask-docs-priority-count-intent was explicitly superseded
using the native dispatcher, not bypassed. Source scope is five files in the
existing P2. General model-summary performance and thread routing unchanged.

The matcher recognizes a bounded explicit priority/state/release count without
requiring the word bugs, and ordinary unrelated object counts still fall
through. Explicit bug wording retains prior behavior. Count questions invoke
`bug-tally.py --json --counts-only`: the regular JSON/CLI contract still
includes fixed_in by default; count-only skips fixed-release history and avoids
resolving added-release tag ancestry for documents with explicit branch
release, retaining history for fallback documents. Invalid counts-only non-JSON
combination is explicitly rejected. It neither changes the deadline nor uses
retrieval/model output as a count.

Fixture histories compare full versus counts-only release totals/paths across
branch/tag/fallback, status transitions and lib-foundation context; default
fixed_in contract preserved. Unrelated noun and invalid priority/state queries
fall through; exact original question bypasses model/retrieval. Existing test
assertions reflecting the operator's earlier rollback were replaced with the
new explicitly authorized requirements and corresponding audit annotations.

Luna initially returned an insufficient implementation: added-history scan
remained expensive, non-JSON option could fail, and noun denylist matched
unrelated object types. Coordinator supplied concrete feedback and Luna resumed
as attempt2. Luna's final reported background counts26.048,11.765,16.002s;
full scan37.767s, later full exceeded45s. These are variable measurements,
not an assurance of live completion under all loads. Coordinator independently
ran background count path: `returncode 0 elapsed_s 3.093 stderr_bytes 0
output_bytes 114049`. Cached state and system load can change timing; live
acceptance remains essential.

## Independent test output

```text
........................................................................ [ 31%]
........................................................................ [ 63%]
........................................................................ [ 95%]
...........                                                              [100%]
227 passed in 17.96s
```

Ruff actual output: `All checks passed!`; git diff --check no output. Python
syntax check Luna exit0/no output. ShellCheck N/A, no shell files changed.
Native land reran focused tripwire tests with existing native promtool:

```text
scope: in-scope
tests: passed
landed: ask-docs-count-tally-luna
```

Native verifier: `verification recorded: ask-docs-count-tally-luna (pass)`
means coordinator offline review, not live Slack verification.

## Transparent gate and environment follow-up

Initial Luna test run reported `217 passed, 2 skipped` and `ruff` not found;
rework used existing Ruff and tripwire, reported225passed/2skips because
promtool absent. Independent run provided existing native promtool and
completed227passed/no skips, above. Initial coordinator checkpoint refused
the replacement of rollback-era assertions; justified `agent-audit: allow
assert-removed` comments were added to both test files and normal audit/hooks
then passed, with replacement assertions retained; no hook bypass. First
land correctly refused a spec already landed by earlier task; normal explicit
`--superseding ask-docs-priority-count-intent` succeeded.

## Live operator acceptance pending

P2 stays OPEN until operator reloads the webhook (also restarts cloud-bridge)
and sends `/ask-docs how many P1 open for v1.43.5` in the existing bot channel.
Confirm a real deterministic count, source revision if provided, and threaded
delivery; compare with the tally for the same ref. A single warm offline timing
is not a live performance guarantee. No operator action was taken by the
coordinator; no credentials/Slack messages/service deployment were invoked.

## Operator live verification failed after first follow-up

Operator supplied screenshot: `Could not count bugs — tally failed (timeout).
Sources: none`. Read-only job metadata matches cc203d78 output at
2026-10-29T03:26:27.311539Z, status success, bot_thread delivered true.
Worker status success means it delivered an error text, not count success.
Webhook PID35701 and bridge PID35707 started 2026-10-28 20:25:11 PDT, after
fix67c26bdf committed20:21:20 PDT; strong evidence the fix was loaded.
No actual in-process bytecode inspection. User screenshot supplied no count.

A separate coordinator-owned bounded background count-only read returned:

```text
returncode 0 elapsed_s 13.486 stderr_bytes 0 output_bytes 113670
```

This warm local success does not explain or supersede the live30s timeout;
load/caches/scheduling differ. No Slack retry, extra restart, credential read,
service mutation or screenshot export by coordinator. P2 staysOPEN.

## Files

- `scripts/bug-tally.py`
- `scripts/lib/webhook/bug_count.py`
- `scripts/tests/bin/test_bug_tally.py`
- `scripts/tests/bin/test_bug_count.py`
- `scripts/tests/bin/test_ask_docs.py`

## Follow-up task and acceptance

The user's explicit Luna P2 dispatch continues after failed live acceptance.
Task `ask-docs-count-timeout-followup-luna` works offline in an isolated
worktree. Investigate and optimize the remaining expensive added-history work
without changing count correctness or existing full CLI/fixed_in behavior.
The observed live trace saw a Git child >22s but did not record its argv;
profile reproducibly before claiming a cause. Prior background runs were
variable and root-only pathspec candidate exceeded60s; do not assume its
selection solves the issue. Retain explicit branch/tag/untagged fallback,
renames, deleted/re-added documents, lib-foundation behavior, state/priority
and fail-closed error semantics. Preserve all previous tests and count routing.

Demonstrate full vs count-only equivalence on real fixture history including
relevant rename/re-add cases, and bounded performance with measured expensive
work reduction under representative Git history/load. A warm one-shot success
is not proof of a robust 30s bound; no deadline increase or synthetic success.
Run focused pytest with tripwire and existing native promtool on PATH, Ruff,
syntax and diff; document actual timing/environment and limits. If an optimization
cannot preserve correctness or be supported by evidence, report that explicitly.
No new cache without clear ref/invalidation correctness; no extra model feature,
new plan/dashboard, production tests, credentials, service/Slack changes or
worker Git commit/push/PR. Coordinator independently reviews, lands via
normal gates, then user conducts any separate live check.

Dispatcher initial start returned `spec has no backticked path in its ## Files
section` because the heading was `## Files for bounded Luna follow-up`.
Corrected to the required exact heading; the listed files and task scope did
not change. No worker started during the failed attempt. Normal retry follows.

## Continued follow-up — no safe performance fix established

Operator later requested continuation after an interrupted turn. Native Luna
follow-up attempt2 exited nonzero at its usage limit, leaving an isolated
batched tag-ancestry candidate. Coordinator ran focused offline tripwire tests:

```text
........................................................................ [ 61%]
..............................................                           [100%]
118 passed in 5.95s
```

Independent Ruff: `All checks passed!`; git diff --check produced no output.
Background-priority comparison against the same repository/ref produced:

```text
baseline exit 0 elapsed 43.471 stderr_bytes 0
candidate exit 0 elapsed 37.997 stderr_bytes 0
release_bucket_equivalence True
```

This candidate still exceeds the30s live deadline, leaves the expensive
added-history walk in place, and a later fixture showed tag-retarget snapshot
race. Not landed. Luna resumed after the usage window; a two-phase Git
no-renames/normal-rename verification produced matching64release buckets in
tested cases, but actual background runs52.506s and58.596s versus original
30.632s. Earlier in-memory prototypes10.986–17.805s were not reliable evidence
for actual implementation. Candidate removed by worker; no code landed.

Coordinator independent background Git scans: normal31.235s, no-renames18.179s;
current-corpus earliest addition maps matched1124paths. That observation alone
is unsafe: the worker's rename fixture proves a path-restricted query can
classify a rename as an addition and change the visible release/count answer.
Output from that fixture:

```text
full answer:
No bug tally found for v2.0.0.
narrowed answer:
v2.0.0: 1 open P1 bug docs — 0 fixed, 1 open, 0 with no Status line.
visible_answers_equal=False
```

A disposable local bare packed-clone comparison was inconclusive; live repo
1.796/0.565s and isolated clone5.371/0.208s in sequential warm samples.
Diagnostic I/O-policy timings also varied; no service scheduling setting was
changed or supported as root cause. No destructive change to user Git storage.

The user's original P1 query needs selected-priority open/closed/unknown and
missing-priority warning counts with complete release attribution. Current ref
had176 fallback docs relevant to this answer (12P1,164unset); narrowing to
those paths alone risks the demonstrated rename misattribution. Bounded
background narrowed-history scans took27.649/25.085s before other work; full
scan timed out after30.749s once, took14.564s another time. Agent found no
validated query-specific shortcut or safe cache.

Worker's final actual offline verification of unchanged source:

```text
invalid_ref rc=2 stdout_bytes=0 stderr_bytes=0
........................................................................ [ 62%]
............................................                             [100%]
116 passed in 10.48s
All checks passed!
AST syntax: 5 files parsed
```

Git diff --check no output; task worktree clean. The P2 remains OPEN and
live still times out. No additional code, timeout increase, cache, restart,
Slack request, credential access, PR or plan was introduced.

### Next design direction for discussion

A precomputed count snapshot/index could move history work out of the
interactive request, but is not yet an implementation proposal ready to ship.
A safe design must bind data to repository identity, immutable resolved commit,
branch fallback context, tag object identities and parser version; validate
ref/tag snapshots before and after construction; publish atomically with
private permissions and concurrent-writer handling; and fail closed on stale,
missing, malformed or racing snapshots. It also needs a plan for the first
cache miss and every later ref/tag change, without silently extending the
30-second deadline or claiming partial counts. Any scheduling/lifecycle change
is separate scope and must be communicated before implementation. Full/filtered
count equivalence, rename/re-add/divergent merge/tag-retarget fixtures, actual
background timing and live Slack confirmation remain required.
