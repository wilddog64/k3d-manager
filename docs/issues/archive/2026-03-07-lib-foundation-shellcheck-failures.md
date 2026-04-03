# Issue: lib-foundation system.sh shellcheck failures

**Date:** 2026-03-07
**Repo:** `lib-foundation`, branch `extract/v0.1.0`
**Reported by:** Claude (review of Codex extraction task)
**Assigned to:** Codex

---

## Summary

Codex's extraction of `core.sh` and `system.sh` into lib-foundation is incomplete.
`core.sh` passes shellcheck. `system.sh` fails shellcheck with exit code 1, blocking CI.

---

## Findings

### core.sh — PASS ✅

Codex applied two correct fixes to make shellcheck pass:
- Added `# shellcheck shell=bash` directive (line 1)
- `pushd /tmp` → `pushd /tmp >/dev/null || return 1` (SC2164)
- `popd` → `popd >/dev/null || return 1` (SC2164)

These changes deviated from the "verbatim copy" instruction but were necessary to satisfy
the shellcheck requirement. Accepted.

### system.sh — FAIL ❌

`shellcheck scripts/lib/system.sh` exits 1. Findings:

| Code | Severity | Count | Lines | Pattern |
|---|---|---|---|---|
| SC2016 | info | 14 | 383,384,394,396,436,438,464,466,488,489,502,503,524,526,543,548 | `bash -c '..."\$1"...'` — intentional arg-passing pattern |
| SC2046 | warning | 1 | 837 | Unquoted `$(lsb_release -is)` in curl URL |
| SC2086 | info | 2 | 857,944 | Unquoted `$USER`, `$HELM_GLOBAL_ARGS` |
| SC2155 | warning | 3 | 1635,1669,1670 | `local var=$(...)` — declare and assign separately |

---

## Required Fix

Codex must resolve shellcheck exit 1 on `system.sh`. Two acceptable approaches:

**Option A (preferred) — targeted `# shellcheck disable` directives:**
Add per-line or per-block disable comments for the SC2016 false positives
(intentional `bash -c` arg-passing). Fix the genuine SC2046, SC2086, SC2155 findings.

```bash
# Example for SC2016 false positives:
# shellcheck disable=SC2016
_no_trace bash -c 'security delete-generic-password -s "$1" ...' _ "$service"
```

**Option B — fix all findings:**
Fix the SC2046, SC2086, SC2155 warnings (genuine issues). For SC2016, add
`# shellcheck disable=SC2016` block-level around the intentional patterns.

**Option C (not acceptable):**
~~Setting `--severity=error` in CI to suppress info/warning findings.~~
This hides real issues and weakens the CI gate.

---

## Verification

```bash
shellcheck scripts/lib/system.sh
# Expected: exit 0, no output
```

CI must pass on `extract/v0.1.0` before PR can be opened.

---

## Additional Protocol Violations (note only — no fix required)

- Branch was not pushed before reporting completion — CI was never run
- Memory-bank marked task `[x]` complete without CI confirmation
- Future: do not mark complete until `gh run list` shows green CI
