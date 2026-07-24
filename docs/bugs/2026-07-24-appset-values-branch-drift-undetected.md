# Bug: ApplicationSet `$values` branch drift is undetectable

**Branch:** `k3d-manager-v1.18.0`
**Files:** `scripts/plugins/argocd.sh`,
`scripts/tests/plugins/argocd_values_branch_drift.bats`,
`docs/api/functions.md`

---

## Before You Start

- `git pull origin k3d-manager-v1.18.0`
- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
- Read `scripts/plugins/argocd.sh` in full before editing — note it uses **3-space
  indentation**, not 2 or 4
- Read `scripts/tests/plugins/argocd_servicemonitors_ensure.bats` for the house
  `_kubectl` stubbing pattern
- Branch: `k3d-manager-v1.18.0` — do NOT commit to `main`

---

## Problem

Five ApplicationSets template a `$values` source that points at this repo on a branch
substituted at apply time:

```yaml
        - repoURL: https://github.com/wilddog64/k3d-manager
          targetRevision: '${K3D_MANAGER_BRANCH}'
          ref: values
```

`K3D_MANAGER_BRANCH` defaults to the branch that was checked out **when the
ApplicationSet was last applied**. Nothing re-applies it on a release, so the pin freezes
while the repo moves on. Config committed to a newer branch is then **inert**: it is in
git, it passes CI, its BATS gates are green, and no cluster is reading it.

This went unnoticed for two releases. The hub `trivy-operator` Application was still
reading values from `k3d-manager-v1.16.0` on 2026-07-24, and was only discovered by
accident while scoping an unrelated version-pin change.

**Root cause:** there is no check anywhere that compares a live Application's `$values`
`targetRevision` against the branch the operator actually intends to deploy.

**Live state at the time of writing** (hub, `k3d-k3d-cluster`, namespace `cicd`) — the
hub half was reapplied manually, the ACG half was not:

| `$values` targetRevision | Applications |
|---|---|
| `k3d-manager-v1.16.0` | `acg-kube-prometheus-stack`, `acg-trivy-operator`, `loki` |
| `k3d-manager-v1.18.0` | `hub-loki`, `kube-prometheus-stack`, `trivy-operator` |

---

## Reproduction

```
$ kubectl --context k3d-k3d-cluster -n cicd get app trivy-operator \
    -o jsonpath='{.spec.sources[0].targetRevision}'
k3d-manager-v1.16.0
```

…while the working branch is `k3d-manager-v1.18.0` and the values file it reads has been
changed on that branch. There is no command that reports this. That is the bug.

**Note (2026-07-24, after this spec was written):** Claude has since reapplied both
ApplicationSets, so the live clusters now report `k3d-manager-v1.18.0` and this command no
longer reproduces the drift. That does not change the task — the missing *detector* is the
bug, and the drift will recur on the next release if nothing reports it. Do not try to
reproduce the stale value, and do not touch a cluster to create one.

---

## Fix

Add one public check function and one private helper. **Append both to the end of
`scripts/plugins/argocd.sh`**, after the closing `}` of `deploy_argocd_platform_ops`
(the current last function in the file). Keep the file's 3-space indentation.

### Change 1 — `scripts/plugins/argocd.sh`: append the check

**Exact new block (append at end of file, preceded by one blank line):**

```bash
function argocd_check_values_branch() {
   local _expected="${1:-${K3D_MANAGER_BRANCH:-}}"
   local _context="${2:-k3d-k3d-cluster}"
   local _namespace="${ARGOCD_NAMESPACE:-cicd}"
   local _apps
   local _drift

   if [[ -z "${_expected}" ]]; then
      _expected="$(git -C "${SCRIPT_DIR}/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
   fi

   _apps="$(_kubectl get application -n "${_namespace}" --context "${_context}" -o json 2>/dev/null)"
   if [[ -z "${_apps}" ]]; then
      _warn "[argocd] Could not read Applications from ${_context}/${_namespace}"
      return 2
   fi

   _info "[argocd] Expected values branch: ${_expected}"
   _drift="$(printf '%s' "${_apps}" | _argocd_values_branch_drift "${_expected}")"

   if [[ -z "${_drift}" ]]; then
      _info "[argocd] All Applications reference values branch ${_expected}"
      return 0
   fi

   _warn "[argocd] Applications on a stale values branch:"
   printf '%s\n' "${_drift}" >&2
   _warn "[argocd] Fix: reapply the ApplicationSets with K3D_MANAGER_BRANCH=${_expected}"
   return 1
}

function _argocd_values_branch_drift() {
   local _expected="$1"
   local _repo="https://github.com/wilddog64/k3d-manager"

   python3 -c '
import json
import sys

expected = sys.argv[1]
repo = sys.argv[2]

try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(3)

checked = 0
for app in doc.get("items", []):
    spec = app.get("spec", {})
    sources = spec.get("sources") or ([spec["source"]] if "source" in spec else [])
    for src in sources:
        if src.get("ref") != "values":
            continue
        if repo not in src.get("repoURL", ""):
            continue
        checked += 1
        revision = src.get("targetRevision", "")
        if revision != expected:
            print("  {} {}".format(app.get("metadata", {}).get("name", "?"), revision))

print("[argocd] checked {} values references".format(checked), file=sys.stderr)
' "${_expected}" "${_repo}"
}
```

**Why it is shaped this way — do NOT "simplify" these three points:**

1. **`_apps` is captured and emptiness-checked before parsing.** If `_kubectl` were piped
   straight into `python3`, an unreachable cluster would yield empty stdin, the drift
   string would be empty, and the function would report **"All Applications reference
   values branch …"** — a false green on a check whose entire purpose is catching a silent
   failure. The `return 2` path is the point of the function, not boilerplate.
2. **The `try/except ValueError` around `json.load`** is the same guard for the case where
   `_kubectl` emits non-JSON (an error page, a partial response) instead of nothing.
3. **`checked` is printed to stderr, not stdout.** It must stay off stdout or it would be
   captured into `_drift` and read as drift. It exists so `checked 0 values references`
   is visible when a wrong namespace or context silently matches nothing.
4. **The unreadable branch uses `_warn`, NOT `_err`.** `_err` in
   `scripts/lib/foundation/scripts/lib/system.sh:1850` ends with `exit 1` — it is fatal,
   not a logging call. Using it here kills the shell with status 1 and makes `return 2`
   dead code, collapsing "cannot read the cluster" into the same exit code as "drift
   found". This was caught by running the suite: the message printed correctly and the
   status was still 1. Do not switch it back to `_err`.

### Change 2 — `scripts/tests/plugins/argocd_values_branch_drift.bats`: new file

**Exact new file contents:**

```bash
#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
}

_mixed_fixture() {
  cat <<'EOF'
{"items":[
 {"metadata":{"name":"trivy-operator"},"spec":{"sources":[
   {"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.18.0"},
   {"chart":"trivy-operator","targetRevision":"0.34.0"}]}},
 {"metadata":{"name":"acg-trivy-operator"},"spec":{"sources":[
   {"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.16.0"},
   {"chart":"trivy-operator","targetRevision":"0.34.0"}]}}
]}
EOF
}

_clean_fixture() {
  cat <<'EOF'
{"items":[
 {"metadata":{"name":"trivy-operator"},"spec":{"sources":[
   {"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.18.0"},
   {"chart":"trivy-operator","targetRevision":"0.34.0"}]}}
]}
EOF
}

@test "argocd values branch: reports drift and returns 1 when an Application is stale" {
  _kubectl() { _mixed_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"acg-trivy-operator"* ]]
  [[ "${output}" == *"k3d-manager-v1.16.0"* ]]
}

@test "argocd values branch: the up-to-date Application is not reported as drifted" {
  _kubectl() { _mixed_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 1 ]
  [[ "${output}" != *"  trivy-operator k3d-manager-v1.18.0"* ]]
}

@test "argocd values branch: returns 0 when every Application matches" {
  _kubectl() { _clean_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"All Applications reference values branch k3d-manager-v1.18.0"* ]]
}

@test "argocd values branch: returns 2 instead of a false green when Applications cannot be read" {
  _kubectl() { return 1; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Could not read Applications"* ]]
}

@test "argocd values branch: chart sources are ignored, only the values ref is checked" {
  _kubectl() { _clean_fixture; }

  run argocd_check_values_branch k3d-manager-v1.18.0
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"checked 1 values references"* ]]
}
```

The suite is **5 tests**. Test 4 is the false-green guard — it is the reason this function
exists, so it must not be dropped or weakened to `-ne 0`.

### Change 3 — `docs/api/functions.md`: register the new public function

`argocd_check_values_branch` is public (no leading underscore), so it must be registered.
The v1.17.0 retro recorded an unregistered public function reaching PR time as a defect.

**Exact old line (line 52):**

```
| `deploy_argocd_bootstrap` | `scripts/plugins/argocd.sh` | Bootstrap ArgoCD with initial apps |
```

**Exact new block:**

```
| `deploy_argocd_bootstrap` | `scripts/plugins/argocd.sh` | Bootstrap ArgoCD with initial apps |
| `argocd_check_values_branch` | `scripts/plugins/argocd.sh` | Report ArgoCD Applications whose `$values` source `targetRevision` has drifted from the expected k3d-manager branch; returns 1 on drift, 2 if Applications cannot be read (v1.18.0+) |
```

---

## Pre-validation (already done — do not redo, but do not assume either)

Every code block in this spec was executed before hand-off, against a mirrored copy of the
tree, so the code you are copying is known-good:

- `bats` on the suite below → `1..5`, **5/5 pass**
- `bash -n` on `argocd.sh` with both functions appended → rc=0
- `shellcheck -S warning` on `argocd.sh` → **0 findings before and 0 after** the append
- The function was run against the live hub and correctly reported the three stale
  Applications with `rc=1` and `checked 6 values references`

You must still run the gates yourself — this note tells you what the answers should be, so
a deviation means you changed something.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/argocd.sh` | Append `argocd_check_values_branch` + `_argocd_values_branch_drift` |
| `scripts/tests/plugins/argocd_values_branch_drift.bats` | New 5-test suite |
| `docs/api/functions.md` | Register the new public function |

---

## Rules

- `shellcheck -S warning scripts/plugins/argocd.sh` — **zero new warnings** (compare
  against the pre-change run; the file may already have findings you did not introduce)
- `bats scripts/tests/plugins/argocd_values_branch_drift.bats` — prints `1..5`, all pass.
  **Paste the `1..5` line.**
- The existing argocd suites must not regress:
  `bats scripts/tests/plugins/argocd.bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats`
- `bash -n scripts/plugins/argocd.sh` — parses clean
- Run `_agent_audit` before reporting done — capture its exit code on its **own line**,
  never after `; echo`, and never through a pipe (`${PIPESTATUS[0]}` comes back empty
  through `| tee` / `| tail`). **Report it as `rc=<n>`, not as its stdout** — quoting
  `running under bash version …` is not evidence the gate passed.

---

## Definition of Done

- [ ] Both functions appended to the **end** of `scripts/plugins/argocd.sh`, 3-space indent
- [ ] `grep -c 'function argocd_check_values_branch' scripts/plugins/argocd.sh` → **1**
- [ ] `grep -c 'function _argocd_values_branch_drift' scripts/plugins/argocd.sh` → **1**
- [ ] `bats scripts/tests/plugins/argocd_values_branch_drift.bats` → `1..5`, 5 pass
- [ ] Pre-existing argocd suites still pass
- [ ] `bash -n` clean, `shellcheck -S warning` shows zero new warnings
- [ ] `docs/api/functions.md` has exactly one row for `argocd_check_values_branch`
- [ ] `_agent_audit` **`rc=0`**
- [ ] Committed and pushed to `k3d-manager-v1.18.0`
- [ ] memory-bank updated with the commit SHA and task status, in a **separate commit**,
      then pushed — do NOT report done until BOTH commits are on
      `origin/k3d-manager-v1.18.0`

**Commit message — use the ENTIRE block below, subject AND body:**

```
feat(argocd): detect ApplicationSet values-branch drift

ApplicationSets template their $values source at ${K3D_MANAGER_BRANCH},
which freezes to whatever branch was checked out when the set was last
applied. Config committed to a newer branch is then inert: in git, CI
green, and read by no cluster. This went unnoticed for two releases.
argocd_check_values_branch compares every live Application's values ref
against the expected branch and returns 1 on drift, 2 when Applications
cannot be read at all so an unreachable cluster cannot read as a pass.
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.18.0`
- Do NOT run any cluster command: no `kubectl apply`, no `argocd app sync`, no
  reapplying ApplicationSets, no `deploy_observability`, no live smoke. **Claude does all
  live-cluster work.** Testing this function against a real cluster is not your step —
  the BATS stubs are the whole test surface for you
- Do NOT pipe `_kubectl` directly into `python3` to "simplify" — that reintroduces the
  false green the `return 2` path exists to prevent
- Do NOT move the `checked …` line from stderr to stdout — it would be captured as drift
- Do NOT rename, delete, or "fix" the Application named `loki` (see Out of Scope)
- Do NOT add an `_agent_audit` allowlist entry or raise `AGENT_AUDIT_MAX_IF`. Both new
  functions are well under the threshold (3 and 0 `if`s); if the audit trips, decompose

---

## Out of Scope (do NOT fix here)

1. **The ACG rollout — already done by Claude on 2026-07-24.** `acg-kube-prometheus-stack`,
   `acg-trivy-operator`, and `loki` now read `k3d-manager-v1.18.0`; all six Applications
   are drift-free. That was Claude's live step and is deliberately not bundled with adding
   the detector. Nothing for you to do here.
2. **The ACG Application named `loki` is inconsistently named.** The `observability-acg`
   ApplicationSet names two elements `acg-kube-prometheus-stack` and `acg-trivy-operator`
   but the third just `loki`, so it sits next to the hub's `hub-loki` and is
   indistinguishable from a hub Application by name. **Renaming it is dangerous** — the
   ApplicationSet name template is `{{.name}}`, and renaming a generator element
   cascade-deletes the live workload (this deleted the hostinger `shopping-cart-apps`
   namespace on 2026-07-19; see also
   `docs/bugs/2026-07-19-services-git-appset-duplicate-application-names.md`). Needs its
   own spec with the finalizer/`preserveResourcesOnDeletion` handling worked out first.
3. **Wiring this check into `make status` or a release target.** Landing the function
   first keeps this task small; where it gets called from is a separate decision.
