# Bug: "Re-read share after compaction" counts only Read-tool calls and cannot tell a needed re-read from a wasted one

**Status:** OPEN — dispatch next session
**Priority:** P3
**Severity:** low — the panel showed 20.6% (30d) from 63 Read calls, while ~13,300 Bash commands read files in the same window; the number cannot support an efficiency judgement either way; no runtime impact
**Approval:** operator, 2026-11-01 ("probably can file it and do that in next session")
**Filed:** 2026-11-01
**Detected by:** operator (asked whether 20.6% means wasteful re-reading), root cause by Claude
**Affected:** `bin/k3dm-dispatch-metrics` (Claude transcript rollup, `k3dm_claude_reads`); `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` (panel "Re-read share after compaction")
**Branch:** `k3d-manager-v1.43.13` (or the next release branch if v1.43.13 has merged)
**Related:** `docs/plans/v1.43.6-claude-context-compaction-metrics.md` (defined the metric); `docs/metrics/context-window-experiment.md`

## Observed failure

On 2026-11-01 the hub Prometheus returned `k3dm_claude_reads{window="30d",kind="all"} 63` and
`kind="reread_after_compaction"` 13, so the panel read 20.6%. A replay of the same transcripts (M4,
`~/.claude/projects/-Users-cliang-src-gitrepo-personal-k3d-manager`, 30d) found:

- 303 compactions, 16,257 Bash calls, ~13,348 of them reading files (`cat`, `sed -n`, `head`, `tail`, `grep`, `awk`),
  against 63 Read calls. The metric sees under 1% of file reading.
- Of the 13 re-reads: 5 were repeat reads within the same post-compaction segment (the file had already been re-read
  after the boundary), 3 followed Claude's own Edit/Write of the file, 4 read a different range than the earlier
  read, and 1 returned the same range with identical content.

## Root cause

- `_claude_rollup` counts only `tool_use` blocks named `Read`. Bash reads are not counted in `all` or in the re-read count.
- A Read is a re-read when, after any compaction, its path is in the set of paths read before the latest boundary.
  That set is not cleared when the file is re-read after the boundary, so every later read of it in the segment
  counts again, and reads after an edit or of a different range count the same as a reload of unchanged content.
- The tool result is never compared, though the transcript holds it (`tool_result` with the matching
  `tool_use_id`), so changed and unchanged content cannot be told apart.

## Fix

1. **Count Bash reads.** A Bash call is a file read when its command (split with `shlex`; on a split error it is
   not a read) is a single pipeline stage, or the first stage of a pipeline, whose program is `cat`, `head`, `tail`,
   `sed -n`, `awk`, `grep` or `rg`, with file operands that are absolute paths or paths under the repo. Each file
   operand is one read, with a range of `(program, options)`. Commands with redirection into a file, `-i`, or more
   than 5 file operands are not reads. Read-tool calls keep the range `(offset, limit, pages)`.
2. **One re-read per file per segment.** After a compaction, the first read of a path read before that boundary is
   the re-read; later reads of the same path in the same segment are ordinary reads.
3. **Changed or unchanged.** Hash the result body (Read: the `tool_result` content; Bash: the tool output). A re-read
   is `unchanged` when the latest read of the same path and range before the boundary had the same hash and no
   Edit, Write or NotebookEdit of the path ran in between; otherwise `changed`. A different range is `changed`.
   Results that are truncated or errored are `changed`.
4. **Metrics.** `k3dm_claude_reads{window,kind}` keeps `all` (now Read + Bash reads) and
   `reread_after_compaction` (= changed + unchanged), and adds `reread_unchanged` and `reread_changed`. Add
   `k3dm_claude_reads_by_tool{window,tool}` with `tool` = `read` or `bash`. No result body or command text goes into a
   label or the cache file; hashes stay in memory.
5. **Dashboard.** Keep "Re-read share after compaction". Add "Wasted re-read share" =
   `reread_unchanged / all` (unit percentunit, "No reads in window" when empty), with a description saying it counts
   re-reads that returned content identical to the pre-compaction read. Grid stays valid.
6. **Docs.** `docs/metrics/context-window-experiment.md`: one row saying the re-read definition changed on the fix
   date, so earlier values are not comparable.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/metrics/context-window-experiment.md`
- `CHANGELOG.md`

## What NOT to do

- Do not put command text, file content, file paths or hashes into metric labels, the Pushgateway, or the
  persisted cache.
- Do not count a Bash call that writes (`sed -i`, redirection to a file, `tee`) as a read.
- Do not drop or rename the existing `kind` values; the existing panel keeps working.
- Do not edit `scripts/tests/fixtures/agent-dispatch-dashboard-pre-split.yaml`.
- Tests use a temp projects dir and the 127.0.0.1:9 Pushgateway pin; never the real `~/.claude`.

## Acceptance

```yaml
must:
  M1: a fixture session with Bash reads (cat, sed -n, head, grep on absolute paths) counts each file operand in kind="all" and in k3dm_claude_reads_by_tool{tool="bash"}
  M2: after a compaction, the first read of a pre-boundary path is one re-read; a second read of it in the same segment is not counted as a re-read
  M3: a re-read whose result matches the pre-boundary read of the same path and range, with no Edit/Write of the path between, is reread_unchanged; one whose content differs, whose range differs, or that follows an Edit/Write is reread_changed (paired with the unchanged case)
  M4: reread_after_compaction equals reread_unchanged plus reread_changed in every window
  M5: the dashboard has "Wasted re-read share" dividing reread_unchanged by all for window="$window", mapping empty to "No reads in window"; "Re-read share after compaction" is still present
must_not:
  N1: a Bash write (sed -i, > file, tee) or a command that fails shlex is never counted as a read
  N2: no metric line, label or cache file contains command text, file content, a file path or a content hash
  N3: dashboard panels never overlap and the JSON stays valid
evidence:
  E1:
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    intent: >-
      You will see test_dispatch_metrics.py build a temp projects dir (asserted not to be ~/.claude) with sessions
      holding Read and Bash reads before and after compact_boundary records: an unchanged re-read, a changed one, a
      different-range one, one after an Edit, a repeat in the same segment, and Bash writes; the exported lines give
      the expected counts, and grepping the output and cache for the fixture paths, commands and content finds
      nothing. Pre-fix, M1, M2 and M3 fail.
    what: pytest scripts/tests/bin/test_dispatch_metrics.py
  E2:
    proves: [M5, N3]
    kind: offline
    intent: >-
      You will see agent_dispatch_dashboard.bats find both panels by title, assert the new expr and empty mapping,
      and check that no gridPos rectangles intersect; pre-fix the new panel assertion fails.
    what: bats scripts/tests/plugins/agent_dispatch_dashboard.bats
  E3:
    proves: [M1, M5]
    kind: live
    intent: >-
      You will see, after the exporter runs on the M4 and the dashboard is synced on the hub, k3dm_claude_reads_by_tool
      with tool="bash" in the thousands for 30d and the Wasted re-read share panel showing a value.
    what: Claude queries Prometheus on the M5; the operator reads the panel
interface:
  - bin/k3dm-dispatch-metrics (--claude-projects DIR, --claude-cache FILE; Pushgateway via PUSHGATEWAY_URL)
  - Prometheus metrics k3dm_claude_reads{window,kind}, k3dm_claude_reads_by_tool{window,tool}
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml
```
