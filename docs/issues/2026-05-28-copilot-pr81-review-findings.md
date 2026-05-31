# Copilot PR #81 Review Findings

**PR:** #81 — fix(v1.4.10): ArgoCD project assignment, sync stability, and bootstrap reliability
**Fix commit:** `2828883b`
**Date:** 2026-05-28

---

## Finding 1 — `kubectl | base64 -d` exits under `set -euo pipefail`

**File:** `scripts/plugins/shopping_cart.sh:391`

**What Copilot flagged:** `kubectl get secret vault-root ... | base64 -d` — if the secret is
missing the pipeline exits immediately under `set -euo pipefail`, bypassing the `_err` + `return 1`
error path.

**Fix:** Added `2>/dev/null || true` to both sides of the pipeline so failures are captured as empty
string and handled by the existing emptiness check.

```bash
# before
_vault_root_token=$(kubectl get secret vault-root ... | base64 -d)

# after
_vault_root_token=$(kubectl get secret vault-root ... 2>/dev/null | base64 -d 2>/dev/null || true)
```

**Root cause:** Pipeline under `set -e` exits on first non-zero command; `|| true` is required to
swallow failures that should be handled as empty-string conditions.

---

## Finding 2 — GHCR imagePullSecrets not patched for payment and data namespaces

**File:** `scripts/plugins/shopping_cart.sh:317-319`

**What Copilot flagged:** `shopping_cart_create_ghcr_pull_secret` applies `ghcr-pull-secret` to
`shopping-cart-apps`, `shopping-cart-payment`, and `shopping-cart-data`, but only patches the
default ServiceAccount in `shopping-cart-apps`. The PR removes per-Deployment `imagePullSecrets`
patches from the kustomize overlays, so `shopping-cart-payment` pods would fail to pull from GHCR.

**Fix:** Loop the SA patch across all three namespaces.

```bash
# before
kubectl patch serviceaccount default -n shopping-cart-apps --context ubuntu-k3s \
  -p '{"imagePullSecrets": [{"name": "ghcr-pull-secret"}]}'

# after
for ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
  kubectl patch serviceaccount default -n "$ns" --context ubuntu-k3s \
    -p '{"imagePullSecrets": [{"name": "ghcr-pull-secret"}]}'
done
```

**Root cause:** The imagePullSecrets refactor (move from per-Deployment patches to SA-level) was
only half-applied — SA patch not extended to match the namespaces where the secret was provisioned.

---

## Finding 3 — `curl -u user:token` exposes PAT in process list

**File:** `scripts/plugins/shopping_cart.sh:184, 207, 228`

**What Copilot flagged:** Three PAT validation calls used `curl -u "${_github_user}:${_ghcr_pat}"`
which puts the token in argv and is visible via `ps`.

**Fix:** Replaced with `--netrc-file` (0600 temp file) for PAT cases; `GH_TOKEN` env + `gh api` for
the gh auth token case.

```bash
# before (lines 184 and 207)
_pat_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${_github_user}:${_ghcr_pat}" \
  "https://api.github.com/user" 2>/dev/null || true)

# after
local _netrc
_netrc=$(mktemp) && chmod 0600 "${_netrc}"
printf 'machine api.github.com login %s password %s\n' "${_github_user}" "${_ghcr_pat}" > "${_netrc}"
_pat_http=$(curl -s -o /dev/null -w "%{http_code}" --netrc-file "${_netrc}" \
  "https://api.github.com/user" 2>/dev/null || true)
rm -f "${_netrc}"

# before (line 228 — gh auth token)
_gh_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${_github_user}:${_gh_token}" \
  "https://api.github.com/user" 2>/dev/null || true)
if [[ "${_gh_http}" != "200" ]]; then return 1; fi

# after
if ! GH_TOKEN="${_gh_token}" gh api user >/dev/null 2>&1; then return 1; fi
```

**Root cause:** `curl -u` passes credentials as a command-line argument, visible in `/proc/<pid>/cmdline`
and `ps aux`. Repo PAT hygiene rules require secrets to stay out of argv.

**Process note:** PAT validation functions must never use `curl -u`; use `--netrc-file` (0600 temp)
or env-var injection (`GH_TOKEN=`) with `gh api`.

---

## Finding 4 — Helm installer pinned to `main` branch (supply-chain risk)

**File:** `scripts/plugins/shopping_cart.sh:374`

**What Copilot flagged:** `curl ... helm/main/scripts/get-helm-3 | bash` downloads from the tip
of `main` — non-reproducible and supply-chain risky per OWASP A08.

**Fix:** Pin to tag `v3.17.3` and set `DESIRED_VERSION` to enforce the version.

```bash
# before
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null

# after
curl -fsSL https://raw.githubusercontent.com/helm/helm/v3.17.3/scripts/get-helm-3 | DESIRED_VERSION=v3.17.3 bash >/dev/null
```

**Root cause:** Script was written before the supply-chain rule was added to CLAUDE.md.

**Process note:** All `curl | bash` installs must pin to a version tag and (ideally) set the
corresponding version env var. Add this check to spec templates.

---

## Finding 5 — `deploy_shopping_cart_data` API doc out of date

**File:** `docs/api/functions.md:75`

**What Copilot flagged:** Description still said "align passwords to CHANGE_ME; create rabbitmq-credentials"
after the function was refactored to deploy MinIO and use ESO-managed secrets.

**Fix:** Updated description to: "Deploy PostgreSQL (orders/payment/products), Redis cart, RabbitMQ,
and MinIO data services; apply Vault-backed ExternalSecrets; wait for readiness"

**Root cause:** `docs/api/functions.md` was not updated when the function behavior changed.

**Process note:** `docs/api/functions.md` must be updated atomically with any change to a public
function's behavior. Add to PR checklist.
