# Bug: _copilot_review missing --allow-all-tools + malformed --deny-tool patterns

**Date:** 2026-05-02
**Branch:** `fix/copilot-deny-tool-patterns`
**File:** `scripts/lib/system.sh`
**Supersedes:** `docs/bugs/2026-05-02-copilot-deny-tool-missing-closing-paren.md`

---

## Before You Start

1. `git pull origin fix/copilot-deny-tool-patterns` in the lib-foundation repo
2. Read `scripts/lib/system.sh` lines 1702–1711 before touching anything

---

## Problem

`copilot_draft_spec` and `copilot_triage_pod` always exit with:

```
copilot command failed (1)
```

Two bugs in `_copilot_review` cause this:

1. **Missing `--allow-all-tools`** — Copilot CLI requires this flag to enter non-interactive
   scripted mode. Without it the CLI rejects the invocation shape and exits 1.

2. **Four malformed `--deny-tool` patterns** — The patterns `shell(sudo`, `shell(eval`,
   `shell(curl`, `shell(wget` are missing their closing `)`. The Copilot CLI requires
   well-formed `tool(command)` names; any malformed entry causes exit 1 before the prompt
   is processed.

---

## Root Cause

`_copilot_review` builds `guard_args` without `--allow-all-tools` and with four
patterns missing the closing `)` (lines 1707–1710):

```bash
   local -a guard_args=(
      "--deny-tool" "shell(cd ..)"
      "--deny-tool" "shell(git push)"
      "--deny-tool" "shell(git push --force)"
      "--deny-tool" "shell(rm -rf)"
      "--deny-tool" "shell(sudo"
      "--deny-tool" "shell(eval"
      "--deny-tool" "shell(curl"
      "--deny-tool" "shell(wget"
   )
```

---

## Fix

### Change 1 — `scripts/lib/system.sh`: add `--allow-all-tools` and close all four patterns

**Exact old block (lines 1702–1711):**

```bash
   local -a guard_args=(
      "--deny-tool" "shell(cd ..)"
      "--deny-tool" "shell(git push)"
      "--deny-tool" "shell(git push --force)"
      "--deny-tool" "shell(rm -rf)"
      "--deny-tool" "shell(sudo"
      "--deny-tool" "shell(eval"
      "--deny-tool" "shell(curl"
      "--deny-tool" "shell(wget"
   )
```

**Exact new block:**

```bash
   local -a guard_args=(
      "--allow-all-tools"
      "--deny-tool" "shell(cd ..)"
      "--deny-tool" "shell(git push)"
      "--deny-tool" "shell(git push --force)"
      "--deny-tool" "shell(rm -rf)"
      "--deny-tool" "shell(sudo)"
      "--deny-tool" "shell(eval)"
      "--deny-tool" "shell(curl)"
      "--deny-tool" "shell(wget)"
   )
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/system.sh` | Add `--allow-all-tools`; close 4 malformed `--deny-tool` patterns |

---

## Rules

- `shellcheck -S warning scripts/lib/system.sh` — zero new warnings
- Code change: `scripts/lib/system.sh` only; memory-bank updates are also required (see DoD)

---

## Definition of Done

- [ ] `--allow-all-tools` added as first element of `guard_args`
- [ ] `shell(sudo"` → `shell(sudo)"` (and same for eval, curl, wget)
- [ ] `shellcheck -S warning scripts/lib/system.sh` passes
- [ ] `env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin" TMPDIR="$TMPDIR" bash --norc --noprofile -c 'bats scripts/tests/lib/'` passes
- [ ] Committed and pushed to `fix/copilot-deny-tool-patterns`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(system): add --allow-all-tools and close malformed --deny-tool patterns in _copilot_review
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `scripts/lib/system.sh`
- Do NOT commit to `main` — work on `fix/copilot-deny-tool-patterns`
- Do NOT change the `_copilot_prompt_guard` forbidden array — those are string match patterns, not CLI flags, and are correct as-is
