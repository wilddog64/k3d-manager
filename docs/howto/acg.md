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

## SSM vs SSH transport

The `k3s-aws` provider reaches the sandbox nodes over one of two transports, chosen by
`_provider_k3s_aws_autoselect_tunnel_mode`:

- **SSH (`autossh`)** — the default. Selected unconditionally whenever `HUB_VAULT_USE_BRIDGE=1`
  (the default), because the laptop Vault profile needs a *reverse* tunnel and the node-side
  `socat` bridge. SSM offers local port forwarding only, so selecting it there would publish a
  dead `vault-bridge` endpoint and stall ESO indefinitely.
- **SSM port forwarding** — no inbound SSH. Only reachable when you set `HUB_VAULT_USE_BRIDGE=0`,
  and only when `iam:CreateRole` is permitted so the stack can be given an SSM instance profile.

Set `K3S_AWS_SSM_ENABLED=true|false` to pin the choice and skip auto-detection.

### SSM degrades to SSH rather than aborting

SSM is selected optimistically. If the agent never registers, the tunnel fails to start, or the
SSM-based bootstrap fails, the provider logs a `WARN`, clears `K3S_AWS_SSM_ENABLED`, and retries
the same work over SSH. Provisioning fails only when **both** transports fail.

This is deliberate: an SSM registration timeout is a transport problem, not a cluster problem, and
it should cost you a detour rather than the whole run.

### Why an SSM timeout can happen on a first provision

When `amazon-ssm-agent` cannot fetch credentials at boot — because the instance launched with no
IAM instance profile — it backs off hard:

```
[CredentialRefresher] Sleeping for 28m50s before retrying retrieve credentials
```

It does not look at IMDS again until that expires. The stack is created with `EnableSsm=false` and
only later updated to `true`, which attaches the profile to the **already-running** nodes — so the
agent stays asleep for up to ~29 minutes after the profile lands. Both registration waits
(`_provider_k3s_aws_wait_ssm_registered` at 150s, `ssm_wait` at 300s) are shorter than that.

**Do not raise the timeouts** — the wait would have to be ~29 minutes. Either let the SSH fallback
take over (the current behaviour), or restart the agent on the node once the profile is attached:

```bash
ssh ubuntu sudo systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service
```

A retry of the whole run often appears to "fix" it, because `_provider_k3s_aws_enable_ssm_stack`
early-returns once `EnableSsm` is already `true` and the backoff has expired in the meantime. The
bug is deterministic on a first provision, not intermittent.

The agent log on the node is `/var/log/amazon/ssm/amazon-ssm-agent.log`. Ignore the loud
`AccessDeniedException: Systems Manager's instance management role is not configured for account`
— that is Default Host Management Configuration failing and is irrelevant. The real line above it
is `EC2RoleRequestError: no EC2 instance role found`.

## Data-layer sync that never converges

`cluster-up` Step 10b waits for the `<cluster>-data-layer` ArgoCD Application to reach `Synced`
(300s, then one force-sync and a further 180s). A sync wait cannot succeed while a pod in
`shopping-cart-data` is stuck pulling its image, so the run now checks for that directly and
aborts with the reason instead of polling until the deadline:

```
WARN: [acg-up] data-layer is blocked on an image pull, not on a slow sync:
WARN: [acg-up]   pod/minio-0 minio ImagePullBackOff: Back-off pulling image "..." 401 UNAUTHORIZED
WARN: [acg-up] An ArgoCD sync cannot clear an image pull failure — aborting instead of waiting out the timeout.
```

The check fires on `ImagePullBackOff`, `ErrImagePull`, `InvalidImageName`, `ErrInvalidImageName`
and `RegistryUnavailable`, in init containers as well as regular ones, and only after the same
verdict on three consecutive polls so a pull still in progress is not mistaken for a failure.
`ContainerCreating`, `CreateContainerConfigError` and `CrashLoopBackOff` are deliberately **not**
fatal — those can still clear on their own (for example once ESO populates a Secret).

When it fires, the image reference is wrong or unreachable, and the fix is in
`shopping-cart-infra` under `data-layer/` — not in this repo.

### Telling a gated registry from a missing tag

Request `latest` with an anonymous bearer token. If that is also `401`, the **repository** is gated
and no tag will pull; if only your pinned tag fails, the tag is gone. Always confirm egress with a
known-public control image from the same registry first:

```bash
T=$(curl -s "https://quay.io/v2/auth?service=quay.io&scope=repository:minio/minio:pull" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
curl -s -o /dev/null -w '%{http_code}\n' -I -H "Authorization: Bearer $T" \
  https://quay.io/v2/minio/minio/manifests/latest
```

As of 2026-09-25 both `quay.io/minio/minio` and `quay.io/minio/mc` answer `401` for every tag,
including `latest`, while `quay.io/prometheus/busybox:latest` returns `200` — so MinIO's images
are no longer anonymously pullable and need a mirror or a pull secret.
