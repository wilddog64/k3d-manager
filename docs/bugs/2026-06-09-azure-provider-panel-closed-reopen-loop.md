# Bug: Azure credential extraction loops on "panel closed" reopen

## Summary

During Azure credential extraction, the sandbox wait loop can repeatedly log:

```text
INFO: Waiting for Azure credentials to populate (up to 420s)...
INFO: Azure panel closed — re-opening to retrieve credentials...
```

even when the Azure sandbox itself is valid. The flow keeps trying to re-open the provider panel instead of progressing to populated Azure credentials.

## Observed Output

From the live run:

```text
INFO: Waiting for Azure credentials to populate (up to 420s)...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
INFO: Azure panel closed — re-opening to retrieve credentials...
```

## Root Cause

The Azure credential wait path is treating the provider panel as closed on each poll iteration and re-clicking the open action forever. That makes the loop self-perpetuating instead of settling on the already-valid sandbox state and extracting the Azure credentials.

## Why this matters

- A valid Azure sandbox should not require a manual panel reopen to continue.
- The retry loop burns the full wait window without producing credentials.
- Repeated reopen logging hides the actual credential state and makes `/acg-up` look broken even when the sandbox is otherwise usable.

## Proposed Follow-up

1. Make the Azure wait loop verify that the reopen actually revealed the credential panel before looping again.
2. Avoid re-opening if the credentials are already present or the panel is already in the expected state.
3. Keep the Azure-specific reopen behavior isolated from the AWS/GCP flows.
