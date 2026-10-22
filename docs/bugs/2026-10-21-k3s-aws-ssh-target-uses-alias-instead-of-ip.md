# Bug: k3s-aws SSH readiness probes the alias instead of the provisioned IP

**Filed:** 2026-10-21 (operator live `make up` output)
**Status:** VERIFIED (offline) — lib-foundation PR #72 merged at `c307df2` and pulled into the v1.43.5 subtree; operator live verification pending
**Priority:** P2 — blocks ACG cluster provisioning, with a manual configuration workaround
**Severity:** high
**Release:** v1.43.5 (bug; exempt from plan cap)
**Branch:** `k3d-manager-v1.43.5`
**Component:** `scripts/etc/k3s/vars.sh`, `scripts/plugins/shopping_cart.sh`, `scripts/lib/foundation/scripts/lib/acg/acg.sh`
**Related:** `docs/bugs/2026-10-21-k3s-aws-ssh-readiness-timeout-hides-failure-cause.md`

## Reproduction and evidence

During a fresh ACG `make up CLUSTER_PROVIDER=k3s-aws`, CloudFormation succeeded and
the provisioning code printed the server's public IP and updated the local SSH
configuration for `Host ubuntu`. The subsequent k3s install nevertheless invoked
SSH readiness against the literal alias `ubuntu`:

```text
INFO: [acg] Updating SSH config with IP 44.247.81.210
INFO: [acg] Server:  44.247.81.210
INFO: [k3s-aws] Installing k3s server + joining agents...
INFO: [shopping_cart] Installing k3s on ubuntu@ubuntu via k3sup...
WARN: [shopping_cart] ssh-keyscan ubuntu not ready after 120s — k3sup may prompt
ERROR: [shopping_cart] SSH readiness failed for ubuntu@ubuntu after 180s (budget 180s): hostname resolution failed; not starting k3sup
```

The classification is direct SSH stderr evidence. It does not establish an EC2
boot, network, or sshd failure. The CloudFormation stack remains running and
billable after this failed bring-up; do not destroy or recreate it as part of the
code task.

## Follow-up live reproduction (2026-10-21)

After `60b43b22` was deployed locally, the operator reran `make
up CLUSTER_PROVIDER=k3s-aws`. CloudFormation reused the healthy stack and reported
server IP `44.247.81.210`, but the install still targeted the literal `ubuntu`:

```text
INFO: [acg] Updating SSH config with IP 44.247.81.210
INFO: [acg] Server:  44.247.81.210
INFO: [k3s-aws] Installing k3s server + joining agents...
INFO: [shopping_cart] Installing k3s on ubuntu@ubuntu via k3sup...
WARN: [shopping_cart] ssh-keyscan ubuntu not ready after 120s — k3sup may prompt
ERROR: [shopping_cart] SSH readiness failed for ubuntu@ubuntu after 0s (budget 180s): hostname resolution failed; not starting k3sup
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

Read-only inspection found no `UBUNTU_K3S_EXTERNAL_IP` override in the tmux
session. The local `~/.ssh/config` contains `Host ubuntu-1` and `Host ubuntu-2`,
but no `Host ubuntu` stanza. `_acg_update_ssh_config` logs the update and then
only substitutes a matching pre-existing stanza; it does not add a missing
server alias. With the source-time default removed by `60b43b22`,
`deploy_app_cluster` now consults this absent stanza and falls back to `ubuntu`.
Thus the previous offline regression fixture covered a pre-existing server stanza
but missed the actual configuration shape. The failure is target/config
provisioning, not evidence of an EC2 boot or SSH daemon issue. k3sup was not run.

The CloudFormation stack was reused and remains present after this failed `make
up`; no teardown was performed. It may be billable.

## Root cause

`scripts/etc/k3s/vars.sh` eagerly exports:

```bash
export UBUNTU_K3S_EXTERNAL_IP="${UBUNTU_K3S_EXTERNAL_IP:-${UBUNTU_K3S_SSH_HOST}}"
```

with `UBUNTU_K3S_SSH_HOST` defaulting to `ubuntu`. This makes
`UBUNTU_K3S_EXTERNAL_IP=ubuntu` a nonempty value at source time. In
`deploy_app_cluster`, the SSH config lookup is conditional on the external-IP
variable being empty, so the freshly provisioned `Host ubuntu` `HostName` value
is never read. The diagnostics fix correctly exposed the resulting DNS failure;
the failure is in target selection, not proven instance readiness.

## Expected behavior

For the k3s-aws provisioning path, resolve the SSH destination to the provisioned
server address or the current `Host ubuntu` `HostName`, and use that same
destination consistently for the readiness probe and `k3sup --ip`. Preserve
intentional explicit `UBUNTU_K3S_EXTERNAL_IP` overrides and non-AWS provider
behavior. If the configured target cannot be resolved, fail early with a clear,
safe diagnostic rather than waiting the full SSH timeout against an alias as an IP.

## Acceptance

- Regression test proves a source-time default alias does not mask the current
  `Host ubuntu` IP after ACG provisioning.
- Readiness probe and `k3sup --ip` use the same resolved destination.
- An explicit operator-provided `UBUNTU_K3S_EXTERNAL_IP` remains authoritative.
- Existing SSH readiness fail-closed behavior remains: no k3sup invocation until
  SSH succeeds.
- Existing non-AWS provider contracts and SSH host-alias operations remain intact.
- No AWS, SSH, or live cluster mutation is performed by offline tests.

## Verification / live status

The first target-selection change, `60b43b22`, passed its offline tests but did
not cover the missing-`Host ubuntu` case and failed live as recorded above. This
bug is OPEN again pending the follow-up. Live verification requires a later
operator-approved ACG bring-up; no live verification is claimed.

Offline implementation evidence (2026-10-21): `bats
scripts/tests/plugins/shopping_cart.bats` passed 41/41, including regression
coverage that sources `vars.sh` before writing the fresh `Host ubuntu` HostName,
checks that readiness and `k3sup --ip` receive the same resolved address, and
checks that an explicit `UBUNTU_K3S_EXTERNAL_IP` remains authoritative. A DNS
resolution failure now stops readiness immediately while retaining the
fail-closed guard. These tests covered an existing `Host ubuntu` stanza and an
explicit IP override, but not a missing stanza; see the follow-up spec.
`shellcheck -S warning` for touched shell files,
`git diff --check`, and `_agent_audit` passed. The related provider contract
suite had two teardown/deregistration failures (28/30) on both the task branch
and unchanged release branch before this fix, confirming they are pre-existing
baseline failures; details are in
`docs/issues/2026-10-21-k3s-aws-ssh-target-provider-contract-failures.md`.
No live infrastructure operation was run. This evidence does not establish
live verification.

The follow-up could not be committed directly under `scripts/lib/foundation/`;
the protected-subtree hook requires upstream-first changes. Lib-foundation PR
[#72](https://github.com/wilddog64/lib-foundation/pull/72) merged to `main` at
`c307df2`. Its update was pulled into this release branch with `git subtree pull
--prefix=scripts/lib/foundation https://github.com/wilddog64/lib-foundation.git
main --squash`; subtree squash commit `18f7c8cc` covers upstream
`c8e18225..c307df28`, and the subtree merge commit is `205d4272`.

Post-pull verification passed: clean-environment
`bats scripts/lib/foundation/scripts/tests/lib/acg.bats` (28/28),
`shellcheck scripts/lib/foundation/scripts/lib/acg/acg.sh`, and
`AGENT_AUDIT_MAX_IF=8 bash scripts/lib/foundation/scripts/lib/agent_rigor.sh
scripts/lib/foundation/scripts/lib/acg/acg.sh`. The source now creates the
missing `Host ubuntu` stanza idempotently while preserving agent/tunnel aliases.
No AWS, SSH, or live cluster operation was run. The bug is VERIFIED offline;
operator live verification remains pending.

## Scope for dispatch

Inspect sourcing and override contracts, fix the stale/defaulted target precedence,
and add focused offline regression coverage. Do not edit unrelated provider code,
do not run `make up`/`make down`, and do not modify or delete the currently running
CloudFormation stack. Commit and push on `k3d-manager-v1.43.5` through the normal
dispatcher workflow; after offline verification, leave live verification to the
operator.
