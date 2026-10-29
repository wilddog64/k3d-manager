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
