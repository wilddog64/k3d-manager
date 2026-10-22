# Dispatch spec: ensure the ACG server SSH target exists

## Objective

Close the missing-host-block gap in `k3s-aws-ssh-target-resolution-fix`. During
live bring-up, ACG printed a valid server IP but the SSH config contained no
`Host ubuntu` stanza. `_acg_update_ssh_config` silently left it absent, causing
`deploy_app_cluster` to fall back to the literal `ubuntu` alias. Implement an
idempotent way for ACG provisioning to provide the server target even when the
SSH config file or server stanza is absent; add regression tests and update the
canonical bug. No live infrastructure operations.

Canonical bug: `docs/bugs/2026-10-21-k3s-aws-ssh-target-uses-alias-instead-of-ip.md`.

## Latest operator evidence

```text
INFO: [acg] Updating SSH config with IP 44.247.81.210
INFO: [acg] Server:  44.247.81.210
INFO: [shopping_cart] Installing k3s on ubuntu@ubuntu via k3sup...
WARN: [shopping_cart] ssh-keyscan ubuntu not ready after 120s — k3sup may prompt
ERROR: [shopping_cart] SSH readiness failed for ubuntu@ubuntu after 0s (budget 180s): hostname resolution failed; not starting k3sup
```

Read-only evidence: no `UBUNTU_K3S_EXTERNAL_IP` override in the tmux session;
`~/.ssh/config` had `Host ubuntu-1` and `Host ubuntu-2`, but no `Host ubuntu`.
The ACG updater only rewrites an existing exact `Host ubuntu` stanza and does
not create it. The new SSH target resolver therefore fell back to `ubuntu`.
Do not attribute this to EC2 boot, network, or sshd without independent evidence.

## Requirements

- Ensure the freshly provisioned server IP reaches `deploy_app_cluster` as its
  target even if `~/.ssh/config` is missing or has no exact `Host ubuntu` stanza.
- Preserve existing SSH config content and update an existing server stanza
  idempotently; do not duplicate host blocks on repeated provisioning.
- Preserve agent aliases (`ubuntu-1`, `ubuntu-2`, etc.), `ubuntu-tunnel`, and
  explicit `UBUNTU_K3S_EXTERNAL_IP` operator overrides.
- Use one resolved destination consistently for SSH readiness and `k3sup --ip`.
- Keep the fail-closed rule: do not start k3sup until SSH succeeds.
- Add offline regression tests for missing config file, config without server
  stanza, existing server stanza update, repeat invocation, and target propagation.
- Do not change unrelated providers or perform `make up`, `make down`, AWS,
  kubectl, or Argo CD operations.

## Files

- `scripts/lib/foundation/scripts/lib/acg/acg.sh`
- `scripts/tests/lib/acg.bats`
- `scripts/etc/k3s/vars.sh`
- `scripts/plugins/shopping_cart.sh`
- `scripts/tests/plugins/shopping_cart.bats`
- `docs/bugs/2026-10-21-k3s-aws-ssh-target-uses-alias-instead-of-ip.md`
- `docs/issues/2026-10-21-k3s-aws-ssh-target-host-block-fix-spec.md`

## Gates

- Focused ACG and shopping-cart BATS suites pass.
- ShellCheck for every touched shell file, `git diff --check`, `_agent_lint`,
  and `_agent_audit` pass.
- Document any unrelated pre-existing test failure with exact output; do not
  expand implementation scope to repair it.
- Leave live verification to the operator after offline verification and landing.
