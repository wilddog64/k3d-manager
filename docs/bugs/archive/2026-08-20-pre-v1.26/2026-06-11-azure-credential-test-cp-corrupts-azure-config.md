# Bug: azure credential-test cp -r corrupts ~/.azure on subsequent runs

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**Fix commit:** `6e1c08b`

---

## Symptom

After `make credential-test PROVIDER=azure` succeeds once, the next run fails:

```
[az] ERROR: AADSTS50126: Error validating credentials due to invalid username or password.
[az] Run the command below to authenticate interactively; additional arguments may be added as needed:
[az] az logout
[az] az login
INFO: Azure portal URL: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Azure screenshot: /Users/cliang/.local/share/k3d-manager/screenshots/k3dm-azure-<ts>.png
make: *** [credential-test] Error 1
```

The portal branch (`_az_portal_valid`) runs even though SP credentials
(`AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET`) are present in the sandbox UI.

---

## Root Cause

The original `_write_azure_credentials` implementation (commit `37f0cc0`, later reverted)
used an isolated `AZURE_CONFIG_DIR` temp directory for `az login`, then did:

```bash
cp -r "$config_dir/." "${HOME}/.azure/"
```

This overwrote `~/.azure` with the probe's isolated config. On the next run, `az` operations
against the corrupted `~/.azure` produced unexpected behavior — specifically, `az account show`
and related calls used stale/invalid session state, causing the SP validation probe inside
`_az_login_probe_clean` to behave differently. The net result was that the SP branch silently
failed or the extraction produced no `AZURE_CLIENT_ID`, falling through to the portal branch
which fails with `AADSTS50126` on MFA-enforced tenants.

---

## Fix

Replaced `cp -r` with a direct `az login --service-principal` to the default `~/.azure`
(no isolated config dir). This is equivalent to what AWS does with `_write_aws_credentials`
writing directly to `~/.aws/credentials`:

```bash
_write_azure_credentials() {
  local client_id secret tenant
  client_id=$(grep '^AZURE_CLIENT_ID=' "$_tmpout" | cut -d= -f2-)
  secret=$(grep '^AZURE_CLIENT_SECRET=' "$_tmpout" | cut -d= -f2-)
  tenant=$(grep '^AZURE_TENANT_ID=' "$_tmpout" | cut -d= -f2-)
  [[ -n "$client_id" && -n "$secret" && -n "$tenant" ]] || return 0
  az login \
    --service-principal \
    -u "$client_id" \
    -p "$secret" \
    --tenant "$tenant" \
    --allow-no-subscriptions \
    --output none 2>/dev/null || true
  printf 'INFO: Azure SP credentials persisted to ~/.azure\n' >&2
}
```

---

## Process Note

The `cp -r` pattern is unsafe for any config directory that maintains internal consistency
(tokens, subscription state, access token cache). Always use the native CLI login command
to persist credentials rather than copying the isolated probe directory.
