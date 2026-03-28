# How-To: ACG Sandbox (AWS EC2)

The ACG plugin provisions a t3.medium EC2 instance on an ACG (A Cloud Guru) sandbox account, installs k3s via k3sup, and wires it into `~/.kube/config` as the `ubuntu-k3s` context.

## Prerequisites

- Active ACG sandbox with AWS credentials copied to `~/.aws/credentials`
- `aws`, `k3sup`, and `ssh` in PATH
- SSH key pair available (generated automatically by `acg_provision`)

## Full Lifecycle

### 1. Provision

```bash
# Restrict ingress to your IP (recommended)
export ACG_ALLOWED_CIDR=$(curl -s ifconfig.me)/32

./scripts/k3d-manager acg_provision --confirm
```

Creates: VPC, subnet, security group, key pair, t3.medium EC2 instance. Updates `~/.ssh/config` with the `ubuntu` host alias.

### 2. Verify

```bash
./scripts/k3d-manager acg_status
```

Shows instance state, public IP, and k3s health. Wait until k3s reports `Running` before proceeding.

### 3. Install k3s and Merge Kubeconfig

```bash
UBUNTU_K3S_SSH_HOST=ubuntu \
  ./scripts/k3d-manager deploy_app_cluster
```

Installs k3s via k3sup and merges the kubeconfig as the `ubuntu-k3s` context.

### 4. Extend Sandbox TTL

ACG sandboxes expire after 4 hours. To extend:

```bash
./scripts/k3d-manager antigravity_acg_extend <sandbox-url>
# Example cloud playground URL
./scripts/k3d-manager antigravity_acg_extend "https://app.pluralsight.com/cloud-playground/cloud-sandboxes"
```

The Antigravity browser opens and clicks the extend button automatically. **First run:** you will be prompted to log into Pluralsight manually in the browser window — session persists for subsequent runs.

Set `K3DM_ACG_SKIP_SESSION_CHECK=1` to bypass the Pluralsight session check (useful for CI or troubleshooting Playwright issues).

### 5. Teardown

```bash
./scripts/k3d-manager acg_teardown --confirm
```

Terminates the EC2 instance, removes the VPC/SG/key pair, and removes the `ubuntu-k3s` context from `~/.kube/config`.

## Notes

- `ACG_ALLOWED_CIDR` defaults to `0.0.0.0/0` (open) — always set it to your IP in shared/public environments
- The sandbox TTL is 4 hours by default; extend before it expires to avoid losing cluster state
- All AWS resources are tagged with `k3d-manager` for easy identification in the ACG console
