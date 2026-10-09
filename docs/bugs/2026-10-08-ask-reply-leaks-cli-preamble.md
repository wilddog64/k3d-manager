# `/ask` replies leak CLI preamble (Claude settings warnings) into Slack

**Filed:** 2026-10-08, Claude (found during the operator's live check of `7089dd10`)
**Branch:** k3d-manager-v1.42.0
**Status:** LIVE-VERIFIED 2026-10-08, FIXED in branch `e92d1d85` — after `make restart-webhook`, a top-level `ask claude: which shell are you in` replied with only the answer (no settings warnings, no `ANSWER:` line)
**Priority:** P2 — the answer is correct, but every claude ask now posts three paragraphs of permission-rule warnings above it, and those warnings quote local allow rules into a Slack channel
**Severity:** Medium
**Component:** `scripts/lib/webhook/agent.py` `_parse_gemini_observations`

## Symptom

Slack, top-level `ask claude: which shell are you in`, threaded reply:

```text
claude: Permission allow rule (.claude/settings.local.json): Bash(awk '...') has a wildcard before
the rest of the command, so it also matches any options ... Replace that with the exact value you mean ...
Permission allow rule (.claude/settings.local.json): Bash(/usr/bin/grep -nE '...' .../bin/k3dm-webhook) ...
Permission allow rule (.claude/settings.local.json): Bash(pkill -f 'ssh.-R 8200:localhost:18200') ...
ANSWER:
I'm running in bash on macOS (Darwin 25.5.0). ...
```

The answer itself is right; the `--` fix (`7089dd10`) and the sandbox `SHELL` fix (`b2c45ae3`) both
work. The preamble is the Claude Code CLI validating the repo's `.claude/settings.local.json` at
startup.

## Root cause

`_parse_gemini_observations` strips the marker with `raw.removeprefix("ANSWER:\n")` (lines 289 and
293). `removeprefix` only acts when `ANSWER:` is the very first text. Anything the CLI prints
before the model's output — these warnings now, a Gemini banner before (see
`v1.6.3-bugfix-gemini-cli-warnings-in-slack.md`) — survives, and so does the literal `ANSWER:` line.

## Fix (spec for Codex)

In `_parse_gemini_observations`, when a line that is exactly `ANSWER:` exists, discard everything up
to and including the **first** such line before the existing logic runs:

```python
m = re.search(r"(?m)^ANSWER:[ \t]*\n", raw)
if m:
    raw = raw[m.end():]
```

Then the two `removeprefix("ANSWER:\n")` calls become no-ops; leave them. Output with no `ANSWER:`
line is returned unchanged (today's fallback). Do not touch the CLI invocation, and do not edit
`.claude/settings.local.json` — that file is the operator's.

## Tests

Add to `scripts/tests/bin/test_webhook_ask_claude_argv.py` (or a sibling file):
- preamble lines + `ANSWER:\nhello` → answer `hello`, no `Permission allow rule` text;
- preamble + `ANSWER:\nhello\n\nOBSERVATIONS:\n- TITLE: t | BODY: b` → answer `hello`, observations still parsed;
- no `ANSWER:` line → raw returned unchanged;
- `ANSWER:` mid-sentence (not its own line) is not treated as the marker.

Show RED for the first test against the pre-fix `agent.py` on a temp copy.

## Operator follow-up (not part of the fix)

The three warnings name real over-broad allow rules in `.claude/settings.local.json`. Tightening
them is the operator's call.

## Live verification

After `make restart-webhook`, a top-level `ask claude: which shell are you in` replies with only the
answer text.
