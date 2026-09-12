# Design spec: App-cluster Vault portability (consolidates 3 bugs)

**Filed:** 2026-07-07
**Source:** /ask agent observations, verified live 2026-07-07
**Branch:** `k3d-manager-v1.14.0`
**Status:** DESIGN — decisions signed off 2026-07-10. Still NOT a copy-paste bugfix: the Phase 1 implementation spec must be written before any handoff.
**Tracked project:** App-cluster Vault auth portability (kubecontext-keyed helper per provider; "Vault endpoint is the open seam")

## Why these three are one bug

Three separately-filed observations are three faces of a single design assumption: **the infra assumes exactly one app cluster at a time.** Fixing any one in isolation leaves the seam open.

| Sub-bug | Observation file | Verified site |
|---------|------------------|---------------|
| #2 Shared hub-Vault profile | `2026-07-07-global-hub-vault-profile-is-shared-across-clusters.md` | `scripts/etc/vault/vars.sh:29-39` |
| #3 Single-target k8s auth mount | `2026-07-07-vault-kubernetes-auth-mount-is-single-target.md` | `scripts/plugins/vault.sh:1695`, `:1730-1732` |
| #4 Stale `ubuntu-k3s` context | `2026-07-07-stale-kube-context-assumptions.md` | 25+ files (see footprint) |

## Verified findings (2026-07-07)

**#2 — one global HUB_VAULT_PROFILE.** `vault/vars.sh:29` exports a single `HUB_VAULT_PROFILE` (`laptop`|`hostinger`), and the `case` at `:30-39` derives one `HUB_VAULT_CSS_SERVER`/`HUB_VAULT_CSS_AUTH` per run. So Hostinger and ACG-AWS cannot both have their own Vault connectivity active simultaneously — the last `make up` wins. (Partially escape-hatched: each export is `${HUB_VAULT_CSS_SERVER:-...}`, so an operator can override per-invocation, but there is no per-cluster persistence.)

**#3 — one fixed auth mount, last cluster wins.** `configure_vault_app_auth` (`vault.sh:1690`) and `configure_vault_app_auth_for_context` (`:1788`) both write to a single mount, default `kubernetes-app` (`:1695`). The mount config at `:1730-1732` stores **one** `kubernetes_host` + CA:

```
vault write auth/${mount}/config kubernetes_host=... kubernetes_ca_cert=@...
```

Configuring a second app cluster overwrites the first cluster's API server + CA on the same mount, invalidating the first cluster's ESO auth path. `configure_vault_app_auth_for_context` already derives per-context `server`/`ca_data` (`:1804-1809`) — it just writes them to a non-per-context mount.

**#4 — `ubuntu-k3s` hardcoded across 25+ files.** `provider.sh:94` maps provider `k3s-aws` → context `ubuntu-k3s`. That AWS cluster was migrated to Hostinger. Footprint includes `provider.sh:94/98/114/118`, `bin/k3dm-webhook:95/99/116/295/1044/1048`, `bin/cluster-up:611/676/688/695/697/703/706`, `argocd/vars.sh`, launchd plist templates, and the `cluster: ubuntu-k3s` Prometheus external label.

> **Correction (2026-07-10).** This finding originally claimed *"the current fleet has no `ubuntu-k3s` context."* That is **wrong** and the conclusion drawn from it was unsafe. Re-verified live:
>
> ```
> $ kubectl config get-contexts -o name
> k3d-k3d-cluster  k3s-gcp  ubuntu-azure  ubuntu-gcp  ubuntu-hostinger  ubuntu-k3s
> ```
>
> The context **does exist**, bound to cluster `ubuntu-k3s` at `https://52.37.60.119:6443` (an AWS address). `kubectl --context ubuntu-k3s get nodes` does not answer — the kubeconfig entry outlived the cluster it points at.
>
> This changes the risk profile of Phase 3. The original reasoning was "the context is absent, so the references are dead and safe to purge." In fact a **live, resolvable, unreachable** context is present: any code path that selects `ubuntu-k3s` will not fail fast with "context not found," it will hang or time out against a dead endpoint. A blind find-replace could also silently retarget an operation at a *reachable* cluster. Open decision #1 must be resolved first — and the dangling kubeconfig entry should be removed independently of this spec.

## The seam

Everything app-cluster-facing should be **keyed by kube-context** instead of assuming a single well-known name/mount/profile:

1. **Vault auth mount** — derive the mount path from the cluster, e.g. `kubernetes-<sanitized-context>` (or `kubernetes-app-<cluster>`), so each app cluster owns its own mount + config + role. ESO in each cluster references its own mount.
2. **Hub-Vault CSS connectivity** — key `HUB_VAULT_CSS_SERVER`/`_AUTH` (and profile) by the target app context, so multiple app clusters coexist. Persist per-context, not one global state file.
3. **Context identity** — stop hardcoding `ubuntu-k3s`; resolve the app context from the active provider / an explicit `APP_CLUSTER_CONTEXT` var. Decide whether `k3s-aws`/`ubuntu-k3s` is retired or renamed to the Hostinger identity.

## Phased plan

**Phase 1 — Vault mount per-context (#3, highest blast radius).**
`configure_vault_app_auth_for_context` already has `cluster_name`/`server`/`ca_data` in scope (`:1798-1809`). Derive `mount="kubernetes-${sanitized_cluster_name}"` there and pass it through to the `auth/${mount}/config` write and the role/policy binding. Keep `kubernetes-app` as the default only for the legacy single-cluster `configure_vault_app_auth` path. ESO SecretStore manifests must reference the per-context mount.

**Phase 2 — Per-context hub-Vault profile (#2).**
Replace the single `HUB_VAULT_PROFILE` global with a per-context lookup (state file keyed by context, or a `HUB_VAULT_PROFILE__<context>` convention). Preserve the current default for the single-cluster case.

**Phase 3 — De-hardcode `ubuntu-k3s` (#4).**
Introduce `APP_CLUSTER_CONTEXT` (resolved from provider, default preserves today's behavior) and thread it through the 25+ sites. This is mechanical but large — split by subsystem (provider/lib, bin/, argocd, launchd, values) into separate commits.

## Decisions — RESOLVED 2026-07-10 (user sign-off)

1. **`k3s-aws`/`ubuntu-k3s` may return — keep the mapping, but demote it.**
   Do NOT rename it to the Hostinger identity and do NOT delete `provider.sh:94`. Instead:
   - make `k3s-aws` **non-default** wherever it is currently reachable as a default,
   - add a **reachability preflight** so selecting the context fails fast instead of hanging.

   This is now a hard requirement, not a nicety. Per the correction above, the `ubuntu-k3s`
   kubeconfig entry resolves but does not answer, so today the failure mode is a timeout, not a
   clean "context not found." The preflight is what makes "keep but demote" safe.

   Separately and independently of this spec: **delete the dangling `ubuntu-k3s` kubeconfig
   entry** pointing at `https://52.37.60.119:6443`.

2. **Mount naming: `kubernetes-<sanitized-context>`.**
   Chosen over `kubernetes-app-<cluster>` — the kube-context is already the keying dimension this
   spec argues for, and `configure_vault_app_auth_for_context` already has it in scope
   (`vault.sh:1798-1809`). The `-app-` infix carries no information once every mount is per-cluster.

   Requires a **sanitizer** for characters invalid in a Vault mount path. Requires a **migration
   path** for live ESO SecretStores already bound to `kubernetes-app` — they must not break on
   redeploy. `kubernetes-app` remains the default for the legacy single-cluster
   `configure_vault_app_auth` path.

3. **>1 live app cluster is a known-future need, not a today need.**
   Phase 1 is therefore **queued behind current v1.14.0 work** — it gets written as a proper
   implementation spec (exact old/new blocks, `## Before You Start`, `## Definition of Done`,
   migration path), but it is **not handed off yet**.

## Phase 3 — grounded evidence (added 2026-09-12)

The 2026-09-11 product-catalog empty-DB incident put a concrete, measured cost on
Phase 3, so the "25+ sites" estimate can now be replaced with an exact inventory
for the highest-value file. `scripts/plugins/shopping_cart.sh` contains **24**
literal `--context ubuntu-k3s` occurrences, confined to three functions:

| Function | Occurrences | Lines |
|---|---|---|
| `shopping_cart_reconcile_product_catalog` | 13 | 841–899 |
| `shopping_cart_reconcile_order_service` | 6 | 922–943 |
| `deploy_shopping_cart_data` | 5 | 114–140 |

**The resolver already exists in this same file.** `_shopping_cart_resolve_app_context()`
(`:553-563`) resolves the provider via `_acg_resolve_provider` → `_acg_provider_context`
and falls back to the literal `ubuntu-k3s`, preserving today's behavior exactly as
decision #1 requires. Five other call sites in the file already consume it as
`_app_context` (`:161`, `:221`, `:407`, `:498`). So for this file Phase 3 is not a
find-replace against an unknown target — it is threading an existing, tested,
default-preserving resolver into three functions that were written before it.

**Why this matters more than it looks.** During the incident
`shopping_cart_reconcile_product_catalog` was the named remediation path for an
empty product catalog, and it could not have helped: on a machine where the app
cluster is reached under a different provider, all 13 of its `kubectl` calls target
a context that is not present, and **every failure is swallowed** — each call ends
in `|| _info WARN` (and several in `2>/dev/null`), so the function runs to
completion and reports success while doing nothing. Per the 2026-07-10 correction
above, an *expired-but-still-resolvable* sandbox context makes this worse, not
better: the calls hang against a dead endpoint before warning.

This is the second defect class in one incident where a real failure was reported
as success. Whatever shape Phase 3 takes, the swallowed-failure behavior in these
three functions should be fixed **with** the context threading, not after it —
otherwise the fix is unverifiable from logs.

Note this is *not* dead code in its intended setting: these functions belong to the
ACG `acg-up` / `bin/cluster-up:1831` flow, where `ubuntu-k3s` is the correct sandbox
context. The defect is the coupling, not the function's existence.

Incident detail: `docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md`
Findings 10 and 12.

## Status

- **Phase 1** — unblocked by the decisions above; needs a proper implementation spec written. **Queued.**
- **Phase 2** — unblocked; follows Phase 1.
- **Phase 3** — scope changed by decision #1: this is now "demote `k3s-aws` + add reachability preflight," **not** a mass rename. Re-scope before writing.
- **Phase 3 inventory** — `shopping_cart.sh` half is now measured (24 sites, 3 functions,
  resolver already present). Still needs the re-scope from decision #1 plus the
  swallowed-failure fix before a spec is written.

## What NOT to Do

- Do NOT blind find-replace `ubuntu-k3s`. Decision #1 keeps the mapping. A resolvable-but-unreachable
  context means a wrong replace hangs instead of erroring, and could silently retarget a *reachable* cluster.
- Do NOT rename the existing `kubernetes-app` mount without a migration path for live ESO stores.
- Do NOT hand **this** document to Codex — it is a design doc, not an implementation spec. It has no
  exact old/new code blocks, no `## Before You Start`, and no `## Definition of Done`. Write the
  Phase 1 spec first, then hand that off.
- Do NOT create a PR, skip hooks, or commit to `main`.
