# Review: dirused PR #14 (M2a fullness levels) — blind diff review

**Filed:** 2026-11-17
**Repo / branch:** `dirused` / `m2a-fullness-levels` (head 90ce085; diff `3865f28..90ce085`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff 3865f28..90ce085` blind. Intended behaviour:

- `/warn <n>` (default 85) and `/crit <n>` (default 90): integers 1-100, else exit 1 with
  `/warn requires an integer between 1 and 100` (same for `/crit`); `/warn` at or above `/crit` is refused with
  `/warn must be below /crit`, including `/warn 95` against the default `/crit 90`.
- A complete target with a probed volume (`TotalBytes > 0`) is `crit` at or above `/crit`, else `warn` at or above `/warn`,
  else `ok`; any other target has no level.
- In `/summary` text and default text, a `warn` volume line ends ` [WARN]`, a `crit` line ` [CRIT]`; an `ok` line is byte
  for byte what it was before. On the real console, not redirected and with `NO_COLOR` unset or empty, `warn` lines are
  yellow and `crit` red via `Console.ForegroundColor`, then reset; any other writer (file, pipe, test `StringWriter`) gets
  plain text. No ANSI escape codes anywhere.
- `/summary` text ends with `<n> volume(s): <c> at or above <crit>%, <w> at or above <warn>%` (`<w>` excludes crit volumes)
  when at least one volume line was printed.
- JSON targets gain `level` (`ok`, `warn`, `crit` or `null`); `/summary` CSV gains a final `level` column (empty on error
  rows); non-summary CSV unchanged.
- Exit code 4 when any target is `crit`; otherwise 3 if any target is incomplete; otherwise 0. Usage errors stay 1.

Look for: a wrong boundary (`>` vs `>=`), a line whose tag or colour disagrees with its level, colour leaking into a
redirected stream or left set after an exception, the console colour never turning on at all, exit-code precedence wrong
or inconsistent with the footer count, JSON or CSV compatibility breaks beyond the one added field and column, `with`
copies that drop `Level`, usage/README/PACKAGE-README text that disagrees with the code, tests that cannot fail.

## Before You Start

1. Read `README.md`, `tools/PACKAGE-README.txt`, `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/Options.cs`,
   `src/Dirused.Common/ScanResult.cs`, `src/Dirused.Common/Renderers/*.cs`, `src/Dirused.Cli/Program.cs` and the changed tests.
2. `git log --oneline -3` and confirm HEAD is 90ce085.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/Renderers/Fullness.cs` | read only |
| `src/Dirused.Cli/Program.cs` | read only |
| `src/Dirused.Common/ArgParser.cs` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT run tests that need Windows; reason from the code. `dotnet test tests/Dirused.Tests.Portable -p:NuGetAudit=false` may be run.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back: one line per finding as `file:line — defect — concrete failure scenario — severity (high/medium/low)`,
      or `no findings`. Mark each as verified-from-code or speculative.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report lists findings or "no findings"
    intent: An independent model checks the fullness-levels change before you try it on the real server list at the office.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "when slot allowed, can you also dispatch dirused tasks?" (M2a); dirused PRs get a blind Argon review per the PR review budget.
