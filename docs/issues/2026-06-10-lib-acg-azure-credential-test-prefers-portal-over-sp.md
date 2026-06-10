# Bug: lib-acg Azure credential-test prefers portal login over service-principal validation

## Summary

`make credential-test PROVIDER=azure` now extracts both portal credentials and service-principal fields, but the run still fails on the Azure portal username/password branch before it can use the service-principal credentials:

```text
[az] ERROR: AADSTS50126: Error validating credentials due to invalid username or password. Trace ID: 51434208-b4ed-4058-85a9-0f8e1ac20700 Correlation ID: 75d1f9ee-6ad4-4f68-9f8a-c4c090d0de45 Timestamp: 2026-06-10 03:02:08Z
[az] Run the command below to authenticate interactively; additional arguments may be added as needed:
[az] az logout
[az] az login
INFO: Azure portal URL: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Azure screenshot: /tmp/k3dm-azure-1781060526428.png
make: *** [credential-test] Error 1
```

The extracted Azure payload in the sandbox UI also shows service-principal fields:

- `Application Client ID`
- `Secret`

but the credential-test still exits on the portal-login failure.

## Root Cause

`bin/acg-credential-test` in lib-acg still takes the Azure portal username/password branch first whenever `AZURE_USERNAME` and `AZURE_PASSWORD` are present. That means `AADSTS50126` on MFA-enforced tenants stops the test before the service-principal branch can run, even when `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET` are already available.

The failure screenshot also remains a `/tmp` file in the lib-acg flow, so the artifact is not archived under the shared k3d-manager screenshots directory.

## Why this matters

- The sandbox now exposes service-principal info, so the validation should use it.
- A portal MFA failure should not prevent the test from succeeding when the service-principal credentials are already present.
- The screenshot artifact is the main clue when the run fails, so it should land in a durable shared directory.

## Proposed Fix

1. Prefer service-principal validation when `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET` are present.
2. Only attempt portal username/password validation when no SP credentials are available.
3. Treat MFA/TAP portal-login failures as a fallback-path issue, not as the final validation result.
4. Archive Azure failure screenshots under `~/.local/share/k3d-manager/screenshots/` instead of leaving them only in `/tmp`.

## Expected Outcome

- `make credential-test PROVIDER=azure` succeeds when SP credentials are present and valid.
- Portal username/password failures no longer block the run when SP validation can pass.
- Azure failure screenshots are preserved in the shared screenshots directory for later inspection.
