# Issue Log: Copilot PR #17 Review Findings

**Date:** 2026-03-25
**PR:** #17 — feat: v0.3.11 — YAML hardcoded-IP check in _agent_audit
**Reviewer:** Copilot
**Fix commit:** `69575fc`

---

## Finding 1 — BATS tests cover only `.yaml`, not `.yml`

**File:** `scripts/tests/lib/agent_rigor.bats` line 226
**What Copilot flagged:** Both YAML tests use `.yaml` files. The `.yml` pathspec has no test coverage.

**Fix:** Added a third test `_agent_audit: fails when staged yml contains hardcoded IP` staging `config.yml` with `host: 10.0.0.1` — confirms `.yml` pathspec triggers the same failure.

**Root cause:** Spec template only included two tests (pass/fail for `.yaml`).

**Process note:** When adding checks for multiple file extensions, spec must include at least one test per extension.

---

## Finding 2 — Spec doc typo "YAML/YAML"

**File:** `docs/plans/v0.3.11-agent-audit-yaml-ip-check.md` line 20
**What Copilot flagged:** "YAML/YAML" reads as a duplicate — should be "`.yaml`/`.yml`".

**Fix:** Corrected to "Add a staged `.yaml`/`.yml` file check to `_agent_audit` that:"

**Root cause:** Copy-paste error in spec Goal section.

---

## Finding 3 — Spec references wrong test file path (Definition of Done)

**File:** `docs/plans/v0.3.11-agent-audit-yaml-ip-check.md` line 44
**What Copilot flagged:** `scripts/tests/agent_rigor.bats` — actual location is `scripts/tests/lib/agent_rigor.bats`.

**Fix:** Updated all occurrences to `scripts/tests/lib/agent_rigor.bats` via `replace_all`.

**Root cause:** Spec was written using a wrong assumption about test layout.

---

## Finding 4 — Spec BATS section header references wrong path

**File:** `docs/plans/v0.3.11-agent-audit-yaml-ip-check.md` line 113
**What Copilot flagged:** Same wrong path in the "Add to" section header.

**Fix:** Covered by the same `replace_all` as Finding 3.

---

## Finding 5 — `for file in $changed_yaml` splits on whitespace

**File:** `scripts/lib/agent_rigor.sh` line 182
**What Copilot flagged:** Word-splitting on `$changed_yaml` mis-handles file paths containing spaces. Prefer NUL-delimited iteration.

**Fix applied (`69575fc`):**

Before:
```bash
local changed_yaml
changed_yaml="$(
   git diff --cached --name-only -- '*.yaml' '*.yml' 2>/dev/null || true
)"
if [[ -n "$changed_yaml" ]]; then
   local file
   for file in $changed_yaml; do
      [[ -f "$file" ]] || continue
      ...
   done
fi
```

After:
```bash
local file
while IFS= read -r -d '' file; do
   ...
done < <(git diff --cached --name-only --diff-filter=ACM -z -- '*.yaml' '*.yml' 2>/dev/null || true)
```

**Root cause:** Initial implementation followed the existing `for file in $changed_sh` pattern; should have used NUL-delimited from the start for robustness.

**Process note:** New file-iteration loops in `_agent_audit` should always use `-z` + `while IFS= read -r -d ''`.

---

## Finding 6 — `[[ -f "$file" ]]` guard checks worktree, not index

**File:** `scripts/lib/agent_rigor.sh` line 182
**What Copilot flagged:** The worktree file check skips staged files that aren't in the worktree (intent-to-add, sparse checkouts). `--diff-filter=ACM` is the correct gate.

**Fix:** Addressed together with Finding 5 — `--diff-filter=ACM` added to `git diff`, `-f` guard removed.

---

## Finding 7 — `rm -rf "$repo"` not called if BATS assertion fails

**File:** `scripts/tests/lib/agent_rigor.bats` line 232
**What Copilot flagged:** If an assertion inside the subshell fails, the test exits before `rm -rf "$repo"` — temp directory leaks.

**Fix applied (`69575fc`):**

Before:
```bash
repo="$(mktemp -d)"
...
rm -rf "$repo"
```

After:
```bash
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' RETURN
...
# rm -rf removed — trap handles cleanup
```

**Root cause:** Missing trap pattern; cleanup was manual.

**Process note:** All BATS tests that create temp dirs must use `trap 'rm -rf "$dir"' RETURN` immediately after `mktemp -d`.
