# `claude -p` live captures (child C, dispatch-stall diagnose)

Captured by Claude on m4-air.local, 2026-11-19 01:50–02:05 UTC (2026-11-18 local), `2.1.328 (Claude Code)`, for
`docs/bugs/2026-11-14-dispatch-stall-c-diagnose.md` evidence E1–E4. Files are raw stdout, unedited, except the two
`*-init-*.jsonl` probes, where the home path is replaced by `/Users/REDACTED`.

Every run: `env -i PATH HOME LANG TMPDIR ANTHROPIC_API_KEY=<key> claude -p --bare --model claude-opus-5-5`, stdin from
`/dev/null` unless stated, cwd an empty scratch directory. The key came from Keychain `k3dm-anthropic-api-key` into the
child environment only; every output file was scanned for the key value afterwards (clean).

| File | Evidence | Extra flags | Exit | Cost USD |
|---|---|---|---|---|
| `claude-help-2.1.328.txt` | help | `--help` | 0 | 0 |
| `result-2.1.328.json` | E1 | `--output-format json --max-budget-usd 0.05`, prompt "Reply with the word ok and nothing else." | 0 | 0.008451 |
| `401-2.1.328.json` | E2 | as E1, key = literal `invalid-key-for-capture` | 1 | 0 |
| `budget-2.1.328.json` | E3 | as E1, `--max-budget-usd 0.0001` | 1 | 0.0004302 |
| `tools-read-grep-glob-2.1.328.json` | E4 | `--max-budget-usd 0.10 --tools Read,Grep,Glob --allowedTools "Read Grep Glob" --permission-mode dontAsk --permission-prompts none`, asked to Write a file and run Bash | 0 | 0.011771 |
| `tools-read-grep-glob-init-2.1.328.jsonl` | E4 probe | E4 flags, `--output-format stream-json --verbose`, prompt "Reply ok" | 0 | 0.000838 |
| `tools-default-bare-init-2.1.328.jsonl` | E4 probe | no `--tools`, `--permission-mode dontAsk --permission-prompts none`, stream-json | 0 | 0.001 |
| `toolless-stdin-2.1.328.jsonl` | E4 (tool-less rework) | `--tools "" --permission-mode dontAsk --permission-prompts none`, stream-json, prompt on stdin asking for a Write | 0 | 0.006784 |

## What the captures show

- **Result fields (E1):** `type: "result"`, `subtype`, `is_error`, `result` (text), `total_cost_usd`,
  `usage.input_tokens`/`output_tokens`/`cache_*`, `modelUsage.<model>.{inputTokens,outputTokens,costUSD}`,
  `num_turns`, `stop_reason`, `terminal_reason`, `api_error_status`, `permission_denials`.
- **401 (E2):** exit 1, `is_error: true`, `api_error_status: 401`, `api_error_type: "authentication_error"`,
  `terminal_reason: "api_error"`, but **`subtype: "success"`**. A classifier must key on `api_error_status` /
  `is_error`, never on `subtype`.
- **Budget (E3):** exit 1, `is_error: true`, `subtype: "error_max_budget_usd"`, `terminal_reason: "budget_exhausted"`,
  `errors: ["Reached maximum budget ($0.0001)"]`. Spend 0.0004302 against a 0.0001 cap (4.3x): the cap is checked after
  the turn, so one turn overshoots. Top-level `usage` tokens are **0** while `modelUsage` carries the real counts
  (4 in, 4 out): token counts must come from `modelUsage`, not `usage`.
- **Tools (E4):** with `--tools Read,Grep,Glob` the init event lists only `["Read"]`; the `--bare` default set is
  `["Bash","Edit","Read"]`. Grep and Glob are not built-in tools in 2.1.328, and Write is not in the bare default set.
  Asked to Write and run Bash, the model reported neither tool exists; `permission_denials` is `[]` (never offered,
  not refused) and no file appeared.
- **Tool-less (E4 rework):** `--tools ""` gives `tools: []`; a prompt piped on stdin is accepted; one turn, no file.
