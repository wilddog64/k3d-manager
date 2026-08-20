# ACG live credential test passed after CDP recovery and sandbox restart

## Test

The canonical live gate was run from `scripts/lib/foundation` with the Homebrew
Node binary available on `PATH`:

```text
PATH="/opt/homebrew/bin:${PATH}" make credential-test PROVIDER=aws
```

The first attempt reclaimed two listeners on port 9222 but the sandboxed shell
could not write the managed Chrome log:

```text
INFO: [acg] A browser listener is present on :9222 but the CDP probe failed — reclaiming the port before relaunching managed Chromium.
INFO: [acg] Reclaiming :9222 — terminating the CDP browser holding it (pid(s): 12976 91089)
INFO: Chrome not running — launching with --remote-debugging-port=9222...
/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/lib/foundation/scripts/lib/acg/cdp.sh: line 148: /Users/cliang/.local/share/k3d-manager/chrome-cdp.log: Operation not permitted
```

The retry with the required local permission reused the authenticated CDP
session. The first extraction attempt hit the known viewport interaction
failure, and the built-in recovery path restarted the sandbox:

```text
INFO: [acg] Reusing existing CDP browser on :9222
INFO: Checking Pluralsight (ACG) session in Antigravity browser...
ACG_SESSION_OK
INFO: Using provider aws
INFO: Found existing Pluralsight session via CDP — reusing existing Chrome instance.
INFO: Found existing sandbox tab: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Already on https://app.pluralsight.com/hands-on/playground/cloud-sandboxes — skipping navigation
INFO: Waiting for page content to load...
INFO: Looking for AWS sandbox buttons...
INFO: Clicking Open Sandbox...
INFO: Clicking Start Sandbox (Step 2)...
ERROR: locator.click: Element is outside of the viewport
INFO: Detached from Chrome CDP session.
ERROR: locator.click: Element is outside of the viewport
WARN: Credential extraction failed — restarting sandbox...
INFO: Deleting and restarting sandbox to recover fresh credentials...
INFO: CDP Chrome still running on port 9222.
INFO: Using provider aws
INFO: Connected via CDP to existing browser session.
INFO: Open tabs (1): ["https://app.pluralsight.com/hands-on/playground/cloud-sandboxes"]
INFO: Already on sandbox page: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Delete Sandbox not visible — clicking Open Sandbox to reveal panel...
INFO: Sandbox panel open but not yet provisioned — clicking Start Sandbox directly...
INFO: Sandbox started. Ready for credential extraction.
RESTART_OK
INFO: Waiting for CDP to be ready after restart...
INFO: CDP ready.
INFO: Using provider aws
INFO: Found existing Pluralsight session via CDP — reusing existing Chrome instance.
INFO: Found existing sandbox tab: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Already on https://app.pluralsight.com/hands-on/playground/cloud-sandboxes — skipping navigation
INFO: Waiting for page content to load...
INFO: Clicking Open Sandbox...
WARN: Scoped Start Sandbox not found for AWS — trying provider-scoped fallback...
WARN: No Start Sandbox button found for AWS after Open Sandbox — proceeding to credential wait
INFO: Waiting for AWS credentials to populate (up to 420s)...
INFO: Extracting credentials...
INFO: Found 4 copyable inputs.
INFO: Detached from Chrome CDP session.
AWS_ACCESS_KEY_ID=***
AWS_SECRET_ACCESS_KEY=***
INFO: AWS credentials written to ~/.aws/credentials [default]
INFO: AWS credentials validated (sts:GetCallerIdentity OK)
```

## Result

The live AWS credential gate passed after the CDP listener recovery and the
existing sandbox restart fallback. No repository source change was required
for this run. The initial viewport failure remains a flaky interaction signal;
the recovery path successfully handled it.

## Follow-up

Keep the viewport failure visible in future live runs. If it recurs after the
restart path, capture the page layout and selector state before changing the
Playwright interaction logic.

## Focused regression verification

The all-case CDP BATS invocation exposed an existing suite-isolation failure:

```text
1..5
ok 1 _browser_launch: reuses the CDP browser and runs the session check when it is healthy
not ok 2 _browser_launch: reclaims an undriveable CDP browser then relaunches the managed Chromium
# (in test file scripts/lib/foundation/scripts/tests/lib/acg_cdp.bats, line 52)
#   `[ "$output" = "relaunched-session-check" ]' failed
not ok 3 _browser_launch: launches the managed Chromium then runs the session check
# (in test file scripts/lib/foundation/scripts/tests/lib/acg_cdp.bats, line 77)
#   `[ "$output" = "launched-session-check" ]' failed
not ok 4 _browser_launch: reclaims an IPv6-only listener when the IPv4 CDP probe fails
# (in test file scripts/lib/foundation/scripts/tests/lib/acg_cdp.bats, line 104)
#   `[ "$output" = "reclaimed-ipv6-session-check" ]' failed
ok 5 _browser_launch: K3DM_ACG_SKIP_SESSION_CHECK=1 still bypasses the session check end-to-end
```

Each failing case passes when run individually; for example, the undriveable
browser case returned `1..1` / `ok 1`. This did not affect the live credential
gate, but the suite-isolation behavior should be investigated separately.
