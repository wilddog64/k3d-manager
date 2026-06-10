# Bug: Prometheus basic auth password should be Vault-managed

**Filed:** 2026-06-09
**Source:** /ask agent observation

## Description

Prometheus basic auth is currently bootstrapped with a hardcoded `admin:password`
fallback during deploy, and `make show-service-passwords` prints that same fixed
login. That makes the credentials deterministic, but it also means the password
is not being managed as a first-class Vault secret.

The follow-up should move the Prometheus login to Vault as the canonical source of
truth, then have both the deploy path and the credential-reporting path read the
same stored value. The deploy flow can continue to derive the bcrypt hash for
`prometheus-web-config`, but the plaintext password itself should be stored and
retrieved from Vault instead of being hardcoded in the Makefile output.

## Why this matters

- Keeps the Prometheus login aligned with the other Vault-managed credentials.
- Avoids hardcoding the bootstrap password in repo-facing output.
- Lets `show-service-passwords` display the actual Vault-backed login instead of
  a repo convention.

## Proposed follow-up

1. Store Prometheus basic auth credentials in Vault as the source of truth.
2. Derive the bcrypt hash from that Vault-backed password when rendering
   `prometheus-web-config`.
3. Update `make show-service-passwords` to read and display the same Vault-backed
   login info.
