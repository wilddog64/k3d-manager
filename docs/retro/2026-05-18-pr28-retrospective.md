# Retrospective — PR #28

**Date:** 2026-05-18
**PR:** #28 — fix: Copilot CLI auth + rigor scanner improvements
**Merged to:** main (`fee313ed`)
**Participants:** Claude, Copilot

## What Went Well

- Copilot CLI auth refactor removed `K3DM_ENABLE_AI` gate from library code — correct architectural decision (consumer gates belong in callers, not backends)
- BATS coverage for `_copilot_auth_check` and `_agent_lint` added from spec exactly — 6 new tests covering all auth paths + staged file detection for `.js` and `.md` files
- Copilot review was clean — no inline comments, zero findings
- CI green on first push
- Process enforced: spec written, addressed, merged, all in one sprint

## What Went Wrong

- None noted

## Process Rules Added

None — all existing rules followed.

## Decisions Made

- `_copilot_auth_check` checks three sources in priority order: env tokens (`COPILOT_GITHUB_TOKEN`/`GH_TOKEN`/`GITHUB_TOKEN`), `~/.config/github-copilot/apps.json`, then `gh auth status` fallback
- `_agent_lint` now detects staged `.js` and `.md` files alongside `.sh` — broadens scope beyond shell scripts
- Malformed Copilot `--deny-tool` patterns fixed: `shell(sudo`, `shell(eval`, `shell(curl`, `shell(wget` were missing closing `)` — Copilot CLI v1.0.40 exits 1 on parse errors

## Theme

v0.3.19 (unreleased) removes consumer-specific gates from lib-foundation backends. The refactor was clean, tests were comprehensive, and review feedback was zero. The BATS suite validates all auth decision paths (3 env var precedence checks, apps.json fallback, gh auth status fallback, plus failure path) — this is the kind of defensive coverage that prevents silent failures in production. Copilot CLI continues to be a good fit for pre-commit gate functions; the malformed pattern fix improves robustness for future `--deny-tool` additions.
