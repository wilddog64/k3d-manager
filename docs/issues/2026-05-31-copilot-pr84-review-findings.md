# Copilot PR #84 Review Findings — 2026-05-31

**PR:** #84 — feat: v1.5.0 — OCI provider, observability stack, Alertmanager

---

## Fixed in this PR (commit cfd073cf)

### 1. Vault token exposed in curl process args (`observability.sh:27`)

**Finding:** `-H "X-Vault-Token: ${_vault_token}"` puts the token in curl's argv, visible via `ps aux`.

**Fix:** Write token to tmpfile; use `curl -H "@${file}"` syntax; `rm -f` after.

```bash
# Before:
curl -sf -H "X-Vault-Token: ${_vault_token}" "${url}" ...

# After:
_vault_hdr=$(mktemp)
printf 'X-Vault-Token: %s\n' "${_vault_token}" > "${_vault_hdr}"
curl -sf -H "@${_vault_hdr}" "${url}" ...
rm -f "${_vault_hdr}"
```

**Root cause:** Direct variable expansion in `-H` arg. Pattern applies to any secret passed via curl headers.

**Process note:** Template rule — secrets in curl headers must use `@file` syntax, never inline expansion.

---

### 2. Gmail app password exposed in kubectl process args (`observability.sh:51`)

**Finding:** `--from-literal=alertmanager.yaml="${_am_config}"` puts the full rendered Alertmanager config (including SMTP password) in kubectl's argv.

**Fix:** Write rendered config to tmpfile; use `--from-file=alertmanager.yaml="${tmpfile}"`; `rm -f` after.

```bash
# Before:
_kubectl create secret generic alertmanager-smtp-secret \
  --from-literal=alertmanager.yaml="${_am_config}" ...

# After:
_am_tmpfile=$(mktemp)
printf '%s' "${_am_config}" > "${_am_tmpfile}"
_kubectl create secret generic alertmanager-smtp-secret \
  --from-file=alertmanager.yaml="${_am_tmpfile}" ...
rm -f "${_am_tmpfile}"
```

**Root cause:** `--from-literal` with secret-containing content. `--from-file` is always safer for rendered configs.

**Process note:** Template rule — `kubectl create secret` with rendered secret content must use `--from-file`, never `--from-literal`.

---

## Deferred / Acknowledged (not fixed in this PR)

### 3. Prometheus published without authentication (`istio.yaml:43`)

**Status:** Deferred — planned fix in v1.5.7 (oauth2-proxy SSO gate).
The Istio VirtualService for `prometheus.3ai-talk.org` will be updated to route through oauth2-proxy backed by Keycloak OIDC.

### 4. `services-git.yaml` references `shopping-cart` AppProject (`services-git.yaml:28`)

**Status:** Not a bug — the `shopping-cart` AppProject is defined in `shopping-cart-infra/argocd/projects/shopping-cart.yaml` and applied via `make argocd-project`. This is a documented cross-repo dependency. A follow-up doc improvement could add a `## Prerequisites` note to the relevant how-to.

### 5. Hardcoded user path in `cloudflared/config.yml`

**Status:** Known limitation — this is a local developer config file committed for reference. The path is specific to the machine. Tracked for improvement when cloudflared config moves to full template substitution.

### 6. OCI security list exposes K8s API to Internet (`security-list-rules.json:15`)

**Status:** Intentional for dev/lab — the OCI Always Free setup is a personal dev cluster, not a shared or production environment. Access requires a valid kubeconfig + cluster cert. Noted in docs as dev-only.

### 7. ArgoCD sync race condition with ESO (`shopping_cart.sh:99`)

**Status:** Known timing issue on fresh cluster installs. Not introduced by this PR. Tracked for a future wait/retry loop improvement.

### 8. PrometheusRule CRD timing on first install (`observability.sh:58`)

**Status:** Known race on first `make observability` — CRD is installed async by the ApplicationSet. Running `make observability` a second time always succeeds. A future improvement could add a CRD existence wait before applying rules.

### 9. `Browser.close()` disrupts shared Chrome in CDP sessions (`acg_extend.js:391`)

**Status:** Pre-existing pattern from lib-acg subtree. Fix belongs upstream in lib-foundation/lib-acg. Tracked for v0.3.x.
