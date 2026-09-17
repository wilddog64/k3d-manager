# Bug: hub ArgoCD objects carry argo-cd-7.8.1 labels owned by `argocd-controller`, so `helm upgrade argocd` fails

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-13
**Status:** FIXED — Codex implementation verified by Claude; live rollout done 2026-09-13
**Files:** `scripts/plugins/argocd.sh`, `scripts/tests/plugins/argocd_reclaim_release_ownership.bats` (new), `docs/api/functions.md`, `CHANGELOG.md`
**Related:** `docs/bugs/2026-09-13-hub-rebuild-skips-argocd-servicemonitors-and-promtail.md`, `docs/issues/2026-06-29-argocd-helm-ssa-conflict-sso-cm.md`

## Problem

On 2026-09-13, `helm upgrade argocd argo/argo-cd --version 10.8.4 --reuse-values` on the hub failed as rev 4, with server-side-apply conflicts against field manager `argocd-controller`. Rev 3 stays `deployed`.

**Cause:**
- Cluster Secret `cicd/ubuntu-k3s-app-cluster` (created 2026-09-11T02:29Z) registers the hub itself (`https://kubernetes.default.svc`) as the app cluster.
- In-cluster registration is intentional for provider `k3d`. Before the v1.33.0 guard in `register_app_cluster` (in-cluster secrets no longer get the `environment` label), the Secret matched the `platform-helm` ApplicationSet.
- The generated app `ubuntu-k3s-platform` rendered chart `argo-cd-7.8.1` into the hub's own `cicd` namespace. At 2026-09-13T13:42–13:45Z, hub ArgoCD (`argocd-controller`) rewrote the labels on its own Helm-owned objects.
- That app no longer exists, but the residue remains.

**Live evidence (2026-09-13):**

| Object | Helm release annotation | `argocd.argoproj.io/instance` | `helm.sh/chart` |
|---|---|---|---|
| ConfigMaps `argocd-cm`, `argocd-cmd-params-cm`, `argocd-gpg-keys-cm`, `argocd-notifications-cm`, `argocd-rbac-cm`, `argocd-ssh-known-hosts-cm`, `argocd-tls-certs-cm` | `argocd` | `ubuntu-k3s-platform` | `argo-cd-7.8.1` |
| Secrets `argocd-secret`, `argocd-notifications-secret` | `argocd` | `ubuntu-k3s-platform` | `argo-cd-7.8.1` |
| ServiceAccount `argocd-dex-server` | none (dex is disabled in the release) | `ubuntu-k3s-platform` | `argo-cd-7.8.1` |

- Each Helm-owned object has a `managedFields` entry `{manager: argocd-controller, operation: Update}` owning `f:helm.sh/chart`, `f:app.kubernetes.io/instance`, `f:app.kubernetes.io/version` and `f:argocd.argoproj.io/instance`.
- Every Helm SSA apply that changes those values conflicts.
- ConfigMap `data` still matches Helm rev 3 for all seven ConfigMaps. Only ownership and labels are wrong.

**Remediation technique (verified with `kubectl patch --dry-run=server` on `argocd-gpg-keys-cm`):**
- A JSON patch that `test`s and `remove`s the `argocd-controller` entry in `/metadata/managedFields` is accepted.
- The server keeps only the `helm` Apply entry and adds no new manager.
- Once unowned, those label fields no longer conflict, and the next Helm apply takes them over.
- `--force-conflicts` or a partial SSA apply under manager `helm` must NOT be used: a partial apply under Helm's manager deletes the `data` fields Helm owns.

## Fix

### S1 — `scripts/plugins/argocd.sh`: `argocd_reclaim_release_ownership`

Append these two functions at the end of `scripts/plugins/argocd.sh`, after `_argocd_values_branch_drift`:

```bash
function argocd_reclaim_release_ownership() {
   local _context="k3d-k3d-cluster"
   local _namespace="${ARGOCD_NAMESPACE:-cicd}"
   local _release="${ARGOCD_HELM_RELEASE:-argocd}"
   local _apply=0

   while [[ $# -gt 0 ]]; do
      case "$1" in
         --context)
            if [[ -z "${2:-}" ]]; then
               _warn "[argocd] --context requires a value"
               return 2
            fi
            _context="$2"
            shift 2
            ;;
         --confirm)
            _apply=1
            shift
            ;;
         -h|--help)
            cat <<'EOF'
Usage: argocd_reclaim_release_ownership [--context <kube-context>] [--confirm]

Find ArgoCD Helm release objects (ConfigMaps, Secrets, ServiceAccounts) whose labels
were taken over by an ArgoCD Application (field manager argocd-controller), and
orphans that Application left behind. Dry run by default.

  --context   Kube context (default: k3d-k3d-cluster)
  --confirm   Strip the argocd-controller managedFields entries and the
              argocd.argoproj.io/instance label from release objects, and
              delete orphan ServiceAccounts. Orphan ConfigMaps/Secrets are
              only reported.
EOF
            return 0
            ;;
         *)
            _warn "[argocd] Unknown option: $1"
            return 2
            ;;
      esac
   done

   local _objects _apps _plan
   _objects="$(_kubectl --no-exit --context "${_context}" -n "${_namespace}" \
      get configmap,secret,serviceaccount -o json --show-managed-fields 2>/dev/null)"
   if [[ -z "${_objects}" ]]; then
      _warn "[argocd] Could not read ConfigMaps/Secrets/ServiceAccounts from ${_context}/${_namespace}"
      return 2
   fi
   _apps="$(_kubectl --no-exit --context "${_context}" -n "${_namespace}" \
      get applications.argoproj.io -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"

   if ! _plan="$(printf '%s' "${_objects}" | _argocd_foreign_ownership_plan "${_release}" "${_apps}")"; then
      _warn "[argocd] Could not parse objects from ${_context}/${_namespace}"
      return 2
   fi
   if [[ -z "${_plan}" ]]; then
      _info "[argocd] No foreign ownership on ${_namespace} objects of Helm release ${_release}"
      return 0
   fi

   local _action _kind _name _indices _instance _patch _idx _rc=0
   local -a _idx_list
   while IFS=$'\t' read -r _action _kind _name _indices _instance; do
      case "${_action}" in
         strip)
            _info "[argocd] ${_kind}/${_name}: argocd-controller managedFields [${_indices}], tracking label ${_instance}"
            (( _apply )) || continue
            if [[ "${_indices}" != "-" ]]; then
               _patch="["
               IFS=',' read -r -a _idx_list <<<"${_indices}"
               for _idx in "${_idx_list[@]}"; do
                  _patch+="{\"op\":\"test\",\"path\":\"/metadata/managedFields/${_idx}/manager\",\"value\":\"argocd-controller\"},"
                  _patch+="{\"op\":\"remove\",\"path\":\"/metadata/managedFields/${_idx}\"},"
               done
               _patch="${_patch%,}]"
               if ! _kubectl --no-exit --context "${_context}" -n "${_namespace}" \
                  patch "${_kind}" "${_name}" --type=json -p "${_patch}" >/dev/null; then
                  _warn "[argocd] ${_kind}/${_name}: managedFields strip failed"
                  _rc=1
                  continue
               fi
            fi
            if [[ "${_instance}" != "-" ]]; then
               if ! _kubectl --no-exit --context "${_context}" -n "${_namespace}" \
                  label "${_kind}" "${_name}" argocd.argoproj.io/instance- >/dev/null; then
                  _warn "[argocd] ${_kind}/${_name}: tracking label removal failed"
                  _rc=1
               fi
            fi
            ;;
         orphan)
            _info "[argocd] ${_kind}/${_name}: orphan of removed Application ${_instance}"
            (( _apply )) || continue
            if ! _kubectl --no-exit --context "${_context}" -n "${_namespace}" \
               delete "${_kind}" "${_name}" >/dev/null; then
               _warn "[argocd] ${_kind}/${_name}: delete failed"
               _rc=1
            fi
            ;;
         review)
            _warn "[argocd] ${_kind}/${_name}: orphan of removed Application ${_instance}; review manually (not deleted)"
            ;;
      esac
   done <<<"${_plan}"

   if (( ! _apply )); then
      _info "[argocd] Dry run; rerun with --confirm to apply"
   fi
   return "${_rc}"
}

function _argocd_foreign_ownership_plan() {
   python3 -c '
import json
import sys

release = sys.argv[1]
apps = set(sys.argv[2].split())
tracking = "argocd.argoproj.io/instance"

try:
    doc = json.load(sys.stdin)
except ValueError:
    sys.exit(3)

for obj in doc.get("items", []):
    meta = obj.get("metadata", {})
    kind = obj.get("kind", "").lower()
    name = meta.get("name", "")
    labels = meta.get("labels") or {}
    annotations = meta.get("annotations") or {}
    instance = labels.get(tracking, "")
    if annotations.get("meta.helm.sh/release-name") == release:
        indices = [str(i) for i, entry in enumerate(meta.get("managedFields") or [])
                   if entry.get("manager") == "argocd-controller"]
        if indices or instance:
            print("\t".join(["strip", kind, name, ",".join(reversed(indices)) or "-", instance or "-"]))
    elif instance and instance not in apps and labels.get("app.kubernetes.io/part-of") == "argocd":
        action = "orphan" if kind == "serviceaccount" else "review"
        print("\t".join([action, kind, name, "-", instance]))
' "$1" "${2:-}"
}
```

Notes:
- The `managedFields` indices are emitted in descending order, so earlier removals in the JSON patch do not shift later indices. Each `remove` is guarded by a `test` on the manager name, so a changed object makes the patch fail rather than remove the wrong entry.
- `strip` changes no `data` and no Helm-owned label values. The stale label values (`helm.sh/chart: argo-cd-7.8.1`, …) are corrected by the next `helm upgrade`, which no longer conflicts.
- Only ServiceAccounts are deleted as orphans. ConfigMaps and Secrets can hold data, so they are only reported.

### S2 — tests: `scripts/tests/plugins/argocd_reclaim_release_ownership.bats` (new)

Follow the setup style of `scripts/tests/plugins/argocd_values_branch_drift.bats`: `source test_helpers.bash`, `init_test_env`, then source `argocd.sh`.

**Fixture.** One `{"items":[...]}` JSON, in a heredoc helper, containing:
- `ConfigMap argocd-cm`
  - Annotation `meta.helm.sh/release-name: argocd`.
  - Labels `argocd.argoproj.io/instance: ubuntu-k3s-platform` and `app.kubernetes.io/part-of: argocd`.
  - `managedFields` managers in order: `helm`, `argocd-controller`, `kubectl-patch`.
- `Secret argocd-secret`
  - Release annotation `argocd`.
  - `managedFields` managers `argocd-controller`, `helm`, `argocd-controller`.
  - No tracking label.
- `ConfigMap argocd-redis-health-configmap`: release annotation `argocd`, managers `helm` only, no tracking label.
- `ServiceAccount argocd-dex-server`: no annotations; labels `argocd.argoproj.io/instance: ubuntu-k3s-platform` and `app.kubernetes.io/part-of: argocd`.
- `Secret stale-notes`: no annotations; same two labels.

**Tests.** Assert tokens only; never `grep -F` a whole source line.

1. **Plan: stripping a release object.**
   - Pipe the fixture to `_argocd_foreign_ownership_plan argocd ""`.
   - Output has a line with `strip`, `configmap`, `argocd-cm`, tab-separated index `1` and `ubuntu-k3s-platform`.
   - Output has a line with `argocd-secret` and indices `2,0`.
   - No line mentions `argocd-redis-health-configmap`.
2. **Plan: orphans.**
   - With apps `""`: a line `orphan … serviceaccount … argocd-dex-server`, and a line `review … secret … stale-notes`.
   - With apps `"ubuntu-k3s-platform other-app"`: neither `argocd-dex-server` nor `stale-notes` appears.
3. **Dry run.**
   - Stub `_kubectl`: log `$*` to `${BATS_TEST_TMPDIR}/calls`.
     - When the args contain `get configmap,secret,serviceaccount`, print the fixture.
     - When they contain `get applications.argoproj.io`, print nothing.
   - `run argocd_reclaim_release_ownership`.
   - Status 0; output contains `--confirm`; the calls file has no line containing ` patch `, ` label ` or ` delete `.
4. **`--confirm`.** Same stub, `run argocd_reclaim_release_ownership --confirm`. Status 0, and the calls file contains:
   - a `patch configmap argocd-cm` line with `/metadata/managedFields/1/manager` and `"op":"test"`;
   - a `patch secret argocd-secret` line in which `/metadata/managedFields/2` appears before `/metadata/managedFields/0` (compare byte offsets with bash `${line%%…}` length, or `awk index()`);
   - a `label configmap argocd-cm` line with `argocd.argoproj.io/instance-`;
   - a `delete serviceaccount argocd-dex-server` line;
   - no line containing `delete secret`.
5. **Failed patch.** The stub returns 1 for `patch` calls. `run argocd_reclaim_release_ownership --confirm`: status 1, output contains `managedFields strip failed`, and the calls file has no `label configmap argocd-cm` line.
6. **Unreadable objects.** The stub prints nothing for every call. Status 2, output contains `Could not read`.
7. **Unknown option.** `run argocd_reclaim_release_ownership --bogus`: status 2, output contains `Unknown option`.

### S3 — `docs/api/functions.md`

Add a row directly after the `argocd_check_values_branch` row:

```
| `argocd_reclaim_release_ownership` | `scripts/plugins/argocd.sh` | Dry-run by default; with `--confirm`, strips `argocd-controller` managedFields entries and the `argocd.argoproj.io/instance` label from ArgoCD Helm release ConfigMaps/Secrets/ServiceAccounts (left by an Application that rendered the argo-cd chart into the hub) so `helm upgrade argocd` no longer hits SSA conflicts, and deletes orphan ServiceAccounts; orphan ConfigMaps/Secrets are only reported (v1.34.0+) |
```

## CHANGELOG

Under `## [Unreleased]` → `### Added`, as the last bullet of that section:

```
- `argocd_reclaim_release_ownership [--context <ctx>] [--confirm]` reports, and with `--confirm` removes, ArgoCD Application ownership (`argocd-controller` managedFields and `argocd.argoproj.io/instance` labels) on the ArgoCD Helm release's own ConfigMaps/Secrets/ServiceAccounts, plus orphan ServiceAccounts; it clears the SSA conflicts that made `helm upgrade argocd` fail on the hub after `ubuntu-k3s-platform` rendered argo-cd 7.8.1 into `cicd`
```

## Definition of Done

- [ ] S1–S3 applied. Nothing else in `scripts/plugins/argocd.sh` changed.
- [ ] `shellcheck -x scripts/plugins/argocd.sh`: no new warnings (paste before/after counts).
- [ ] `bats scripts/tests/plugins/argocd_reclaim_release_ownership.bats scripts/tests/plugins/argocd_values_branch_drift.bats scripts/tests/plugins/argocd.bats`: all pass (paste the summary).
- [ ] CHANGELOG bullet added.
- [ ] Commit message, verbatim: `feat(argocd): reclaim ArgoCD Helm release objects from foreign Application ownership`
- [ ] Pushed; `git rev-parse origin/k3d-manager-v1.34.0` equals the commit SHA.

## Live rollout (operator; NOT for Codex)

1. `./scripts/k3d-manager argocd_reclaim_release_ownership`: expect 9 `strip` lines and 1 `orphan` (`argocd-dex-server`).
2. With a go: add `--confirm`.
3. `helm upgrade argocd argo/argo-cd -n cicd --version 10.8.4 --reuse-values --kube-context k3d-k3d-cluster`: expect `deployed` (rev 5). The labels return to `argo-cd-10.8.4` / `argocd`.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT run `kubectl`, `helm` or any `k3d-manager` command against a live cluster. Use stubs only.
- Do NOT use `--force-conflicts`, `kubectl apply --server-side`, or `--field-manager=helm` in the new function.
- Do NOT change `register_app_cluster`, the ApplicationSets, `bin/cluster-up`, `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or memory-bank.
- Do NOT `grep -F` whole source lines in BATS.
