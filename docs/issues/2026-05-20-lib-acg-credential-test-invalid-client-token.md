# lib-acg credential-test fails with InvalidClientTokenId

## What was attempted

Ran `make credential-test` from `~/src/gitrepo/personal/lib-acg/` after the Ghost State
`waitForSelector` change in `playwright/acg_extend.js`.

## Actual output

```text
bin/acg-credential-test "https://app.pluralsight.com/hands-on/playground/cloud-sandboxes" 
INFO: Using provider aws
INFO: Found existing Pluralsight session via CDP — reusing existing Chrome instance.
INFO: Found existing sandbox tab: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Already on https://app.pluralsight.com/hands-on/playground/cloud-sandboxes — skipping navigation
INFO: Waiting for page content to load...
INFO: Looking for Start/Open button...
INFO: Clicking Open Sandbox...
INFO: Waiting for credentials to populate (up to 420s)...
INFO: "Extend Your Session" dialog detected — activating tab and pressing Enter on focused close button...
WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing
INFO: Extracting credentials...
INFO: Found 4 copyable inputs.
INFO: Detached from Chrome CDP session.
INFO: AWS credentials written to ~/.aws/credentials [default]
ERROR: AWS credentials written to ~/.aws/credentials but sts:GetCallerIdentity failed
make: *** [credential-test] Error 1
```

Direct STS probe:

```text
aws: [ERROR]: An error occurred (InvalidClientTokenId) when calling the GetCallerIdentity operation: The security token included in the request is invalid.
```

## Root cause

The live Pluralsight page exposed four copyable inputs:
`Username`, `Password`, `Access Key Id`, and `Secret Access Key`. The extracted AWS
credentials were accepted into `~/.aws/credentials`, but AWS STS rejected them with
`InvalidClientTokenId`. That looks like a live credential/session issue rather than a
selector regression in `playwright/acg_extend.js`.

## Recommended follow-up

Verify the active sandbox credentials in the live Pluralsight session, or rerun against
a sandbox instance that yields valid AWS STS credentials.
