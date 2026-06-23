# Bugfix: v1.8.0 — worker-setup secret paste-swap + OAuth fallback

**Branch (implement on a NEW branch off main):** `fix/worker-setup-secret-validation-oauth-fallback`
**Files:** `bin/k3dm-worker-setup`, `Makefile`

---

## Problem

`bin/k3dm-worker-setup --rotate` prompts for three secrets (Cloudflare API token,
Slack signing secret, webhook token) in one undifferentiated flow with hidden input.
During a real rotation (2026-06-23) the signing secret got pasted into the Cloudflare
API-token prompt; the script silently stored it in Keychain **and pushed it to the
GitHub `CLOUDFLARE_API_TOKEN` secret** before failing at deploy. Two distinct defects:

1. **No per-secret validation** — any non-empty string is accepted, so a paste-swap
   (signing secret ↔ CF token) is stored and propagated with no warning.
2. **No OAuth fallback** — both the script (line ~97) and the `deploy-worker` Make
   target force `export CLOUDFLARE_API_TOKEN=<keychain value>`. When that value is
   missing or malformed, wrangler fails with `Authentication error 6111` even though a
   valid `wrangler login` OAuth session exists on the machine. The env var overrides
   OAuth, so a bad stored token blocks deploy entirely.

**Root cause:** generic prompt with no shape/identity check, and an unconditional
`CLOUDFLARE_API_TOKEN` export that shadows wrangler's OAuth credentials.

---

## Reproduction

```
$ bin/k3dm-worker-setup --rotate
# paste the 32-hex signing secret at the "CLOUDFLARE_API_TOKEN" prompt
# -> stored in Keychain + pushed to GitHub with NO error
# -> later: ✘ [ERROR] ... Authentication error [code: 6111]
```
Expected: the CF prompt rejects a value that is not a 40-char token that passes
`tokens/verify`; deploy falls back to OAuth when no valid CF token is present.

---

## Fix

### Change 1 — `bin/k3dm-worker-setup`: add `_validate_secret` helper

**Exact old block (lines 20-26):**

```bash
_keychain_get() {
  security find-generic-password -s "${1}" -a k3dm -w 2>/dev/null || true
}

_keychain_set() {
  security add-generic-password -U -s "${1}" -a k3dm -w "${2}"
}
```

**Exact new block:**

```bash
_keychain_get() {
  security find-generic-password -s "${1}" -a k3dm -w 2>/dev/null || true
}

_keychain_set() {
  security add-generic-password -U -s "${1}" -a k3dm -w "${2}"
}

# Validate a secret by kind before storing/pushing it — guards against paste-swaps.
# Prints a human-readable reason on failure; returns non-zero.
_validate_secret() {
  local kind="$1" val="$2"
  case "${kind}" in
    cf)
      [[ "${val}" =~ ^[A-Za-z0-9_-]{40}$ ]] || { echo "expected a 40-char Cloudflare API token (got ${#val} chars)"; return 1; }
      curl -fsS -o /dev/null "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer ${val}" 2>/dev/null \
        || { echo "Cloudflare rejected the token (tokens/verify failed)"; return 1; }
      ;;
    signing)
      [[ "${val}" =~ ^[a-f0-9]{32}$ ]] || { echo "expected a 32-char hex Slack signing secret"; return 1; }
      ;;
    *) return 0 ;;
  esac
}
```

### Change 2 — `bin/k3dm-worker-setup`: validate inside `_ensure_secret`

**Exact old block (lines 33-54):**

```bash
_ensure_secret() {
  local gh_name="$1"
  local kc_name="$2"
  local hint="$3"
  local _rotate="${4:-false}"

  local _val
  _val="$(_keychain_get "${kc_name}")"

  if [[ -n "${_val}" && "${_rotate}" != "true" ]]; then
    _info "${gh_name}: found in Keychain ✓"
  else
    echo ""
    _info "Secret needed: ${gh_name}"
    _info "${hint}"
    printf "[k3dm-worker-setup] Enter value (input hidden): "
    read -rs _val
    echo ""
    [ -z "${_val}" ] && _error "Empty value — ${gh_name} not set."
    _keychain_set "${kc_name}" "${_val}"
    _info "Stored in Keychain: ${kc_name}"
  fi
```

**Exact new block:**

```bash
_ensure_secret() {
  local gh_name="$1"
  local kc_name="$2"
  local hint="$3"
  local _rotate="${4:-false}"
  local _kind="${5:-}"

  local _val
  _val="$(_keychain_get "${kc_name}")"

  if [[ -n "${_val}" && "${_rotate}" != "true" ]]; then
    _info "${gh_name}: found in Keychain ✓"
  else
    echo ""
    _info "Secret needed: ${gh_name}"
    _info "${hint}"
    printf "[k3dm-worker-setup] Enter value (input hidden): "
    read -rs _val
    echo ""
    [ -z "${_val}" ] && _error "Empty value — ${gh_name} not set."
    if [[ -n "${_kind}" ]]; then
      local _why
      _why="$(_validate_secret "${_kind}" "${_val}")" \
        || _error "${gh_name}: rejected — ${_why}. Did you paste the wrong secret? (CF token = 40 chars; signing secret = 32 hex)"
    fi
    _keychain_set "${kc_name}" "${_val}"
    _info "Stored in Keychain: ${kc_name}"
  fi
```

### Change 3 — `bin/k3dm-worker-setup`: pass the kind at both call sites

**Exact old block (lines 70-76):**

```bash
_ensure_secret "CLOUDFLARE_API_TOKEN"  "k3dm-cloudflare-api-token" \
  "Get from: dash.cloudflare.com → My Profile → API Tokens → 'Edit Cloudflare Workers' template" \
  "${_rotate}"

_ensure_secret "SLACK_SIGNING_SECRET" "k3dm-slack-signing-secret" \
  "Get from: api.slack.com/apps → your app → Basic Information → Signing Secret" \
  "${_rotate}"
```

**Exact new block:**

```bash
_ensure_secret "CLOUDFLARE_API_TOKEN"  "k3dm-cloudflare-api-token" \
  "Get from: dash.cloudflare.com → My Profile → API Tokens → 'Edit Cloudflare Workers' template" \
  "${_rotate}" "cf"

_ensure_secret "SLACK_SIGNING_SECRET" "k3dm-slack-signing-secret" \
  "Get from: api.slack.com/apps → your app → Basic Information → Signing Secret" \
  "${_rotate}" "signing"
```

### Change 4 — `bin/k3dm-worker-setup`: OAuth fallback in deploy

**Exact old block (lines 90-100):**

```bash
echo ""
_info "Deploying Cloudflare Worker..."

_cf_token="$(_keychain_get "k3dm-cloudflare-api-token")"
_signing_secret="$(_keychain_get "k3dm-slack-signing-secret")"

cd "${WORKER_DIR}"
export CLOUDFLARE_API_TOKEN="${_cf_token}"
printf '%s' "${_webhook_token}" | npx --yes wrangler secret put WEBHOOK_TOKEN
printf '%s' "${_signing_secret}" | npx --yes wrangler secret put SLACK_SIGNING_SECRET
npx --yes wrangler deploy
```

**Exact new block:**

```bash
echo ""
_info "Deploying Cloudflare Worker..."

_cf_token="$(_keychain_get "k3dm-cloudflare-api-token")"
_signing_secret="$(_keychain_get "k3dm-slack-signing-secret")"

cd "${WORKER_DIR}"
if [[ -n "${_cf_token}" ]] && _validate_secret cf "${_cf_token}" >/dev/null 2>&1; then
  export CLOUDFLARE_API_TOKEN="${_cf_token}"
  _info "Auth: Cloudflare API token (Keychain)"
else
  unset CLOUDFLARE_API_TOKEN
  if npx --yes wrangler whoami >/dev/null 2>&1; then
    _info "Auth: wrangler OAuth login (no valid Keychain CF token)"
  else
    _error "No valid Cloudflare API token and no wrangler OAuth login — run: npx wrangler login"
  fi
fi
printf '%s' "${_webhook_token}" | npx --yes wrangler secret put WEBHOOK_TOKEN
printf '%s' "${_signing_secret}" | npx --yes wrangler secret put SLACK_SIGNING_SECRET
npx --yes wrangler deploy
```

### Change 5 — `Makefile`: OAuth fallback in `deploy-worker`

**Exact old block (lines 264-272):**

```make
## Re-deploy Cloudflare Worker and sync secrets from Keychain (run after Worker code changes)
deploy-worker:
	@_cf=$$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -w 2>/dev/null) && \
	_tok=$$(security find-generic-password -s k3dm-webhook-token -a k3dm -w 2>/dev/null) && \
	_sig=$$(security find-generic-password -s k3dm-slack-signing-secret -a k3dm -w 2>/dev/null) && \
	cd workers/slack-relay && \
	printf '%s' "$$_tok" | CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler secret put WEBHOOK_TOKEN && \
	printf '%s' "$$_sig" | CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler secret put SLACK_SIGNING_SECRET && \
	CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler deploy
```

**Exact new block:**

```make
## Re-deploy Cloudflare Worker and sync secrets from Keychain (run after Worker code changes)
deploy-worker:
	@_cf=$$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -w 2>/dev/null); \
	_tok=$$(security find-generic-password -s k3dm-webhook-token -a k3dm -w 2>/dev/null); \
	_sig=$$(security find-generic-password -s k3dm-slack-signing-secret -a k3dm -w 2>/dev/null); \
	if [ -n "$$_cf" ] && curl -fsS -o /dev/null https://api.cloudflare.com/client/v4/user/tokens/verify -H "Authorization: Bearer $$_cf" 2>/dev/null; then \
	  export CLOUDFLARE_API_TOKEN="$$_cf"; echo "Auth: Cloudflare API token"; \
	else \
	  unset CLOUDFLARE_API_TOKEN; \
	  npx --yes wrangler whoami >/dev/null 2>&1 || { echo "ERROR: no valid CF token and no wrangler OAuth login — run: npx wrangler login"; exit 1; }; \
	  echo "Auth: wrangler OAuth login"; \
	fi; \
	cd workers/slack-relay && \
	printf '%s' "$$_tok" | npx --yes wrangler secret put WEBHOOK_TOKEN && \
	printf '%s' "$$_sig" | npx --yes wrangler secret put SLACK_SIGNING_SECRET && \
	npx --yes wrangler deploy
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-worker-setup` | add `_validate_secret`; validate in `_ensure_secret`; pass kind at call sites; OAuth fallback in deploy |
| `Makefile` | `deploy-worker`: OAuth fallback when Keychain CF token missing/invalid |

---

## Rules

- `shellcheck -S warning bin/k3dm-worker-setup` — zero new warnings
- `bash -n bin/k3dm-worker-setup` — parses clean
- `make -n deploy-worker` — recipe expands without syntax error (do NOT actually deploy)
- `./scripts/k3d-manager _agent_audit` — passes (no bare sudo, no inline creds, no hardcoded IPs)
- No other files touched. Do NOT hardcode any token value.

---

## Definition of Done

- [ ] `_validate_secret` rejects a 32-hex value at the `cf` prompt and a 40-char value at the `signing` prompt
- [ ] deploy uses OAuth when the Keychain CF token is absent/invalid; errors clearly when neither auth is available
- [ ] `shellcheck`, `bash -n`, `make -n deploy-worker`, `_agent_audit` all pass
- [ ] Committed and pushed to `fix/worker-setup-secret-validation-oauth-fallback`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(worker-setup): validate secrets by kind + fall back to wrangler OAuth
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-worker-setup` and `Makefile`
- Do NOT commit to `main` — work on `fix/worker-setup-secret-validation-oauth-fallback`
- Do NOT run an actual `wrangler deploy` or push any secret during verification
