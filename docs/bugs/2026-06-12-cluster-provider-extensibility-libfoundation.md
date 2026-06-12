# lib-foundation: make `_cluster_provider` validation extensible (optional consumer hook)

**Date:** 2026-06-12
**Repo (work):** `lib-foundation` (NOT k3d-manager — the spec lives in k3d-manager, the code change is in lib-foundation)
**Branch (lib-foundation):** `feat/v0.3.21`
**File:** `scripts/lib/core.sh`

---

## Why

k3d-manager's `core.sh` is a **subtree** of this file. The cloud-provider allowlist
(`k3s-aws|k3s-gcp|k3s-oci|k3s-azure`) was added **directly to the k3d-manager subtree** across
several releases (v1.1.0+), diverging from lib-foundation, whose `_cluster_provider` validation
only knows `k3d|orbstack|k3s`. That divergence is why a subtree file kept getting edited directly
(a discipline violation surfaced when commit `976a9617` renamed `k3s-azure`→`k3s-az` *in the
subtree core.sh*).

The fix: make lib-foundation's provider validation **extensible** via an optional consumer-defined
predicate — mirroring the pattern lib-foundation already uses at the bottom of the same function
(`if declare -f _cluster_provider_set_active >/dev/null 2>&1; then _cluster_provider_set_active ...; fi`).
With this, lib-foundation stays the generic base (knows only `k3d|orbstack|k3s`), and k3d-manager
registers its cloud providers locally — so the subtree `core.sh` can return to pristine == upstream.

**Backward compatible:** with no consumer hook defined, behaviour is identical to today (only
`k3d|orbstack|k3s` accepted).

---

## Before You Start

- Repo: `lib-foundation` (single repo for THIS spec)
- Branch: `feat/v0.3.21` — `git -C <lib-foundation> checkout feat/v0.3.21 && git pull origin feat/v0.3.21`
- Read in full: `scripts/lib/core.sh` — the function `_cluster_provider()` (near the top) and the
  second provider `case` (in the deploy-cluster flow, the one preceding `export CLUSTER_PROVIDER=...`)
- The hook name to introduce: `_cluster_provider_is_extra_supported` — an **optional**,
  consumer-defined predicate. lib-foundation does NOT define it; it only *consults* it via
  `declare -f`. Returns 0 if the consumer recognises the (non-base) provider, non-zero otherwise.

---

## Change 1 — `_cluster_provider()` first `case`

**Exact old block:**
```bash
   case "$provider" in
      k3d|orbstack|k3s)
         printf '%s' "$provider"
         ;;
      *)
         _err "Unsupported cluster provider: $provider"
         ;;
   esac
```

**Exact new block:**
```bash
   case "$provider" in
      k3d|orbstack|k3s)
         printf '%s' "$provider"
         ;;
      *)
         if declare -f _cluster_provider_is_extra_supported >/dev/null 2>&1 \
            && _cluster_provider_is_extra_supported "$provider"; then
            printf '%s' "$provider"
         else
            _err "Unsupported cluster provider: $provider"
         fi
         ;;
   esac
```

---

## Change 2 — second `case` (deploy-cluster flow, preceding `export CLUSTER_PROVIDER=`)

**Exact old block:**
```bash
   case "$provider" in
      k3d|orbstack|k3s)
         ;;
      "")
         _err "Failed to determine cluster provider."
         ;;
      *)
         _err "Unsupported cluster provider: $provider"
         ;;
   esac
```

**Exact new block:**
```bash
   case "$provider" in
      k3d|orbstack|k3s)
         ;;
      "")
         _err "Failed to determine cluster provider."
         ;;
      *)
         if declare -f _cluster_provider_is_extra_supported >/dev/null 2>&1 \
            && _cluster_provider_is_extra_supported "$provider"; then
            :
         else
            _err "Unsupported cluster provider: $provider"
         fi
         ;;
   esac
```

> The `""` (empty) arm is matched before `*)`, so an unset/empty provider still errors exactly
> as before. Only a non-empty, non-base provider reaches the hook.

---

## Test (contract lock)

Find the existing BATS coverage for `_cluster_provider` (e.g. under `scripts/tests/`). If a test
file exercises `_cluster_provider`, extend it; otherwise add `scripts/tests/cluster_provider_extensibility.bats`.
Add cases asserting the contract:

1. **No hook defined** → an unknown provider (e.g. `K3D_MANAGER_PROVIDER=k3s-foo`) makes
   `_cluster_provider` call `_err` (fails / non-zero), unchanged from today.
2. **Hook defined** → with a stub:
   ```bash
   _cluster_provider_is_extra_supported() { [[ "$1" == "k3s-foo" ]]; }
   ```
   `K3D_MANAGER_PROVIDER=k3s-foo _cluster_provider` prints `k3s-foo` and succeeds.
3. **Base providers** (`k3d`, `orbstack`, `k3s`) still succeed with or without the hook.

Follow the existing BATS style in the repo (helper sourcing, `setup`, `run`, `assert`*). Do not
invent a new harness.

---

## Rules

- `shellcheck -S warning scripts/lib/core.sh` — zero new warnings (the `\`-continued `if` must
  stay shellcheck-clean; keep the `&&` on the continued line as written)
- Run the repo's existing BATS suite — must stay green
- No file other than `scripts/lib/core.sh` and the one test file touched
- Do NOT change the base allowlist `k3d|orbstack|k3s` — extensibility only
- Do NOT add any cloud-provider names here — those live in the consumer (k3d-manager)

---

## Definition of Done

- [ ] Both `case` blocks updated exactly as above
- [ ] Test added/extended locking the 3 contract cases
- [ ] `shellcheck -S warning scripts/lib/core.sh` passes
- [ ] Full BATS suite green
- [ ] Committed and pushed to `feat/v0.3.21`
- [ ] CHANGELOG `[Unreleased]` gets a `### Changed` entry: "Make `_cluster_provider` validation
      extensible via optional `_cluster_provider_is_extra_supported` consumer hook"
- [ ] memory-bank (lib-foundation) updated with commit SHA and task status

**Commit message (exact):**
```
feat(core): extensible cluster-provider validation via optional consumer hook
```

---

## What NOT to Do

- Do NOT create a PR (Claude runs `/create-pr` after verifying)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/core.sh` + the one test file
- Do NOT commit to `main` — work on `feat/v0.3.21`
- Do NOT add cloud-provider names to lib-foundation
