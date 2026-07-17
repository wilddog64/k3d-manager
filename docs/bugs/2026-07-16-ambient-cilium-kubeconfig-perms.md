# Bugfix: v1.16.0 — `_ambient_install_cilium` uses root-only kubeconfig as non-root SSH user

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/plugins/shopping_cart.sh`

---

## Problem

The Phase 1 ambient-mesh smoke (`K3S_AMBIENT_MESH=true K3S_AWS_SSM_ENABLED=false
CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager deploy_cluster --confirm`) fails at the
Cilium install step with:

```
INFO: [shopping_cart] Installing Cilium 1.16.5 (CNI for Istio ambient)...
Error: Kubernetes cluster unreachable: error loading config file
"/etc/rancher/k3s/k3s.yaml": open /etc/rancher/k3s/k3s.yaml: permission denied
```

The node then stays `NotReady` (flannel is correctly off, but Cilium never installs), and
`_ambient_install_cilium` spins its 18×10s rollout loop for 3 min and returns 1.

**Root cause:** `_ambient_install_cilium` was ported from `_oci_install_cilium` and runs `helm`
/`kubectl` over SSH **as the `ubuntu` user**, but points `KUBECONFIG` at
`/etc/rancher/k3s/k3s.yaml`, which is `root:root 0600` — unreadable by `ubuntu`. The OCI flow
tolerated this; the k3sup flow does not. `deploy_app_cluster` already copies the kubeconfig to a
user-readable location (`/home/${ssh_user}/.kube/k3s.yaml`, `ubuntu:ubuntu 0600`, `server:
https://127.0.0.1:6443`) in the `REMOTE` heredoc **before** this helper is called, so the fix is
to read that copy.

---

## Reproduction

On a fresh ACG sandbox (creds imported), run:

```
K3S_AMBIENT_MESH=true K3S_AWS_SSM_ENABLED=false CLUSTER_PROVIDER=k3s-aws \
  ./scripts/k3d-manager deploy_cluster --confirm
```

Expected: 3 nodes `Ready` on Cilium. Actual: server node `NotReady`, permission-denied on the
root kubeconfig, deploy exits 1.

**Fix already proven live:** running the identical helm command with
`KUBECONFIG=$HOME/.kube/k3s.yaml` installed Cilium and flipped the node to `Ready`
(`cilium 1/1 Running`, `cni.exclusive=false`).

---

## Fix

### Change 1 — `scripts/plugins/shopping_cart.sh`: read the user-readable kubeconfig copy

Replace every `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` in `_ambient_install_cilium` with the
user-home copy (5 occurrences: idempotent check, `helm repo add`, `helm repo update`,
`helm upgrade --install`, rollout status).

**Exact old block (lines 1064–1096):**

```bash
  # Idempotent — skip if already installed
  if ${ssh_cmd} "KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm status cilium -n kube-system >/dev/null 2>&1" 2>/dev/null; then
    _info "[shopping_cart] Cilium already installed — skipping"
    return 0
  fi

  _info "[shopping_cart] Installing Cilium ${_AMBIENT_CILIUM_VERSION} (CNI for Istio ambient)..."
  # shellcheck disable=SC2029
  ${ssh_cmd} "
    if ! command -v helm >/dev/null 2>&1; then
      curl -fsSL https://raw.githubusercontent.com/helm/helm/v3.17.3/scripts/get-helm-3 | DESIRED_VERSION=v3.17.3 bash >/dev/null
    fi
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo update >/dev/null 2>&1
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install cilium cilium/cilium \
      --version '${_AMBIENT_CILIUM_VERSION}' \
      --namespace kube-system \
      --set operator.replicas=1 \
      --set cni.exclusive=false \
      --set kubeProxyReplacement=true \
      --set k8sServiceHost='${external_ip}' \
      --set k8sServicePort=6443
  "
  local attempts=0
  until ${ssh_cmd} "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n kube-system rollout status daemonset/cilium --timeout=10s >/dev/null 2>&1" 2>/dev/null; do
    (( attempts++ ))
    if (( attempts >= 18 )); then
      _err "[shopping_cart] Cilium DaemonSet not ready after 3 min"
      return 1
    fi
    sleep 10
  done
  _info "[shopping_cart] Cilium ready"
```

**Exact new block:**

```bash
  local remote_kubeconfig="/home/${ssh_user}/.kube/k3s.yaml"

  # Idempotent — skip if already installed
  if ${ssh_cmd} "KUBECONFIG=${remote_kubeconfig} helm status cilium -n kube-system >/dev/null 2>&1" 2>/dev/null; then
    _info "[shopping_cart] Cilium already installed — skipping"
    return 0
  fi

  _info "[shopping_cart] Installing Cilium ${_AMBIENT_CILIUM_VERSION} (CNI for Istio ambient)..."
  # shellcheck disable=SC2029
  ${ssh_cmd} "
    if ! command -v helm >/dev/null 2>&1; then
      curl -fsSL https://raw.githubusercontent.com/helm/helm/v3.17.3/scripts/get-helm-3 | DESIRED_VERSION=v3.17.3 bash >/dev/null
    fi
    KUBECONFIG=${remote_kubeconfig} helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
    KUBECONFIG=${remote_kubeconfig} helm repo update >/dev/null 2>&1
    KUBECONFIG=${remote_kubeconfig} helm upgrade --install cilium cilium/cilium \
      --version '${_AMBIENT_CILIUM_VERSION}' \
      --namespace kube-system \
      --set operator.replicas=1 \
      --set cni.exclusive=false \
      --set kubeProxyReplacement=true \
      --set k8sServiceHost='${external_ip}' \
      --set k8sServicePort=6443
  "
  local attempts=0
  until ${ssh_cmd} "KUBECONFIG=${remote_kubeconfig} kubectl -n kube-system rollout status daemonset/cilium --timeout=10s >/dev/null 2>&1" 2>/dev/null; do
    (( attempts++ ))
    if (( attempts >= 18 )); then
      _err "[shopping_cart] Cilium DaemonSet not ready after 3 min"
      return 1
    fi
    sleep 10
  done
  _info "[shopping_cart] Cilium ready"
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | `_ambient_install_cilium` reads `/home/${ssh_user}/.kube/k3s.yaml` (user-readable copy) instead of the root-only `/etc/rancher/k3s/k3s.yaml` |

---

## Rules

- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — zero new warnings
- No other files touched
- Do NOT change `k8sServiceHost='${external_ip}'` — the k3s API cert includes the public IP as a
  SAN, so it is valid. (Agent-node reachability of the public IP:6443 is being verified separately
  in the live re-run; only touch it if that re-run proves agents can't reach the API.)

---

## Definition of Done

- [ ] `_ambient_install_cilium` uses `/home/${ssh_user}/.kube/k3s.yaml` for all helm/kubectl calls
- [ ] `shellcheck -S warning scripts/plugins/shopping_cart.sh` clean
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(mesh): _ambient_install_cilium reads user-readable kubeconfig (k3sup non-root SSH)
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/shopping_cart.sh`
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`
- Do NOT change the `k8sServiceHost` value in this fix
