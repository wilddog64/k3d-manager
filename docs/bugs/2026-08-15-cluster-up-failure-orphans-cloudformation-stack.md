# Bug: cluster-up failure leaves the CloudFormation cluster stack orphaned and billable

**Status:** Open
**Discovered:** 2026-08-15
**Branch:** `k3d-manager-v1.25.0`
**Files:** `bin/cluster-up` (`_acg_up_cleanup`), `scripts/lib/providers/k3s-aws.sh`

---

## Problem

When `make up` (k3s-aws) fails *after* the CloudFormation stack
`k3d-manager-cluster` has been created but *before* the run completes, the EXIT
trap cleans up only local processes. The 3-node EC2 stack is left running —
orphaned and billing — until a human notices and runs `make down`.

Observed 2026-08-15: a full provision failed at SSM agent registration (see
[`2026-08-14-k3s-aws-ssm-agent-cannot-register.md`](2026-08-14-k3s-aws-ssm-agent-cannot-register.md)).
The stack with 3 running EC2 instances (server + 2 agents) survived the failed
run. Only the explicit `make down` teardown reclaimed it.

**Root cause:** `_acg_up_cleanup` in `bin/cluster-up` (lines 112–124) kills local
port-forward PIDs and boots out the cloudflare-tunnel launch agent, but never
touches the remote CloudFormation stack:

```bash
function _acg_up_cleanup() {
  local _exit_code=$?
  [[ "${_exit_code}" -eq 0 ]] && return
  _warn "[acg-up] failed (exit ${_exit_code}) — cleaning up local processes..."
  for _pid_file in vault-pf frontend-pf acg-prom-pf; do
    local _f="${_ACG_STATE_DIR}/run/${_pid_file}.pid"
    if [[ -f "${_f}" ]]; then
      kill "$(cat "${_f}")" 2>/dev/null || true
      rm -f "${_f}"
    fi
  done
  launchctl bootout "gui/$(id -u)" "${HOME}/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist" 2>/dev/null || true
}
```

There is no remote-teardown branch, so any post-stack-creation failure leaks the
stack.

---

## Impact

- **Billing leak.** Three EC2 instances run until a human intervenes. On an ACG
  sandbox the 4h TTL eventually reaps them, but on a real account (or a sandbox
  that gets extended) the cost accrues silently.
- **Blocks the next run.** The leaked stack is the upstream cause of
  [`2026-05-16-k3s-aws-cloudformation-rollback-state.md`](2026-05-16-k3s-aws-cloudformation-rollback-state.md):
  a failed stack left behind lands in `CREATE_FAILED` / `ROLLBACK_COMPLETE`, and
  the next `make up` trips on it (255) unless `--recreate` deletes it first. Both
  bugs stem from the same missing failure-time teardown.

---

## Reproduction

1. `make up` (k3s-aws) on a sandbox whose SSM agents cannot register (current
   state — see the SSM spec).
2. Provision fails at the SSM registration wait (`Instance … did not become
   Online after 300s`), exit 1.
3. Observe: `aws cloudformation describe-stacks --stack-name k3d-manager-cluster`
   still returns the stack; `aws ec2 describe-instances` shows 3 running nodes.
4. The trap logged only "cleaning up local processes" — no stack deletion.

---

## Recommended fix (design — not yet implemented)

The cleanup must not blindly delete every partial stack (a transient app-stage
failure over a healthy cluster should be recoverable, not torn down). Options,
in order of preference:

1. **Opt-in teardown on hard provisioning failure.** When the failure occurs
   *before* the cluster is reachable (stack created but kube API never came up),
   the trap should offer/perform a `bin/cluster-down --confirm` for the stack it
   created. Gate it behind an env flag (e.g. `K3S_AWS_ROLLBACK_ON_FAILURE=1`) so
   interactive debugging of a partially-up cluster is still possible.
2. **At minimum: warn loudly with the exact reclaim command.** If auto-teardown
   is too aggressive, the trap must detect that a stack was created this run and
   print an actionable warning:
   `WARN: CloudFormation stack 'k3d-manager-cluster' is still running (N instances). Run 'make down' to reclaim it.`
   Silent leakage is the worst outcome; a loud warning is the floor.
3. **Track stack ownership per run.** Record in `${_ACG_STATE_DIR}/run/` whether
   *this* invocation created the stack (vs. attached to a pre-existing one), so
   cleanup only reclaims what it created.

---

## Rules

- `shellcheck -S warning bin/cluster-up` — zero new warnings
- The trap must remain safe under `set -euo pipefail` and must not itself exit
  non-zero (it runs on the EXIT path).
- Do NOT tear down a healthy, reachable cluster on a late-stage app failure —
  only reclaim on pre-cluster-readiness failure or behind the opt-in flag.

---

## Related

- [`2026-08-14-k3s-aws-ssm-agent-cannot-register.md`](2026-08-14-k3s-aws-ssm-agent-cannot-register.md)
  — the failure that surfaced this leak.
- [`2026-05-16-k3s-aws-cloudformation-rollback-state.md`](2026-05-16-k3s-aws-cloudformation-rollback-state.md)
  — the downstream symptom (next run blocked by leaked terminal-state stack).

No live mutation or deployment was performed while writing this spec.
