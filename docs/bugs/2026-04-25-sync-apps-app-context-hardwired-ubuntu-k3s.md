# Bug: make sync-apps uses APP_CONTEXT=ubuntu-k3s regardless of CLUSTER_PROVIDER

**Branch:** `k3d-manager-v1.2.0`
**File:** `Makefile` (sync-apps target)

## Root Cause

`bin/acg-sync-apps` defaults `APP_CONTEXT` to `ubuntu-k3s` (the AWS cluster context).
The `sync-apps` Makefile target passes no override, so `make sync-apps CLUSTER_PROVIDER=k3s-gcp`
still checks pod status against the AWS cluster, which is unreachable:

```
INFO: [sync-apps] Pod status (ubuntu-k3s):
Unable to connect to the server: dial tcp 35.90.75.113:6443: i/o timeout
```

The ArgoCD steps (port-forward, login, sync) all succeed — only the final
`kubectl get pods --context ubuntu-k3s` fails.

## Fix

Update the `sync-apps` Makefile target to pass `APP_CONTEXT=ubuntu-gcp` when
`CLUSTER_PROVIDER=k3s-gcp`, keeping `ubuntu-k3s` as the default for all other providers.

**Old:**
```makefile
## Sync ArgoCD data-layer and show remote pod status
sync-apps:
	bin/acg-sync-apps
```

**New:**
```makefile
## Sync ArgoCD data-layer and show remote pod status
sync-apps:
	APP_CONTEXT=$(if $(filter k3s-gcp,$(CLUSTER_PROVIDER)),ubuntu-gcp,ubuntu-k3s) bin/acg-sync-apps
```

---

# Follow-up — fully provider-generic resolution (Codex spec, 2026-06-21)

**Branch (all work in k3d-manager):** `fix/sync-apps-provider-generic`
**Status:** Codex-ready.

## Why this follow-up

The GCP-only ternary above was a point fix. It hardcodes a two-way `gcp ? ubuntu-gcp : ubuntu-k3s`
choice and ignores `k3s-az`, `k3s-hostinger`, and `k3s-oci`. The permanent app cluster is now
`ubuntu-hostinger`, so `make sync-apps CLUSTER_PROVIDER=k3s-hostinger` still dumps pod status against
the retired `ubuntu-k3s` context — the same failure mode as the original bug. (Note: the script was
renamed `bin/acg-sync-apps` → `bin/cluster-sync-apps`.)

The repo **already has the resolver** to fix this generically:
`scripts/lib/provider.sh` provides `_acg_resolve_provider` (env → active-provider state file →
live kube-context probe) and `_acg_provider_context` (provider → app kubecontext). `bin/cluster-status`
already consumes both. The fix is to make `bin/cluster-sync-apps` use the same machinery — **no new
provider→context map**. `k3s-oci` is special: it runs its own in-cluster ArgoCD (separate kubeconfig,
no hub context), so it is explicitly out of scope for this hub-driven sync tool.

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git checkout -b fix/sync-apps-provider-generic origin/main` (work only in k3d-manager).
- Read the targets in full before editing: `bin/cluster-sync-apps`, `Makefile` (sync-apps + status
  targets), `scripts/lib/provider.sh` (reuse only — see What NOT to Do), `bin/cluster-status` (the
  pattern to mirror), `scripts/tests/bin/cluster_sync_apps.bats`,
  `scripts/tests/lib/provider_contract.bats`.
- The untracked `docs/issues/2026-06-19-empty-rabbitmq-client-pr-base-ref.md` must stay out of every
  commit — stage only the explicit target files.

## Reuse — do NOT reinvent

`scripts/lib/provider.sh` (already on main):

```bash
_acg_resolve_provider     # CLUSTER_PROVIDER env → ~/.local/share/k3d-manager/active-provider → live probe; defaults k3s-aws
_acg_provider_context     # k3s-aws→ubuntu-k3s · k3s-az→ubuntu-azure · k3s-gcp→ubuntu-gcp · k3s-hostinger→ubuntu-hostinger · *→ubuntu-k3s
```

`bin/cluster-status` already wires them — mirror it exactly:

```bash
source "${REPO_ROOT}/scripts/lib/provider.sh"
CLUSTER_PROVIDER="$(_acg_resolve_provider)"
APP_CONTEXT="${APP_CONTEXT:-$(_acg_provider_context "${CLUSTER_PROVIDER}")}"
```

## Change 1 — `bin/cluster-sync-apps`: resolve provider + context, OCI guard, `--resolve-only`

**Old** (header env comment + the source/var block near the top):

```bash
# Environment:
#   INFRA_CONTEXT  kubectl context for infra cluster (default: k3d-k3d-cluster)
#   APP_CONTEXT    kubectl context for app cluster   (default: ubuntu-k3s)
#   ARGOCD_NS      ArgoCD namespace                  (default: cicd)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/system.sh"
_ACG_STATE_DIR="${HOME}/.local/share/k3d-manager"
mkdir -p "${_ACG_STATE_DIR}/run" "${_ACG_STATE_DIR}/logs"

INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-k3d-cluster}"
APP_CONTEXT="${APP_CONTEXT:-ubuntu-k3s}"
ARGOCD_NS="${ARGOCD_NS:-cicd}"
ARGOCD_APP="${ARGOCD_APP:-rollout-demo-default}"
```

**New:**

```bash
# Environment:
#   CLUSTER_PROVIDER  cluster provider; selects the app context when APP_CONTEXT is unset.
#                     Auto-resolved (active-provider state file / live probe) when empty.
#   INFRA_CONTEXT     kubectl context for infra/hub cluster (default: k3d-k3d-cluster)
#   APP_CONTEXT       kubectl context for app cluster (default: resolved from CLUSTER_PROVIDER)
#   ARGOCD_NS         ArgoCD namespace                (default: cicd)
#   ARGOCD_APP        ArgoCD app(s) to sync; space-separated list (default: rollout-demo-default)
#
# Pass --resolve-only (or SYNC_APPS_RESOLVE_ONLY=1) to print the resolved
# CLUSTER_PROVIDER / INFRA_CONTEXT / APP_CONTEXT / ARGOCD_APP and exit (no side effects).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/system.sh"
source "${REPO_ROOT}/scripts/lib/provider.sh"
_ACG_STATE_DIR="${HOME}/.local/share/k3d-manager"
mkdir -p "${_ACG_STATE_DIR}/run" "${_ACG_STATE_DIR}/logs"

CLUSTER_PROVIDER="$(_acg_resolve_provider)"
INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-k3d-cluster}"
APP_CONTEXT="${APP_CONTEXT:-$(_acg_provider_context "${CLUSTER_PROVIDER}")}"
ARGOCD_NS="${ARGOCD_NS:-cicd}"
ARGOCD_APP="${ARGOCD_APP:-rollout-demo-default}"

if [[ "${1:-}" == "--resolve-only" || "${SYNC_APPS_RESOLVE_ONLY:-0}" == "1" ]]; then
  printf 'CLUSTER_PROVIDER=%s\nINFRA_CONTEXT=%s\nAPP_CONTEXT=%s\nARGOCD_APP=%s\n' \
    "${CLUSTER_PROVIDER}" "${INFRA_CONTEXT}" "${APP_CONTEXT}" "${ARGOCD_APP}"
  exit 0
fi

if [[ "${CLUSTER_PROVIDER}" == "k3s-oci" ]]; then
  _info "[sync-apps] k3s-oci runs its own in-cluster ArgoCD (not the hub); sync it directly with KUBECONFIG=\$HOME/.kube/k3s-oci.yaml argocd ... — nothing to sync from the hub."
  exit 0
fi
```

Both the `--resolve-only` and the OCI guard must sit **before** the existing
`if ! kubectl config get-contexts "${INFRA_CONTEXT}" ...` hub check, so neither needs a live hub.

## Change 2 — `bin/cluster-sync-apps`: support a space-separated `ARGOCD_APP` list

Wrap the existing single-app block (`argocd app get` → `terminate-op` → wait loop → `argocd app sync`)
in a loop over the list. Use `read -ra` (not unquoted expansion) to avoid SC2086.

**Old:**

```bash
if ! argocd app get "${ARGOCD_APP}" >/dev/null 2>&1; then
  _info "[sync-apps] ERROR: ArgoCD app '${ARGOCD_APP}' not found — is bootstrap complete?"
  _info "[sync-apps] Available apps (set ARGOCD_APP=<name> to target a different one):"
  argocd app list --output name 2>/dev/null || true
  exit 1
fi

_info "[sync-apps] Terminating any in-progress operation on ${ARGOCD_APP}..."
argocd app terminate-op "${ARGOCD_APP}" 2>/dev/null || true

_info "[sync-apps] Waiting for operation to clear..."
for _i in $(seq 1 20); do
  _phase=$(argocd app get "${ARGOCD_APP}" --output json 2>/dev/null \
    | grep -o '"phase":"[^"]*"' | head -1 | grep -o '[^"]*$' || echo "none")
  if [[ "$_phase" == "none" || "$_phase" == "Succeeded" || \
        "$_phase" == "Failed"  || "$_phase" == "Error" ]]; then
    break
  fi
  _info "[sync-apps] Operation still ${_phase}, waiting... (${_i}/20)"
  sleep 3
done

_info "[sync-apps] Syncing ${ARGOCD_APP} (async)..."
argocd app sync "${ARGOCD_APP}" --async
```

**New:**

```bash
read -ra _argocd_apps <<< "${ARGOCD_APP}"
for _argocd_app in "${_argocd_apps[@]}"; do
  if ! argocd app get "${_argocd_app}" >/dev/null 2>&1; then
    _info "[sync-apps] ERROR: ArgoCD app '${_argocd_app}' not found — is bootstrap complete?"
    _info "[sync-apps] Available apps (set ARGOCD_APP=<name> to target a different one):"
    argocd app list --output name 2>/dev/null || true
    exit 1
  fi

  _info "[sync-apps] Terminating any in-progress operation on ${_argocd_app}..."
  argocd app terminate-op "${_argocd_app}" 2>/dev/null || true

  _info "[sync-apps] Waiting for operation to clear..."
  for _i in $(seq 1 20); do
    _phase=$(argocd app get "${_argocd_app}" --output json 2>/dev/null \
      | grep -o '"phase":"[^"]*"' | head -1 | grep -o '[^"]*$' || echo "none")
    if [[ "$_phase" == "none" || "$_phase" == "Succeeded" || \
          "$_phase" == "Failed"  || "$_phase" == "Error" ]]; then
      break
    fi
    _info "[sync-apps] Operation still ${_phase}, waiting... (${_i}/20)"
    sleep 3
  done

  _info "[sync-apps] Syncing ${_argocd_app} (async)..."
  argocd app sync "${_argocd_app}" --async
done
```

The pod-status and frontend port-forward steps after this block are unchanged (they already use
`${APP_CONTEXT}`, which is now provider-resolved).

## Change 3 — `Makefile`: provider-aware pass-through (mirror the `status` target)

**Old:**

```makefile
## Sync ArgoCD data-layer and show remote pod status
sync-apps:
	APP_CONTEXT=$(if $(filter k3s-gcp,$(CLUSTER_PROVIDER)),ubuntu-gcp,ubuntu-k3s) bin/cluster-sync-apps
```

**New:**

```makefile
## Sync ArgoCD data-layer and show remote pod status (provider-aware; auto-resolves APP_CONTEXT)
sync-apps:
	@$(if $(filter command line environment,$(origin APP_CONTEXT)),APP_CONTEXT=$(APP_CONTEXT) )$(if $(filter command line environment,$(origin CLUSTER_PROVIDER)),CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) )bin/cluster-sync-apps
```

This is byte-for-byte the same mechanism the `status` target already uses (only-pass-through-when-set),
so the script does the resolution and an explicit `APP_CONTEXT=...` / `CLUSTER_PROVIDER=...` on the
command line still wins (original intent preserved).

## Change 4 — tests (pure logic, no cluster mocks)

### 4a. `scripts/tests/lib/provider_contract.bats` — close the hostinger gap

In the `_acg_provider_context maps providers to app contexts` test, add a hostinger assertion next to
the gcp one:

```bash
  [[ "$(_acg_provider_context k3s-gcp)" == "ubuntu-gcp" ]]
  [[ "$(_acg_provider_context k3s-hostinger)" == "ubuntu-hostinger" ]]
  [[ "$(_acg_provider_context foo)" == "ubuntu-k3s" ]]
```

### 4b. `scripts/tests/bin/cluster_sync_apps.bats` — resolution + OCI guard + list

Add tests that run the real script with `--resolve-only` (the existing `setup()` stubs and the
tmpdir `HOME` make this side-effect-free; setting `CLUSTER_PROVIDER` explicitly means
`_acg_resolve_provider` returns it without probing). Add:

```bash
@test "cluster-sync-apps resolves APP_CONTEXT from CLUSTER_PROVIDER=k3s-hostinger" {
  run env CLUSTER_PROVIDER=k3s-hostinger "${BATS_TEST_DIRNAME}/../../../bin/cluster-sync-apps" --resolve-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_CONTEXT=ubuntu-hostinger"* ]]
}

@test "cluster-sync-apps resolves APP_CONTEXT from CLUSTER_PROVIDER=k3s-gcp" {
  run env CLUSTER_PROVIDER=k3s-gcp "${BATS_TEST_DIRNAME}/../../../bin/cluster-sync-apps" --resolve-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_CONTEXT=ubuntu-gcp"* ]]
}

@test "cluster-sync-apps honors an explicit APP_CONTEXT override" {
  run env CLUSTER_PROVIDER=k3s-hostinger APP_CONTEXT=my-ctx \
    "${BATS_TEST_DIRNAME}/../../../bin/cluster-sync-apps" --resolve-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_CONTEXT=my-ctx"* ]]
}

@test "cluster-sync-apps preserves a space-separated ARGOCD_APP list" {
  run env CLUSTER_PROVIDER=k3s-aws ARGOCD_APP="app-a app-b" \
    "${BATS_TEST_DIRNAME}/../../../bin/cluster-sync-apps" --resolve-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARGOCD_APP=app-a app-b"* ]]
}

@test "cluster-sync-apps skips the hub for k3s-oci (own in-cluster ArgoCD)" {
  run env CLUSTER_PROVIDER=k3s-oci "${BATS_TEST_DIRNAME}/../../../bin/cluster-sync-apps"
  [ "$status" -eq 0 ]
  [[ "$output" == *"own in-cluster ArgoCD"* ]]
  ! grep -q "port-forward svc/argocd-server" "${BATS_TEST_TMPDIR}/kubectl.log"
}
```

## Rules

- `set -euo pipefail` stays. No bare `sudo`; no `command sudo`; route privileged calls via `_run_command`.
- `shellcheck bin/cluster-sync-apps` must pass with zero new warnings (use `read -ra`, not unquoted
  `${ARGOCD_APP}`).
- Run and pass: `bats scripts/tests/bin/cluster_sync_apps.bats`,
  `bats scripts/tests/lib/provider_contract.bats`, and the full `bats scripts/tests`.
- Run `./scripts/k3d-manager _agent_audit` — must pass (abnormal-code tripwire).
- Sanity-check the resolution without a cluster:
  `CLUSTER_PROVIDER=k3s-hostinger bin/cluster-sync-apps --resolve-only` prints `APP_CONTEXT=ubuntu-hostinger`.

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`); fix your own hook failures.
- Do NOT edit `scripts/lib/provider.sh` — reuse `_acg_resolve_provider` / `_acg_provider_context`
  only. If you believe a provider/context gap exists, handle it in `bin/cluster-sync-apps`
  (OCI is already handled by the guard above) and note it — do not modify the resolver.
- Do NOT add a new provider→context map anywhere; the resolver is the single source of truth.
- Do NOT modify files outside: `bin/cluster-sync-apps`, `Makefile`,
  `scripts/tests/bin/cluster_sync_apps.bats`, `scripts/tests/lib/provider_contract.bats`,
  and the memory-bank files.
- Do NOT commit to `main` — work only on `fix/sync-apps-provider-generic`.
- Do NOT stage `docs/issues/2026-06-19-empty-rabbitmq-client-pr-base-ref.md`.

## Definition of Done

- [ ] Changes 1–4 applied exactly as written.
- [ ] `shellcheck bin/cluster-sync-apps` clean; `bats scripts/tests` all pass; `_agent_audit` passes.
- [ ] `CLUSTER_PROVIDER=k3s-hostinger bin/cluster-sync-apps --resolve-only` → `APP_CONTEXT=ubuntu-hostinger`.
- [ ] Commit on `fix/sync-apps-provider-generic` with message exactly:
      `fix(sync-apps): provider-generic APP_CONTEXT resolution + multi-app sync`
- [ ] `git push origin fix/sync-apps-provider-generic` — do NOT report done until the push succeeds.
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with the commit SHA and status.
- [ ] Report back: commit SHA + the memory-bank lines you updated.
