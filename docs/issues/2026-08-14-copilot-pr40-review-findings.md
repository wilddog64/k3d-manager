# Copilot review findings — PR #40 (feat/v0.4.9 DRY_RUN guard primitives)

**PR:** https://github.com/wilddog64/lib-foundation/pull/40
**Fix commit:** `bc06608`
**Date:** 2026-08-14

---

## Finding 1 — DRY_RUN bats tests are not location-independent

**File:** `scripts/tests/lib/system.bats:12–37` (flagged at line 17)

Copilot: the new tests spawn `bash -c` subshells that `source scripts/lib/system.sh`
via a **repo-root-relative** path, which fails if BATS is invoked from a different
working directory. The file's `setup()` already computes an absolute
`$SYSTEM_LIB="${BATS_TEST_DIRNAME}/../../lib/system.sh"` — use that.

**Root cause:** the v0.4.9 spec prescribed the literal `source scripts/lib/system.sh`
preamble, which diverged from the file's existing convention (all other tests call
already-sourced functions directly, or rely on `setup()`). CI only passed because it
runs from the repo root; a foreign cwd would fail the `source` silently, leave the
functions undefined, and produce bogus results.

**Fix:**

```bash
# before
run bash -c 'source scripts/lib/system.sh; DRY_RUN=1 _dry_run_active'
# after
run bash -c "source \"$SYSTEM_LIB\"; DRY_RUN=1 _dry_run_active"
```

Verified: `cd /tmp && bats <abs-path>/system.bats` now passes (would have failed before).

---

## Finding 2 — `mktemp -u` sentinels are racy

**File:** `scripts/tests/lib/system.bats:22,30`

Copilot: `mktemp -u` only *prints* an unused name without reserving it; a colliding
path can make the test flaky. Prefer `mktemp` (create) then `rm -f` to guarantee a
unique, currently-non-existent path.

**Fix:**

```bash
# before
sentinel="$(mktemp -u)"
# after
sentinel="$(mktemp)"
rm -f "${sentinel}"
```

---

## Finding 3 — spec references the wrong changelog filename

**File:** `docs/plans/v0.4.9-dry-run-guard-primitives.md:4,81`

Copilot: the plan lists `CHANGELOG.md`, but this repo's changelog is `CHANGE.md`
(and the PR correctly updated `CHANGE.md`). Fixed both references in the spec so the
doc matches reality if reused.

---

## Process note

The spec author (Claude) hand-wrote the bats preamble instead of instructing the
implementer to **match the existing `setup()`/`$SYSTEM_LIB` convention already in the
target file**. Add to the `/bugfix` + `/handoff` spec rules: when prescribing new BATS
tests, either reuse the file's existing source/setup pattern or explicitly state
"adapt the source preamble to the file's `setup()`" — never paste a divergent
repo-relative `source` line. The changelog-filename mismatch is the same class of
error the spec already carried (spec said `CHANGELOG.md`; implementer correctly used
`CHANGE.md`) — verify referenced filenames against the actual repo before handoff.
