# Bugfix: `make refresh` / `make status` are not provider-aware — hardcoded to AWS

**Date:** 2026-06-12
**Branch:** `k3d-manager-v1.6.5`
**Files:** `scripts/lib/provider.sh`, `bin/acg-up`, `bin/acg-down`, `bin/acg-refresh`, `bin/acg-status`, `Makefile`

---

## Problem

After provisioning an **Azure** cluster, `make refresh` and `make status` still drive the **AWS**
path, and passing `CLUSTER_PROVIDER=az` does not help:

```
$ make refresh CLUSTER_PROVIDER=az
INFO: [acg-refresh] Checking AWS credentials...
[tunnel] started — 0.0.0.0:6443 -> ubuntu:6443
INFO: [acg-refresh] Refreshing ArgoCD cluster secret (ubuntu-k3s SA token)...
Unable to connect to the server: dial tcp 54.184.31.89:6443: i/o timeout   # AWS host
```

Three independent defects:

1. **`bin/acg-refresh` ignores `CLUSTER_PROVIDER` entirely** and is hardcoded to AWS + the
   `ubuntu-k3s` context at every step: credential check (`Checking AWS credentials`, line 163),
   ArgoCD secret (`ubuntu-k3s` lines 225/228/238/242/253), Prometheus port-forward
   (`--context ubuntu-k3s`, line 269), Grafana kubeconfig (line 327/344), final nodes check
   (line 419). No `grep CLUSTER_PROVIDER bin/acg-refresh` match exists.
2. **`make refresh` does not even forward the variable** — the target is just
   `bin/acg-refresh "$(URL)"`.
3. **`make status` has no `k3s-az` case** (Makefile `status:` `case`) — `az`/`k3s-az` fall through
   to `*) APP_CONTEXT=ubuntu-k3s`, i.e. AWS.

Root cause: **the active provider is never recorded at provision time**, and the daily-driver
scripts assume AWS. `bin/acg-up` already branches per-provider for credentials
(`k3s-aws`→AWS STS, `k3s-az`→`_az_ok`/azure cred-test, `k3s-gcp`→`gcp_get_credentials`) but throws
that knowledge away after it finishes.

---

## Design (user decision, 2026-06-12)

**Auto-detect the provider — operators should not need to type `CLUSTER_PROVIDER=`.**

Resolution precedence (`_acg_resolve_provider`):
1. **Explicit `CLUSTER_PROVIDER` env** (when set on the command line / environment) — wins.
2. **State file** `${_ACG_STATE_DIR}/active-provider` — written by `acg-up`, removed by `acg-down`.
3. **Kube-context probe fallback** — first reachable of `ubuntu-k3s` / `ubuntu-azure` / `ubuntu-gcp`.
4. **Default** `k3s-aws` (with a warning).

Short forms are normalized (`aws|az|azure|gcp|oci` → `k3s-*`). Provider→app-context map:
`k3s-aws`→`ubuntu-k3s`, `k3s-az`→`ubuntu-azure`, `k3s-gcp`→`ubuntu-gcp`.

All logic lives in **one shared helper** (`scripts/lib/provider.sh`, already sourced by `acg-up`)
so `acg-up`, `acg-refresh`, and `acg-status` agree.

---

## Fix

### Change 1 — `scripts/lib/provider.sh`: add shared resolver + context map

Append these functions (after the existing provider helpers). They are pure logic — BATS-testable.

```bash
_ACG_ACTIVE_PROVIDER_FILE="${_ACG_ACTIVE_PROVIDER_FILE:-${HOME}/.local/share/k3d-manager/active-provider}"

function _acg_normalize_provider() {
  case "${1:-}" in
    aws|k3s-aws)       printf 'k3s-aws\n' ;;
    az|azure|k3s-az)   printf 'k3s-az\n' ;;
    gcp|k3s-gcp)       printf 'k3s-gcp\n' ;;
    oci|k3s-oci)       printf 'k3s-oci\n' ;;
    *)                 printf '%s\n' "${1:-}" ;;
  esac
}

function _acg_provider_context() {
  case "$(_acg_normalize_provider "${1:-}")" in
    k3s-aws) printf 'ubuntu-k3s\n' ;;
    k3s-az)  printf 'ubuntu-azure\n' ;;
    k3s-gcp) printf 'ubuntu-gcp\n' ;;
    *)       printf 'ubuntu-k3s\n' ;;
  esac
}

function _acg_record_provider() {
  local provider; provider="$(_acg_normalize_provider "${1:-}")"
  [[ -z "${provider}" ]] && return 0
  mkdir -p "$(dirname "${_ACG_ACTIVE_PROVIDER_FILE}")"
  printf '%s\n' "${provider}" > "${_ACG_ACTIVE_PROVIDER_FILE}"
}

function _acg_resolve_provider() {
  # precedence: explicit env > state file > reachable-context probe > default
  local p="${CLUSTER_PROVIDER:-}"
  if [[ -z "${p}" && -f "${_ACG_ACTIVE_PROVIDER_FILE}" ]]; then
    p="$(cat "${_ACG_ACTIVE_PROVIDER_FILE}" 2>/dev/null || true)"
  fi
  if [[ -z "${p}" ]]; then
    local ctx
    for ctx in ubuntu-k3s ubuntu-azure ubuntu-gcp; do
      if kubectl --context "${ctx}" --request-timeout=5s get --raw=/readyz >/dev/null 2>&1; then
        case "${ctx}" in
          ubuntu-k3s)   p=k3s-aws ;;
          ubuntu-azure) p=k3s-az ;;
          ubuntu-gcp)   p=k3s-gcp ;;
        esac
        break
      fi
    done
  fi
  _acg_normalize_provider "${p:-k3s-aws}"
}
```

### Change 2 — `bin/acg-up`: record the active provider on success

`acg-up` already resolves `_cluster_provider` (line 59) and sources `scripts/lib/provider.sh`
(line 43). After a successful provision (end of the script, once the cluster is up), record it:

```bash
_acg_record_provider "${_cluster_provider}"
```

Place it at the point where provisioning is known to have succeeded (after the final
checkpoint / before the closing success log). Do NOT record on early `exit 1` paths.

### Change 3 — `bin/acg-down`: clear the active-provider state

After teardown, remove the file so a stale provider can't mislead a later `refresh`:

```bash
rm -f "${HOME}/.local/share/k3d-manager/active-provider"
```

(Use the literal path; `acg-down` may not source `provider.sh`. If it does, use
`"${_ACG_ACTIVE_PROVIDER_FILE}"`.)

### Change 4 — `bin/acg-refresh`: resolve provider + context, parametrize all AWS/`ubuntu-k3s` sites

1. Source the resolver: add `source "${REPO_ROOT}/scripts/lib/provider.sh"` with the other
   `source` lines (~20-25) if not already sourced.
2. Near the top of the run (before "── 1. credentials"), resolve once:
   ```bash
   _cluster_provider="$(_acg_resolve_provider)"
   _app_context="$(_acg_provider_context "${_cluster_provider}")"
   _info "[acg-refresh] Active provider: ${_cluster_provider} (context ${_app_context})"
   ```
3. Replace the **AWS-only credential block** (lines ~162-168) with a per-provider branch that
   mirrors `acg-up` Step 1:
   - `k3s-aws` → `_acg_check_credentials` / `acg_get_credentials` (current behavior)
   - `k3s-az`  → `_az_ok` check, else `scripts/lib/acg/bin/acg-credential-test "<url>" --provider azure`
   - `k3s-gcp` → `gcp_get_credentials`
   Source the matching provider plugin as needed (`aws.sh` is already sourced; add `azure`/`gcp`
   plugin sourcing guarded by provider).
4. Replace every hardcoded `ubuntu-k3s` with `${_app_context}` at lines **228, 242, 253, 269, 419**
   and the ArgoCD secret name `cluster-ubuntu-k3s` (line 238) → `cluster-${_app_context}`, plus the
   log strings at 225/253. (Enumerate with `grep -n ubuntu-k3s bin/acg-refresh` — every hit becomes
   `${_app_context}`.)
5. **Tunnel host:** the tunnel targets ssh alias `ubuntu` (`-> ubuntu:6443`). Ensure that alias
   resolves to the **active provider's** host. `acg-up` maintains the per-provider SSH host config;
   `acg-refresh` must not assume AWS. If `tunnel_start` reads a host var, pass the provider's host;
   otherwise confirm `acg-up` rewrites the `ubuntu` alias on every provision and document that
   `refresh` relies on it. (If this needs its own state, record the host alongside the provider in
   Change 2 and have the tunnel use it.)

### Change 5 — `bin/acg-status`: self-resolve when not told

`acg-status` currently defaults `APP_CONTEXT=ubuntu-k3s`. Make it resolve via the shared helper
when `APP_CONTEXT`/`CLUSTER_PROVIDER` are not explicitly set:

```bash
source "${REPO_ROOT}/scripts/lib/provider.sh"
CLUSTER_PROVIDER="$(_acg_resolve_provider)"
APP_CONTEXT="${APP_CONTEXT:-$(_acg_provider_context "${CLUSTER_PROVIDER}")}"
```

(Keep honoring an explicitly-passed `APP_CONTEXT`.)

### Change 6 — `Makefile`: forward provider only when explicit; delegate status resolution

- **`refresh:`** — forward `CLUSTER_PROVIDER` to `acg-refresh` **only when the user set it**, so the
  default `?= k3s-aws` does not clobber auto-detection. Use `$(origin …)`:
  ```make
  refresh:
  	$(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/acg-refresh "$(URL)"
  ```
- **`status:`** — let `acg-status` self-resolve; forward `CLUSTER_PROVIDER` only when explicit, and
  keep the `k3s-oci` special case. Add a `k3s-az`→`ubuntu-azure` arm (or, preferred, drop the
  `case` for the non-oci providers entirely and call `bin/acg-status` directly now that it
  resolves itself).

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/provider.sh` | add `_acg_normalize_provider`, `_acg_provider_context`, `_acg_record_provider`, `_acg_resolve_provider` + `_ACG_ACTIVE_PROVIDER_FILE` |
| `bin/acg-up` | `_acg_record_provider "${_cluster_provider}"` on success |
| `bin/acg-down` | remove `active-provider` state file |
| `bin/acg-refresh` | resolve provider+context; per-provider creds; `ubuntu-k3s` → `${_app_context}`; tunnel host honors provider |
| `bin/acg-status` | self-resolve provider/context via shared helper |
| `Makefile` | `refresh:` forwards `CLUSTER_PROVIDER` only when explicit; `status:` delegates resolution |

---

## Rules

- `shellcheck -S warning scripts/lib/provider.sh bin/acg-up bin/acg-down bin/acg-refresh bin/acg-status` — zero new warnings
- `./scripts/k3d-manager _agent_audit` — passes
- If `scripts/tests/lib/` has a provider BATS suite, add cases for `_acg_normalize_provider`
  (`az`→`k3s-az`, `aws`→`k3s-aws`, `gcp`→`k3s-gcp`, passthrough) and `_acg_provider_context`
  (`k3s-az`→`ubuntu-azure`)
- No behavior change when `CLUSTER_PROVIDER` is explicitly set to `k3s-aws` (regression guard)

---

## Definition of Done

- [ ] Shared resolver added to `scripts/lib/provider.sh` (4 functions + file var)
- [ ] `acg-up` records provider on success; `acg-down` clears it
- [ ] `acg-refresh` resolves provider, uses per-provider creds, and every `ubuntu-k3s` literal is `${_app_context}`
- [ ] `acg-status` self-resolves; `make status` (no args) reports the **Azure** cluster after an Azure `acg-up`
- [ ] `make refresh` (no args) after an Azure `acg-up` checks **Azure** creds and tunnels to the **Azure** host (no `Checking AWS credentials` / `54.x` AWS IP)
- [ ] `make refresh CLUSTER_PROVIDER=k3s-aws` still drives AWS (explicit override honored)
- [ ] shellcheck + `_agent_audit` pass; BATS pass if added
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg): provider-aware refresh/status via recorded active-provider state
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the six listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` (subtrees)
- Do NOT change the precedence order (explicit env must win over the state file)
