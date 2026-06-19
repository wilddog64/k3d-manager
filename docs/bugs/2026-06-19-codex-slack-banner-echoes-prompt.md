# 2026-06-19 — Slack `/codex` posts the same answer every time (codex banner + echoed prompt captured as the answer)

**Filed:** 2026-06-19 (Claude)
**Type:** bugfix
**Branch:** `k3d-manager-v1.7.1`
**Files:** `bin/k3dm-webhook` (ONLY)

> NOT the same as `docs/bugs/v1.6.5-bugfix-codex-repeat-answer.md` (thread-context
> cross-contamination — that fix is already in the code: `_find_job_by_thread_ts`
> skips `action=ask` sub-jobs). This is a distinct root cause: codex's CLI output
> capture, affecting **every** `/codex` invocation, thread or not.

## Problem

Every Slack `/codex <question>` reply looks the same — the visible message is dominated by a
constant boilerplate header (`OpenAI Codex v0.136.0` … `workdir` … `model` … and the **echoed
system prompt**), with codex's real answer buried far below (and often truncated by Slack).
`/claude` and `/gemini` are unaffected.

## Root cause (verified 2026-06-19)

- `codex exec [PROMPT]` (codex-cli 0.136.0) echoes a banner **and the entire prompt it was given**
  (system + user) to **stderr**, then the final assistant message. Codex writes **nothing to stdout**
  in non-TTY mode.
- `_handle`/`_run_cluster_ask` runs codex via `_posix_spawn_capture`, whose docstring states it
  returns **"stdout+stderr as a string"** — so `raw` = banner + echoed system prompt + answer.
- For codex `_observe = True`, so `raw` is passed to `_parse_gemini_observations`. `raw` does not
  start with `ANSWER:\n`, so `removeprefix("ANSWER:\n")` is a no-op and nothing is stripped; the
  posted message is the whole banner blob. Because the banner + echoed system prompt are constant,
  every reply reads the same.
- Claude uses `claude -p` (no system-prompt echo to its captured output); Gemini uses
  `_call_gemini`. Only codex echoes its prompt, which is why only `/codex` is broken.

Verified by direct CLI runs:
- `codex exec "...what is 2+2?"` → answer `4`; `...capital of France?` → `Paris` (codex itself is fine).
- `codex exec --output-last-message <FILE> "...capital of Japan?"` → `<FILE>` contains exactly
  `Tokyo is the capital of Japan.` and nothing else (no banner, no echoed prompt).
- `_posix_spawn_capture` docstring confirms stdout+stderr are merged.

## Fix

Use codex's `--output-last-message <FILE>` to capture only the final assistant message, and read
that file as the answer instead of the merged stdout/stderr banner.

### Change 1 — codex command: add `--output-last-message`

**Exact old block:**
```python
            cmd = ["codex", "exec", "--skip-git-repo-check", f"{codex_system}\n\n{user_prompt}"]
            timeout = 120
            _observe = True
```

**Exact new block:**
```python
            _codex_last = job_dir / "codex_last_message.txt"
            cmd = ["codex", "exec", "--skip-git-repo-check",
                   "--output-last-message", str(_codex_last),
                   f"{codex_system}\n\n{user_prompt}"]
            timeout = 120
            _observe = True
```

### Change 2 — prefer the last-message file as the answer for codex

**Exact old block:**
```python
        try:
            raw, timed_out = _posix_spawn_capture(cmd, timeout, cwd=REPO_ROOT, env=env)
            if timed_out:
                _finish(f"❌ *{agent}* timed out after {timeout}s — try a more specific question", status="failed")
                return
            answer = _ANSI.sub("", raw).strip() or f"No output from {agent}."
```

**Exact new block:**
```python
        try:
            raw, timed_out = _posix_spawn_capture(cmd, timeout, cwd=REPO_ROOT, env=env)
            if timed_out:
                _finish(f"❌ *{agent}* timed out after {timeout}s — try a more specific question", status="failed")
                return
            if agent == "codex":
                try:
                    raw = _codex_last.read_text()
                except OSError:
                    pass
            answer = _ANSI.sub("", raw).strip() or f"No output from {agent}."
```

`job_dir` is already defined at the top of `_run_cluster_ask` (`job_dir = JOB_DIR / job_id`), so
`_codex_last` resolves into the per-job dir. The `if agent == "codex"` guard ensures `_codex_last`
is only referenced on the codex path, where it is always assigned before the `try`. If codex exits
without writing the file (timeout/error), the `except OSError: pass` falls back to the old `raw`.

## Rules

- `python3 -m py_compile bin/k3dm-webhook` — zero errors.
- No other files touched. No `--no-verify`. LF only.
- `./scripts/k3d-manager _agent_audit` — clean.
- Do NOT alter the claude/gemini branches, the `codex_system`/`user_prompt` text, or
  `_parse_gemini_observations`.

## Definition of Done

- [ ] Codex command includes `--output-last-message <per-job file>`.
- [ ] For `agent == "codex"`, the answer is read from that file (with OSError fallback to `raw`).
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes.
- [ ] `./scripts/k3d-manager _agent_audit` clean.
- [ ] Committed + pushed to `k3d-manager-v1.7.1`; SHA reported and confirmed on origin.
- [ ] memory-bank `activeContext.md` + `progress.md` updated with the SHA and status.

**Commit message (exact):**
```
fix(webhook): read codex final message via --output-last-message so /codex stops echoing its prompt banner
```

## What NOT to do

- Do NOT create a PR.
- Do NOT run `make restart-webhook` — that is Claude's post-verify step on this machine.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `bin/k3dm-webhook`.
- Do NOT commit to `main` — work on `k3d-manager-v1.7.1`.
