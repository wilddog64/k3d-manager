# Repository Guidelines

## Project Structure & Module Organization
`scripts/` houses the dispatcher (`k3d-manager`), shared libs in `scripts/lib/`, provider glue in `scripts/lib/providers/`, and optional `scripts/plugins/*.sh`. Tests live under `scripts/tests/` with helper BATS harness files beside suite directories (`lib`, `plugins`). Documentation is in `docs/` (architecture, providers, guides, issues) while `memory-bank/` tracks active spec context. Use `bin/` for helper binaries and keep user-specific scratch work in `scratch/`.

## Build, Test, and Development Commands
- `./scripts/k3d-manager <function>` — primary entrypoint; run `deploy_cluster`, `deploy_vault`, etc. from repo root.
- `./scripts/k3d-manager test all` — runs the curated BATS bundles defined in `scripts/lib/test.sh`.
- `bats scripts/tests` — executes every suite; handy before large refactors.
- `shellcheck scripts/**/*.sh` — lint every touched shell file; CI blocks on failures.
- `./install.sh` — bootstrap local deps (bash 5, bats, shellcheck, jq) if the host is fresh.

## Coding Style & Naming Conventions
Write pure Bash with portable `#!/usr/bin/env bash`. Match the existing 2-space indentation used in `scripts/`, prefer snake_case for functions/files (`deploy_vault`, `plugins/shopping_cart.sh`), and guard sourced files with `# shellcheck source=` hints. Keep functions idempotent, avoid unbounded `if` depth (Agent Rigor flags this), and favor `_run_command` helpers instead of raw subshell pipelines. Templates in `scripts/etc/` should stay `.yaml.tmpl` and load values from `vars.sh`.

## Testing Guidelines
BATS is the canonical framework. Name suites `<area>.bats` and tests `@test "<component>: <expectation>"`. Extend shared helpers via `scripts/tests/test_helpers.bash` rather than duplicating logic. Every PR must keep `./scripts/k3d-manager test all` green, preserve or increase `@test` counts (enforced by `_agent_audit`), and document new suites in `docs/tests` if they cover novel flows. For provider-specific behavior, add focused suites under `scripts/tests/lib/provider_contract.bats` or create plugin-level suites mirroring the file under test.

## Commit & Pull Request Guidelines
Follow the short, Conventional-style prefixes seen in history (`docs:`, `fix:`, `v0.9.0 — …`). Squash unrelated work, explain *why* in the body, and mention linked issues or specs when possible. Before committing, run `_agent_checkpoint`, `_agent_lint`, and `_agent_audit` (pre-commit hook) to prove specs, lint, and security gates pass. Pull requests should state the scenario exercised, include command output for key flows (e.g., `bats` summary), and attach screenshots when UI manifests (Jenkins, ArgoCD) change. Keep branches rebased so Agent Rigor diffs stay tight.

---

## Agent Session Rules (read every session — no exceptions)

### 1. Read memory-bank first
Before touching any file, read both:
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
Reporting "done" requires ALL of the following — paste actual output, not summaries:

- **Commit SHA** — run `git log origin/<branch> --oneline -3` and paste the output
- **BATS output** — paste the full `bats scripts/tests/...` result (pass/fail counts)
- **shellcheck** — paste `shellcheck scripts/plugins/<touched>.sh` output (must be clean)
- **`_agent_audit`** — must pass (all functions ≤ 8 if-blocks)

A memory-bank update alone is NOT proof of completion.
A summary like "all tests passed" without pasted output is NOT proof of completion.

### 4. Commit before reporting done
Every task ends with a real git commit pushed to the remote branch.
Never report completion without a verifiable commit SHA on the remote.

### 5. Do NOT create PRs — that is Claude's job
Your task ends at: commit + push to branch + update memory-bank.
Do NOT run `gh pr create`. Do NOT rerun CI jobs (`gh run rerun`).
If CI fails, read the failure logs (`gh run view <id> --log-failed`), fix the root cause, and push a new commit.

### 6. Do not revert intentional decisions
Comments marked `# DO NOT REMOVE` or `<!-- DO NOT REMOVE -->` in code must not be deleted.
Decisions recorded in `memory-bank/` must not be silently reversed.
If you believe a decision is wrong, report it — do not quietly undo it.

### 7. Stay within spec scope
Do not add features, refactor code, or make improvements beyond what the spec requires.
Do not modify files outside the scope of the current task.
If you find a bug outside your scope, report it in the memory-bank — do not fix it silently.

### 8. Never bypass hooks
- Never use `git commit --no-verify`
- Never use `git push --force` on shared branches
- Never use `git rebase` or `git reset --hard` on shared branches
- If a pre-commit hook fails, fix the underlying issue and retry

### 9. Update memory-bank on completion
When your task is done, update `memory-bank/activeContext.md` and `memory-bank/progress.md`
to reflect what you completed. Include the real commit SHA and PR URL.
