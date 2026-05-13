# acg-up concatenated the Keycloak realm import status with the fallback `000`

## What Happened
`make up` failed during the Keycloak realm import step with:

```text
ERROR: [acg-up] Realm import returned HTTP 409000 — SSO cannot be trusted without a successful realm sync
```

## Root Cause
The import status capture used `curl` plus a fallback `|| echo "000"`. When the realm already existed, Keycloak correctly returned `409`, but the command substitution also appended the fallback string, producing `409000`.

## Fix
- Keep the `curl` HTTP status capture independent from the fallback path.
- Treat an empty capture as `000` after the command finishes, rather than concatenating fallback output into the status string.

## Follow-Up
- Keep `409` reserved for the “realm already exists” reconciliation path.
- Avoid `|| echo ...` in command substitutions that are meant to return a single status token.
