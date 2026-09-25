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

**Scope: `scripts/tests/core/deploy_app_cluster_confirm.bats` only.** No production file changes.

The real leak is the kubeconfig path, not `KUBECONFIG`. `deploy_app_cluster` builds its own:

```bash
  local local_kubeconfig="${UBUNTU_K3S_LOCAL_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"
```

and probes with `KUBECONFIG="${local_kubeconfig}" kubectl get nodes`. The test's
`KUBECONFIG=/dev/null` is therefore ignored, and the probe reads the operator's real
`~/.kube/k3s-ubuntu.yaml`. Three changes, in this order:

**A1 — add the hard-fail network stubs first.** These are the safety belt: with them in place no
subsequent step can contact a host even if A2 is wrong. Add to `setup()` after the `k3sup` stub:

```bash
  printf '#!/usr/bin/env bash\necho "stub: ssh must not be called" >&2\nexit 97\n' > "${STUB_DIR}/ssh"
  printf '#!/usr/bin/env bash\necho "stub: scp must not be called" >&2\nexit 97\n' > "${STUB_DIR}/scp"
  chmod +x "${STUB_DIR}/ssh" "${STUB_DIR}/scp"
```

**A2 — make the reachability probe deterministic.** Add a `kubectl` stub that emits no `Ready`
line, and point the kubeconfig at a path under `STUB_DIR` so nothing reads the operator's file:

```bash
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_DIR}/kubectl"
  chmod +x "${STUB_DIR}/kubectl"
```

and add to the `run env` list in test 3:

```bash
    UBUNTU_K3S_LOCAL_KUBECONFIG="${STUB_DIR}/absent-kubeconfig.yaml" \
```

Both are needed: the env var alone still invokes the operator's real `kubectl`, and the stub alone
still reads the real kubeconfig path if a future change drops the probe's `KUBECONFIG` override.

**A3 — assert no contact was made.** Add to test 3, after the existing assertions:

```bash
  [[ "$output" != *"Merging ubuntu-k3s context"* ]]
  [[ "$output" != *"Installing socat"* ]]
  [[ "$output" != *"stub: ssh must not be called"* ]]
```

Keep the three existing assertions on lines 41-43 unchanged — they are the Finding 2b contract.

**Mutation check (required).** With A1-A3 applied, temporarily delete the
`[[ -f "${ssh_key}" ]]` guard block from `scripts/plugins/shopping_cart.sh` and confirm test 3
**fails**. Then restore it with `git checkout -- scripts/plugins/shopping_cart.sh` and confirm
`git diff --quiet scripts/plugins/shopping_cart.sh`. A test that passes both with and without the
guard is not testing the guard (see the `new_test_passing_does_not_mean_it_can_fail` rule).

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

---

## Before You Start

- Repo: `/Users/cliang/src/gitrepo/personal/k3d-manager`
- Branch: `k3d-manager-v1.38.0` — `git pull origin k3d-manager-v1.38.0` first. Never `main`.
- Read `memory-bank/activeContext.md` (top section, dated 2026-09-25) for the failure context.
- Read these files in full before editing:
  - `scripts/tests/core/deploy_app_cluster_confirm.bats` (44 lines)
  - `scripts/plugins/shopping_cart.sh` lines 1330-1420 (read only — Part B is NOT approved)
  - `scripts/tests/test_helpers.bash`
- **A live ACG `k3s-aws` cluster is currently reachable at `44.250.167.86`.** That is what makes
  this test destructive. Apply step A1 (the `ssh`/`scp` hard-fail stubs) **before running the
  suite even once.** Do not run `bats` on this file before A1 is in place.

## Definition of Done

- [ ] A1, A2, A3 applied to `scripts/tests/core/deploy_app_cluster_confirm.bats`.
- [ ] `bats scripts/tests/core/deploy_app_cluster_confirm.bats` — 3/3 pass. Paste the output.
- [ ] Mutation check performed and reported: test 3 fails with the guard removed, and
      `git diff --quiet scripts/plugins/shopping_cart.sh` is clean afterwards. Paste both results.
- [ ] Output of the passing run contains none of `Merging ubuntu-k3s context`, `Installing socat`,
      `Permanently added`, `vault-bridge active`. Paste the grep result proving it.
- [ ] `shellcheck` clean on the changed file with zero new warnings.
- [ ] Exactly one file changed. `git show --stat` must list only the `.bats` file.
- [ ] Commit message, verbatim:

```
fix(tests): stop deploy_app_cluster_confirm test 3 provisioning live infra

Test 3 stubbed only k3sup, so with a k3s cluster reachable deploy_app_cluster
took its live path: it merged the ubuntu-k3s context into ~/.kube/config and
installed socat plus a vault-bridge systemd unit on the EC2 server, returning 0
instead of the asserted 1. Stub the reachability probe (kubectl plus a
STUB_DIR-scoped UBUNTU_K3S_LOCAL_KUBECONFIG), hard-fail ssh/scp so no future
path change can contact a host, and assert the absence of the provisioning
output. Test-only; the SSH-key guard placement in shopping_cart.sh is unchanged.

See docs/bugs/2026-09-25-deploy-app-cluster-confirm-bats-mutates-live-cluster.md
```

- [ ] `git push origin k3d-manager-v1.38.0` — do NOT report done until the push succeeds.
- [ ] Verify with `git rev-parse origin/k3d-manager-v1.38.0` and report that SHA.
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with the SHA and status,
      and paste the lines you changed.

## What NOT to Do

- Do NOT touch `scripts/plugins/shopping_cart.sh`. **Part B is unapproved** — moving the SSH-key
  guard changes behavior on the already-Ready path and is the owner's decision. Read it, do not
  edit it. The only permitted interaction is the temporary mutation check, which must be reverted.
- Do NOT run `bats` on this file before the `ssh`/`scp` stubs exist.
- Do NOT run `scripts/k3d-manager deploy_app_cluster` by hand, with or without `--confirm`.
- Do NOT run `make up`, `make deploy-worker`, `kubectl`, `ssh`, `helm` or `docker` against any
  live cluster or host. No live-cluster mutation of any kind.
- Do NOT modify `~/.kube/config` or any file outside the repo.
- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` (subtrees).
- Do NOT `git add -A`. Stage the one file by path.
- Do NOT touch any other file in `scripts/tests/` — the broader sweep is a separate spec.
