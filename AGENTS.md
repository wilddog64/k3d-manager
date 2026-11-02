# Repository Guidelines — lib-foundation

## Project Overview

Shared Bash foundation library consumed by `k3d-manager`, `rigor-cli`, and `shopping-carts` via git subtree.
No dispatcher, no cluster — this is a pure Bash library. All work is code + tests.

## Project Structure

```
scripts/lib/           # Library source files
  core.sh              # Cluster lifecycle, provider abstraction, _resolve_script_dir
  system.sh            # _run_command privilege model, package helpers, OS detection
  agent_rigor.sh       # Agent audit tooling: _agent_checkpoint, _agent_audit, _agent_lint
scripts/tests/lib/     # BATS unit tests (one suite per lib file)
memory-bank/           # activeContext.md + progress.md — read first, update after
docs/plans/            # Task specs — read the assigned spec before touching any file
docs/issues/           # Post-mortems and issue logs
```

## Build, Test, and Quality Commands

```bash
# BATS unit tests — always use clean env
env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin" TMPDIR="$TMPDIR" \
  bash --norc --noprofile -c 'bats scripts/tests/lib/system.bats scripts/tests/lib/core.bats scripts/tests/lib/agent_rigor.bats'

# shellcheck — run on every touched .sh file before commit
shellcheck scripts/lib/system.sh scripts/lib/core.sh scripts/lib/agent_rigor.sh

# Agent rigor if-count audit
AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/lib/system.sh
```

## Coding Style

- `#!/usr/bin/env bash` + `set -euo pipefail` on all scripts
- 2-space indentation, snake_case functions and variables
- Public functions: no underscore. Private: `_` prefix
- Double-quote all variable expansions — never bare `$var` in command args
- No bare `sudo` — always `_run_command --prefer-sudo -- <cmd>`
- LF line endings only

## Bash 3.2 Compatibility (hard requirement)

- **No `local -n`** (nameref, requires bash 4.3+)
- **No `declare -A`** (associative arrays)
- **No `mapfile` / `readarray`**
- Use global temp vars (e.g., `_RCRS_RUNNER`) for array output from helper functions

## `_run_command` — Privilege Escalation Wrapper

Never call `sudo` directly. Always route through `_run_command`:

```bash
_run_command --prefer-sudo -- apt-get install -y jq    # sudo if available, else user
_run_command --require-sudo -- mkdir /etc/myapp         # fail if sudo unavailable
_run_command --probe 'config current-context' -- kubectl get nodes  # probe to decide
_run_command --quiet -- command_that_might_fail         # suppress stderr, return exit code
```

## Commit & Pull Request Guidelines

- Conventional-style prefixes: `fix:`, `feat:`, `docs:`, `test:`
- Explain *why* in the commit body
- Run shellcheck + BATS (`env -i`) + agent_rigor audit before every commit
- **Do NOT create PRs** — that is Claude's job. Your task ends at: commit + push + memory-bank update

---

## Agent Session Rules (read every session — no exceptions)

### 1. Read memory-bank first

Before touching any file, read:
- `memory-bank/activeContext.md` — current branch, focus, open items
- `memory-bank/progress.md` — what is complete, what is pending

These contain decisions already made. Do not re-derive them from scratch.

### 2. Verify your machine

First command of every session:
```bash
hostname && uname -n
```
Confirm you are on the correct machine before doing anything else.

### 3. Proof of work — commit SHA + test results required

Reporting "done" requires:
- A real commit SHA pushed to the remote branch (`git log origin/<branch> --oneline -3`)
- BATS output showing all tests passing (with `env -i`)
- `shellcheck` clean on every touched `.sh` file
- `AGENT_AUDIT_MAX_IF=8` audit passing — all functions ≤ 8 if-blocks

A memory-bank update alone is NOT proof of completion.

### 4. Commit before reporting done

Every task ends with a real git commit pushed to the remote branch.
Never report completion without a verifiable commit SHA on the remote.

### 5. Do NOT create PRs — that is Claude's job

Your task ends at: commit + push to branch + update memory-bank.
Do NOT run `gh pr create`. Do NOT rerun CI jobs.
If CI fails, read the failure logs, fix the root cause, and push a new commit.

### 6. Stay within spec scope

Do not add features, refactor code, or make improvements beyond what the spec requires.
Do not modify files outside the scope of the current task.
If you find a bug outside your scope, report it in the memory-bank — do not fix it silently.

### 7. Never bypass hooks

- Never use `git commit --no-verify`
- Never use `git push --force` on shared branches
- If a pre-commit hook fails, fix the underlying issue and retry

### 8. Update memory-bank on completion

When your task is done, update `memory-bank/activeContext.md` and `memory-bank/progress.md`
to reflect what you completed. Include the real commit SHA.
