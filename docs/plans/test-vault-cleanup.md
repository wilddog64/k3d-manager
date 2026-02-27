# Plan: test_vault — Revert Non-Fatal Pod Test Workaround

**Date:** 2026-02-27
**Status:** Ready for implementation
**Branch:** `fix/test-vault-cleanup` (create from `main`)
**Related:** `docs/issues/2026-02-27-vault-auth-delegator-helm-managed.md`

---

## Background

During Stage 2 CI debugging on m2-air, the `test_vault` projected SA token test (vault-read
pod) was temporarily made non-fatal. At the time, the vault service account was missing the
`system:auth-delegator` ClusterRoleBinding, so the pod's projected SA token was rejected by
the TokenReview API with HTTP 403.

The workaround at `scripts/lib/test.sh` lines 780–793 downgrades the failure to a warning
and falls through to a `kubectl create token` test as the "authoritative" validation. The
comment calls this a "known OrbStack/k3s limitation" — but the actual root cause was the
missing ClusterRoleBinding, which is now fixed in `deploy_vault`.

**Both fixes are now in place:**
- `vault.sh`: adds `vault-auth-delegator` ClusterRoleBinding in both k8s auth setup paths
- Vault Helm chart: `server.authDelegator.enabled=true` creates `vault-server-binding` by default

The non-fatal workaround should be reverted so that any future regression in vault RBAC is
caught immediately rather than silently bypassed.

---

## Scope

**One file:** `scripts/lib/test.sh`

**Change:** Lines 780–793 — replace non-fatal warning block with a hard-fail `_err`.

---

## Before (current code, lines 780–793)

```bash
  if [[ "$secret" != "$secret_val" ]]; then
    # Projected SA token auth failed from the vault-read pod. This is a known
    # limitation on OrbStack/k3s where Vault can't validate projected SA tokens
    # (either TokenReview RBAC is missing or strict audience validation applies).
    # Log diagnostics and fall through to the kubectl-create-token auth test,
    # which is the authoritative k8s auth validation for this cluster.
    _info "WARNING: vault-read pod projected SA token auth failed (known OrbStack/k3s limitation)"
    _info "Vault k8s auth config (for diagnosis):"
    _kubectl -n "$vault_ns" exec "$vault_pod" -- \
      sh -c "VAULT_TOKEN='$root_token' vault read auth/kubernetes/config" 2>/dev/null || true
    _info "vault-read pod logs:"
    _kubectl -n "$test_ns" logs vault-read 2>/dev/null || true
    _info "Continuing with kubectl-create-token auth test as authoritative validation..."
  fi
```

## After (target code)

```bash
  if [[ "$secret" != "$secret_val" ]]; then
    _info "vault-read pod logs:"
    _kubectl -n "$test_ns" logs vault-read 2>/dev/null || true
    _err "Vault pod projected SA token auth failed — expected '$secret_val', got '$secret'"
  fi
```

Keep the `kubectl create token` secondary test (lines 795–806) unchanged. It validates a
different auth path (explicitly created token vs auto-mounted projected SA token) and is
a useful defense-in-depth check.

---

## Implementation Steps

1. **Create branch** from `main`:
   ```bash
   git checkout main && git pull
   git checkout -b fix/test-vault-cleanup
   ```

2. **Edit `scripts/lib/test.sh`** (lines 780–793):
   Replace the non-fatal warning block with the hard-fail block shown above.
   Use the Edit tool — old_string must match exactly.

3. **Verify the change** looks correct:
   ```bash
   sed -n '775,810p' scripts/lib/test.sh
   ```

4. **Commit:**
   ```bash
   git add scripts/lib/test.sh
   git commit -m "test_vault: revert non-fatal pod test workaround to hard-fail

   The system:auth-delegator ClusterRoleBinding is now added by deploy_vault
   (vault-auth-delegator + Helm-managed vault-server-binding). The projected
   SA token test should pass on all supported clusters. Revert the soft-failure
   path so future RBAC regressions are caught immediately."
   ```

5. **Update memory-bank** — mark this task `[x]` in `memory-bank/progress.md` after
   Gemini validates.

---

## Validation (Gemini — m2-air or m4-air)

Run on a cluster where `deploy_vault` was run with the current `vault.sh`:

```bash
# 0. Confirm cluster is healthy
kubectl get nodes

# 1. Confirm vault-auth-delegator binding exists
kubectl get clusterrolebinding vault-auth-delegator -o yaml | grep system:auth-delegator

# 2. Run test_vault
PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_vault

# Expected: "Vault test succeeded" with no WARNING lines.
# If the pod test fails with _err, the RBAC setup is incomplete.
```

The test output must contain `Vault test succeeded` without any
`WARNING: vault-read pod projected SA token auth failed` line.

---

## Acceptance Criteria

- [ ] `test_vault` passes on m2-air (k3s via Parallels) with no non-fatal warning
- [ ] `test_vault` passes on m4-air/OrbStack with no non-fatal warning
- [ ] No `WARNING: vault-read pod` line in test output
- [ ] `memory-bank/progress.md` updated to `[x]` after Gemini validation
