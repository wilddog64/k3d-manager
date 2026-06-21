# Bugfix: webhook `_call_gemini` — retarget Slack `/gemini` to the agy (Antigravity) CLI

**Branch:** `<migration branch — see Before You Start>`
**Files:** `bin/k3dm-webhook`

---

## Problem

Google retired `gemini-cli`. The webhook's shared `_call_gemini` helper shells out to the
`gemini` binary (`K3DM_GEMINI_BIN`, default `gemini`) with `--model gemini-2.5-flash --prompt`.
That binary no longer exists, so **every** call site — the Slack `/gemini` command, stall
analysis, diagnosis, and `ask gemini` — now returns `"gemini CLI not found — skipping AI
analysis"`. The replacement is the standalone Antigravity agent CLI (`agy`, installed at
`~/.local/bin/agy`).

**Root cause:** `_call_gemini` is pinned to the retired `gemini` binary and its
`gemini-2.5-flash` model namespace; agy uses different flags (`--print` with a **positional**
prompt) and a different model namespace (`gemini-2.5-flash` does not exist; closest analog is
`Gemini 3.5 Flash (Medium)`).

---

## Reproduction

In Slack thread: `/gemini why is the order pod crashlooping?`
- Expected: an AI answer.
- Actual: `🤖 *gemini:* gemini CLI not found — skipping AI analysis`

Verified-good agy invocation (run from any dir):
```
agy --model "Gemini 3.5 Flash (Medium)" --print-timeout 60s --print "reply with exactly: MODELOK"
# → MODELOK
```

---

## Fix

Retarget the **shared** `_call_gemini` helper (all call sites are dead, not just `/gemini`).
Minimal change: binary resolution, env, model default, and the argv. The function name,
the `/gemini` Slack command trigger, and the `*gemini:*` reply label are intentionally
**unchanged** (keeps muscle memory and avoids touching 8+ call sites / docs).

### Change 1 — `bin/k3dm-webhook` line 130: model default

**Exact old block:**
```python
GEMINI_MODEL = os.environ.get("K3DM_ANALYSIS_MODEL", "gemini-2.5-flash")
```

**Exact new block:**
```python
AGY_MODEL = os.environ.get("K3DM_ANALYSIS_MODEL", "Gemini 3.5 Flash (Medium)")
```

### Change 2 — `bin/k3dm-webhook` lines 897–908: docstring, binary resolution, env

**Exact old block:**
```python
def _call_gemini(prompt):
    """Shell out to the gemini CLI. Returns response text or error string.

    Uses os.posix_spawn (no fork) to avoid macOS NEF atfork SIGSEGV.
    Output is captured via a temp file rather than a pipe.
    """
    import shutil, tempfile, time
    gemini_bin = os.environ.get("K3DM_GEMINI_BIN", "gemini")
    resolved = shutil.which(gemini_bin) or gemini_bin
    if not os.path.isfile(resolved):
        return "gemini CLI not found — skipping AI analysis"
    env = {**os.environ, "GEMINI_CLI_TRUST_WORKSPACE": "true", "TERM": "xterm-256color"}
```

**Exact new block:**
```python
def _call_gemini(prompt):
    """Shell out to the agy (Antigravity) CLI. Returns response text or error string.

    Uses os.posix_spawn (no fork) to avoid macOS NEF atfork SIGSEGV.
    Output is captured via a temp file rather than a pipe.
    """
    import shutil, tempfile, time
    agy_bin = os.environ.get("K3DM_AGY_BIN", "agy")
    resolved = shutil.which(agy_bin)
    if not resolved:
        _fallback = os.path.expanduser("~/.local/bin/agy")
        resolved = _fallback if os.path.isfile(_fallback) else agy_bin
    if not os.path.isfile(resolved):
        return "agy CLI not found — skipping AI analysis"
    env = {**os.environ, "TERM": "xterm-256color"}
```

### Change 3 — `bin/k3dm-webhook` line 918: argv

**Exact old block:**
```python
        cmd = [resolved, "--model", GEMINI_MODEL, "--prompt", prompt]
```

**Exact new block:**
```python
        cmd = [resolved, "--model", AGY_MODEL, "--print-timeout", "110s", "--print", prompt]
```

---

## Design notes (do not change beyond the three blocks above)

- **Prompt is positional.** agy's `--prompt` is only an alias for the `--print` flag; the
  prompt text is a positional argument *after* the flag. All value-flags (`--model`,
  `--print-timeout`) MUST precede `--print` because Go's flag parser stops at the first
  positional. The argv order in Change 3 is the verified-good order.
- **`--print-timeout 110s`** keeps agy under the function's existing 120s `os.kill` deadline
  (line ~923) so the daemon never blocks indefinitely.
- **No `--dangerously-skip-permissions`.** agy is agentic and that flag auto-approves tool
  execution. A Slack-triggered prompt must NOT be able to make agy run kubectl/shell with the
  webhook's privileges (prompt-injection risk). Print mode without it answers from the supplied
  context — same behavior the old `gemini --prompt` path had. Leave it off.
- The temp-file prefix `k3dm-gemini-`, the `"gemini returned no output"` fallback strings, and
  the `Warning:`-banner stripping regex are left as-is (internal/harmless). Do not rename them.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | retarget `_call_gemini` to agy: model default, binary resolution + env, argv |

---

## Rules

- This is a Python file — run `python3 -m py_compile bin/k3dm-webhook` (must pass).
- Run `./scripts/k3d-manager _agent_audit` — must pass (no bare sudo, inline creds, hardcoded IPs).
- Run the repo BATS entrypoint `./scripts/k3d-manager test all` — webhook suite must stay green.
- No other files touched. No new env vars beyond `K3DM_AGY_BIN`.
- Do NOT rename `_call_gemini`, the `/gemini` command, or the `*gemini:*` label.

---

## After implementing — operator step (NOT Codex)

`bin/k3dm-webhook` changed → the running webhook must be restarted with `make restart-webhook`
to pick up the change. Codex does NOT run this; the operator (Claude) does after verifying the
commit.

---

## Definition of Done

- [ ] All three blocks applied exactly.
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes.
- [ ] `./scripts/k3d-manager _agent_audit` passes.
- [ ] `./scripts/k3d-manager test all` green.
- [ ] CHANGELOG.md `[Unreleased]` → `### Changed` entry added.
- [ ] Committed and pushed to the migration branch.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(webhook): retarget _call_gemini to agy (Antigravity) CLI — gemini-cli retired
```

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `bin/k3dm-webhook` (+ CHANGELOG.md + memory-bank).
- Do NOT add `--dangerously-skip-permissions` (security — see Design notes).
- Do NOT rename the function, command, or label.
- Do NOT commit to `main` — work on the migration branch.
