# Test integrity batch — stale assertion, envsubst drift, and a mechanical guard

**Branch:** `k3d-manager-v1.16.0`
**Repo:** k3d-manager only (single repo)

This supersedes three separate specs, now merged into one handoff:

- `docs/bugs/2026-07-18-provider-contract-stale-data-layer-assertion.md`
- `docs/bugs/2026-07-18-appset-envsubst-var-drift.md`
- `docs/bugs/2026-07-18-stale-test-reference-check.md`

Those files remain as the detailed background for each item. **This file is the one you
implement from.** Where they disagree with this file (specifically: the expected
`provider_contract.bats` count), **this file wins**.

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/tests/lib/provider_contract.bats` (Phase 1 target, test at lines ~460-502)
  - `scripts/etc/argocd/applicationsets/data-git.yaml` (what the name is NOW — do not edit)
  - `scripts/plugins/argocd.sh` — `_argocd_deploy_applicationsets` (~lines 1160-1204)
  - `scripts/plugins/istio_ambient.sh` lines 15-38 (the CORRECT targeted apply, for contrast)
  - the three superseded specs listed above, for background
- Implement exactly what is written — no interpretation, no extra refactors.

**Work the phases IN ORDER. Each phase is its own commit.** Do not squash them: Phase 1 is a
test fix, Phase 2 is a behaviour change, Phase 3 is a new tool. They need to be revertable
independently, and Phase 1 changes the expected result of a gate the later phases use.

---

## Phase 1 — retarget the stale `data-layer` assertion

### Background

`f03df202` renamed the generated Application to fix a multi-cluster collision:

```yaml
name: data-layer            →   name: '{{.name}}-data-layer'
```

`provider_contract.bats:495` still asserts the pre-rename literal.
Verified by worktree bisect: `1..52` all ok at `f03df202^`, `51/52` at `f03df202`.

The correct idiom already exists six lines below at line 501 (`name: '{{.name}}-platform'`) —
the rendered manifest keeps Go templates literal.

### Change 1.1 — `scripts/tests/lib/provider_contract.bats`

**Exact old block (line 495):**

```bash
  [[ "$output" == *"name: data-layer"* ]]
```

**Exact new block:**

```bash
  [[ "$output" == *"name: '{{.name}}-data-layer'"* ]]
  [[ "$output" != *"name: data-layer"* ]]
```

### Phase 1 gates

- `bats scripts/tests/lib/provider_contract.bats` → **`1..52`, all 52 ok**
- `grep -c "name: data-layer" scripts/tests/lib/provider_contract.bats` → **`1`**
- `grep -c "name: '{{.name}}-data-layer'" scripts/tests/lib/provider_contract.bats` → **`1`**
- `git show --stat` → exactly ONE file

**Phase 1 commit message (exact):**
```
test(provider): retarget data-layer assertion after per-cluster rename
```

---

## Phase 2 — derive the appset envsubst list per file

### Background

`_argocd_deploy_applicationsets` applies every appset through a hardcoded three-variable
envsubst list. `istio-ambient.yaml` needs a fourth (`$AMBIENT_ISTIO_VERSION`), so the
bootstrap path ships a literal `${AMBIENT_ISTIO_VERSION}` as `targetRevision`, and
`istio-base/cni/istiod-ubuntu-hostinger` sit `Unknown` with `ComparisonError: improper
constraint` on the live hub. This is **not** stale state: `istio_ambient.sh:32` substitutes
correctly on its own targeted apply and the generic loop overwrites it, so it reproduces on
every bootstrap.

### Change 2.1 — `scripts/plugins/argocd.sh`

**Exact old block (line 1196):**

```bash
      if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH $APP_CLUSTER_NAME' < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

**Exact new block:**

```bash
      local _vars
      _vars="$(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$file" 2>/dev/null \
         | tr -d '${}' | sort -u | sed 's/^/$/' | tr '\n' ' ')"
      if envsubst "${_vars}" < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

This keeps envsubst on an explicit allow-list (so Go templates `{{...}}` and `$`-literals
stay safe) but derives it from the file being applied.

### Change 2.2 — NEW `scripts/tests/plugins/appset_envsubst_coverage.bats`

Write exactly this file:

```bash
#!/usr/bin/env bats

APPSETS="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
ARGOCD="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"

@test "appset deploy derives envsubst vars from each file" {
  run grep -c "envsubst '\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH \$APP_CLUSTER_NAME'" "${ARGOCD}"
  [ "${output}" -eq 0 ]
}

@test "every appset variable is exported by some deploy path" {
  local missing=""
  for f in "${APPSETS}"/*.yaml; do
    for v in $(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$f" | tr -d '${}' | sort -u); do
      grep -rqh "export .*${v}\|: \"\${${v}:=" "${BATS_TEST_DIRNAME}/../../plugins/" \
        || missing="${missing} $(basename "$f"):${v}"
    done
  done
  [ -z "${missing}" ] || { echo "unexported appset vars:${missing}"; false; }
}
```

**What these two tests do and do not catch** (measured 2026-07-18 against both unfixed and
fixed code): test 1 is the real gate — it fails on unfixed code and passes on fixed code.
Test 2 would **not** have caught this bug and is not claimed to; `AMBIENT_ISTIO_VERSION` *is*
exported, so test 2 passes even unfixed. It guards a different case (a variable exported
nowhere at all). Change 2.1 is what makes this defect structurally impossible.

### Phase 2 gates

- `bash -n scripts/plugins/argocd.sh` — clean
- `shellcheck -S warning scripts/plugins/argocd.sh` — zero NEW warnings
- `bats scripts/tests/plugins/appset_envsubst_coverage.bats` → **2/2**
- Disappearance gate:
  `grep -c "envsubst '\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH \$APP_CLUSTER_NAME'" scripts/plugins/argocd.sh` → **`0`**
- The full set of suites touching this code path (derived from
  `grep -rln '_argocd_deploy_applicationsets\|applicationsets' scripts/tests/`), all pass
  unchanged: `argocd.bats`, `argocd_app_cluster_generator.bats`,
  `argocd_image_updater_flap_fix.bats`, `argocd_image_updater_annotations.bats`,
  `argocd_loki.bats`, `trivy_operator_observability.bats`, `grafana_dashboard_appsets.bats`,
  `argocd_metrics_servicemonitor.bats` (`15/15`)
- `bats scripts/tests/lib/provider_contract.bats` → **`52/52`** (Phase 1 already fixed test 17)
- `git show --stat` → exactly TWO files

**Phase 2 commit message (exact):**
```
fix(argocd): derive appset envsubst vars per file to stop version drift
```

---

## Phase 3 — add the mechanical stale-reference check

### Background

Three regressions on this branch share one cause: a spec moved or renamed a string in
`scripts/etc/` and a BATS suite asserting the old string was never updated, because the gate
list was written from memory instead of derived from a grep. Phases 1 and 2 of this very
batch are two of them. This makes the rule mechanical.

### Change 3.1 — NEW `scripts/check-stale-test-refs.sh`

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

### Change 3.2 — NEW `scripts/tests/lib/stale_test_refs.bats`

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

### Phase 3 gates

- `bash -n scripts/check-stale-test-refs.sh` — clean
- `shellcheck -S warning scripts/check-stale-test-refs.sh` — zero warnings
- `test -x scripts/check-stale-test-refs.sh` — must be executable (`chmod +x`)
- `bats scripts/tests/lib/stale_test_refs.bats` → **4/4**
- `git show --stat` → exactly TWO files

**Phase 3 commit message (exact):**
```
test(ci): add stale test reference check for moved and renamed strings
```

---

## Files Changed (whole batch)

| Phase | File | Change |
|---|---|---|
| 1 | `scripts/tests/lib/provider_contract.bats` | retarget line 495 + disappearance guard |
| 2 | `scripts/plugins/argocd.sh` | derive envsubst allow-list per file |
| 2 | `scripts/tests/plugins/appset_envsubst_coverage.bats` | NEW — 2 tests |
| 3 | `scripts/check-stale-test-refs.sh` | NEW — stale-reference detector (executable) |
| 3 | `scripts/tests/lib/stale_test_refs.bats` | NEW — 4 tests |

**Five files, three commits.** Nothing else.

---

## Final gates (run once, after all three commits)

- `bats scripts/tests/lib/provider_contract.bats` → **`52/52`**
- `bats scripts/tests/plugins/appset_envsubst_coverage.bats` → **2/2**
- `bats scripts/tests/lib/stale_test_refs.bats` → **4/4**
- `bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats` → **`15/15`**
- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` → **`5/5`**
- `shellcheck -S warning scripts/plugins/argocd.sh scripts/check-stale-test-refs.sh` — clean
- `./scripts/k3d-manager _agent_audit` — exit 0
- `git log --oneline origin/k3d-manager-v1.16.0..HEAD` → exactly THREE commits, in phase order

---

## Definition of Done

- [ ] Phase 1 committed — `provider_contract.bats` at `52/52`
- [ ] Phase 2 committed — envsubst derived per file, new suite 2/2
- [ ] Phase 3 committed — checker executable, new suite 4/4
- [ ] Exactly three commits, exactly five files total
- [ ] All final gates pass
- [ ] `_agent_audit` exit 0
- [ ] All three commits pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with all three commit SHAs and task status

---

## What NOT to Do

- Do NOT squash the three phases into one commit. They must be independently revertable.
- Do NOT edit `scripts/etc/argocd/applicationsets/data-git.yaml` to restore
  `name: data-layer`. That reintroduces the multi-cluster collision `f03df202` fixed, and it
  is live on the hub right now — `ubuntu-hostinger-data-layer` and `ubuntu-k3s-data-layer`
  are both Synced/Healthy. Making a test pass that way would break a working two-cluster
  deployment.
- Do NOT fix Phase 2 by appending `$AMBIENT_ISTIO_VERSION` to the hardcoded list. It works
  today and recreates the bug for the next variable. Derive the list.
- Do NOT switch to bare `envsubst` with no allow-list — it would mangle Go templates.
- Do NOT wire `check-stale-test-refs.sh` into `.githooks/` or `.github/workflows/`. It ships
  standalone and advisory so its false-positive behaviour can be observed on real commits
  first. Wiring it up is a separate later decision.
- Do NOT "improve" the checker heuristics — the length floor, the `${` skip, the same-file
  guard and the quoted-value extraction each fix a specific measured failure. Changing them
  without re-measuring will regress it.
- Do NOT delete or skip any test. Retarget it. A deleted test is not a passing test.
- Do NOT edit any file under `scripts/etc/`.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the five listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Pre-validation (Claude, 2026-07-18 — reproduce, do not re-litigate)

Every change here was applied and measured before this spec was written; scaffolding was
reverted and the tree left clean.

- **Phase 1:** patched → `52/52`. Mutation test (patch applied AND `data-git.yaml` reverted
  to the bare name) → test 17 **fails**. The new assertion is real, not vacuous.
- **Phase 2:** Change 2.1 verified to emit `targetRevision: 1.24.2` with `{{ .name }}`
  intact. New test 1 verified to FAIL on unfixed code and PASS on fixed code. `bash -n` and
  shellcheck clean under the patch. Affected-suite list DERIVED from a grep across
  `scripts/tests/` — 8 suites, not the 2 originally listed.
- **Phase 3:** `f03df202` → flagged, names `provider_contract.bats`. `4c89dabb` → flagged
  9 hits, names `argocd_metrics_servicemonitor.bats`. `e128e8b3` was a genuine false positive
  (a prefix line replaced by a longer line in the same file), fixed by the same-file guard.
  20-commit sweep: only the two real regressions plus `5c412e15`, an artifact of the sweep
  method (it greps today's tests against an old diff; those tests were updated in that same
  commit — `argocd_loki.bats` passes 8/8 at HEAD).

**Known limitation of the Phase 3 checker, stated honestly:** it catches whole-line renames
and quoted-value moves. It will NOT catch a test asserting an unquoted substring of a changed
line, and it only scans `scripts/etc/`. It reduces this failure class; it does not eliminate
it. Grep discipline in specs is still required.
