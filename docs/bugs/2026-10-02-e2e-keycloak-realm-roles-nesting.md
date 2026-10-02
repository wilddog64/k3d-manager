# Bug: the substrate Keycloak realm import fails because `roles.realm` is nested one level too deep

**Status:** OPEN
**Branch:** `k3d-manager-v1.40.0`
**File:** `scripts/etc/e2e/keycloak.yaml`
**Tests:** `scripts/tests/plugins/e2e.bats`
**Introduced by:** `570734c7 fix(e2e): add a substrate Keycloak so payment tests use a real token` (2026-10-02)

## Symptom

`make e2e` run `1790961998-24160` reached the Keycloak rollout for the first time. Every earlier
run had failed at an earlier step. Keycloak then went into `Error` with 2 restarts, and the rollout
timed out after 300s. From `~/.k3dm/e2e/1790961998-24160.substrate.txt`:

```
ERROR: Failed to import realms
ERROR: Cannot deserialize value of type `java.util.ArrayList<org.keycloak.representations.idm.RoleRepresentation>` from Object value (token `JsonToken.START_OBJECT`)
 ... RealmRepresentation["roles"]->RolesRepresentation["realm"])
```

## Root cause

In Keycloak's `RolesRepresentation`, `realm` is a **list** of roles. The ConfigMap wraps that
list in another `{"roles": [...]}` object.

## Fix (`scripts/etc/e2e/keycloak.yaml`)

Old:
```json
      "roles": {
        "realm": {
          "roles": [
            {"name": "PAYMENT_USER"},
            {"name": "PAYMENT_WRITE"}
          ]
        }
      },
```
New:
```json
      "roles": {
        "realm": [
          {"name": "PAYMENT_USER"},
          {"name": "PAYMENT_WRITE"}
        ]
      },
```

## Test (append to `scripts/tests/plugins/e2e.bats`)

```bash
@test "substrate Keycloak realm lists realm roles as an array" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  run python3 - "${BATS_TEST_DIRNAME}/../../etc/e2e/keycloak.yaml" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
block = re.search(r"shopping-cart-realm\.json: \|\n((?:    .*\n|\n)+)", text).group(1)
realm = json.loads("\n".join(l[4:] for l in block.splitlines()))
roles = realm["roles"]["realm"]
assert isinstance(roles, list), type(roles)
assert {r["name"] for r in roles} >= {"PAYMENT_USER", "PAYMENT_WRITE"}
PY
  [ "$status" -eq 0 ]
}
```

The `${E2E_KC_CLIENT_SECRET}` placeholder sits inside a JSON string, so the block parses without
substituting it. If the regex fails to find the block, fix the regex, not the assertion.

**Mutation check (must report):** restore the old nested form, and the test goes red. Put the fix
back, and the test is green.

## Definition of Done

- [ ] Fix applied; test added; `bats scripts/tests/plugins/e2e.bats` all green (paste the summary)
- [ ] Mutation result reported
- [ ] Status line set to `FIXED (<short sha>)`
- [ ] Commit message: `fix(e2e): realm roles must be a list in the substrate Keycloak import`

## What NOT to Do

- Do NOT create a PR, skip hooks, commit to `main`, or touch files outside the two listed above
  (plus this doc)
- Do NOT run `make e2e`
