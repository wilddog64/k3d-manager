# Failed-startup Log live verification

Operator UI screenshot: Version v1.43.9, Slug vectordb-retrieval-key-cache,
Run 1, heading `Run log — exit 127; local only (not shipped)`. PASS.
No terminal output supplied for UI check; screenshot not exported.
Documentation only; implementation tests not rerun.

Initial recording checkpoint failed because the canonical bug lacked a structured
Live evidence line. Actual hook output:
```text
docs/bugs/2026-10-27-dispatch-startup-failure-log-link-empty.md: LIVE-VERIFIED requires a well-formed **Live evidence:** line or a typed **Live investigation evidence:** line
Pre-commit hook: newly LIVE-VERIFIED bug docs need a well-formed Live evidence line
  format: **Live evidence:** YYYY-MM-DD · run <id> · env <value> · scenario <value> · commit <sha> · proves <ids>
ERROR: Checkpoint commit failed; resolve git errors and retry
```
Added the required structured evidence; retry through normal hooks, no bypass.
Separate task-name GitHub404 publication/click check remains pending.

Second checkpoint returned the same hook output: initial structured line used spaces
in env/scenario and a custom proves ID. Parser requires single-token env/scenario
and proves fix or E-number IDs. Corrected to that exact grammar; no bypass.
