# Bug: `_agent_audit` blocks a commit that replaces a Python assertion with a stronger one

**Status:** FIXED 2026-10-11 (PR #65, merge `f987c40`; released v0.5.2)
**Filed:** 2026-10-11
**Branch:** `fix/agent-audit-assert-removed-allow`
**Approval:** explicit 2026-10-11 (operator chose "Add an audit allow marker" when k3d-manager's pre-commit blocked a spec-mandated assertion replacement)
**Priority:** P2 — a spec-required test change cannot be committed; the only workaround is `--no-verify`, which is forbidden
**Severity:** medium
**Files:** `scripts/lib/agent_rigor.sh`, `scripts/tests/lib/agent_rigor.bats`, `docs/api/functions.md` (the `_agent_audit` row), `README.md` (the `# agent-audit: allow` marker section), `CHANGE.md`

## Symptom

k3d-manager `k3d-manager-v1.43.2`, spec `docs/bugs/2026-10-11-hermes-kine-evidence-not-human-readable.md`:
the evidence text `last_compaction_age=3600s` no longer exists, so the spec replaces

```python
    assert "last_compaction_age=3600s" in kine(lambda *_: (0, payload), state)["evidence"]
```

with three stronger assertions (`evidence.startswith("last compaction 1h 0m ago;")`, …). The
pre-commit hook fails:

```
WARN: Agent audit: assertions removed from Python test files
Pre-commit hook: _agent_audit failed — fix violations before committing
```

## Root cause

`_agent_audit` (`scripts/lib/agent_rigor.sh`, the Python test block) fails on ANY `-assert` line
in the staged diff of a Python test file. A line that is changed is a removal in a diff, so every
legitimate rewrite of an assertion fails. The Python static rules already have a sanctioned escape
(`# agent-audit: allow <rule> <reason>`); the removed-assertion check has none. The warning also
does not say which assertions were removed.

## Fix

`scripts/lib/agent_rigor.sh`, `_agent_audit`, the Python test-file block only:

1. Check removed assertions **per file**, not on the concatenated diff.
2. A file whose staged diff **adds** a line containing
   `# agent-audit: allow assert-removed <reason>` (reason required, non-empty) does not fail on
   its removed assertions. The marker must be on an added (`+`) line: a marker already committed
   in the file, or on a removed line, does not count.
3. Without the marker, fail as today, and print the file path and the removed assertion lines,
   plus the hint `(add '# agent-audit: allow assert-removed <reason>' on an added line in that file if intended)`.
4. With the marker, print the allowed removals with `_info` (so they stay visible in the commit
   output) and do not set `status=1`.
5. The test-function-count check (`test functions decreased`) is unchanged and has no marker.

Replace the current block:

```bash
   local py_file py_status py_path
   local py_test_diff="" removed_py_tests=0 added_py_tests=0 removed_py_assertions=""
   while IFS= read -r -d '' py_file; do
      py_status="${py_file%"${py_file#?}"}"
      py_path="${py_file#?}"
      if { [[ "$py_status" == D ]] && _agent_audit_is_python "$py_path" HEAD; } ||
         { [[ "$py_status" == A ]] && _agent_audit_is_python "$py_path" ""; }; then
         _agent_audit_is_py_test "$py_path" || continue
         py_test_diff+="$(git diff --cached --no-renames -- "$py_path" 2>/dev/null || true)"$'\n'
      fi
   done < <(_agent_audit_py_files)
   if [[ -n "$py_test_diff" ]]; then
      removed_py_tests=$(grep -cE '^-[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_' <<<"$py_test_diff" || true)
      added_py_tests=$(grep -cE '^\+[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_' <<<"$py_test_diff" || true)
      if (( removed_py_tests > added_py_tests )); then
         _warn "Agent audit: number of test functions decreased in Python test files"
         status=1
      fi
      removed_py_assertions=$(grep -E '^-[[:space:]]*(assert([[:space:](]|$)|self\.assert)' <<<"$py_test_diff" || true)
      if [[ -n "$removed_py_assertions" ]]; then
         _warn "Agent audit: assertions removed from Python test files"
         status=1
      fi
   fi
```

with:

```bash
   local py_file py_status py_path py_file_diff py_file_removed
   local py_test_diff="" removed_py_tests=0 added_py_tests=0 removed_py_assertions="" allowed_py_assertions=""
   local assert_allow_re='^\+.*#[[:space:]]*agent-audit:[[:space:]]*allow[[:space:]]+assert-removed[[:space:]]+[^[:space:]]'
   while IFS= read -r -d '' py_file; do
      py_status="${py_file%"${py_file#?}"}"
      py_path="${py_file#?}"
      if { [[ "$py_status" == D ]] && _agent_audit_is_python "$py_path" HEAD; } ||
         { [[ "$py_status" == A ]] && _agent_audit_is_python "$py_path" ""; }; then
         _agent_audit_is_py_test "$py_path" || continue
         py_file_diff="$(git diff --cached --no-renames -- "$py_path" 2>/dev/null || true)"
         py_test_diff+="$py_file_diff"$'\n'
         py_file_removed=$(grep -E '^-[[:space:]]*(assert([[:space:](]|$)|self\.assert)' <<<"$py_file_diff" || true)
         if [[ -n "$py_file_removed" ]]; then
            if grep -Eq "$assert_allow_re" <<<"$py_file_diff"; then
               allowed_py_assertions+="$py_path:"$'\n'"$py_file_removed"$'\n'
            else
               removed_py_assertions+="$py_path:"$'\n'"$py_file_removed"$'\n'
            fi
         fi
      fi
   done < <(_agent_audit_py_files)
   if [[ -n "$py_test_diff" ]]; then
      removed_py_tests=$(grep -cE '^-[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_' <<<"$py_test_diff" || true)
      added_py_tests=$(grep -cE '^\+[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_' <<<"$py_test_diff" || true)
      if (( removed_py_tests > added_py_tests )); then
         _warn "Agent audit: number of test functions decreased in Python test files"
         status=1
      fi
      if [[ -n "$removed_py_assertions" ]]; then
         _warn "Agent audit: assertions removed from Python test files (add '# agent-audit: allow assert-removed <reason>' on an added line in that file if intended):"
         _warn "${removed_py_assertions%$'\n'}"
         status=1
      fi
      if [[ -n "$allowed_py_assertions" ]]; then
         _info "Agent audit: Python assertions removed under an assert-removed allow marker:"
         _info "${allowed_py_assertions%$'\n'}"
      fi
   fi
```

Note: Python test files are excluded from the static-rule scan (`! _agent_audit_is_py_test`), so
the marker comment cannot trip another rule.

## Tests

`scripts/tests/lib/agent_rigor.bats`, next to `_agent_audit detects removed Python assertions`
(keep that test; extend it to also assert the output contains `assert value` and `tests/test_a.py`):

1. **Marker allows:** commit `tests/test_a.py` with `assert value`; restage with
   `assert value2  # agent-audit: allow assert-removed format changed` → status 0, output contains
   `assert-removed allow marker` and `assert value`.
2. **Reason required:** the marker with no reason (`# agent-audit: allow assert-removed`) → status
   non-zero, `assertions removed`.
3. **Per file:** two test files each lose an assertion; only `tests/test_a.py` adds the marker →
   status non-zero, output names `tests/test_b.py`.
4. **Already-committed marker does not count:** commit a file that already contains the marker
   comment and `assert value`; remove only `assert value` → status non-zero.
5. **Test-count check has no escape:** delete a `def test_` function while adding the marker →
   status non-zero, `test functions decreased`.

Mutations (each must turn a test red, restore with `cmp` against a snapshot):
- drop the reason requirement (`[[:space:]]+[^[:space:]]` → empty) → test 2 red;
- check the marker against `py_test_diff` (all files) instead of `py_file_diff` → test 3 red;
- drop the leading `^\+` from `assert_allow_re` → test 4 red.

Gates: `bats scripts/tests/lib/agent_rigor.bats` and the full `bats scripts/tests/lib/`;
`shellcheck scripts/lib/agent_rigor.sh` at **default severity** (CI runs default).

## Docs

- `CHANGE.md` `[Unreleased]` → `### Fixed` entry.
- `docs/api/functions.md` `_agent_audit` row: add the `# agent-audit: allow assert-removed <reason>`
  marker (per file, on an added line, reason required; the test-count check has no marker).
- `README.md`, the section around the `# agent-audit: allow shell-true` example: one short
  paragraph and example for `assert-removed`.

## What NOT to Do

- Do NOT add an escape for the test-function-count check.
- Do NOT accept a marker without a reason, or a marker that is not on an added line.
- Do NOT change any other `_agent_audit` check.
- Do NOT commit, push, or create a PR. Claude verifies and commits.
- Do NOT modify files outside the Files list.
