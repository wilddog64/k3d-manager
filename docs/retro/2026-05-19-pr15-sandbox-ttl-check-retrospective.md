# Retrospective — PR #15 — Sandbox TTL Check

**Date:** 2026-05-19
**Milestone:** feat(acg): expose sandbox TTL via --check flag; add acg_check_ttl()
**PR:** #15 — merged to main (`9c9b9b44`)
**Participants:** Claude, Codex, Copilot

## What Went Well
- Codex implemented the `--check` flag and `acg_check_ttl()` function correctly on first try
- Spec was surgical: two targeted insertions in `acg_extend.js` + one new function in `acg.sh`
- CI passed on both the implementation commit and the Copilot fix commit
- Copilot correctly caught two real bugs (help text mismatch, Button First click in check mode)
- Branch protection blocked an accidental `push.default=upstream` → main push — no data loss

## What Went Wrong
- `push.default=upstream` with stale branch tracking ref caused initial push to target `main` (blocked by branch protection); Codex had to use explicit refspec `HEAD:refs/heads/fix/acg-sandbox-ttl-check`
- `--check` mode did not short-circuit the Button First click path — would have extended if modal was already open; caught by Copilot

## Process Rules Added
| Rule | File |
|------|------|
| Always use explicit refspec `HEAD:refs/heads/<branch>` when pushing from lib-acg feature branches | spec template |
| `--check`/read-only flags must skip all write/click actions by detecting the flag at the top of the function, not inline after writes | spec template |

## Decisions Made
- `acg_check_ttl()` returns a plain integer (not the `REMAINING_MINS:<n>` prefix) — callers get a clean number ready for arithmetic
- `checkMode` const declared at the top of `extendSandbox()` — single source of truth for the flag, used throughout
- Phase 2 (k3d-manager `bin/acg-up` TTL gate) depends on this PR; spec already written at `k3d-manager/docs/bugs/2026-05-19-acg-up-sandbox-ttl-check-before-provision.md`

## Theme
PR #15 added a lightweight read-only probe mode to `acg_extend.js` so callers can query the sandbox TTL without extending. The implementation was clean but Copilot caught a structural bug: the "Button First" click path ran before the `--check` flag was even inspected, meaning a visible extend button would have triggered an extension. The fix was to hoist `checkMode` to the top of the function and gate the click behind it. The push workflow also hit a git config trap — `push.default=upstream` with a stale tracking ref silently targeted main; branch protection saved us.
