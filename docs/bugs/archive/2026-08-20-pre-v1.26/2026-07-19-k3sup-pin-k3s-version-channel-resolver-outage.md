# Bugfix: v1.16.0 — pin k3s version in k3sup install/join (survive `update.k3s.io` channel-resolver outage)

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/plugins/shopping_cart.sh`
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this unblocks the OPEN
  blocker "istio-cni live re-verify BLOCKED on external `update.k3s.io` 404 outage".
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/plugins/shopping_cart.sh` — the `k3sup install` call in `deploy_app_cluster`
    (currently lines ~1164–1170) and the `k3sup join` call in `_k3sup_join_agent`
    (currently lines ~1015–1019). Both currently omit any version pin, so k3sup resolves the
    `stable` channel via `https://update.k3s.io/v1-release/channels/stable` at install time.
- Implement exactly what is written — no interpretation, no scope expansion. **Minimal patch only.**

---

## Problem

`make up CLUSTER_PROVIDER=k3s-aws` provisions the app cluster with `k3sup install` / `k3sup join`,
neither of which pins a k3s version. k3sup therefore resolves the `stable` channel through the k3s
channel server `https://update.k3s.io/v1-release/channels/stable` at run time. When that server is
unavailable, k3sup falls back to the **literal** string `stable` and tries to download
`https://github.com/k3s-io/k3s/releases/download/stable/sha256sum-amd64.txt`, which does not exist,
so the install fails and `make up` aborts before k3s (and therefore Cilium / istio-cni) ever comes
up.

**Live evidence (2026-07-19, fresh k3s-aws rebuild, SSH-tunnel sandbox):**
```
[INFO]  Finding release for channel stable
[INFO]  Using stable as release
[INFO]  Downloading hash https://github.com/k3s-io/k3s/releases/download/stable/sha256sum-amd64.txt
[ERROR]  Download failed
Error: error received processing command: Process exited with status 1
make: *** [up] Error 1
```
Confirmed the channel resolver itself was down, not our side:
- `curl https://update.k3s.io/v1-release/channels/stable` → **HTTP 404** (from the laptop AND the
  remote node — the node's DNS and connectivity were fine, github.com resolved and round-tripped in
  ~0.2s).
- GitHub itself healthy: latest tag `v1.36.2+k3s1`; concrete-version asset
  `.../releases/download/v1.32.0%2Bk3s1/sha256sum-amd64.txt` → **HTTP 200**.

**Root cause:** provisioning depends on the `update.k3s.io` channel resolver being up. Pinning an
exact `--k3s-version` makes k3sup skip channel resolution entirely and download the concrete release
asset directly, so a channel-server outage can no longer block provisioning.

---

## Reproduction

1. With `update.k3s.io/v1-release/channels/stable` returning non-2xx (or simulate by pointing k3sup
   at a dead channel), run `make up CLUSTER_PROVIDER=k3s-aws`.
2. k3sup logs `Using stable as release` then a 404 on `.../download/stable/sha256sum-amd64.txt`;
   `make up` exits non-zero at k3s install.

Expected after fix: k3sup logs the pinned version (e.g. `v1.32.0+k3s1`) and downloads that concrete
release, independent of the channel server.

---

## Fix

Introduce an overridable `K3S_VERSION` env var (default `v1.32.0+k3s1`, matching the hub image pin
from `1cc55252` — the istioctl precheck floor — to minimize version skew) and pass it as
`--k3s-version` on both the `k3sup install` and `k3sup join` calls. Both call sites use the same
`${K3S_VERSION:-v1.32.0+k3s1}` default so a single override changes both.

### Change 1 — `scripts/plugins/shopping_cart.sh`, `deploy_app_cluster` `k3sup install` (lines ~1164–1170)

**Exact old block:**

```bash
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${local_kubeconfig}" \
    --context "${kube_context}" \
    --k3s-extra-args "${_k3s_extra_args}"
```

**Exact new block:**

```bash
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${local_kubeconfig}" \
    --context "${kube_context}" \
    --k3s-version "${K3S_VERSION:-v1.32.0+k3s1}" \
    --k3s-extra-args "${_k3s_extra_args}"
```

### Change 2 — `scripts/plugins/shopping_cart.sh`, `_k3sup_join_agent` `k3sup join` (lines ~1015–1019)

**Exact old block:**

```bash
  _run_command -- k3sup join \
    --ip "${agent_ip}" \
    --server-ip "${server_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}"
```

**Exact new block:**

```bash
  _run_command -- k3sup join \
    --ip "${agent_ip}" \
    --server-ip "${server_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --k3s-version "${K3S_VERSION:-v1.32.0+k3s1}"
```

Do NOT touch any other line, any other function, `_ssm_bootstrap_k3s` (SSM path is out of scope),
`k3s-aws.sh`, any appset YAML, or `vars.sh`.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | Pin k3s version via `--k3s-version "${K3S_VERSION:-v1.32.0+k3s1}"` on both `k3sup install` and `k3sup join`, so provisioning no longer depends on the `update.k3s.io` channel resolver |

---

## Rules

- **Appearance gate:** `grep -c 'k3s-version "${K3S_VERSION:-v1.32.0+k3s1}"' scripts/plugins/shopping_cart.sh` → **`2`**
- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — **0 warnings** (baseline on
  `origin/k3d-manager-v1.16.0` is 0; must stay 0).
- `bats scripts/tests/plugins/shopping_cart.bats` — all tests pass (capture the `N tests, 0 failures`
  line). Do NOT add or modify tests — no existing test asserts the k3sup arg list; the change is
  additive.
- `./scripts/k3d-manager _agent_audit` — exit 0
- `git show --stat` shows exactly ONE file changed
- No other files touched

---

## Definition of Done

- [ ] Both `k3sup install` and `k3sup join` pass `--k3s-version "${K3S_VERSION:-v1.32.0+k3s1}"`
- [ ] `grep -c 'k3s-version "${K3S_VERSION:-v1.32.0+k3s1}"'` → `2` (record output)
- [ ] `shellcheck -S warning scripts/plugins/shopping_cart.sh` — 0 warnings (record baseline + after)
- [ ] `bats scripts/tests/plugins/shopping_cart.bats` — 0 failures (record the summary line)
- [ ] `_agent_audit` exit 0
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit)

**Commit message (exact):**
```
fix(k3s-aws): pin k3sup --k3s-version so provisioning survives update.k3s.io channel outage
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Fresh `make down` then `make up CLUSTER_PROVIDER=k3s-aws`. Confirm k3sup installs the pinned version
without contacting the channel resolver, then complete the ambient re-verify (Cilium pods Running →
node `/etc/cni/net.d` holds a Cilium conflist → `istio-cni-node` `1/1` ×3 → ztunnel `1/1` → ambient
dataplane capture), then re-check the two broken app services (Frontend + Product images).

---

## What NOT to Do

- Do NOT change `k3s-aws.sh`, `bca7d59a`, `ce4d83f0`, any appset YAML, or `vars.sh`.
- Do NOT modify `_ssm_bootstrap_k3s` — the SSM path is out of scope for this fix.
- Do NOT hardcode the version inline without the `${K3S_VERSION:-...}` override.
- Do NOT add or edit BATS tests.
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the one listed target.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
