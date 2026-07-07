# Design spec: App-cluster Vault portability (consolidates 3 bugs)

**Filed:** 2026-07-07
**Source:** /ask agent observations, verified live 2026-07-07
**Branch:** `k3d-manager-v1.14.0`
**Status:** DESIGN — needs decision sign-off before handoff (not a copy-paste bugfix)
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

**#4 — `ubuntu-k3s` hardcoded across 25+ files.** The current fleet has no `ubuntu-k3s` context (`kubectl config get-contexts` → `k3d-k3d-cluster`, `k3s-gcp`, `ubuntu-azure`, `ubuntu-gcp`, `ubuntu-hostinger`). But `ubuntu-k3s` is not a typo — `provider.sh:94` maps provider `k3s-aws` → context `ubuntu-k3s`. That AWS cluster was migrated to Hostinger, so every `ubuntu-k3s` reference is stale **for this machine's current fleet**. Footprint includes `provider.sh:94/98/114/118`, `bin/k3dm-webhook:95/99/116/295/1044/1048`, `bin/cluster-up:611/676/688/695/697/703/706`, `argocd/vars.sh`, launchd plist templates, and the `cluster: ubuntu-k3s` Prometheus external label.

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

## Open decisions (must resolve before handoff)

1. **Is the `k3s-aws`/`ubuntu-k3s` cluster retired, or coming back?** If retired → Phase 3 becomes a rename to the Hostinger identity. If it may return → keep the mapping but make it non-default. This gates Phase 3 entirely.
2. **Mount naming scheme** — `kubernetes-<context>` vs `kubernetes-app-<cluster>`? Affects every existing ESO SecretStore already bound to `kubernetes-app`; needs a migration note so live clusters don't break on redeploy.
3. **Do we need >1 app cluster live *today*, or is this hardening for a known-future need?** Determines whether Phase 1 ships now or waits.

## What NOT to Do

- Do NOT blind find-replace `ubuntu-k3s` — resolve open decision #1 first.
- Do NOT rename the existing `kubernetes-app` mount without a migration path for live ESO stores (open decision #2).
- Do NOT hand this to Codex as a single spec — Phase 1 is the only self-contained unit; Phases 2–3 need the decisions above.
- Do NOT create a PR, skip hooks, or commit to `main`.
