# Bug: Azure credential-test screenshots stay in `/tmp` instead of shared screenshots dir

## Summary

When `make credential-test PROVIDER=azure` fails, the credential-test flow reports a screenshot path under `/tmp`:

```text
INFO: Azure portal URL: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Azure screenshot: /tmp/k3dm-azure-1781059613981.png
make: *** [credential-test] Error 1
```

That makes the failure artifact easy to lose and hard to inspect later, because `/tmp` is transient and is already used by other cleanup paths in the repo.

## Why this is a problem

- The Azure credential extraction loop is already flaky enough that the screenshot is often the only useful artifact from a failed run.
- A `/tmp` screenshot is not part of the repo-owned state directory, so it is easy to prune or miss after the run.
- The repo already uses `~/.local/share/k3d-manager` for persistent runtime state, so failure screenshots should land there too.

## Root Cause

The Playwright failure helper still emits the screenshot to `/tmp`, and the surrounding failure analysis only learns about that temporary path from the log line. The artifact is therefore ephemeral instead of being archived under the shared k3d-manager screenshots directory.

## Proposed Fix

1. Save Azure failure screenshots directly under `~/.local/share/k3d-manager/screenshots/`.
2. Create the screenshots directory on demand if it does not exist.
3. Update failure analysis to recognize the archived path.
4. Keep the screenshot filename stable enough to correlate with the job log.

## Expected Outcome

- Azure credential-test failures leave a durable PNG under `~/.local/share/k3d-manager/screenshots/`.
- The screenshot remains available after cleanup.
- The next investigation can use the archived PNG without depending on `/tmp`.
