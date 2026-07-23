# Add `scripts/check-stale-test-refs.sh` — catch stale test assertions after a move/rename

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/check-stale-test-refs.sh` (NEW), `scripts/tests/lib/stale_test_refs.bats` (NEW)

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "stale test reference check" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `docs/bugs/2026-07-18-provider-contract-stale-data-layer-assertion.md` (regression #2)
  - `docs/bugs/2026-07-18-argocd-dashboard-bats-regression.md` (regression #1)
  - `scripts/check-doc-links.sh` if it exists — match its style and exit-code convention
- Implement exactly what is written — no interpretation, no extra refactors.

---

## Problem

Three regressions on branch `k3d-manager-v1.16.0` share one root cause: a spec moved or
renamed a string in `scripts/etc/`, and a BATS suite that asserted the old string was never
updated because the spec's gate list did not include it.

| Commit | Change | Suite left stale | Caught by |
|---|---|---|---|
| `4c89dabb` | trivy panels moved to a new dashboard file | `argocd_metrics_servicemonitor.bats` | Codex, while blocked on another task |
| `f03df202` | `data-layer` → `'{{.name}}-data-layer'` | `provider_contract.bats` | incidental, 14 days later |
| (near miss) | envsubst spec listed 2 suites; a grep found 8 | — | pre-handoff validation |

The written rule ("derive the gate list from a grep across `scripts/tests/`") has now been
violated twice and nearly a third time. A rule that depends on remembering to apply it is
not working; this makes it mechanical.

---

## Fix

### Change 1 — NEW `scripts/check-stale-test-refs.sh`

Write exactly this file, then `chmod +x` it:

```bash
#!/usr/bin/env bash
# Fail when a commit removes a string from scripts/etc/ that scripts/tests/ still asserts.
set -euo pipefail

_range="${1:-HEAD^..HEAD}"
cd "$(git rev-parse --show-toplevel)"

_hits=0
_report() {
  printf '%s\n  removed from: %s\n' "$1" "$2"
  printf '%s\n' "$3" | sed 's/^/  still asserted in: /'
  _hits=$((_hits + 1))
}

while IFS= read -r _file; do
  [[ -z "${_file}" ]] && continue
  _base="$(basename "${_file}")"
  while IFS= read -r _line; do
    _frag="${_line#"${_line%%[![:space:]]*}"}"
    _frag="${_frag%"${_frag##*[![:space:]]}"}"
    [[ ${#_frag} -lt 10 ]] && continue
    [[ "${_frag}" != *:* && "${_frag}" != *[[:space:]]* ]] && continue
    [[ "${_frag}" == *'${'* ]] && continue
    [[ -f "${_file}" ]] && grep -qF -- "${_frag}" "${_file}" 2>/dev/null && continue
    _consumers="$(grep -rlF -- "${_frag}" scripts/tests/ 2>/dev/null || true)"
    [[ -z "${_consumers}" ]] && continue
    if grep -rqF -- "${_frag}" scripts/etc/ 2>/dev/null; then
      _tied="$(printf '%s\n' "${_consumers}" | xargs -r grep -lF -- "${_base}" 2>/dev/null || true)"
      [[ -n "${_tied}" ]] && _report "MOVED OUT OF ${_base}: ${_frag}" "${_file}" "${_tied}"
    else
      _report "REMOVED: ${_frag}" "${_file}" "${_consumers}"
    fi
  done < <(git diff "${_range}" -- "${_file}" | grep '^-' | grep -v '^---' | sed 's/^-//' \
    | awk '{ print } /"/ { n=split($0, a, /"/); for (i=2; i<=n; i+=2) if (length(a[i]) >= 10) print a[i] }' \
    | sort -u || true)
done < <(git diff --name-only "${_range}" -- scripts/etc/ || true)

if (( _hits > 0 )); then
  printf '\n%s stale test reference(s) — retarget the tests or list them in the spec gates.\n' "${_hits}"
  exit 1
fi
printf 'no stale test references\n'
```

### Change 2 — NEW `scripts/tests/lib/stale_test_refs.bats`

Write exactly this file:

```bash
#!/usr/bin/env bats

CHECK="${BATS_TEST_DIRNAME}/../../check-stale-test-refs.sh"

@test "stale-ref check is executable" {
  [ -x "${CHECK}" ]
}

@test "stale-ref check flags the f03df202 data-layer rename" {
  run "${CHECK}" 'f03df202^..f03df202'
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"provider_contract.bats"* ]]
}

@test "stale-ref check flags the 4c89dabb trivy split" {
  run "${CHECK}" '4c89dabb^..4c89dabb'
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"argocd_metrics_servicemonitor.bats"* ]]
}

@test "stale-ref check is quiet on a commit that touched no etc files" {
  run "${CHECK}" 'e3a75f1f^..e3a75f1f'
  [ "${status}" -eq 0 ]
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/check-stale-test-refs.sh` | NEW — detects stale test assertions after a move/rename |
| `scripts/tests/lib/stale_test_refs.bats` | NEW — 4 tests, pinned to the two real regressions |

---

## Rules

- `bash -n scripts/check-stale-test-refs.sh` — clean
- `shellcheck -S warning scripts/check-stale-test-refs.sh` — zero warnings
- `test -x scripts/check-stale-test-refs.sh` — must be executable (`chmod +x`)
- `bats scripts/tests/lib/stale_test_refs.bats` — **4/4 pass**
- `bats scripts/tests/lib/provider_contract.bats` — expected **`51/52`**, failing ONLY test 17
  (pre-existing, fixed separately in
  `docs/bugs/2026-07-18-provider-contract-stale-data-layer-assertion.md`; if that one has
  already landed, expect `52/52`). Do NOT edit that file either way.
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] `scripts/check-stale-test-refs.sh` exists, is executable, and passes shellcheck
- [ ] New BATS suite passes 4/4
- [ ] `git show --stat` shows exactly TWO files changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
test(ci): add stale test reference check for moved and renamed strings
```

---

## What NOT to Do

- Do NOT wire this into `.githooks/` or `.github/workflows/` in this task. It ships as a
  standalone script first so its false-positive behaviour can be observed on real commits
  before it can block anyone. Wiring it up is a separate, later decision.
- Do NOT "improve" the heuristics — the length floor, the `${` skip, the same-file guard,
  and the quoted-value extraction were each added to fix a specific measured failure
  (see Measured Behaviour below). Changing them without re-measuring will regress it.
- Do NOT edit any existing test or any file under `scripts/etc/`.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Measured Behaviour (Claude, 2026-07-18 — do not re-litigate, reproduce)

Validated against real history before this spec was written:

- **`f03df202` (rename):** flagged, 1 hit, correctly names `provider_contract.bats`.
- **`4c89dabb` (move):** flagged, 9 hits, correctly names `argocd_metrics_servicemonitor.bats`.
- **`e128e8b3`:** initially a FALSE POSITIVE — `value: ArgoCDAppDegraded` was replaced by a
  longer line in the same file. Fixed by the same-file guard; now clean.
- **20-commit sweep:** only the two real regressions plus `5c412e15`, which is an artifact of
  the sweep method (it greps *today's* tests against an old diff; those tests were updated in
  that same commit — `argocd_loki.bats` passes 8/8 at HEAD). Not a defect in pre-commit use.

**Known limitation, stated honestly:** this catches whole-line renames and quoted-value moves.
It will NOT catch a test that asserts an unquoted substring of a changed line, and it only
looks at `scripts/etc/`. It reduces this failure class; it does not eliminate it. The grep
discipline in specs is still required.
