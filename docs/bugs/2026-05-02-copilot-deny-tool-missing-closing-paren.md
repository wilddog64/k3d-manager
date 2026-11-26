# Bug: _copilot_review --deny-tool patterns missing closing paren — copilot exits 1

**Status:** SUPERSEDED — by `2026-05-02-copilot-review-noninteractive-combined-fix.md`, fixed in v0.3.19 (`09f42b1`)
**Priority:** P2 — `_copilot_review` exited 1, so no Copilot review ran; workaround: review by hand

**Date:** 2026-05-02
**Branch:** `fix/copilot-deny-tool-patterns`
**File:** `scripts/lib/system.sh`

---

## Before You Start

1. `git pull origin fix/copilot-deny-tool-patterns` in the lib-foundation repo
2. Read `scripts/lib/system.sh` lines 1700–1712 before touching anything

---

## Problem

`copilot_draft_spec` and `copilot_triage_pod` always exit with:

```
copilot command failed (1)
```

even when auth is valid and the prompt is safe.

---

## Root Cause

`_copilot_review` builds `guard_args` and passes them as `--deny-tool` values to the
copilot CLI. Four of the eight patterns are missing the closing `)`:

```bash
"--deny-tool" "shell(sudo"    # invalid — copilot CLI rejects, exits 1
"--deny-tool" "shell(eval"    # invalid
"--deny-tool" "shell(curl"    # invalid
"--deny-tool" "shell(wget"    # invalid
```

The copilot CLI requires well-formed tool names in the format `tool(command)`. Any
malformed entry causes the CLI to exit 1 before processing the prompt. The other four
patterns (`shell(cd ..)`, `shell(git push)`, etc.) have closing parens and are valid.

---

## Fix

### Change 1 — `scripts/lib/system.sh`: close the four malformed deny-tool patterns

**Exact old block (lines 1707–1710):**

```bash
      "--deny-tool" "shell(sudo"
      "--deny-tool" "shell(eval"
      "--deny-tool" "shell(curl"
      "--deny-tool" "shell(wget"
```

**Exact new block:**

```bash
      "--deny-tool" "shell(sudo)"
      "--deny-tool" "shell(eval)"
      "--deny-tool" "shell(curl)"
      "--deny-tool" "shell(wget)"
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/system.sh` | Close 4 malformed `--deny-tool` patterns (4-character change) |

---

## Rules

- `shellcheck -S warning scripts/lib/system.sh` — zero new warnings
- Code change: `scripts/lib/system.sh` only; memory-bank updates are also required (see DoD)

---

## Definition of Done

- [ ] `shell(sudo"` → `shell(sudo)"` (and same for eval, curl, wget)
- [ ] `shellcheck -S warning scripts/lib/system.sh` passes
- [ ] `env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin" TMPDIR="$TMPDIR" bash --norc --noprofile -c 'bats scripts/tests/lib/'` passes
- [ ] Committed and pushed to `fix/copilot-deny-tool-patterns`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(system): close malformed --deny-tool patterns in _copilot_review
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `scripts/lib/system.sh`
- Do NOT commit to `main` — work on `fix/copilot-deny-tool-patterns`
- Do NOT change the `_copilot_prompt_guard` forbidden array — those are string match patterns, not CLI flags, and are correct as-is
