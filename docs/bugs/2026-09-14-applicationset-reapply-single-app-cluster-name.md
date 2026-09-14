# Bug: `deploy_argocd_applicationsets` applies one `APP_CLUSTER_NAME` and the Cilium CNI defaults to every set

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** OPEN — ready for Codex
**Files:** `scripts/plugins/argocd.sh`, `scripts/tests/plugins/argocd_appset_live_overrides.bats` (new), `CHANGELOG.md`
**Related:** memory `reference_preserveresourcesondeletion_rename_trap`; `scripts/plugins/istio_ambient.sh`

## Problem

The per-release reapply step (CLAUDE.md "Reapply the ApplicationSets on every release") cannot be run safely with `deploy_argocd_applicationsets --confirm`.

Live hub state, read-only, 2026-09-14:

| ApplicationSet | Live `destination.name` | Live istio-cni dirs |
|---|---|---|
| `istio-ambient` | `ubuntu-k3s` | `/var/lib/rancher/k3s/agent/etc/cni/net.d`, `/bin` |
| `observability-acg` | `ubuntu-hostinger` | — |

What `_argocd_deploy_applicationsets` does today:
- It resolves **one** `APP_CLUSTER_NAME` (env → active provider context → `ubuntu-k3s`) and substitutes it into every file.
- `AMBIENT_CNI_CONF_DIR` / `AMBIENT_CNI_BIN_DIR` come from `scripts/etc/argocd/vars.sh`, whose defaults are the Cilium paths `/etc/cni/net.d` and `/opt/cni/bin`.

Consequences:
- **Hostinger active:** `istio-ambient` is re-rendered with `APP_CLUSTER_NAME=ubuntu-hostinger`.
  - Its generated Applications `istio-*-ubuntu-k3s` are renamed to `istio-*-ubuntu-hostinger`. The old apps are deleted, which is the preserveResourcesOnDeletion rename trap.
  - Their destination moves to another cluster.
- **Any provider:** `istio-cni` gets the Cilium dirs on a flannel k3s node, which breaks ambient pod networking.
- **ACG active:** `observability-acg` is retargeted away from `ubuntu-hostinger`.

On 2026-09-13/14 the release reapply had to be done by hand, one set at a time, with hand-picked env.

## Fix

**Rule:** a reapply re-pins the values branch; it does not retarget. For each file, when a live ApplicationSet of the same name exists, keep its live `destination.name` and live istio-cni dirs.
- When no live set exists (fresh hub), resolve the CNI dirs with the same resolver `deploy_istio_ambient` uses.
- `ARGOCD_APPSET_IGNORE_LIVE=1` turns the preservation off for a deliberate retarget.

### S1 — `scripts/plugins/argocd.sh`: new helper

Insert immediately **above** `function _argocd_deploy_applicationsets() {`:

```bash
function _argocd_appset_live_overrides() {
   local file="$1" name live value conf bin provider dirs
   name="$(sed -n 's/^  name: //p' "$file" | head -1)"
   [[ -z "${name}" ]] && return 0
   live="$(_kubectl --no-exit get applicationset "${name}" -n "${ARGOCD_NAMESPACE:-cicd}" -o json 2>/dev/null || true)"
   if [[ -n "${live}" ]] && ! printf '%s' "${live}" | jq -e '.kind == "ApplicationSet"' >/dev/null 2>&1; then
      live=""
   fi

   if grep -q '\${APP_CLUSTER_NAME}' "$file" && [[ -n "${live}" ]]; then
      value="$(printf '%s' "${live}" | jq -r '.spec.template.spec.destination.name // ""')"
      if [[ -n "${value}" && "${value}" != *'{{'* && "${value}" != *'$'* ]]; then
         printf 'APP_CLUSTER_NAME=%s\n' "${value}"
      fi
   fi

   if grep -q '\${AMBIENT_CNI_CONF_DIR}' "$file"; then
      if [[ -n "${live}" ]]; then
         value="$(printf '%s' "${live}" | jq -r '[.spec.generators[]?.list.elements[]? | select(.name == "istio-cni") | .values][0] // ""')"
         conf="$(printf '%s\n' "${value}" | sed -n 's/^[[:space:]]*cniConfDir:[[:space:]]*//p' | head -1)"
         bin="$(printf '%s\n' "${value}" | sed -n 's/^[[:space:]]*cniBinDir:[[:space:]]*//p' | head -1)"
      fi
      if [[ -z "${conf:-}" || -z "${bin:-}" ]]; then
         if ! declare -f _istio_ambient_cni_dirs >/dev/null 2>&1 && [[ -r "${PLUGINS_DIR}/istio_ambient.sh" ]]; then
            # shellcheck disable=SC1090,SC1091
            source "${PLUGINS_DIR}/istio_ambient.sh"
         fi
         if declare -f _istio_ambient_target_provider >/dev/null 2>&1; then
            provider="${AMBIENT_CNI_PROVIDER:-$(_istio_ambient_target_provider "${ARGOCD_CONTEXT:-k3d-k3d-cluster}" "${ARGOCD_NAMESPACE:-cicd}" "${APP_CLUSTER_NAME:-ubuntu-k3s}")}"
            if [[ -n "${provider}" ]]; then
               dirs="$(_istio_ambient_cni_dirs "${provider}")"
               conf="${dirs%% *}"
               bin="${dirs##* }"
            fi
         fi
      fi
      if [[ -n "${conf:-}" && -n "${bin:-}" ]]; then
         printf 'AMBIENT_CNI_CONF_DIR=%s\nAMBIENT_CNI_BIN_DIR=%s\n' "${conf}" "${bin}"
      fi
   fi
   return 0
}

```

`${APP_CLUSTER_NAME}` inside the helper's fallback is the global value that `_argocd_deploy_applicationsets` has already exported. It only matters when no live set exists.

### S2 — `_argocd_deploy_applicationsets`: apply the overrides per file

Old:

```bash
      if [[ -n "${_unset}" ]]; then
         _err "[argocd] Refusing to apply ${filename}: unset variable(s):${_unset}"
         continue
      fi
      if envsubst "${_vars}" < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

New:

```bash
      if [[ -n "${_unset}" ]]; then
         _err "[argocd] Refusing to apply ${filename}: unset variable(s):${_unset}"
         continue
      fi
      local -a _overrides=()
      local _ov
      if [[ "${ARGOCD_APPSET_IGNORE_LIVE:-0}" != "1" ]]; then
         while IFS= read -r _ov; do
            [[ -n "${_ov}" ]] && _overrides+=("${_ov}")
         done < <(_argocd_appset_live_overrides "$file")
      fi
      if (( ${#_overrides[@]} > 0 )); then
         _info "[argocd] ${filename}: keeping live ${_overrides[*]}"
      fi
      if env ${_overrides[@]+"${_overrides[@]}"} envsubst "${_vars}" < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

Change nothing else in `_argocd_deploy_applicationsets`.

### S3 — `deploy_argocd_applicationsets --help`: document the behaviour

Old:

```
   APP_CLUSTER_NAME     App-cluster name for ACG variants (default: resolved/ubuntu-k3s)
   ARGOCD_NAMESPACE     Namespace for Argo CD (default: cicd)
```

New:

```
   APP_CLUSTER_NAME     App-cluster name for sets not yet live (default: resolved/ubuntu-k3s)
   ARGOCD_NAMESPACE     Namespace for Argo CD (default: cicd)
   ARGOCD_APPSET_IGNORE_LIVE
                        1 = do not preserve each live set's destination cluster and
                        istio-cni dirs (default: preserve; a reapply never retargets)
```

### S4 — tests: `scripts/tests/plugins/argocd_appset_live_overrides.bats` (new)

Use the `setup()` from `scripts/tests/plugins/argocd.bats` (`test_helpers.bash`, `init_test_env`, source `argocd.sh`), then also source `scripts/plugins/istio_ambient.sh`.

In each test:
- Point `ARGOCD_CONFIG_DIR` at a temp dir whose `applicationsets/` holds copies of the real `istio-ambient.yaml`, `observability-acg.yaml` and `observability.yaml`.
- Export `ARGOCD_NAMESPACE=cicd`, `K3D_MANAGER_BRANCH=test-branch`, `APP_CLUSTER_NAME=ubuntu-k3s`, `AMBIENT_ISTIO_VERSION=1.24.2`, `AMBIENT_CNI_CONF_DIR=/etc/cni/net.d`, `AMBIENT_CNI_BIN_DIR=/opt/cni/bin`.
- Define `_argocd_set_active_app_cluster() { :; }` and `unset -f _acg_provider_context _acg_resolve_provider`.
- Define `_kubectl`:
  - `get applicationset <name>` prints the fixture JSON for that name, or prints `Error from server (NotFound)` and returns 1.
  - `apply -f -` writes stdin to a new `mktemp "${BATS_TEST_TMPDIR}/applied.XXXX"` file.

Assert with `yq -r` on the applied manifests. Assert tokens; never `grep -F` whole lines.

1. **Live sets are preserved.**
   - Fixtures:
     - `istio-ambient`: `destination.name` `ubuntu-k3s`; the istio-cni element's `values` contains `cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d` and `cniBinDir: /bin`.
     - `observability-acg`: `destination.name` `ubuntu-hostinger`.
   - Run with `APP_CLUSTER_NAME=ubuntu-hostinger` exported (the dangerous case).
   - The applied `observability-acg` has `.spec.template.spec.destination.name == "ubuntu-hostinger"`.
   - The applied `istio-ambient` has destination `ubuntu-k3s`, template name ending `-ubuntu-k3s`, and istio-cni values containing `cniBinDir: /bin`.
   - The output contains `keeping live`.
2. **No live set → CNI resolver fallback.**
   - All `get applicationset` calls return NotFound; `_istio_ambient_target_provider() { printf 'k3d\n'; }`.
   - The applied `istio-ambient` has `cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d` and `cniBinDir: /bin`.
   - The applied `observability-acg` destination is the global `ubuntu-k3s`.
3. **No live set, no provider label → env defaults unchanged.** `_istio_ambient_target_provider() { :; }`. The applied `istio-ambient` has `cniBinDir: /opt/cni/bin`.
4. **`ARGOCD_APPSET_IGNORE_LIVE=1`.**
   - Same fixtures as test 1, `APP_CLUSTER_NAME=ubuntu-k3s`.
   - The applied `observability-acg` destination is `ubuntu-k3s`, and no `get applicationset` call is made.
5. **Sets without those vars are untouched.** The applied `observability` has `targetRevision` `test-branch`, and the helper prints nothing for `observability.yaml`.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, as the last bullet:

```
- `deploy_argocd_applicationsets` now keeps each live ApplicationSet's destination cluster and istio-cni dirs when it re-pins the values branch (falling back to the `deploy_istio_ambient` CNI resolver for sets not yet applied); previously one `APP_CLUSTER_NAME` and the Cilium CNI defaults were applied to every set, which renamed the `istio-*-ubuntu-k3s` Applications and retargeted `observability-acg`. Set `ARGOCD_APPSET_IGNORE_LIVE=1` to retarget deliberately
```

## Definition of Done

- [ ] S1–S4 applied; `git diff --stat` shows only the three listed files.
- [ ] `shellcheck -x scripts/plugins/argocd.sh`: no new warnings (paste the before/after counts).
- [ ] `bats scripts/tests/plugins/argocd_appset_live_overrides.bats scripts/tests/plugins/argocd.bats scripts/tests/plugins/argocd_values_branch_drift.bats`: all pass (paste the summary).
- [ ] Commit message, verbatim: `fix(argocd): preserve live per-set destination and CNI dirs on ApplicationSet reapply`

## Operator follow-up (NOT for Codex)

1. Claude renders with `--dry-run` or `kubectl diff` against the hub.
2. The user runs `deploy_argocd_applicationsets --confirm` at release close-out.
3. Expected diff: `targetRevision` only.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT run `kubectl`, `helm`, or any `k3d-manager` command against a live cluster; stubs only.
- Do NOT change the ApplicationSet YAML files, `scripts/etc/argocd/vars.sh`, or `scripts/plugins/istio_ambient.sh`.
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or memory-bank.
