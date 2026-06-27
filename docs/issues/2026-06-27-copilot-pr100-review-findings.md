# Copilot PR #100 Review Findings

**PR:** #100 — `feat(vault): Tier 3 hub-vault relocation + provider-agnostic auth`
**Branch:** `feat/v1.10.0-vault-auth-portable`
**Fix commit:** `1fd01e24`
**Date:** 2026-06-27

Copilot raised 3 findings, all in `scripts/plugins/vault.sh`. All 3 fixed.

---

## Finding 1 — `vault_install_unseal_watchdog`: unchecked `kubectl apply` return code

**Location:** `scripts/plugins/vault.sh` ~line 919 (Tier 3 P2a watchdog installer)

Copilot: the `kubectl apply` (and `_kubectl apply`) result is never checked. A failed apply
falls through to `_cleanup_on_success` and the function returns 0 — a broken install reports
success.

**Before:**
```bash
   if [[ -n "$app_context" ]]; then
      kubectl apply --context "$app_context" -f "$rendered"
   else
      _kubectl apply -f "$rendered"
   fi
   _cleanup_on_success "$rendered"
```

**After:**
```bash
   if [[ -n "$app_context" ]]; then
      kubectl apply --context "$app_context" -f "$rendered" \
         || _err "[vault] failed to apply unseal watchdog to context '$app_context'"
   else
      _kubectl apply -f "$rendered" \
         || _err "[vault] failed to apply unseal watchdog"
   fi
   _cleanup_on_success "$rendered"
```

Note: the `--context` branch keeps raw `kubectl` deliberately — `_kubectl` is a lib-foundation
subtree passthrough to the ambient current-context and does not accept `--context`. The
actionable defect was the unchecked rc, now guarded with `_err`.

---

## Finding 2 — `configure_vault_app_auth_for_context`: kubeconfig context name ≠ cluster name

**Location:** `scripts/plugins/vault.sh` ~line 1469

Copilot: the server/CA lookup queried `.clusters[?(@.name=="<context>")]`, but in kubeconfig a
context name and its cluster name are independent. The lookup silently returns empty whenever
they differ — directly undermining the provider-agnostic goal of this PR (k3d happens to use
matching names; EKS/AKS/etc. do not).

**Fix:** resolve the cluster name from `.contexts[]` first, fall back to the context name
(preserves prior behavior for matching-name setups), then query `.clusters[]` by cluster name.

```bash
  local cluster_name
  cluster_name="$("${kctl[@]}" config view --raw \
    -o jsonpath="{.contexts[?(@.name==\"${app_context}\")].context.cluster}" 2>/dev/null)"
  [[ -n "${cluster_name}" ]] || cluster_name="${app_context}"

  local server ca_data ca_file
  server="$("${kctl[@]}" config view --raw \
    -o jsonpath="{.clusters[?(@.name==\"${cluster_name}\")].cluster.server}" 2>/dev/null)"
  # ...certificate-authority-data / certificate-authority likewise keyed on ${cluster_name}
```

---

## Finding 3 — CA decode not portable on macOS/BSD

**Location:** `scripts/plugins/vault.sh` ~line 1485

Copilot: `base64 -d` is GNU-only; macOS/BSD `base64` uses `-D`. On macOS the decode fails
silently and the CA is dropped. Precedent fix exists at `scripts/lib/identity_tools.sh:36`.

**Before:**
```bash
    printf '%s' "${ca_data}" | base64 -d > "${tmp_ca}" 2>/dev/null || {
```

**After:**
```bash
    printf '%s' "${ca_data}" | base64 --decode > "${tmp_ca}" 2>/dev/null \
      || printf '%s' "${ca_data}" | base64 -D > "${tmp_ca}" 2>/dev/null || {
```

---

## Verification

- `shellcheck -S warning scripts/plugins/vault.sh` — clean
- `./scripts/k3d-manager _agent_audit` — rc=0
- `bats scripts/tests/plugins/vault_app_auth.bats` — 11/11 pass (incl. the changed
  `configure_vault_app_auth_for_context` path; the context-name fallback keeps the existing
  mock-kubeconfig tests green)
- `bats scripts/tests/etc/hub_vault_profile.bats` — 5/5
- `bats scripts/tests/etc/vault_unseal_watchdog.bats` — 5/5

---

## Process note

The kubeconfig context-vs-cluster-name assumption (Finding 2) is a recurring portability trap
when adding multi-provider support. Future specs that read cluster server/CA from kubeconfig
should resolve `.contexts[].context.cluster` first, never key `.clusters[]` on the context name.
The `base64 -d` vs `--decode||-D` portability rule already has prior art — new base64 decodes in
plugin code should use the dual-flag idiom from `identity_tools.sh`.
