# `bin/vault-exec` returns 403 without Vault auth

## What happened

Running the new troubleshooting helper against a live Vault pod with a `vault kv list` command failed with `403 permission denied`.

## Actual output

```text
╰─❯ bin/vault-exec -namespace secrets -- vault kv list secret/                                                                             
Error making API request.

URL: GET http://127.0.0.1:8200/v1/sys/internal/ui/mounts/secret
Code: 403. Errors:

* permission denied
command terminated with exit code 2
```

## Root cause

The helper was execing into the Vault pod and invoking the `vault` CLI without first authenticating with the live root token from the `vault-root` secret.

## Follow-up

- Auto-login inside `bin/vault-exec` before running `vault ...` commands.
- Keep the raw shell path available for interactive inspection, but do not leave the `vault kv` troubleshooting path unauthenticated.
