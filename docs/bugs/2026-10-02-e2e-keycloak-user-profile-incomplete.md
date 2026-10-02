# Bug: e2e Keycloak user has no profile attributes, so every payments token request fails "Account is not fully set up"

**Filed:** 2026-10-02
**Status:** OPEN — dispatched to Codex 2026-10-02
**Branch:** `k3d-manager-v1.41.0`
**Found by:** live Tier 1 `make e2e` run `1790968818-9643` (image `shopping-cart-e2e-tests:sha-35098aca…`): 48 passed, 8 failed, all `api/payments.spec.ts`
**Related:** `docs/bugs/archive/2026-08-20-pre-v1.26/2026-07-23-smoke-login-keycloak-user-profile-attributes.md` (same root cause, smoke user), `docs/bugs/2026-10-02-e2e-keycloak-token-request-sent-as-json.md` (previous blocker, now fixed)

## Symptom

Every `api/payments.spec.ts` test fails on the token request:

```
Error: Keycloak <redacted> failed: 400 {"error":"invalid_grant","error_description":"Account is not fully set up"}
```

The token request itself now works: e2e-tests PR #10 fixed the JSON body, and Keycloak accepts the form-encoded grant.

## Root cause

The substrate runs `quay.io/keycloak/keycloak:24.0`. Keycloak 24 turns on the declarative User Profile by default, and it requires `email`, `firstName` and `lastName`. A user without them has an incomplete profile, and the direct-access (password) grant refuses to issue a token. The realm import in `scripts/etc/e2e/keycloak.yaml` creates `e2e-user` with none of the three. The smoke user had the same defect (2026-07-23 bug), and adding the three attributes fixed it there.

## Fix

### S1: `scripts/etc/e2e/keycloak.yaml`

Old:
```
          "username": "e2e-user",
          "enabled": true,
          "emailVerified": true,
```
New:
```
          "username": "e2e-user",
          "enabled": true,
          "email": "e2e-user@example.invalid",
          "firstName": "E2E",
          "lastName": "User",
          "emailVerified": true,
```

### S2: `scripts/tests/plugins/e2e.bats`

Add this test directly after the existing `@test "substrate Keycloak realm lists realm roles as an array"` block:

```bash
@test "substrate Keycloak e2e-user has a complete Keycloak 24 user profile" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  run python3 - "${BATS_TEST_DIRNAME}/../../etc/e2e/keycloak.yaml" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
block = re.search(r"shopping-cart-realm\.json: \|\n((?:    .*\n|\n)+)", text).group(1)
realm = json.loads("\n".join(l[4:] for l in block.splitlines()))
user = next(u for u in realm["users"] if u["username"] == "e2e-user")
missing = [k for k in ("email", "firstName", "lastName") if not user.get(k)]
assert not missing, missing
PY
  [ "$status" -eq 0 ]
}
```

## Gate (paste output)

1. `bats scripts/tests/plugins/e2e.bats` reports 0 failures.
2. `bats scripts/tests/plugins/e2e.bats -f "complete Keycloak 24 user profile"` passes. Then remove the `"firstName": "E2E",` line from `scripts/etc/e2e/keycloak.yaml` and rerun it; it must FAIL. Restore the line, and confirm `git diff --stat` shows only the 2 spec files.
3. `grep -rnE '^[[:space:]]*! ' scripts/tests --include='*.bats'` prints nothing.

## Definition of Done

- [ ] S1 and S2 applied exactly; only `scripts/etc/e2e/keycloak.yaml` and `scripts/tests/plugins/e2e.bats` changed
- [ ] Gates 1–3 output pasted
- [ ] Commit message: `fix(e2e): give the substrate Keycloak e2e-user a complete user profile`
- [ ] Pushed to `origin/k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than the 2 listed
- Do NOT commit to `main`
- Do NOT edit memory-bank
