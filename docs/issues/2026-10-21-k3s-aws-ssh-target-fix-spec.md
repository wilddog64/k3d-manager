# Dispatch spec: resolve the provisioned k3s-aws SSH target

## Objective

Fix the ACG `make up` path so k3s installation uses the fresh server public IP
instead of the literal `ubuntu` alias when `UBUNTU_K3S_EXTERNAL_IP` received its
source-time default. Add offline regression tests and update the canonical bug
with implementation and test evidence. Do not perform live infrastructure work.

Canonical bug: `docs/bugs/2026-10-21-k3s-aws-ssh-target-uses-alias-instead-of-ip.md`.

## Evidence and diagnosis

The operator's live run reported:

```text
INFO: [acg] Updating SSH config with IP 44.247.81.210
INFO: [acg] Server:  44.247.81.210
INFO: [shopping_cart] Installing k3s on ubuntu@ubuntu via k3sup...
ERROR: [shopping_cart] SSH readiness failed for ubuntu@ubuntu after 180s (budget 180s): hostname resolution failed; not starting k3sup
```

`scripts/etc/k3s/vars.sh` source-time defaults
`UBUNTU_K3S_EXTERNAL_IP` to `UBUNTU_K3S_SSH_HOST` (`ubuntu`).
`deploy_app_cluster` only consults the current SSH config `HostName` when that
variable is empty, so the new CloudFormation IP in `Host ubuntu` is masked.
Treat this diagnosis as strongly supported by code and matching runtime output;
do not infer any EC2 boot or network fault.

## Requirements

- Resolve the ACG server destination after provisioning so the current server IP
  is used by both SSH readiness and `k3sup --ip`.
- Preserve a deliberate non-default `UBUNTU_K3S_EXTERNAL_IP` override.
- Preserve SSH host alias semantics for operations that should connect using
  `UBUNTU_K3S_SSH_HOST`; do not globally replace aliases with IPs.
- Preserve the fail-closed readiness guard and avoid full-timeout DNS waits when
  a required address cannot be resolved.
- Add regression coverage for the source-time alias default masking a configured
  IP, explicit override precedence, and same-target readiness/k3sup behavior.
- Keep unrelated providers and features unchanged.
- Do not run live `make up`, `make down`, AWS, kubectl, or Argo CD operations.

## Allowed files

- `scripts/etc/k3s/vars.sh`
- `scripts/plugins/shopping_cart.sh`
- `scripts/lib/providers/k3s-aws.sh` only if needed to scope ACG behavior
- Relevant tests under `scripts/tests/plugins/`, `scripts/tests/lib/`, or
  `scripts/tests/bin/`
- `docs/bugs/2026-10-21-k3s-aws-ssh-target-uses-alias-instead-of-ip.md`
- This dispatch spec

## Gates

- Focused BATS tests for changed behavior and related provider contract.
- ShellCheck for every touched shell file.
- `git diff --check` and `_agent_audit`.
- Do not land or mark VERIFIED without independent test review; live verification
  remains operator-owned.
