# How-To: ACG Sandbox (AWS EC2)

The ACG plugin provisions a t3.medium EC2 instance on an ACG (A Cloud Guru) sandbox account, installs k3s via k3sup, and wires it into `~/.kube/config` as the `ubuntu-k3s` context.

## Prerequisites

- Active ACG sandbox with AWS credentials copied to `~/.aws/credentials`
- `aws`, `k3sup`, and `ssh` in PATH
- SSH key pair available (generated automatically by `acg_provision`)

## Full Lifecycle

### 0. Extract AWS Credentials

Before provisioning, extract the sandbox AWS credentials from the Pluralsight Cloud Access panel.

**Option A - Playwright (browser helper must be running):**

```bash
./scripts/k3d-manager acg_get_credentials "https://app.pluralsight.com/cloud-playground/cloud-sandboxes/<sandbox-id>"
```

**Option B - Paste from clipboard (no Playwright needed):**

1. Open the Pluralsight sandbox page and copy the credentials block
2. Run:

```bash
pbpaste | ./scripts/k3d-manager acg_import_credentials
```

Both options write to `~/.aws/credentials` under `[default]` and confirm with a masked key preview.

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
./scripts/k3d-manager acg_extend_playwright <sandbox-url>
# Example cloud playground URL
./scripts/k3d-manager acg_extend_playwright "https://app.pluralsight.com/cloud-playground/cloud-sandboxes"
```

The browser helper opens the sandbox page and clicks the extend button automatically. First run: you will be prompted to log into Pluralsight manually in the browser window; the session persists for subsequent runs.

Set `K3DM_ACG_SKIP_SESSION_CHECK=1` to bypass the Pluralsight session check (useful for CI or troubleshooting Playwright issues).

### 4a. Recover an Expired Sandbox

Once a sandbox has expired there is nothing left to extend — it has to be replaced. `make acg-restart`
does the whole recovery in one call:

```bash
make acg-restart
```

That deletes the expired sandbox, starts a fresh one through the Playwright/CDP browser helper,
re-runs `acg_get_credentials`, and verifies the result — so `~/.aws/credentials` is refreshed by the
time it returns.

Override the defaults when you need a specific sandbox or cloud:

```bash
make acg-restart URL="https://app.pluralsight.com/cloud-playground/cloud-sandboxes/<sandbox-id>" PROVIDER=aws
```

`URL` defaults to the sandbox list page and `PROVIDER` defaults to `aws` (`gcp` and `azure` are also accepted).

**Prerequisites:**

- The Chrome CDP helper must be available — run `make chrome-cdp` first if the launchd agent is not loaded.
- The first Pluralsight login of a session is manual, so this needs a **real TTY**. It cannot be run
  from a non-interactive agent or CI shell.

`acg_restart` replaces the **Pluralsight sandbox account** and its AWS credentials. It does not
provision the EC2 instance or install k3s — that is `make up` (Step 2), which also re-registers the
app cluster with ArgoCD (Step 10). So the full recovery is three commands:

```bash
make chrome-cdp     # regenerates and loads the CDP launchd agent
make acg-restart    # new sandbox + fresh credentials
make up             # provision EC2, install k3s, register with ArgoCD, deploy the stack
```

`make argocd-registration` is *not* the step to reach for here — there is no cluster to register
until `make up` has run. It is for re-registering an existing cluster whose IP changed.

### 4b. One-Shot Recovery

`make acg-recover` chains all three:

```bash
make acg-recover
```

It runs `chrome-cdp`, then `acg-restart`, then `make up` — and forces `K3DM_RESUME=` empty for that
final step. That matters: `cluster-up` clears its lifecycle checkpoints only when `K3DM_RESUME` is
not `1`, so with `K3DM_RESUME=1` exported in your shell a recovery would happily skip "Step 2 —
Provisioning 3-node cluster" against a sandbox where nothing exists yet. The override neutralises an
exported value, so `acg-recover` always provisions from scratch.

`URL=` and `PROVIDER=` pass through to `acg-restart` as above.

### 5. Teardown

```bash
./scripts/k3d-manager acg_teardown --confirm
```

Terminates the EC2 instance, removes the VPC/SG/key pair, and removes the `ubuntu-k3s` context from `~/.kube/config`.

## Notes

- `ACG_ALLOWED_CIDR` defaults to `0.0.0.0/0` (open) - always set it to your IP in shared/public environments
- The sandbox TTL is 4 hours by default; extend before it expires to avoid losing cluster state
- All AWS resources are tagged with `k3d-manager` for easy identification in the ACG console
