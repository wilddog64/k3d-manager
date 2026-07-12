# Bugfix: v1.14.0 — `_acg_provider_context` has no `k3s-oci` case, so OCI resolves to the AWS sandbox context

**Branch:** `k3d-manager-v1.14.0`
**Files:** `scripts/lib/provider.sh`, `scripts/tests/lib/provider_contract.bats`

---

## Before You Start

1. `git pull origin k3d-manager-v1.14.0` — work on this branch, never `main`.
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
3. Read both target files in full:
   - `scripts/lib/provider.sh` (`_acg_normalize_provider`, `_acg_provider_context` — lines 81–100)
   - `scripts/tests/lib/provider_contract.bats` (the `_acg_provider_context maps providers to app contexts` test — lines 34–40)
4. Confirm the starting state: `grep -c 'k3s-oci' scripts/lib/provider.sh` returns `1` (only the `_acg_normalize_provider` arm). If it returns more, this has already been fixed — **stop**.

---

## Problem

`_acg_normalize_provider` accepts `oci` / `k3s-oci` and normalizes both to `k3s-oci` (`provider.sh:86`). But `_acg_provider_context` has **no `k3s-oci` arm** (`provider.sh:93-99`), so `k3s-oci` falls through the `*)` default and returns `ubuntu-k3s` — the AWS ACG sandbox context.

```bash
$ _acg_provider_context k3s-oci
ubuntu-k3s          # wrong — should be k3s-oci
```

The OCI provider itself tells the operator the context is `k3s-oci`:

```
scripts/lib/providers/k3s-oci.sh:603:
  _info "[k3s-oci] Verify: kubectl --context k3s-oci get nodes"
```

So `k3s-oci.sh` creates/uses a context named `k3s-oci`, while every caller that routes through `_acg_provider_context` targets `ubuntu-k3s` instead. Affected callers: `bin/cluster-refresh:170`, `bin/cluster-up:1730`, `bin/cluster-status:23`, `scripts/plugins/shopping_cart.sh:347,543`, `scripts/plugins/observability.sh:301`, `scripts/plugins/argocd.sh:1164`, `scripts/etc/vault/vars.sh:31`.

**Root cause:** `k3s-oci` was added to `_acg_normalize_provider` when the OCI provider landed, but `_acg_provider_context` was never given the matching arm. The two `case` statements drifted.

**Why it was invisible.** `ubuntu-k3s` is the ACG AWS sandbox context. An ACG sandbox lives **4 hours, extendable once to 8**, so `ubuntu-k3s` is unreachable most of the time. The misrouted OCI call therefore hung against a dead endpoint rather than failing with a clear error — and when the sandbox *was* alive, it silently operated on the wrong cluster.

---

## Reproduction

```bash
source scripts/lib/provider.sh
_acg_provider_context k3s-oci
# actual:   ubuntu-k3s
# expected: k3s-oci

_acg_provider_context oci
# actual:   ubuntu-k3s
# expected: k3s-oci
```

---

## Fix

### Change 1 — `scripts/lib/provider.sh`: add the missing `k3s-oci` arm

**Exact old block (lines 92–100):**

```bash
function _acg_provider_context() {
    case "$(_acg_normalize_provider "${1:-}")" in
        k3s-aws)       printf 'ubuntu-k3s\n' ;;
        k3s-az)        printf 'ubuntu-azure\n' ;;
        k3s-gcp)       printf 'ubuntu-gcp\n' ;;
        k3s-hostinger) printf 'ubuntu-hostinger\n' ;;
        *)             printf 'ubuntu-k3s\n' ;;
    esac
}
```

**Exact new block:**

```bash
function _acg_provider_context() {
    case "$(_acg_normalize_provider "${1:-}")" in
        k3s-aws)       printf 'ubuntu-k3s\n' ;;
        k3s-az)        printf 'ubuntu-azure\n' ;;
        k3s-gcp)       printf 'ubuntu-gcp\n' ;;
        k3s-hostinger) printf 'ubuntu-hostinger\n' ;;
        k3s-oci)       printf 'k3s-oci\n' ;;
        *)             printf 'ubuntu-k3s\n' ;;
    esac
}
```

### Change 2 — `scripts/tests/lib/provider_contract.bats`: pin the OCI mapping

**Exact old block (lines 34–40):**

```bash
@test "_acg_provider_context maps providers to app contexts" {
  [[ "$(_acg_provider_context k3s-aws)" == "ubuntu-k3s" ]]
  [[ "$(_acg_provider_context k3s-az)" == "ubuntu-azure" ]]
  [[ "$(_acg_provider_context k3s-gcp)" == "ubuntu-gcp" ]]
  [[ "$(_acg_provider_context k3s-hostinger)" == "ubuntu-hostinger" ]]
  [[ "$(_acg_provider_context foo)" == "ubuntu-k3s" ]]
}
```

**Exact new block:**

```bash
@test "_acg_provider_context maps providers to app contexts" {
  [[ "$(_acg_provider_context k3s-aws)" == "ubuntu-k3s" ]]
  [[ "$(_acg_provider_context k3s-az)" == "ubuntu-azure" ]]
  [[ "$(_acg_provider_context k3s-gcp)" == "ubuntu-gcp" ]]
  [[ "$(_acg_provider_context k3s-hostinger)" == "ubuntu-hostinger" ]]
  [[ "$(_acg_provider_context k3s-oci)" == "k3s-oci" ]]
  [[ "$(_acg_provider_context oci)" == "k3s-oci" ]]
  [[ "$(_acg_provider_context foo)" == "ubuntu-k3s" ]]
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/provider.sh` | Add the `k3s-oci)` arm to `_acg_provider_context` |
| `scripts/tests/lib/provider_contract.bats` | Assert `k3s-oci` and the `oci` alias both map to context `k3s-oci` |

---

## Rules

- `shellcheck -S warning scripts/lib/provider.sh` — zero new warnings
- `bats scripts/tests/lib/provider_contract.bats` — all tests pass
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched. Do NOT change the `*)` fallback in this commit — see Deferred.

---

## Definition of Done

- [ ] `_acg_provider_context k3s-oci` prints `k3s-oci`
- [ ] `_acg_provider_context oci` prints `k3s-oci`
- [ ] `shellcheck -S warning scripts/lib/provider.sh` clean
- [ ] `bats scripts/tests/lib/provider_contract.bats` — all pass
- [ ] `./scripts/k3d-manager _agent_audit` — exit 0
- [ ] Committed and pushed to `k3d-manager-v1.14.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(provider): map k3s-oci provider to its own kube context
```

---

## Deferred — do NOT do in this change

- **The `*)` fallback.** An unknown provider (e.g. a typo) still returns `ubuntu-k3s`, silently
  targeting the AWS sandbox. `provider_contract.bats:39` pins this as a deliberate contract
  (`_acg_provider_context foo == ubuntu-k3s`), so changing it is a contract change, not a bugfix.

  Urgency is now **low**: the stale `ubuntu-k3s` kubeconfig entry was deleted on 2026-07-10, so the
  fallback fails in ~0.03s with `context was not found` instead of hanging. It is still wrong to map
  a typo onto a real cluster name. Needs a decision: fail loudly (`return 1`, empty output) versus
  keep the fallback. Callers such as `bin/cluster-status:23`
  (`APP_CONTEXT="${APP_CONTEXT:-$(_acg_provider_context "${CLUSTER_PROVIDER}")}"`) would need to
  handle an empty result, or `kubectl --context ""` will silently use the *current* context.

- **`_acg_resolve_provider`'s default of `k3s-aws`** (`provider.sh:129`). Same class of problem,
  same decision.

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.14.0`
- Do NOT change the `*)` fallback or `_acg_resolve_provider`'s default — both are Deferred above
- Do NOT rename the `k3s-oci` context to match the `ubuntu-*` naming of the other providers;
  `scripts/lib/providers/k3s-oci.sh:603` already documents `k3s-oci` to the operator
