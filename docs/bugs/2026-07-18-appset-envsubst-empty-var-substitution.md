# Bug: derived envsubst list substitutes UNSET vars with empty string (regression from `db1ed1ce`)

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/plugins/argocd.sh`, `scripts/etc/argocd/vars.sh`, `scripts/tests/plugins/appset_envsubst_coverage.bats`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "appset envsubst empty var" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/plugins/argocd.sh` — `_argocd_deploy_applicationsets` (~1154-1205)
  - `scripts/plugins/istio_ambient.sh` — lines 18-33 (where the default currently lives)
  - `scripts/etc/argocd/vars.sh` — the file argocd.sh sources at load time
  - `docs/bugs/2026-07-18-test-integrity-batch.md` — Phase 2, which introduced this
- Implement exactly what is written — no interpretation, no extra refactors.

---

## Problem

Phase 2 (`db1ed1ce`) replaced the hardcoded three-variable envsubst list with a list derived
per file. That was correct and is not being reverted. But it silently widened the blast
radius: a variable that appears in an ApplicationSet and is **unset at runtime** is now
substituted with the **empty string** instead of being passed through as a literal.

`AMBIENT_ISTIO_VERSION` is defaulted in exactly one place:

```bash
scripts/plugins/istio_ambient.sh:22:  : "${AMBIENT_ISTIO_VERSION:=1.24.2}"
```

That line is **inside `deploy_istio_ambient()`**, reachable only via the
`deploy_istio_ambient` dispatcher entry. The bootstrap path
(`argocd.sh:557` and `argocd.sh:1042` → `_argocd_deploy_applicationsets`) never loads that
plugin, so the variable is unset there.

**Measured, 2026-07-18:**

```
$ env -u AMBIENT_ISTIO_VERSION  # + the derived-list code from db1ed1ce
derived list: [$AMBIENT_ISTIO_VERSION $APP_CLUSTER_NAME $ARGOCD_NAMESPACE ]
53:        targetRevision:
```

`istio-ambient.yaml` uses a Helm chart source
(`repoURL: https://istio-release.storage.googleapis.com/charts`, `chart: '{{ .chart }}'`).
An empty `targetRevision` on a Helm source is not a pinned version.

**Before `db1ed1ce`:** `targetRevision: ${AMBIENT_ISTIO_VERSION}` — ArgoCD rejects it loudly
(`improper constraint`), Applications sit `Unknown`. Broken, but visibly broken.

**After `db1ed1ce`:** `targetRevision:` — no error. This trades a loud failure for a silent
unpinned one, and violates the standing rule in `CLAUDE.md`:
*"New Helm chart installations must pin chart versions explicitly — no floating `latest`."*

**Why the new test did not catch it:** `appset_envsubst_coverage.bats` test 2 greps all of
`scripts/plugins/` for `export .*VAR` or `: "${VAR:=`. It matches `istio_ambient.sh:22`
regardless of whether that line is reachable from the bootstrap path, so it passes. The test
checks that a default exists *somewhere*, not that it is *in scope where the appset is applied*.

---

## Fix

### Change 1 — `scripts/etc/argocd/vars.sh`: default the variable where the bootstrap path reaches it

`argocd.sh:29-37` sources this file at plugin load, and every entry is exported. Append to
the end of the file:

```bash

# Istio ambient mesh chart version (consumed by istio-ambient.yaml ApplicationSet).
# Must be defaulted here, not only in istio_ambient.sh — the ArgoCD bootstrap path
# applies that ApplicationSet without loading the istio_ambient plugin.
export AMBIENT_ISTIO_VERSION="${AMBIENT_ISTIO_VERSION:-1.24.2}"
```

### Change 2 — `scripts/plugins/argocd.sh`: refuse to substitute an unset variable

**Exact old block (lines ~1196-1199):**

```bash
      local _vars
      _vars="$(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$file" 2>/dev/null \
         | tr -d '${}' | sort -u | sed 's/^/$/' | tr '\n' ' ')"
      if envsubst "${_vars}" < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

**Exact new block:**

```bash
      local _vars _v _name _unset=""
      _vars="$(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$file" 2>/dev/null \
         | tr -d '${}' | sort -u | sed 's/^/$/' | tr '\n' ' ')"
      for _v in ${_vars}; do
         _name="${_v#\$}"
         [[ -z "${!_name:-}" ]] && _unset="${_unset} ${_name}"
      done
      if [[ -n "${_unset}" ]]; then
         _err "[argocd] Refusing to apply ${filename}: unset variable(s):${_unset}"
         continue
      fi
      if envsubst "${_vars}" < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

An unset variable must never become an empty string in a manifest that is about to be applied
to a cluster. Skipping the file and logging is strictly better than shipping a blank
`targetRevision`, a blank `namespace`, or a blank cluster name.

**Note on the indirect expansion — do not "simplify" it.** The `$` must be stripped into its
own variable *before* the `${!...}` indirection. Writing it as `${!_v#$}` looks equivalent and
is not: bash parses the indirection first and fails with
`$AMBIENT_ISTIO_VERSION: invalid variable name`, leaving `_unset` empty so the guard silently
passes and the broken file is applied anyway. Verified 2026-07-18. The two-line
`_name="${_v#\$}"` then `${!_name:-}` form is correct — it reports
`AMBIENT_ISTIO_VERSION` when unset and reports nothing when set.

### Change 3 — `scripts/tests/plugins/appset_envsubst_coverage.bats`: make test 2 check scope, not existence

**Exact old block (test 2, the whole test):**

```bash
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

**Exact new block:**

```bash
@test "every appset variable is defaulted in the argocd bootstrap scope" {
  local missing=""
  local vars_file="${BATS_TEST_DIRNAME}/../../etc/argocd/vars.sh"
  local argocd_sh="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  for f in "${APPSETS}"/*.yaml; do
    for v in $(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$f" | tr -d '${}' | sort -u); do
      grep -qE "^export ${v}=|^: \"\\\$\{${v}:=" "${vars_file}" \
        || grep -qE "^\s*(export )?${v}=|^\s*: \"\\\$\{${v}:=" "${argocd_sh}" \
        || missing="${missing} $(basename "$f"):${v}"
    done
  done
  [ -z "${missing}" ] || { echo "appset vars not defaulted in bootstrap scope:${missing}"; false; }
}
```

The point is the **anchoring**: only a top-level default in `argocd/vars.sh` or `argocd.sh`
counts. A default buried inside another plugin's function no longer satisfies it, because it
does not satisfy the runtime.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/vars.sh` | default `AMBIENT_ISTIO_VERSION` in bootstrap scope |
| `scripts/plugins/argocd.sh` | skip + `_err` when a derived var is unset |
| `scripts/tests/plugins/appset_envsubst_coverage.bats` | test 2 checks scope, not mere existence |

---

## Rules

- `bash -n scripts/plugins/argocd.sh scripts/etc/argocd/vars.sh` — clean
- `shellcheck -S warning scripts/plugins/argocd.sh` — zero NEW warnings
- `bats scripts/tests/plugins/appset_envsubst_coverage.bats` — **2/2**
- **Mutation check (required, paste the output):** with Change 1 reverted but Changes 2 and 3
  applied, test 2 must **FAIL**. If it passes, the test is vacuous — fix it, do not proceed.
- These must still pass unchanged:
  `argocd.bats`, `argocd_app_cluster_generator.bats`, `argocd_image_updater_flap_fix.bats`,
  `argocd_image_updater_annotations.bats`, `argocd_loki.bats`,
  `trivy_operator_observability.bats`, `grafana_dashboard_appsets.bats`,
  `argocd_metrics_servicemonitor.bats` (`15/15`),
  `scripts/tests/lib/provider_contract.bats` (`52/52`),
  `scripts/tests/lib/stale_test_refs.bats` (`4/4`)
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] `AMBIENT_ISTIO_VERSION` defaulted in `scripts/etc/argocd/vars.sh`
- [ ] `_argocd_deploy_applicationsets` skips + logs on any unset derived var
- [ ] Test 2 rewritten and proven non-vacuous by the mutation check
- [ ] `git show --stat` shows exactly THREE files changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(argocd): fail loudly on unset appset envsubst vars instead of substituting empty
```

---

## What NOT to Do

- Do NOT revert `db1ed1ce`. Deriving the list per file is correct and stays. This adds the
  guard that should have come with it.
- Do NOT "fix" this by removing `${AMBIENT_ISTIO_VERSION}` from `istio-ambient.yaml` or
  hardcoding `1.24.2` into the YAML. The version must stay configurable.
- Do NOT delete the default in `istio_ambient.sh:22` — that path still needs it and is
  independently correct.
- Do NOT change the guard from `continue` to `return 1`. One bad appset file must not abort
  deployment of the others.
- Do NOT re-apply anything to a live cluster — Claude does live verification, not agents.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the three listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

The live hub e2e is **blocked until this lands**. Running the current bootstrap path against
`k3d-k3d-cluster` today would apply `istio-ambient` with an empty `targetRevision` against a
public Helm repo — an unpinned chart on `ubuntu-hostinger`. After this fix, Claude re-runs the
bootstrap appset deploy and confirms `targetRevision` resolves to `1.24.2` and the three
`istio-*-ubuntu-hostinger` Applications leave `Unknown`.

Live state at time of filing (hub `k3d-k3d-cluster`, namespace `cicd`):

```
istio-ambient appset targetRevision: ${AMBIENT_ISTIO_VERSION}
istio-base-ubuntu-hostinger   Unknown   Healthy
istio-cni-ubuntu-hostinger    Unknown   Healthy
istiod-ubuntu-hostinger       Unknown   Healthy
```
