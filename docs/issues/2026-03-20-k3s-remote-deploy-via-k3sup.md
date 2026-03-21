# Issue: k3s Deployment Requires Manual SSH — No Remote Deploy Support

**Date:** 2026-03-20
**Status:** Open
**Target:** v0.9.5

## Problem

`deploy_cluster` with `CLUSTER_PROVIDER=k3s` installs k3s locally on whichever machine
runs the script. There is no way to deploy k3s to a remote node from the management
machine (M4 Air). The current workaround is to SSH into the target node manually and
run the installer there — which means Gemini (or any operator) must shell into Ubuntu
EC2 to do what k3d-manager should handle automatically.

Every ACG sandbox recreation requires the same manual sequence:
1. SSH to EC2
2. Clone k3d-manager on the remote node
3. Run deploy_cluster on the remote node
4. SCP kubeconfig back to M4
5. Merge kubeconfig manually

## Fix: Add `deploy_app_cluster` using k3sup

[`k3sup`](https://github.com/alexellis/k3sup) installs k3s on remote nodes over SSH
with a single command. Wrap it in a new `deploy_app_cluster` function so the full
flow runs from M4 Air with no manual SSH required.

### Target UX

```bash
# From M4 Air — deploys k3s to EC2, merges kubeconfig automatically
./scripts/k3d-manager deploy_app_cluster --host ubuntu
```

### Implementation Plan

#### 1. Add `k3sup` install check to `deploy_app_cluster`

In `scripts/plugins/cluster_provider.sh` (or a new `scripts/plugins/k3sup.sh`):

```bash
function _ensure_k3sup() {
  if ! command -v k3sup &>/dev/null; then
    _info "k3sup not found — installing"
    _run_command --require-sudo -- curl -sLS https://get.k3sup.dev | sh
    _run_command --require-sudo -- install k3sup /usr/local/bin/
  fi
}
```

#### 2. `deploy_app_cluster` function

```bash
function deploy_app_cluster() {
  local host="${1:?Usage: deploy_app_cluster <ssh-host>}"
  local ssh_key="${K3DM_APP_CLUSTER_SSH_KEY:-${HOME}/.ssh/k3d-manager-key.pem}"
  local ssh_user="${K3DM_APP_CLUSTER_SSH_USER:-ubuntu}"
  local context_name="${K3DM_APP_CLUSTER_CONTEXT:-ubuntu-k3s}"

  _ensure_k3sup

  _info "Deploying k3s to ${host} as ${ssh_user}"
  _run_command -- k3sup install \
    --host "${host}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --context "${context_name}" \
    --local-path "${HOME}/.kube/config" \
    --merge \
    --skip-install

  _info "Verifying node ready"
  kubectl --context="${context_name}" get nodes
}
```

> `--local-path ~/.kube/config --merge` — k3sup merges the remote kubeconfig directly.
> `--skip-install` omitted when actually installing; shown here for illustration.

#### 3. Env vars to add to `scripts/etc/vars.sh`

```bash
K3DM_APP_CLUSTER_SSH_KEY="${HOME}/.ssh/k3d-manager-key.pem"
K3DM_APP_CLUSTER_SSH_USER="ubuntu"
K3DM_APP_CLUSTER_CONTEXT="ubuntu-k3s"
```

#### 4. Update Gemini rebuild spec

Replace Steps 2–4 in `docs/plans/v0.9.4-gemini-rebuild-ubuntu-k3s-e2e.md` with:

```bash
./scripts/k3d-manager deploy_app_cluster ubuntu
kubectl --context=ubuntu-k3s get nodes
```

## Definition of Done

- [ ] `_ensure_k3sup` installs k3sup if missing
- [ ] `deploy_app_cluster <host>` deploys k3s and merges kubeconfig in one command
- [ ] Env vars documented in `scripts/etc/vars.sh`
- [ ] Gemini rebuild spec updated to use `deploy_app_cluster`
- [ ] BATS test: `deploy_app_cluster` calls k3sup with correct flags (mock k3sup)
- [ ] No changes to existing `deploy_cluster` (local k3s install remains unchanged)

## What NOT to Do

- Do NOT remove the local `deploy_cluster` k3s path — still needed for in-VM installs
- Do NOT hardcode SSH key paths — use env vars with defaults
- Do NOT add `--skip-install` to the actual deploy call (only for dry-run/test use)
