# Copilot PR #37 Review Findings

**PR:** #37 — `fix(acg): acg_restart entrypoint + sweep stale playwright temp dirs`
**Branch:** `feat/v0.4.6`
**Date:** 2026-07-20
**Fix commit:** `330083b`

Copilot flagged two inline findings on the new/moved ACG shell-wrapper code. Both were
valid and fixed in `330083b`.

---

## Finding 1 — `_acg_sweep_stale_artifacts`: empty sweep path when `TMPDIR=/`

**File:** `scripts/lib/acg/acg.sh:446` (`_acg_sweep_stale_artifacts`)

Copilot: `find "${tmpdir%/}"` — if `TMPDIR=/`, the `%/` strip yields an empty string, so
`find ""` runs against a bad path (and `-exec rm -rf {} +` makes any path confusion
dangerous).

**Before:**
```bash
local tmpdir="${TMPDIR:-/tmp}"
find "${tmpdir%/}" -maxdepth 1 -name 'playwright-artifacts-*' -type d -mmin +120 \
  -exec rm -rf {} + 2>/dev/null || true
```

**After:**
```bash
local tmpdir="${TMPDIR:-/tmp}"
tmpdir="${tmpdir%/}"
find "${tmpdir:-/}" -maxdepth 1 -name 'playwright-artifacts-*' -type d -mmin +120 \
  -exec rm -rf {} + 2>/dev/null || true
```

`${tmpdir:-/}` restores `/` when the trailing-slash strip emptied it, so `TMPDIR=/`
correctly sweeps `/playwright-artifacts-*`.

---

## Finding 2 — node exit capture aborts the caller under `set -e`

**File:** `scripts/lib/acg/acg.sh:465` (`_acg_restart_playwright`) — Copilot-flagged.
Same latent bug fixed in sibling `_acg_extend_playwright:430` (the matched wrapper this
PR's sweep helper also feeds).

Copilot: `output=$(node ...)` followed by `exit_code=$?` — under a caller `set -e`, a
non-zero `node` exit terminates the shell at the assignment, so the graceful
`if [[ $exit_code -ne 0 ]]; then ... return 1` error path is never reached. (`acg.sh`
runs under `set -euo pipefail`, so this is live.) The happy path worked — which is why
the wiring live-verified — but the failure path was dead.

**Before:**
```bash
local output exit_code
output=$(node "$playwright_script" "$sandbox_url" --provider "$provider" 2>&1)
exit_code=$?
```

**After:**
```bash
local output exit_code=0
output=$(node "$playwright_script" "$sandbox_url" --provider "$provider" 2>&1) || exit_code=$?
```

Moving the capture into a `|| exit_code=$?` list suppresses `set -e` for the substitution
and still records `node`'s real exit code. Same class as the k3d-manager k3s-aws
`(( var++ ))` set -e fix.

---

## Root cause

Both wrappers were authored with the "assign then check `$?`" idiom, which is not
`set -e`-safe for command substitutions. The canonical form already in this file
(`acg.sh:307`, `if ! output=$(node ...); then`) was the model that should have been used.

## Process note / follow-up

- **Pre-existing sibling (out of scope for #37):** `acg.sh:517` (`acg_check_ttl` node
  probe) has the identical `output=$(...)` / `exit_code=$?` pattern. It predates this PR
  and is not touched here — file a follow-up to convert it to the `|| exit_code=$?` form.
- **Local vs CI shellcheck drift:** local `shellcheck 0.11.0` did not flag SC2119/SC2120
  that CI's newer build did (fixed in `1c0dc51`). Pre-PR gates should run shellcheck at
  the CI version, not just the locally-installed one.
