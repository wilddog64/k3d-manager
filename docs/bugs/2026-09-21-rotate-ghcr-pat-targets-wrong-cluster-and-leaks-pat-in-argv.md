# `bin/rotate-ghcr-pat` cannot fix the hub, accepts a PAT that cannot pull, and puts the PAT in argv

**Filed:** 2026-09-21
**Branch:** `k3d-manager-v1.36.0`
**Severity:** Medium — the tool an operator would reach for during a GHCR outage silently does not
touch the affected cluster, and leaks credentials into the process table.
**Status:** Assigned to Codex 2026-09-21

## Context

Found while walking the operator restore for
`docs/bugs/2026-09-21-ghcr-pat-validated-for-auth-not-packages-scope.md`. `bin/rotate-ghcr-pat` is the
obvious tool to reach for — the plugin's own error message recommends it:

```
_err "[acg-up] GHCR_PAT not set and no valid PAT in Vault — set GHCR_PAT env var or run: pbpaste | bin/rotate-ghcr-pat"
```

It is the wrong tool for a hub outage, in three independent ways.

Confirmed live on 2026-09-21: all four `shopping-cart-apps` deployments on the hub sat in
`ImagePullBackOff` for 11h with `403 Forbidden` from `ghcr.io`, and every GitHub token on the
operator's machine failed the real pull probe. `rotate-ghcr-pat` would have reported success.

## Defect 1 — hardcoded `ubuntu-k3s` context, so it cannot fix the hub

`--context ubuntu-k3s` is hardcoded in the propagation loop. Running this during a **hub**
`ImagePullBackOff` reports `✅ namespace: shopping-cart-apps` three times while changing nothing on
the hub. The success output is actively misleading.

This is a **recurrence** of an already-filed defect —
`docs/bugs/2026-06-14-bugfix-ghcr-pull-secret-hardcoded-context.md` — in a different file.

Related: on the hub, `ghcr-pull-secret` is **ESO-managed** from Vault `secret/github/pat`. A
`kubectl create secret` there would be reverted on the next reconcile anyway, so the correct path on
an ESO-managed namespace is *write Vault, then force-sync the ExternalSecret* — not a direct write.

## Defect 2 — validates authentication, not package-pull

`GET /user` returns 200 for any token that authenticates and never checks `read:packages`, the only
scope GHCR enforces. This tool will accept a scope-less PAT, **store it to Vault**, push it to seven
GitHub repos as `PACKAGES_TOKEN`, and write it into three namespaces — all reporting success.

Use the helper added in `cb428d09`: `_shopping_cart_ghcr_pat_can_pull`, a real GHCR token exchange
plus a pull-scoped `tags/list` call.

Do **not** substitute an `X-OAuth-Scopes` header check: fine-grained PATs omit that header entirely,
so header parsing rejects valid credentials and cannot distinguish "expired" from "fine-grained".

## Defect 3 — PAT and Vault token in argv

Three violations of the CLAUDE.md rule that secrets must never appear in script arguments or in
`kubectl` command strings that reach logs — all visible in the process table:

```bash
curl -s -u "${SHOPPING_CART_ORG}:${TOKEN}" "https://api.github.com/user"
curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" -d "{\"data\": {\"token\": \"${TOKEN}\"}}" ...
kubectl create secret docker-registry ... --docker-password="${TOKEN}" ...
```

The `-d "{\"data\": {\"token\": \"${TOKEN}\"}}"` form also produces invalid JSON when the PAT
contains a quote or backslash.

## Interim mitigation already in place

`bin/restore-hub-ghcr-pat` was added for the hub path: stdin-only PAT, probe-before-write, explicit
`HUB_CONTEXT` (default `k3d-k3d-cluster`), Vault write via the hardened helper, ESO force-sync, then
rollout restart. It does **not** replace `rotate-ghcr-pat`, which still owns the seven-repo
`PACKAGES_TOKEN` rotation.

---

## Before You Start

**Branch (all work):** `k3d-manager-v1.36.0` — never commit to `main`.

1. `git pull origin k3d-manager-v1.36.0`
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
3. Read these files in full before editing:
   - `bin/rotate-ghcr-pat` (the target)
   - `bin/restore-hub-ghcr-pat` (the reference implementation — mirror its patterns)
   - `scripts/plugins/shopping_cart.sh` lines 240–300 (`_shopping_cart_ghcr_pat_can_pull`,
     `_shopping_cart_store_ghcr_pat_in_vault`) and line 625 (`_shopping_cart_resolve_app_context`)
   - `scripts/tests/bin/alertmanager_auth_proxy.bats` (BATS style for `bin/` scripts)

## Change 1 — source the libraries and resolve the context

**OLD** (lines 14–16):

```bash
set -euo pipefail

SHOPPING_CART_ORG="${SHOPPING_CART_ORG:-wilddog64}"
```

**NEW:**

```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/system.sh
source "${REPO_ROOT}/scripts/lib/system.sh"
# shellcheck source=scripts/lib/core.sh
source "${REPO_ROOT}/scripts/lib/core.sh"
# shellcheck source=scripts/plugins/shopping_cart.sh
source "${REPO_ROOT}/scripts/plugins/shopping_cart.sh"

SHOPPING_CART_ORG="${SHOPPING_CART_ORG:-wilddog64}"
HUB_CONTEXT="${HUB_CONTEXT:-k3d-k3d-cluster}"
TARGET_CONTEXT="${TARGET_CONTEXT:-$(_shopping_cart_resolve_app_context)}"
_vault_local_port="${VAULT_LOCAL_PORT:-18200}"
```

Also update the `# Environment:` header comment block to document `HUB_CONTEXT`,
`TARGET_CONTEXT` and `VAULT_LOCAL_PORT`.

## Change 2 — read the Vault PAT via a header file, and validate it by pull

**OLD** (lines 29–51):

```bash
if [[ -t 0 ]]; then
  # Try to read from Vault first
  _vault_root_token=$(kubectl get secret vault-root -n secrets --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' | base64 -d 2>/dev/null || true)
  if [[ -n "$_vault_root_token" ]]; then
    TOKEN=$(curl -s -H "X-Vault-Token: ${_vault_root_token}" "http://localhost:18200/v1/secret/data/github/pat" | jq -r '.data.data.token // empty' 2>/dev/null || true)
  fi

  if [[ -n "${TOKEN:-}" ]]; then
    _pat_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${SHOPPING_CART_ORG}:${TOKEN}" "https://api.github.com/user" 2>/dev/null || true)
    if [[ "$_pat_http" == "200" ]]; then
      echo "Using PAT from Vault..."
    else
      echo "⚠️  Vault PAT is expired (HTTP ${_pat_http}) — please paste a new one" >&2
      TOKEN=""
    fi
  fi
  if [[ -z "${TOKEN:-}" ]]; then
    read -r -s -p "Paste new GitHub PAT (repo + read:packages) and press Enter: " TOKEN
    echo ""
  fi
else
  read -r TOKEN
fi
```

**NEW:**

```bash
if [[ -t 0 ]]; then
  _vault_root_token=$(kubectl get secret vault-root -n secrets --context "${HUB_CONTEXT}" \
    -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d 2>/dev/null || true)
  if [[ -n "${_vault_root_token}" ]]; then
    _hdr=$(_seed_vault_header_file "${_vault_root_token}") || _hdr=""
    if [[ -n "${_hdr}" ]]; then
      TOKEN=$(curl -s --config "${_hdr}" \
        "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" \
        | jq -r '.data.data.token // empty' 2>/dev/null || true)
      rm -f "${_hdr}"
    fi
  fi

  if [[ -n "${TOKEN:-}" ]]; then
    if _shopping_cart_ghcr_pat_can_pull "${SHOPPING_CART_ORG}" "${TOKEN}"; then
      _info "using PAT from Vault — verified it can pull from ghcr.io"
    else
      _warn "the PAT in Vault cannot pull from ghcr.io — please paste a new one"
      TOKEN=""
    fi
  fi

  if [[ -z "${TOKEN:-}" ]]; then
    read -r -s -p "Paste new GitHub PAT (repo + read:packages) and press Enter: " TOKEN
    echo ""
  fi
else
  read -r TOKEN
fi
```

## Change 3 — refuse a PAT that cannot pull, before anything is persisted

**OLD** (lines 53–71):

```bash
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: No token provided — exiting" >&2
  exit 1
fi

if [[ -z "${_vault_root_token:-}" ]]; then
  _vault_root_token=$(kubectl get secret vault-root -n secrets --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

if [[ -n "${TOKEN}" && -n "${_vault_root_token:-}" ]]; then
  echo "Saving new token to Vault..."
  if curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" \
    -d "{\"data\": {\"token\": \"${TOKEN}\"}}" \
    "http://localhost:18200/v1/secret/data/github/pat" >/dev/null; then
    echo "  ✅ Token persisted to Vault"
  else
    echo "  ⚠️ Failed to save token to Vault — you may need to re-paste after acg-down" >&2
  fi
fi
```

**NEW:**

```bash
if [[ -z "${TOKEN:-}" ]]; then
  _err "no token provided — exiting"
fi

if ! _shopping_cart_ghcr_pat_can_pull "${SHOPPING_CART_ORG}" "${TOKEN}"; then
  TOKEN=""
  _err "that PAT cannot pull from ghcr.io — it is missing the read:packages scope. Nothing was written or pushed. Mint a classic PAT with read:packages at https://github.com/settings/tokens"
fi
_info "PAT verified — it can pull from ghcr.io"

if [[ -z "${_vault_root_token:-}" ]]; then
  _vault_root_token=$(kubectl get secret vault-root -n secrets --context "${HUB_CONTEXT}" \
    -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

if [[ -n "${_vault_root_token:-}" ]]; then
  if _shopping_cart_store_ghcr_pat_in_vault "${TOKEN}"; then
    _info "token persisted to Vault at secret/github/pat"
  else
    _warn "failed to save token to Vault — you may need to re-paste after acg-down"
  fi
else
  _warn "no Vault root token available — skipping the Vault write"
fi
```

## Change 4 — ESO-aware cluster propagation with no PAT in argv

**OLD** (lines 89–114):

```bash
# --- Cluster Update (Quick Fix) -------------------------------------------

echo ""
echo "Propagating ghcr-pull-secret to ubuntu-k3s cluster..."
echo ""

NAMESPACES=(
  shopping-cart-apps
  shopping-cart-payment
  shopping-cart-data
)

for ns in "${NAMESPACES[@]}"; do
  if kubectl create secret docker-registry ghcr-pull-secret \
    --docker-server=ghcr.io \
    --docker-username="${SHOPPING_CART_ORG}" \
    --docker-password="${TOKEN}" \
    --context ubuntu-k3s \
    -n "$ns" \
    --dry-run=client -o yaml \
    | kubectl apply --context ubuntu-k3s -f - >/dev/null 2>&1; then
    echo "  ✅ namespace: ${ns}"
  else
    echo "  ❌ namespace: ${ns} — check kubectl connectivity and context" >&2
  fi
done
```

**NEW:**

```bash
# --- Cluster Update --------------------------------------------------------

echo ""
_info "propagating ghcr-pull-secret to context ${TARGET_CONTEXT}"
echo ""

NAMESPACES=(
  shopping-cart-apps
  shopping-cart-payment
  shopping-cart-data
)

_auth=$(printf '%s:%s' "${SHOPPING_CART_ORG}" "${TOKEN}" | base64 | tr -d '\n')
_dockercfg=$(printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' "${_auth}" | base64 | tr -d '\n')
_auth=""
_sync_ts="$(date +%s)"

for ns in "${NAMESPACES[@]}"; do
  if kubectl get externalsecret ghcr-pull-secret -n "${ns}" --context "${TARGET_CONTEXT}" >/dev/null 2>&1; then
    if kubectl annotate externalsecret ghcr-pull-secret -n "${ns}" --context "${TARGET_CONTEXT}" \
      force-sync="${_sync_ts}" --overwrite >/dev/null 2>&1; then
      _info "namespace ${ns}: ESO-managed — force-sync triggered"
    else
      _warn "namespace ${ns}: could not annotate the ExternalSecret"
    fi
    continue
  fi

  _manifest=$(mktemp) && chmod 0600 "${_manifest}"
  cat > "${_manifest}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ghcr-pull-secret
  namespace: ${ns}
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: ${_dockercfg}
EOF
  if kubectl apply --context "${TARGET_CONTEXT}" -f "${_manifest}" >/dev/null 2>&1; then
    _info "namespace ${ns}: secret applied"
  else
    _warn "namespace ${ns}: apply failed — check kubectl connectivity and context"
  fi
  rm -f "${_manifest}"
done

_dockercfg=""
```

Note: `printf` is a bash builtin, so the PAT never reaches the process table through it. The
manifest is written `0600` and removed immediately after apply.

## Change 5 — BATS coverage

Create `scripts/tests/bin/rotate_ghcr_pat.bats`. Model the style on
`scripts/tests/bin/alertmanager_auth_proxy.bats`. Required assertions:

1. **Context is resolved, not hardcoded** — `grep -cF -- '--context ubuntu-k3s' bin/rotate-ghcr-pat`
   must be `0`, and `grep -F 'TARGET_CONTEXT' bin/rotate-ghcr-pat` must match.
2. **PAT is gated on the pull probe** — `grep -F '_shopping_cart_ghcr_pat_can_pull' bin/rotate-ghcr-pat`
   matches, and it appears **before** the first `gh secret set` line (compare line numbers).
3. **No PAT in argv** — each of these must be `0`:
   - `--docker-password`
   - `-u "${SHOPPING_CART_ORG}:${TOKEN}"`
   - `X-Vault-Token: ${_vault_root_token}`
4. **No `api.github.com/user` auth-only validation** — `grep -cF -- 'api.github.com/user'` is `0`.
5. **ESO branch exists** — `grep -F 'get externalsecret ghcr-pull-secret' bin/rotate-ghcr-pat` matches.

**Every one of these must be verified to fail against the pre-fix file.** Run each pattern against
`git show HEAD:bin/rotate-ghcr-pat > /tmp/old-rotate` first and confirm the count goes non-zero → 0
(or 0 → non-zero). Paste those before/after counts in your report. A gate that reads `0` on both the
old and the new file is vacuous and does not count as coverage.

## Rules

- `shellcheck bin/rotate-ghcr-pat` must pass with **zero new warnings**. Paste the output.
- `bats scripts/tests/bin/rotate_ghcr_pat.bats` must pass. Paste the output.
- Do not run `make test` (~15 min); the targeted suite above is sufficient.
- Double-quote every variable expansion. `set -euo pipefail` stays.
- No inline comments in shell blocks beyond the two already specified.
- LF line endings only.
- Minimal patch — do not refactor the `gh secret set` repo loop, the `pass`/`fail` counters, or the
  final summary output. They are correct.
- Do **not** modify `bin/restore-hub-ghcr-pat`, `scripts/plugins/shopping_cart.sh`, or anything under
  `scripts/lib/foundation/` or `scripts/lib/acg/`.

## Commit message (verbatim)

```
fix(bin): resolve the cluster context and verify GHCR pull in rotate-ghcr-pat

rotate-ghcr-pat hardcoded --context ubuntu-k3s, so running it during a hub
GHCR outage reported success per namespace while changing nothing on the hub.
It also validated the PAT with GET /user, which checks authentication and
never read:packages, and passed the PAT and the Vault root token in argv.

Resolve the target context via _shopping_cart_resolve_app_context, gate every
store and push on _shopping_cart_ghcr_pat_can_pull, write Vault through
_shopping_cart_store_ghcr_pat_in_vault, force-sync the ExternalSecret on
ESO-managed namespaces instead of writing the Secret directly, and build the
dockerconfigjson manifest in a 0600 file so no credential reaches argv.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## Definition of Done

- [ ] Cluster context resolved, never a hardcoded `ubuntu-k3s`
- [ ] PAT gated on `_shopping_cart_ghcr_pat_can_pull` before any store or push
- [ ] No PAT or Vault token in argv, including `--docker-password`
- [ ] Vault write goes through `_shopping_cart_store_ghcr_pat_in_vault`
- [ ] ESO-managed namespaces get a force-sync, not a direct `kubectl create secret`
- [ ] `scripts/tests/bin/rotate_ghcr_pat.bats` added, all gates proven non-vacuous against pre-fix
- [ ] `shellcheck` clean, BATS green, both outputs pasted
- [ ] Committed with the message above, on `k3d-manager-v1.36.0`
- [ ] Pushed — `git rev-parse origin/k3d-manager-v1.36.0` matches your local HEAD
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA

## What NOT to Do

- Do NOT create a PR. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT use `--no-verify`.
- Do NOT hardcode a kube context in a tool that runs against more than one cluster.
- Do NOT treat `GET /user` 200 as evidence a PAT can pull from GHCR.
- Do NOT substitute an `X-OAuth-Scopes` header check — fine-grained PATs omit that header.
- Do NOT `kubectl create secret` a credential on a cluster where ESO owns it — it will be reverted.
- Do NOT run this script against a live cluster to test it. The BATS gates are static-source
  assertions; no cluster access is needed or permitted for this task.
- Do NOT modify files outside `bin/rotate-ghcr-pat`, `scripts/tests/bin/rotate_ghcr_pat.bats`,
  and the two memory-bank files.
