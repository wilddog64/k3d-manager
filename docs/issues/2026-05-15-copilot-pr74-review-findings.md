# Copilot PR #74 Review Findings

**PR:** #74 — fix(acg): skip sandbox navigation only when already on sandbox URL
**Fix commit:** `6e5a050d`

---

## Finding 1 — `acg_extend.js`: `includes()` on full URL risks false positives

**File:** `scripts/lib/acg/playwright/acg_extend.js` line 126–127

**What Copilot flagged:** `currentUrl.includes(...)` checks the entire URL string including query parameters and fragments. A URL like `https://example.com/page?redirect=hands-on/playground/cloud-sandboxes` would incorrectly match.

**Fix:** Parse `currentUrl` with `new URL()` and check only `parsedUrl.pathname`. Wrap in try/catch for malformed URLs (same pattern as the original `isPluralsight` code it replaced).

**Root cause:** The initial fix was simplified for clarity but overlooked that `includes()` on the full URL is imprecise.

---

## Finding 2 — PR scope too broad for description

**File:** `scripts/lib/acg/playwright/acg_extend.js` line 133

**What Copilot flagged:** The PR description focuses on the `acg_extend.js` navigation fix but the branch includes many other changes (identity, ESO, Vault, ArgoCD, bin scripts).

**Resolution:** This is a milestone branch (`k3d-manager-v1.4.5`) — the branch accumulates the full milestone's work. The acg_extend fix is the last functional commit; all other changes shipped via prior PRs on this branch or are docs/memory-bank only.

**Process note:** For future milestone branches, add a Notes section to the PR body explicitly calling out that this is a milestone branch and naming the single functional change being reviewed.

---

## Finding 3 — `keycloak.sh`: `PGPASSWORD` visible in kubectl exec command line

**File:** `scripts/plugins/keycloak.sh` line 342

**What Copilot flagged:** The database password was passed as an `env VAR=value` argument in the
`kubectl exec` call, embedding it in the host-side command args visible in `ps aux` and shell history.

**Fix:** Switch to `kubectl exec -i` with a bash heredoc so the password is passed via stdin and set as a shell variable inside the pod — not in the kubectl command args. The heredoc exports the variable inside the pod session rather than embedding it in the host-side kubectl argv.

**Root cause:** The `env KEY=value cmd` pattern is common but exposes values in process args. The heredoc + exec -i pattern avoids this.

---

## Finding 4 — `ldap.sh`: ESO function existence not verified after sourcing

**File:** `scripts/plugins/ldap.sh` line 24–30

**What Copilot flagged:** If `eso.sh` is unreadable, the `if [[ -r ... ]]` guard silently skips sourcing. The later call to `_eso_apply_vault_cluster_store` then fails with a cryptic `command not found`. If `eso.sh` exists but doesn't define the function, the same problem occurs.

**Fix:** Add `else` branch erroring when `eso.sh` is unreadable, plus a post-source check that errors if the function still isn't defined after sourcing.

**Root cause:** The guard only protected against sourcing a missing file, not against a missing function after a successful source.

---

## Finding 5 — `vault.sh`: revoke failure silently swallowed

**File:** `scripts/plugins/vault.sh` line 1800–1804

**What Copilot flagged:** When `vault write` revoke fails, the function warns but returns 0. Callers cannot distinguish between a cert not found (benign, return 0) and a failed revoke (error, should propagate).

**Fix:** Return 1 when the revoke write fails. The "cert not found" path already correctly returns 0.

**Root cause:** The `_warn + return 0` pattern was applied uniformly without considering that revoke failure is a real error that callers should see.
