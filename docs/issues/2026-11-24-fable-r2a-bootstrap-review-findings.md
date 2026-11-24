# Fable design + code review of R2 child A (`bin/k3dm-verified-stage`), after correction 3

**Date:** 2026-11-24
**Reviewer:** Fable (blind, from the parent spec, the child spec and the uncommitted worktree code)
**Verdict:** NEEDS FIXES — no blocker, no route to root for the file/environment attacker; five medium items.
**Gate:** operator, 2026-11-24 ("go ahead to do correction 3" + "go for it": Fable review before landing).

## Claude's check

Confirmed from code: the ancestor walk starts at `$_VS_BASE`, so `$_VS_BASE/stage` is never checked (`:134`); the fetch
adds `origin` and fetches by name, so the URL comes from `repo.git` config (`:92-94`). The spec drift (seams, process
substitution) was caused by Claude's correction-2 instruction to delete dead helpers; the spec is amended instead.

## Mapping

| Finding | Severity | Disposition |
|---|---|---|
| `base/stage` not in the ancestor walk | medium | correction 4 F1 |
| URL read from `repo.git` config | medium | correction 4 F2; spec Clarification 2 |
| spec requires `_vs_git_argv`/`_vs_child_argv`, process-substitution line | medium | spec amended (Clarification 2) |
| SIGQUIT kills `run`/wrapper with no trap | medium | correction 4 F5; spec Clarification 2 |
| `--install-self` e2e test cannot fail (same copy staged) | medium | correction 4 T1 |
| wrapper ticket live during fetch; `sudo -k <command>` would avoid it | medium (speculative) | operator decision: needs a sudo probe at home before any spec change |
| residual 5 wording (`tty` ticket shared within the terminal session) | medium (speculative) | spec Clarification 2; howto (child D) |
| entry list via caller-owned `/tmp` file (fail-open on truncation) | low | correction 4 F3 |
| root git without `-C`, no `cd /` in root forms | low | correction 4 F4 |
| `sudo -k \|\| true` before the child (fail-open) | low | correction 4 F6 |
| exit 5 prints no tips | low | correction 4 F7 |
| bare `cat`; `id -P` failure exits 1 | low | correction 4 F8 |
| deferred HUP/INT/TERM traps while the child waits | low | residual, recorded in Clarification 2 |
| run-mode re-check is an operator-mistake detector, not an attacker defence | low | spec Clarification 2 |
| no anti-rollback; rejected stages stay runnable | low (speculative) | deferred: candidate for the P3 `installer-direct-run-hardening-deferred` |
| env_reset/env_keep unproven for root's other tools | low | covered by `cd /` (F4); probe with the sudo one above |
| test gaps: diff-guard content, entry-point failing child/presence vars, real constants in some copies, misleading title, timing-margin signal tests | low | correction 4 T2-T6 |
| redundant checks mask some mutants; slow per-entry forks | low | accepted (defence in depth; performance not measured) |
