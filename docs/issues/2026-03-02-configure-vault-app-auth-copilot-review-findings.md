# Issue: Copilot PR #16 Review — configure_vault_app_auth findings

## Date
2026-03-02

## PR
[#16 feat(vault): configure_vault_app_auth — v0.6.0](https://github.com/wilddog64/k3d-manager/pull/16)

## Reviewer
`copilot-pull-request-reviewer` (GitHub Copilot)

---

## Finding 1 — `disable_local_ca_jwt=true` has wrong semantics (Critical)

**File:** `scripts/plugins/vault.sh` line 1268

**Problem:** The flag `disable_local_ca_jwt=true` was used with a comment saying "local JWT
validation, no outbound call to Ubuntu API". This is the opposite of what the flag does.
`disable_local_ca_jwt=true` disables local CA JWT validation and forces Vault to use
**TokenReview mode** — which requires network access to the Kubernetes API and a
`token_reviewer_jwt`. Without setting `token_reviewer_jwt`, the mount would fail to
authenticate any JWT.

**Fix:** Removed `disable_local_ca_jwt=true` entirely. The default Vault behavior (without the
flag) is local CA cert validation using `kubernetes_ca_cert` — which is exactly what was
intended: no outbound TokenReview API calls, no `token_reviewer_jwt` needed.

**Status:** FIXED — commit `b9bda33`

---

## Finding 2 — Unquoted shell variables in `vault write role` command (Medium)

**File:** `scripts/plugins/vault.sh` line 1289

**Problem:** Variables `$eso_sa`, `$eso_ns`, `$mount`, and `$role` were interpolated into a
command string passed to `_vault_exec` (which evaluates via `sh -lc`) without escaping.
Values containing spaces or shell metacharacters could break the command or allow unintended
shell expansion.

**Fix:** Added `printf -v '%q'` quoting for `$eso_sa` and `$eso_ns` before interpolation
into the `vault write` command string.

**Status:** FIXED — commit `b9bda33`

---

## Finding 3 — Bats test asserted removed flag (Low)

**File:** `scripts/tests/plugins/vault_app_auth.bats` line 143

**Problem:** The test suite asserted `grep -q "disable_local_ca_jwt=true"` which locked in
the buggy behavior from Finding 1. Once the flag was removed, the test would fail.

**Fix:** Updated assertion to `grep -q "kubernetes_ca_cert=@/tmp/app-cluster-ca.crt"` which
validates the correct local CA cert config path.

**Status:** FIXED — commit `b9bda33`

---

## Finding 4 — CHANGE.md description was misleading (Low)

**File:** `CHANGE.md` line 14

**Problem:** The changelog described `disable_local_ca_jwt=true` as "local JWT validation
without requiring network access from the Vault pod to the Ubuntu k3s API" — the exact
opposite of what the flag does. Operators relying on this description during incident
response would be misled.

**Fix:** Updated to accurately describe the default local CA cert validation behavior: "Vault
verifies ESO's JWT against the provided app cluster CA cert without calling the Ubuntu k3s
TokenReview API (no `token_reviewer_jwt` needed)."

**Status:** FIXED — commit `b9bda33`

---

## Verification

- `shellcheck -S error scripts/plugins/vault.sh` — clean
- `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/vault_app_auth.bats` — 6/6 pass
- CI lint + stage2 — both pass on commit `b9bda33`
