# Issue: deploy_cluster exceeds if-count threshold (12 > 8)

**Date:** 2026-03-07
**File:** `scripts/lib/core.sh` — `deploy_cluster`, line 627
**Detected by:** `_agent_audit` pre-commit hook (triggered when core.sh was touched)
**Threshold:** `AGENT_AUDIT_MAX_IF=8`
**Actual count:** 12

---

## If-block inventory

| # | Line | Condition |
|---|---|---|
| 1 | 664 | `if (( show_help ))` |
| 2 | 696 | `if [[ -n "$platform_msg" ]]` |
| 3 | 701 | `if [[ -n "$provider_cli" ]]` |
| 4 | 707 | `if [[ -n "$env_override" ]]` |
| 5 | 714 | `if [[ "$platform" == "mac" && "$provider" == "k3s" ]]` |
| 6 | 718 | `if [[ -z "$provider" ]]` |
| 7 | 719 | `if [[ "$platform" == "mac" ]]` |
| 8 | 723 | `if [[ -t 0 && -t 1 ]]` |
| 9 | 727 | `if (( has_tty ))` |
| 10 | 733 | `if [[ -z "$choice" ]]` |
| 11 | 754 | `if [[ "$platform" == "mac" && "$provider" == "k3s" ]]` (duplicate of #5) |
| 12 | 772 | `if declare -f _cluster_provider_set_active ...` |

---

## Root cause

`deploy_cluster` does three things in one function:
1. **Arg parsing** — flags, positional args, help
2. **Provider resolution** — CLI flag → env var → interactive prompt → platform default
3. **Provider validation + export** — mac+k3s guard, provider export, provider call

Also note: line 714 and line 754 are **duplicate guards** (`mac + k3s` check). One of them is dead code.

---

## Fix

Extract provider resolution into `_deploy_cluster_resolve_provider`:

```bash
# Returns resolved provider string; exits on error
_deploy_cluster_resolve_provider() {
  local platform="$1" provider_cli="$2" force_k3s="$3"
  local provider=""

  if [[ -n "$provider_cli" ]]; then
    provider="$provider_cli"
  elif (( force_k3s )); then
    provider="k3s"
  else
    local env_override="${CLUSTER_PROVIDER:-${K3D_MANAGER_PROVIDER:-${K3DMGR_PROVIDER:-${K3D_MANAGER_CLUSTER_PROVIDER:-}}}}"
    if [[ -n "$env_override" ]]; then
      provider="$env_override"
    fi
  fi

  provider="$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')"

  if [[ -z "$provider" ]]; then
    if [[ "$platform" == "mac" ]]; then
      provider="k3d"
    elif [[ -t 0 && -t 1 ]]; then
      provider="$(_deploy_cluster_prompt_provider)"
    else
      provider="k3d"
      _info "Non-interactive session detected; defaulting to k3d provider."
    fi
  fi

  printf '%s' "$provider"
}
```

`deploy_cluster` becomes a thin orchestrator — under 8 if-blocks.
Also remove the duplicate mac+k3s guard (keep only the post-resolution check).

---

## Scope

- Edit only `scripts/lib/core.sh` — `deploy_cluster` (line 627) and new helpers
- Must not change the external behaviour of `deploy_cluster`
- Run `shellcheck scripts/lib/core.sh` — must pass
- Run full BATS suite — must not regress
- Target: **v0.7.0**

---

## Notes

- This violation was hidden until `core.sh` was touched by an unrelated change
- The `_agent_audit` if-count check correctly flagged it — working as designed
- The duplicate mac+k3s guard (lines 714 + 754) is a separate minor bug — fix in same PR
- `CLUSTER_NAME` env var not respected during `deploy_cluster` is a related open bug
  (`docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`) — consider fixing together
