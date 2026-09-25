# `deploy_app_cluster_confirm.bats` test 3 provisions live infrastructure when a cluster is reachable

**Filed:** 2026-09-25
**Area:** `scripts/tests/core/deploy_app_cluster_confirm.bats` (test 3); `scripts/plugins/shopping_cart.sh` (`deploy_app_cluster`, SSH-key guard placement)
**Type:** bugfix
**Related:** `docs/bugs/2026-08-29-dispatcher-confirm-flag-deploy-app-cluster.md` (the Finding 2b fix this test guards)

## Problem

`make test` on `k3d-manager-v1.38.0` is 1128 ok / 1 not ok. The single failure is:

```
not ok 3 deploy_app_cluster --confirm reaches the confirmed path (Finding 2b)
# (in test file scripts/tests/core/deploy_app_cluster_confirm.bats, line 41)
#   `[ "$status" -eq 1 ]' failed
```

The test drives the real `deploy_app_cluster` with a deliberately nonexistent SSH key and
asserts the function aborts (`status` 1, output contains `SSH key not found`). It stubs only
`k3sup`. Observed status is **0**, and the captured output is live provisioning work against
the currently-running ACG `k3s-aws` sandbox:

```
INFO: [shopping_cart] k3s server already Ready — skipping server install
INFO: [shopping_cart] Merging ubuntu-k3s context into ~/.kube/config
INFO: [shopping_cart] Installing socat and vault-bridge systemd unit on ubuntu...
Warning: Identity file /nonexistent/k3d-manager-key.pem not accessible: No such file or directory.
Warning: Permanently added '44.250.167.86' (ED25519) to the list of known hosts.
INFO: [shopping_cart] vault-bridge active on ubuntu:8201
INFO: [shopping_cart] k3s install complete.
```

So the suite SSHed into the live EC2 server, installed a systemd unit, and rewrote
`~/.kube/config` — three times on 2026-09-25 (one `make test` run plus two reproductions
during diagnosis). The mutations were idempotent in this instance (the `ubuntu-k3s` context
already existed), which is luck, not design.

This is **not a v1.37.0 regression.** `git blame` dates both the reachability probe and the
guard to `1bbe54393` (2026-08-21); the test file last changed in `62c9ff27` (v1.27.0). It
passes in CI because no k3s cluster is reachable there. The trigger is purely ambient host
state.

## Root cause — two distinct defects

### 1. Test defect: outcome decided by unstubbed host state, and the test writes

`scripts/tests/core/deploy_app_cluster_confirm.bats` test 3 stubs `k3sup` only. It does not
stub `kubectl`, `ssh` or `scp`, so `deploy_app_cluster` takes its live path. CLAUDE.md
declares `scripts/tests/` **"pure logic only — no cluster mocks"**, and
`.github/copilot-instructions.md` already carries a *Test Reachability (v1.35.0+)* rule
against tests that read host state without stubbing. This one does not merely read it —
it mutates a remote host.

### 2. Production concern: the SSH-key guard is nested inside the not-ready branch

`scripts/plugins/shopping_cart.sh:1375-1400`:

```bash
  local ssh_key="${UBUNTU_K3S_SSH_KEY:-${HOME}/.ssh/k3d-manager-key.pem}"

  local _server_ready=0
  if KUBECONFIG="${local_kubeconfig}" kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready"; then
    _server_ready=1
    _info "[shopping_cart] k3s server already Ready — skipping server install"
  fi

  if (( _server_ready == 0 )); then
    _ensure_k3sup

    [[ -f "${ssh_key}" ]] || {
      _err "[shopping_cart] SSH key not found: ${ssh_key}"
      return 1
    }
```

The guard only runs on the install path, but the function SSHes **after** that block
regardless of `_server_ready` (socat + vault-bridge install). A missing or wrong
`UBUNTU_K3S_SSH_KEY` therefore reaches an unguarded `ssh` invocation. Today that still
connects, because `ssh` falls back to ssh-agent / default identities when `-i` points at a
nonexistent file — it warns (`Identity file ... not accessible`) and proceeds. So the key
variable is effectively ignored on the already-Ready path.

## Fix

### A. Test (required)

Make test 3 assert what its name claims without depending on, or touching, live
infrastructure. Stub the reachability probe so the not-ready branch is taken
deterministically — add a `kubectl` stub to `STUB_DIR` alongside the existing `k3sup` stub,
printing no `Ready` line:

```bash
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_DIR}/kubectl"
  chmod +x "${STUB_DIR}/kubectl"
```

`KUBECONFIG=/dev/null` is already set but is not sufficient — `deploy_app_cluster` builds
its own `local_kubeconfig` path. Also stub `ssh` and `scp` as hard failures so that any
future path change that reaches them fails the test loudly instead of contacting a host.

Mutation-check the new stubs against pre-fix behavior: with the `kubectl` stub in place the
test must fail if the `SSH key not found` guard is removed (see
`reference_new_test_passing_does_not_mean_it_can_fail`).

### B. Production (owner's call — not covered by A)

Move the `[[ -f "${ssh_key}" ]]` guard out of the `if (( _server_ready == 0 ))` block to
just before the first use of `ssh`, so both paths validate it. This changes behavior on the
already-Ready path: a run that currently succeeds via ssh-agent would start failing when
`UBUNTU_K3S_SSH_KEY` is bogus. That is the correct contract, but it is a functional change
and needs an explicit decision.

If B is deferred, the test fix in A still stands on its own and must not be delayed for it.

## Constraints

- Minimal patch. Keep `${var}` quoting, existing indentation, LF endings, no inline
  comments in shell blocks.
- No bare `!` and no whole-line `grep -F` in the BATS additions.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` (subtrees).
- Do NOT add cluster mocks beyond the PATH stubs the file already uses.

## Verification

- `bats scripts/tests/core/deploy_app_cluster_confirm.bats` — green **while the ACG
  `k3s-aws` cluster is reachable**, which is the condition that currently breaks it.
- Re-run with the sandbox down to confirm the result is identical either way.
- During verification, confirm the run makes no network contact with the sandbox: the
  output must contain no `Merging ubuntu-k3s context`, no `Installing socat`, and no
  `Permanently added` host-key line.

## Out of scope

Auditing the rest of `scripts/tests/` for the same class of reachability-dependent live
mutation. That sweep is worth doing — this file was found by a failure, not by a search, so
others may exist — but it belongs in its own spec.
