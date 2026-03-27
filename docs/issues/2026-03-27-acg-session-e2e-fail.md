# Issue: ACG Session E2E Test Failure — 2026-03-27

## Description
The E2E live test for `_antigravity_ensure_acg_session` failed even after implementing the model fallback helper (`gemini-2.5-flash` responded). The nested `gemini` agent failed to execute the Playwright automation due to tool restrictions and default Plan Mode operation.

## Environment
- Machine: `m4-air.local`
- Branch: `k3d-manager-v0.9.17`
- Browser: Antigravity (CDP port 9222)

## Verbatim Output (Scenario 1 — Success path)
```
INFO: Checking ACG session in Antigravity browser...
INFO: Trying gemini model: gemini-1.5-flash...
INFO: Model gemini-1.5-flash unavailable (exhausted or not found) — trying next model...
INFO: Trying gemini model: gemini-2.0-flash...
INFO: Model gemini-2.0-flash unavailable (exhausted or not found) — trying next model...
INFO: Trying gemini model: gemini-2.5-flash...
Keychain initialization encountered an error: An unknown error occurred.
Using FileKeychain fallback for secure storage.
Loaded cached credentials.
I will create a Playwright script `ag_acg_session.js` at `/tmp/ag_acg_session.js`. ...
Error executing tool write_file: Path not in workspace: Attempted path "/tmp/ag_acg_session.js" resolves outside the allowed workspace directories: /Users/cliang/src/gitrepo/personal/k3d-manager or the project temp directory: /Users/cliang/.gemini/tmp/k3d-manager
...
Error executing tool write_file: Tool execution denied by policy. You are in Plan Mode and cannot modify source code. ...
```

## Root Cause
1.  **Nested Agent Policy:** The `gemini` CLI tool when run non-interactively via `--prompt` defaults to Plan Mode or applies strict tool policies when it detects it's being driven by another agent.
2.  **Path Restriction:** The `write_file` tool in the `gemini` CLI respects workspace boundaries. The prompt in `antigravity.sh` specifies `/tmp/ag_acg_session.js`, which is blocked.
3.  **Model Availability:** `gemini-1.5-flash` and `gemini-2.0-flash` were unavailable (exhausted/429/404), requiring the fallback to `gemini-2.5-flash`.

## Recommended Follow-up
1.  **Update `antigravity.sh`:** Add `--approval-mode yolo` to the `gemini` call to bypass Plan Mode.
2.  **Path Hygiene:** Update the `gemini_prompt` in `antigravity.sh` to use the project's temporary directory (`K3DM_TEMP_DIR` or similar) instead of a hardcoded `/tmp/`.
3.  **Codex Task:** Assign the fix implementation to Codex once the spec is updated.
