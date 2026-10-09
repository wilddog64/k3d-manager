# `/ask claude` with no thread context fails: the prompt is parsed as a CLI option

**Filed:** 2026-10-08, Claude (found during the operator's live check of `b2c45ae3`)
**Branch:** k3d-manager-v1.42.0
**Status:** LIVE-VERIFIED 2026-10-08 — FIXED in branch `7089dd10`; top-level `ask claude` answered in thread (operator screenshot). Found the preamble leak, filed as `2026-10-08-ask-reply-leaks-cli-preamble.md`
**Priority:** P1 — top-level `/ask claude` is fully broken; only a thread ask (prompt starts with context) works
**Severity:** High
**Component:** `scripts/lib/webhook/agent.py` `_run_cluster_ask` (claude branch)

## Symptom

Slack, top-level `ask claude: what shell are you in`, threaded reply:

```text
claude: error: unknown option '---USER QUESTION START---
what shell are you in
---USER QUESTION END---'
```

Job `a79931a2` is the only occurrence in `webhook-jobs/`.

## Root cause

`_run_cluster_ask` builds `["claude", "-p", user_prompt, "--system-prompt", ...]`. `-p` is the
boolean `--print` flag, so `user_prompt` is a positional argument. Without thread context it
starts with `---USER QUESTION START---`, and the Claude Code CLI (2.1.290, installed 2026-10-05)
rejects any argument beginning with `-` that it does not recognise as an option. With thread
context the prompt starts with the context block, so thread asks still work. That is why this
went unnoticed. The `b2c45ae3` change (the `SHELL` env var) did not cause it.

Reproduced locally, outside the webhook:

```text
$ claude -p $'---X START---\nhi' --max-turns 0
error: unknown option '---X START---
hi'
$ claude -p --max-turns 1 --allowedTools Bash -- $'---X START---\nreply with the single word pong\n---X END---'
pong
```

The codex path (`codex_system` first) and the gemini path (`gemini_system` first) do not start
with `-` and are not affected.

## Fix (spec for Codex)

`scripts/lib/webhook/agent.py`: in **both** claude `cmd` lists, remove `user_prompt` from
position 2 and append `"--", user_prompt` as the last two elements. Leave every other option, and
its order, unchanged:

```python
cmd = [
    "claude", "-p",
    "--system-prompt", composite_system,
    "--allowedTools", "Bash,Write" if filing else "Bash",
    "--add-dir", REPO_ROOT,
    "--add-dir", SHOPPING_CARTS_ROOT,
    "--max-turns", str(max_turns),
    "--", user_prompt,
]
```

Do the same for the non-filing branch, with `claude_system` and `"Bash"`.

## Tests

New `scripts/tests/bin/test_webhook_ask_claude_argv.py`. Stub `_posix_spawn_capture` to record
`cmd` and return `("ok", False)`, and stub the Slack and finish helpers. Then drive the claude
path for:
- a plain question with no thread context;
- a filing question (`file an issue ...`);
- a question with thread context.

Assert for each:
- `cmd[-2] == "--"`;
- `cmd[-1]` contains `---USER QUESTION START---`;
- the prompt does not appear anywhere in `cmd[:-2]`.

Show RED against the pre-fix `agent.py` on a temp copy.

## Live verification

After `make restart-webhook`, a top-level `ask claude: what shell are you in` answers in its
thread. This also completes the pending live check of `b2c45ae3`: the answer should name the
sandbox bash.
