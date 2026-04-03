# Copilot PR #45 Review Findings

**PR:** #45 — feat(ci): dynamic plugin detection — skip docs-only, map plugins to smoke tests
**Date:** 2026-03-22
**Files reviewed:** `docs/plans/v0.9.11-dynamic-plugin-ci.md`
**Findings:** 2 (both doc accuracy)

---

## Finding 1 — Plugin path prefix missing in mapping table

**File:** `docs/plans/v0.9.11-dynamic-plugin-ci.md:45`
**Copilot flagged:** Plugin file paths listed as `plugins/<name>.sh` but the repo layout and workflow grep both use `scripts/plugins/`. Misleading for anyone cross-referencing the spec with the workflow.

**Before:**
```
| `plugins/jenkins.sh` | `test_jenkins` | Full suite |
| `plugins/vault.sh` | `test_vault` | ... |
...
```

**After:**
```
| `scripts/plugins/jenkins.sh` | `test_jenkins` | Full suite |
| `scripts/plugins/vault.sh` | `test_vault` | ... |
...
```

**Fix commit:** `85e0063`
**Root cause:** Spec written with abbreviated paths for readability; actual layout not double-checked.
**Process note:** Spec tables referencing file paths must use paths relative to repo root, matching what `git diff --name-only` would output.

---

## Finding 2 — Rules vs Definition of Done contradiction

**File:** `docs/plans/v0.9.11-dynamic-plugin-ci.md:193`
**Copilot flagged:** `## Rules` said "Do NOT modify any file other than `.github/workflows/ci.yml`" but `## Definition of Done` required updating `memory-bank/activeContext.md` — contradictory.

**Before:**
```
- Do NOT modify any file other than `.github/workflows/ci.yml`
```

**After:**
```
- Do NOT modify any file other than `.github/workflows/ci.yml` (and `memory-bank/activeContext.md` after the commit — required by Definition of Done)
```

**Fix commit:** `85e0063`
**Root cause:** Rules section copied from a previous spec without updating the file list; memory-bank update requirement is standard DoD boilerplate but wasn't reflected in Rules.
**Process note:** When writing Rules, always cross-check against Definition of Done — any file listed in DoD must be explicitly allowed in Rules.
