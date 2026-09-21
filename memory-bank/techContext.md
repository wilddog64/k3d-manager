# Technical Context – k3d-manager

_Last verified against the tree on 2026-09-21 (branch `k3d-manager-v1.36.0`). The previous revision
dated from v1.24.0 (2026-08-11) and had drifted badly — it listed 15 BATS files against 117, two
plugins against 26, and three providers against nine._

## Runtime Prerequisites

| Tool | Notes |
|---|---|
| Docker | Required for k3d (macOS default) |
| k3d | Installed automatically if missing |
| k3s | Required on Linux and on all remote/cloud providers; systemd-based |
| kubectl | Must be on PATH |
| helm | Used for ESO, Vault, Istio, observability installs |
| jq | JSON parsing throughout |
| Bats | Auto-installed by `_ensure_bats`; also bare on PATH at `/opt/homebrew/bin/bats` |
| Python 3 + pytest | Hermes suites are pytest, not BATS. Use the pyenv shim — `pytest` is **not** on `/opt/homebrew/bin/python3` |
| vault CLI | PKI / unseal operations |
| Node.js | `_ensure_node` — Playwright browser automation (ACG lifecycle) |
| Playwright | ACG sandbox automation |
| cosign | Image signing and attestation (v1.27.0 onward) |
| trivy | Vulnerability scanning; `trivy-operator` also runs in-cluster |
| argocd CLI | GitOps app management; the most-referenced external CLI in the tree |
| gh CLI | GitHub API work from `bin/` scripts. Note its OAuth token needs `read:packages` for GHCR |
| Rust/cargo | `_ensure_cargo` — RTK output compression |
| agy CLI | `_ensure_agy_cli` — Antigravity; `agy models` is the source of truth for model IDs |
| Azure CLI / AWS session-manager-plugin | Provider-specific, installed on demand |

## Platform Defaults

- **macOS**: OrbStack auto-detected when available (`orb` CLI + daemon running); falls back to k3d.
  Detection order: orbstack → k3d → k3s → kubeconfig.
- **Linux**: `CLUSTER_PROVIDER=k3s` (systemd-based, requires root/sudo for install)
- **Remote**: `k3s-hostinger` is the live long-running cluster; `k3s-aws` / `k3s-az` / `k3s-gcp` /
  `k3s-oci` exist for cloud sandboxes. **OCI is de-scoped** — infra lives on the laptop and Hostinger.

## Technology Stack

### Kubernetes Layer
- **OrbStack**: Recommended macOS runtime; optimized network/storage for k3d.
- **k3d**: Runs k3s in Docker; the k3d load balancer handles port mapping.
- **k3s**: Lightweight Kubernetes; kubeconfig at `/etc/rancher/k3s/k3s.yaml`.
- **vCluster**: Ephemeral per-PR preflight clusters (Tier 1 of the e2e harness).

### Service Mesh
- **Istio**: Installed during `deploy_cluster`; TLS ingress routing (Gateway + VirtualService) for
  hub services (ArgoCD, Grafana, Keycloak, …). An ambient-mode plugin exists
  (`plugins/istio_ambient.sh`).

### Secret Management
- **HashiCorp Vault**: Helm-deployed; auto-initialized and unsealed; PKI enabled; K8s auth for ESO.
- **ESO (External Secrets Operator)**: Helm-deployed; SecretStore points at Vault; service plugins
  create ExternalSecret resources.
- **Vault PKI**: Short-TTL TLS leaf certs (≤720h), stored as K8s Secrets in `istio-system`.
- **cert-manager**: `plugins/cert-manager.sh`, alongside the Vault PKI path.

### GitOps and Delivery
- **ArgoCD**: App delivery, driven by ApplicationSets. **ApplicationSets template `$values` at
  `${K3D_MANAGER_BRANCH}` and must be reapplied every release** for both hub and ACG variants, then
  confirmed with `argocd_check_values_branch` — otherwise committed config is inert.
- **GitHub Actions**: Repo CI. The shopping-cart repos call a reusable
  `shopping-cart-infra/.github/workflows/build-push-deploy.yml`, which builds, scans, pushes, cosign
  signs/attests, and promotes the image tag over SSH using a per-repo `sc-image-promoter` deploy key.
- **Image signing**: cosign sign + attest, with a staged Audit→Enforce Kyverno rollout.

### Observability
- **Prometheus / Alertmanager / Grafana** via `plugins/observability.sh`. Alertmanager inline
  templates have **no sprig functions**, and `amtool` skips inline templates entirely.
- **trivy-operator** for in-cluster CVE scanning.

### Directory Services
- **OpenLDAP**: Deployed in-cluster; standard and AD-compatible schema
  (`bootstrap-ad-schema.ldif`).
- **Active Directory**: External only; validated via DNS + LDAP port probe. Never deployed here.
- **Keycloak**: Browser SSO / OIDC; `kcadm` auth-flow API has a flattened-listing contract.

### Agents and Automation
- **Hermes** (`scripts/lib/hermes/`): monitoring, triage, approvals, paging. Python, pytest-tested.
- **Webhook server** (`scripts/lib/webhook/`): `bin/k3dm-webhook`; run `make restart-webhook` after
  editing. Subject of a standing security audit.
- **Copilot / Gemini / Antigravity** plugins for agent workflows.

### Deprecated
- **Jenkins** — disabled by default (`ENABLE_JENKINS=0`), **not deployed**. Code retained but
  unsupported; removal was cancelled. Its cert-rotation CronJob and JCasC LDAP/AD auth remain in the
  tree for reference only.

## Layout

| Path | Purpose |
|---|---|
| `scripts/k3d-manager` | Main dispatcher / entry point (lazy plugin loading) |
| `scripts/lib/system.sh` | `_run_command`, `_kubectl`, `_helm`, `_curl`, `_ensure_bats`, `_err`/`_warn` |
| `scripts/lib/core.sh` | Cluster lifecycle: create / deploy / destroy |
| `scripts/lib/cluster_provider.sh`, `provider.sh` | Provider abstraction |
| `scripts/lib/providers/` | 9 providers: `k3d`, `orbstack`, `k3s`, `k3s-hostinger`, `k3s-aws`, `k3s-az`, `k3s-gcp`, `k3s-oci`, `k3s-oci-storage` |
| `scripts/lib/foundation/` | **lib-foundation subtree — upstream-first, never edit here** |
| `scripts/lib/hermes/` | Hermes agent internals |
| `scripts/lib/webhook/` | Webhook server internals |
| `scripts/lib/dirservices/` | `openldap.sh`, `activedirectory.sh` |
| `scripts/lib/secret_backends/` | `vault.sh` |
| `scripts/lib/agent_rigor.sh` | Agent verification helpers |
| `scripts/plugins/` | 26 lazy-loaded modules (see below) |
| `scripts/etc/` | 25 config dirs of `*.yaml.tmpl` and `vars.sh` |
| `bin/` | ~55 operator scripts — cluster lifecycle, credential rotation, smoke tests, Hermes, webhook |
| `scripts/tests/` | BATS suites, by area |

**Plugins** (`scripts/plugins/`): `acg`, `argocd`, `aws`, `azure`, `cert-manager`, `copilot`, `e2e`,
`e2e_remote`, `eso`, `gcp`, `gemini`, `hello`, `hub_recovery`, `istio_ambient`, `jenkins`,
`keycloak`, `ldap`, `loadtest`, `observability`, `shopping_cart`, `signing`, `smb-csi`, `ssm`,
`tunnel`, `vault`, `vcluster`.

**Note on the dispatcher:** it lazy-loads *only the invoked plugin*. Cross-plugin calls silently
no-op unless the other plugin is sourced — a `declare -f` guard is the smell that this is happening.

## Key Variable Files

| File | Purpose |
|---|---|
| `scripts/etc/cluster_var.sh` | Cluster ports, k3d cluster name defaults |
| `scripts/etc/vault/vars.sh` | Vault PKI TTLs, paths, roles |
| `scripts/etc/ldap/vars.sh` | LDAP base DN, admin DN, ports |
| `scripts/etc/ad/vars.sh` | AD-specific defaults |
| `scripts/etc/k3s/vars.sh` | k3s kubeconfig path, node IP |
| `scripts/etc/hostinger/` | Hostinger cluster config |
| `scripts/etc/argocd/` | ApplicationSets and app definitions |
| `scripts/etc/observability/`, `prometheus/`, `grafana/` | Monitoring config |
| `scripts/etc/signing/` | cosign / Kyverno policy config |
| `scripts/etc/azure/azure-vars.sh` | Azure Key Vault ESO backend settings |
| `scripts/etc/jenkins/*` | Deprecated Jenkins config (retained, unused) |

## Testing

**BATS: 117 files, 1118 cases.** `make test` takes **~15 minutes** — agents routinely mistake it for
a hang and abandon it. Check the log mtime and re-run backgrounded rather than killing it.

| Area | Files | Cases |
|---|---|---|
| `scripts/tests/plugins/` | 59 | 614 |
| `scripts/tests/lib/` | 28 | 345 |
| `scripts/tests/bin/` | 22 | 116 |
| `scripts/tests/etc/` | 2 | 18 |
| `scripts/tests/core/` | 3 | 9 |

`scripts/tests/hermes/` is **pytest**, not BATS (`test_hermes.py`, `test_approvals.py`,
`test_audit.py`, `test_pager.py`, `test_preflight.py`, `test_repairs.py`, `test_triage`/`schedule`/
`bugs` e2e).

Suites are pure-logic only — no cluster mocks. Integration confidence comes from live smoke tests and
the two-tier e2e harness (Tier 1 vCluster, Tier 2 ACG).

**Test-writing rules that have burned us:**
- A new test passing does not mean it *can* fail — check the pattern against the pre-fix source and
  confirm the count moves. Mutation-test the guard.
- Prefer disappearance gates (`old → 0`); `grep -c` exits 1 on zero matches.
- Never `grep -F` a whole source line — assertions rot. Assert meaningful tokens.
- No bare `!` in BATS.
- `grep` with a pattern starting `-` needs `--`: `grep -cF -- "$pat"`.

Smoke entrypoints:

```bash
./scripts/k3d-manager test smoke
bin/smoke-test-cluster-health
bin/smoke-test-webhook
```

## Debugging

```bash
ENABLE_TRACE=1 ./scripts/k3d-manager <command>   # trace to /tmp/k3d.trace
DEBUG=1 ./scripts/k3d-manager <command>           # bash -x mode
```

`_args_have_sensitive_flag` auto-disables trace for commands carrying `--password`, `--token` or
`--username`. **New sensitive flags must be registered there.**

## Known Behaviours

**ESO SecretStore `mountPath`** must be `kubernetes`, not `auth/kubernetes`. Wrong path ⇒ SecretStore
NotReady. Source: `docs/issues/2025-10-19-eso-secretstore-not-ready.md`.

**Vault seals on every pod/node restart.** `reunseal_vault` pulls unseal shards from the macOS
Keychain (or Linux `libsecret`). Everything Vault-dependent (ESO, LDAP auth) is unhealthy while
sealed. Run it after any node restart.

**Kine compaction dies silently** on the hub. Ask "when was the last `msg=\"COMPACT deleted\"`?" —
288/day is healthy. A restart does **not** fix it and induces a bootstrap crash loop; rebuild instead.

**ArgoCD `selfHeal` reverts out-of-band `kubectl patch`** — the patch exits 0, then vanishes. Needs
`ignoreDifferences` *and* `RespectIgnoreDifferences=true`. Always read the value back.

**GHCR packages are private.** Pulling needs `read:packages`; a credential without it returns 403,
which is what `ImagePullBackOff` on the hub means. CI's registry login uses the ephemeral
`secrets.GITHUB_TOKEN`, so a green push proves nothing about any long-lived credential.
