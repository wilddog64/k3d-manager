# Copilot PR #29 Review Findings

**PR:** [#29 fix(v0.3.1): pre-commit word-split, acg_check_ttl sentinel, package version align](https://github.com/wilddog64/lib-acg/pull/29)
**Fix commit:** `41993e2`

---

## Finding 1 — `scripts/hooks/pre-commit:46` — `git grep` regex metachar false positives

**What Copilot flagged:**
`git grep` treats the pattern as a regex by default. A deleted basename like `foo.sh` causes `.` to match any character, potentially matching unrelated strings and falsely blocking commits.

**Fix applied:**
```bash
# Before:
_refs="$(git grep --cached -l "$_base" -- '*.sh' '*.js' 2>/dev/null || true)"

# After:
_refs="$(git grep -F --cached -l "$_base" -- '*.sh' '*.js' 2>/dev/null || true)"
```

**Root cause:** `-F` (fixed-string) flag omitted from original `git grep` call.

**Process note:** All `git grep` calls searching for literal filenames must use `-F`.

---

## Findings 2–4 — Spec doc "Rules" wording — `docs/bugs/v0.3.1-bugfix-*.md`

**What Copilot flagged:**
Three spec docs used "No other files touched" in the `## Rules` section, which conflicts with the process rule that docs/memory-bank updates may accompany any code-only change.

**Fix applied** (all three files):
```
# Before:
- No other files touched

# After:
- Code change limited to <file(s)>; docs/memory-bank updates may also be required
```

**Root cause:** `/bugfix` spec template uses "No other files touched" — template needs updating.

**Process note:** Update the `/bugfix` skill spec template `## Rules` boilerplate to use the new phrasing.
