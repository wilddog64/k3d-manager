# Bug: Hostinger app-cluster registers with insecure TLS + assumes argocd-manager SA exists

**Date:** 2026-06-25
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`
**Affects:** `k3d-manager` (`scripts/plugins/argocd.sh`, `scripts/lib/providers/k3s-hostinger.sh`)
**Files (code):** `scripts/plugins/argocd.sh`, `scripts/lib/providers/k3s-hostinger.sh`, `scripts/tests/lib/provider_contract.bats`

> Follow-up to the cutover spec
> `docs/bugs/2026-06-25-hostinger-cutover-app-cluster-role-and-green1-retire.md`.
> That spec's Change 4 routed the Hostinger registration through `register_app_cluster`
> (commit `c9e10fb4`) to get the `environment` / `argocd-chart-version` / `argocd-replicas`
> labels. `register_app_cluster` is **token + `insecure: true`** by design (it was the
> ubuntu-k3s SSH-tunnel path), so the cutover introduced the two regressions below.

---

## Problem

After `c9e10fb4`, `_hostinger_register_cluster` registers `cluster-ubuntu-hostinger` with the
hub by:
1. minting a bearer token via `kubectl --context ubuntu-hostinger create token argocd-manager
   -n kube-system`, and
2. calling `register_app_cluster`, whose secret hardcodes
   `"tlsClientConfig": { "insecure": ${ARGOCD_APP_CLUSTER_INSECURE} }` and is fed
   `ARGOCD_APP_CLUSTER_INSECURE` defaulting to **`true`**.

**Two consequences:**

- **(A) TLS regression.** The pre-cutover Hostinger secret used `caData` (CA-verified TLS read
  from the kubeconfig). The new path drops `caData` and connects hub→Hostinger with
  `insecure: true`. Hostinger fronts **live public hostnames** (`frontend.3ai-talk.org`), so this
  trips the project rule: *"`insecureSkipVerify: true` … dev-only. Never introduce in production
  config paths."*
- **(B) Hidden prerequisite.** `create token argocd-manager` requires the `argocd-manager`
  ServiceAccount to exist in `kube-system` on the Hostinger cluster. If it is absent the token is
  empty and the new guard aborts the refresh — where the old `caData`/cert path succeeded. The
  refresh now silently depends on out-of-band SA setup.

**Root cause:** `register_app_cluster` has no CA-verified TLS option, and the Hostinger provider
neither supplies `caData` nor ensures the SA it depends on.

---

## Fix

Keep the cutover's design (token auth + routing through `register_app_cluster` for the labels),
but make the connection **CA-verified by default** and make the SA prerequisite **self-healing**.

### Change 1 — `scripts/plugins/argocd.sh`: optional CA-verified TLS in `register_app_cluster`

Add support for `ARGOCD_APP_CLUSTER_CA_DATA`. When set, emit `caData` and force `insecure:false`;
otherwise preserve the existing `insecure` behavior (backward-compatible for ubuntu-k3s, which
sets no CA data).

**Exact old block (help text — `register_app_cluster`, the `Config (...)` lines):**

```bash
  ARGOCD_APP_CLUSTER_INSECURE      Skip TLS      (default: true — dev only)
  ARGOCD_APP_CLUSTER_TOKEN         Bearer token  (required — no default)
HELP
```

**Exact new block:**

```bash
  ARGOCD_APP_CLUSTER_INSECURE      Skip TLS      (default: true — dev only)
  ARGOCD_APP_CLUSTER_CA_DATA       CA bundle     (optional, base64; when set forces insecure=false)
  ARGOCD_APP_CLUSTER_TOKEN         Bearer token  (required — no default)
HELP
```

**Exact old block (secret render, the `local rendered` block through the `EOF`):**

```bash
  local rendered
  rendered="$(mktemp -t argocd-cluster-secret.XXXXXX.yaml)"
  trap '$(_cleanup_trap_command "$rendered")' RETURN

  local _wasx=0
  case $- in *x*) _wasx=1; set +x;; esac
  cat > "$rendered" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGOCD_APP_CLUSTER_SECRET_NAME}
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: cluster
    argocd.argoproj.io/cluster-name: "${ARGOCD_APP_CLUSTER_NAME}"
    environment: "${app_cluster_environment}"
    argocd-chart-version: "${ARGOCD_CHART_VERSION}"
    argocd-replicas: "2"
type: Opaque
stringData:
  name: ${ARGOCD_APP_CLUSTER_NAME}
  server: ${ARGOCD_APP_CLUSTER_SERVER}
  config: |
    {
      "bearerToken": "${ARGOCD_APP_CLUSTER_TOKEN}",
      "tlsClientConfig": {
        "insecure": ${ARGOCD_APP_CLUSTER_INSECURE}
      }
    }
EOF
```

**Exact new block:**

```bash
  local _tls_client_config
  if [[ -n "${ARGOCD_APP_CLUSTER_CA_DATA:-}" ]]; then
    _tls_client_config="\"caData\": \"${ARGOCD_APP_CLUSTER_CA_DATA}\", \"insecure\": false"
  else
    _tls_client_config="\"insecure\": ${ARGOCD_APP_CLUSTER_INSECURE:-true}"
  fi

  local rendered
  rendered="$(mktemp -t argocd-cluster-secret.XXXXXX.yaml)"
  trap '$(_cleanup_trap_command "$rendered")' RETURN

  local _wasx=0
  case $- in *x*) _wasx=1; set +x;; esac
  cat > "$rendered" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGOCD_APP_CLUSTER_SECRET_NAME}
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: cluster
    argocd.argoproj.io/cluster-name: "${ARGOCD_APP_CLUSTER_NAME}"
    environment: "${app_cluster_environment}"
    argocd-chart-version: "${ARGOCD_CHART_VERSION}"
    argocd-replicas: "2"
type: Opaque
stringData:
  name: ${ARGOCD_APP_CLUSTER_NAME}
  server: ${ARGOCD_APP_CLUSTER_SERVER}
  config: |
    {
      "bearerToken": "${ARGOCD_APP_CLUSTER_TOKEN}",
      "tlsClientConfig": { ${_tls_client_config} }
    }
EOF
```

> Note: `caData` is the base64 CA bundle (not secret); only `bearerToken` is sensitive and it is
> already inside the existing `set +x` guard. Do not move the token outside that guard.

### Change 2 — `scripts/lib/providers/k3s-hostinger.sh`: supply caData, default to secure, ensure the SA

Read the cluster `certificate-authority-data` from the kubeconfig, ensure the `argocd-manager`
SA exists on the Hostinger cluster **before** minting the token, pass `ARGOCD_APP_CLUSTER_CA_DATA`,
and flip the insecure default to **`false`** (refuse to register insecure unless explicitly
overridden).

**Exact old block (`_hostinger_register_cluster`, lines 119–148):**

```bash
function _hostinger_register_cluster() {
  _hostinger_load_argocd_plugin || return 1
  local argocd_ns="${ARGOCD_NAMESPACE:-cicd}"
  local secret_name="cluster-${_HOSTINGER_KUBE_CONTEXT}"
  local server token
  server="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${_HOSTINGER_KUBE_CONTEXT}\")].cluster.server}" 2>/dev/null)"
  token="$(kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" create token argocd-manager -n kube-system --duration="${HOSTINGER_ARGOCD_MANAGER_TOKEN_DURATION:-8760h}" 2>/dev/null || true)"
  if [[ -z "${server}" || -z "${token}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] could not read ${_HOSTINGER_KUBE_CONTEXT} server/token for ArgoCD registration" >&2
    return 1
  fi

  _info "[k3s-hostinger] Registering '${_HOSTINGER_KUBE_CONTEXT}' (${server}) with hub ArgoCD ns ${argocd_ns}..."
  local -a hub_kubectl=()
  read -r -a hub_kubectl <<< "$(_argocd_hub_kubectl_cmd)"
  (
    _kubectl() {
      "${hub_kubectl[@]}" "$@"
    }
    ARGOCD_NAMESPACE="${argocd_ns}" \
    ARGOCD_APP_CLUSTER_SECRET_NAME="${secret_name}" \
    ARGOCD_APP_CLUSTER_NAME="${_HOSTINGER_KUBE_CONTEXT}" \
    ARGOCD_APP_CLUSTER_SERVER="${server}" \
    ARGOCD_APP_CLUSTER_ENVIRONMENT="${HOSTINGER_ARGOCD_APP_CLUSTER_ENVIRONMENT:-${ARGOCD_APP_CLUSTER_ENVIRONMENT:-dev}}" \
    ARGOCD_APP_CLUSTER_INSECURE="${HOSTINGER_ARGOCD_APP_CLUSTER_INSECURE:-${ARGOCD_APP_CLUSTER_INSECURE:-true}}" \
    ARGOCD_APP_CLUSTER_TOKEN="${token}" \
    register_app_cluster
  ) || return 1
  _info "[k3s-hostinger] Registered — verify: kubectl get secret ${secret_name} -n ${argocd_ns}"
}
```

**Exact new block:**

```bash
function _hostinger_ensure_argocd_manager_sa() {
  local manifest="${SCRIPT_DIR}/etc/argocd-manager.yaml"
  if [[ ! -r "${manifest}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] argocd-manager manifest not found: ${manifest}" >&2
    return 1
  fi
  if ! kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" apply -f "${manifest}" >/dev/null 2>&1; then
    printf 'ERROR: %s\n' "[k3s-hostinger] failed to ensure argocd-manager SA/RBAC on ${_HOSTINGER_KUBE_CONTEXT}" >&2
    return 1
  fi
  _info "[k3s-hostinger] ensured argocd-manager SA/RBAC on ${_HOSTINGER_KUBE_CONTEXT}"
}

function _hostinger_register_cluster() {
  _hostinger_load_argocd_plugin || return 1
  local argocd_ns="${ARGOCD_NAMESPACE:-cicd}"
  local secret_name="cluster-${_HOSTINGER_KUBE_CONTEXT}"
  local insecure="${HOSTINGER_ARGOCD_APP_CLUSTER_INSECURE:-${ARGOCD_APP_CLUSTER_INSECURE:-false}}"
  local server ca_data token
  server="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${_HOSTINGER_KUBE_CONTEXT}\")].cluster.server}" 2>/dev/null)"
  ca_data="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${_HOSTINGER_KUBE_CONTEXT}\")].cluster.certificate-authority-data}" 2>/dev/null)"
  _hostinger_ensure_argocd_manager_sa || return 1
  token="$(kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" create token argocd-manager -n kube-system --duration="${HOSTINGER_ARGOCD_MANAGER_TOKEN_DURATION:-8760h}" 2>/dev/null || true)"
  if [[ -z "${server}" || -z "${token}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] could not read ${_HOSTINGER_KUBE_CONTEXT} server/token for ArgoCD registration" >&2
    return 1
  fi
  if [[ -z "${ca_data}" && "${insecure}" != "true" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] no certificate-authority-data for ${_HOSTINGER_KUBE_CONTEXT} in kubeconfig; refusing to register with insecure TLS (set HOSTINGER_ARGOCD_APP_CLUSTER_INSECURE=true to override)" >&2
    return 1
  fi

  _info "[k3s-hostinger] Registering '${_HOSTINGER_KUBE_CONTEXT}' (${server}) with hub ArgoCD ns ${argocd_ns}..."
  local -a hub_kubectl=()
  read -r -a hub_kubectl <<< "$(_argocd_hub_kubectl_cmd)"
  (
    _kubectl() {
      "${hub_kubectl[@]}" "$@"
    }
    ARGOCD_NAMESPACE="${argocd_ns}" \
    ARGOCD_APP_CLUSTER_SECRET_NAME="${secret_name}" \
    ARGOCD_APP_CLUSTER_NAME="${_HOSTINGER_KUBE_CONTEXT}" \
    ARGOCD_APP_CLUSTER_SERVER="${server}" \
    ARGOCD_APP_CLUSTER_ENVIRONMENT="${HOSTINGER_ARGOCD_APP_CLUSTER_ENVIRONMENT:-${ARGOCD_APP_CLUSTER_ENVIRONMENT:-dev}}" \
    ARGOCD_APP_CLUSTER_INSECURE="${insecure}" \
    ARGOCD_APP_CLUSTER_CA_DATA="${ca_data}" \
    ARGOCD_APP_CLUSTER_TOKEN="${token}" \
    register_app_cluster
  ) || return 1
  _info "[k3s-hostinger] Registered — verify: kubectl get secret ${secret_name} -n ${argocd_ns}"
}
```

### Change 3 — `scripts/tests/lib/provider_contract.bats`

Update the existing `_hostinger_register_cluster routes through register_app_cluster labels`
test and add CA-verified coverage:

- Stub `_hostinger_ensure_argocd_manager_sa() { :; }` (or mock the
  `--context ubuntu-hostinger apply -f` call) so the test does not hit a real cluster.
- Mock the `kubectl config view ... certificate-authority-data` jsonpath to return a value
  (e.g. `ca-data`).
- Assert the rendered secret now contains `"caData": "ca-data"` **and** `"insecure": false`
  (NOT `"insecure": true`).
- Add a focused assertion that when `ARGOCD_APP_CLUSTER_CA_DATA` is empty the rendered
  `tlsClientConfig` falls back to `"insecure": <value>` (backward-compat for ubuntu-k3s).

---

## Definition of Done

- [ ] `register_app_cluster` emits `caData` + `insecure:false` when `ARGOCD_APP_CLUSTER_CA_DATA`
      is set; unchanged behavior when it is empty.
- [ ] Hostinger registration reads `certificate-authority-data`, ensures the `argocd-manager` SA
      via `scripts/etc/argocd-manager.yaml`, defaults to secure TLS, and refuses insecure unless
      `HOSTINGER_ARGOCD_APP_CLUSTER_INSECURE=true`.
- [ ] `shellcheck -S warning scripts/plugins/argocd.sh scripts/lib/providers/k3s-hostinger.sh scripts/tests/lib/provider_contract.bats` — zero new warnings.
- [ ] `bats scripts/tests/lib/provider_contract.bats` passes.
- [ ] `./scripts/k3d-manager _agent_audit` exit 0.
- [ ] Committed + pushed to `feat/v1.8.0-acg-absorb-phase2-agy`; memory-bank updated with SHA.

**Commit message (exact):**
```
fix(hostinger): CA-verified TLS + ensure argocd-manager SA for app-cluster registration
```

---

## What NOT to Do

- Do NOT change `register_app_cluster`'s behavior when `ARGOCD_APP_CLUSTER_CA_DATA` is unset
  (ubuntu-k3s must keep working).
- Do NOT move the bearer token outside the existing `set +x` guard.
- Do NOT broaden `scripts/etc/argocd-manager.yaml` RBAC — reuse it as-is.
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the listed targets.
- Do NOT commit to `main` — work on `feat/v1.8.0-acg-absorb-phase2-agy`.
