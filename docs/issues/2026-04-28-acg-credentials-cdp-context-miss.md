# Issue: `make up` stops at ACG credential extraction despite visible sandbox credentials

**Date:** 2026-04-28
**Status:** Source fix merged and pulled into k3d-manager subtree
**Severity:** Critical

## What Was Attempted

User ran:

```text
make up
```

Observed output:

```text
[make] Running bin/acg-up...
INFO: [acg-up] Step 1/12 — Getting k3s-aws credentials...
INFO: [acg] Extracting AWS credentials from https://app.pluralsight.com/cloud-playground/cloud-sandboxes...
make: *** [up] Error 1
```

User then confirmed the Pluralsight sandbox page was already open and populated with:

```text
Username: cloud_user
Password: [visible in browser]
Access Key Id: [visible in browser]
Secret Access Key: [visible in browser]
Sandbox URL: https://905293745314.signin.aws.amazon.com/console?region=us-east-1
```

Credential values are intentionally not copied into this issue.

## Actual Behavior

`make up` aborts during Step 1 because `acg_get_credentials` returns non-zero.

The failure happens before cluster provisioning, SSH tunnel setup, Vault, ESO, ArgoCD, or shopping-cart deployment. The visible sandbox credentials prove the sandbox is running; the automation failed to extract them.

Follow-up live check during the fix attempt exposed an earlier launcher failure:

```text
running under bash version 5.3.9(1)-release
INFO: [acg] Chrome CDP not available on port 9222 — launching Chrome...
INFO: Chrome not running — launching with --remote-debugging-port=9222...
Unable to find application named 'Google Chrome'
ERROR: Antigravity browser not ready on port 9222 after 30s — launch Antigravity with --remote-debugging-port=9222
```

`/Applications/Google Chrome.app` exists on the machine, so the `open -a "Google Chrome"` launch path is not reliable enough for this automation.

After switching to the direct Chrome executable, the Codex sandbox still blocked the live GUI launch:

```text
running under bash version 5.3.9(1)-release
INFO: [acg] Chrome CDP not available on port 9222 — launching Chrome...
INFO: Chrome not running — launching with --remote-debugging-port=9222...
[0428/042410.319236:ERROR:third_party/crashpad/crashpad/util/mach/bootstrap.cc:65] bootstrap_check_in org.chromium.crashpad.child_port_handshake.48635.179615.GBOPUSGHJYWLYWSV: Permission denied (1100)
[0428/042410.319451:ERROR:third_party/crashpad/crashpad/util/file/file_io.cc:103] ReadExactly: expected 4, observed 0
[0428/042410.319674:ERROR:third_party/crashpad/crashpad/util/file/file_io_posix.cc:208] open /Users/cliang/Library/Application Support/Google/Chrome/Crashpad/settings.dat: Operation not permitted (1)
[0428/042410.319754:ERROR:third_party/crashpad/crashpad/util/file/file_io_posix.cc:208] open /Users/cliang/Library/Application Support/Google/Chrome/Crashpad/settings.dat: Operation not permitted (1)
ERROR: Antigravity browser not ready on port 9222 after 30s — launch Antigravity with --remote-debugging-port=9222
```

This second failure is a Codex sandbox permission issue during validation, not necessarily a repo runtime issue.

## Current Root Cause

The current credential path depends on browser UI state:

1. `bin/acg-up` calls `acg_get_credentials` if `aws sts get-caller-identity` is not already valid.
2. `acg_get_credentials` runs `playwright/acg_credentials.js`.
3. The Playwright script tries to connect to Chrome CDP and extract `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from visible copyable inputs.
4. If those values are not printed by the Node script, the Bash wrapper returns `1`, which stops `make up`.

Two fragile points are present:

- `_browser_launch` treats any responder on CDP port 9222 as usable, without proving it is the expected k3d-manager Chrome profile.
- `acg_credentials.js` only reuses CDP when it already finds a Pluralsight tab; if CDP exists but has no matching tab, it disconnects and launches a persistent context, which can miss the user's currently authenticated visible sandbox session.
- On macOS, `_browser_launch` uses `open -a "Google Chrome"` even though the launchd agent already uses the direct Chrome executable path. The `open -a` form failed live on this machine despite Chrome existing under `/Applications`.
- Direct navigation to `/hands-on/playground/cloud-sandboxes` can land on signed-in `/library/` first. The old script then waited for sandbox buttons on the wrong page and timed out.

There is also a URL mismatch in the command output: `make up` still passes the legacy `cloud-playground/cloud-sandboxes` URL even though the active Pluralsight UI uses `hands-on/playground/cloud-sandboxes`.

## Recommended Follow-Up

Fix the credential automation so `make up` can run unattended after the user has signed in once:

1. Use the current `hands-on/playground/cloud-sandboxes` URL as the AWS default.
2. Reuse the existing CDP browser context even when no Pluralsight tab is open; create the sandbox tab inside that context instead of launching a separate context.
3. Print sanitized Playwright diagnostics on extraction failure so future failures identify the exact step without leaking AWS secrets.
4. Keep the persistent profile path stable at `~/.local/share/k3d-manager/profile`.

## Source Fix

The implementation belongs in `wilddog64/lib-acg`, which is consumed by k3d-manager through the `scripts/lib/acg/` subtree. Do not manually patch the vendored subtree in k3d-manager.

Source PR:

```text
https://github.com/wilddog64/lib-acg/pull/2
```

Merged source commit:

```text
7cb7f64a701ef3f30d14f018a9a9d1635b899ed9
```

k3d-manager subtree sync:

```text
88cb8bbc Merge commit 'a0b44c878b9922974aea787342bf9d4242e5252b' into k3d-manager-v1.2.0
a0b44c87 Squashed 'scripts/lib/acg/' changes from 5c0e8e2d..7cb7f64a
```

Implemented fix:

- Default AWS sandbox navigation to `https://app.pluralsight.com/hands-on/playground/cloud-sandboxes`.
- Reuse the active CDP browser context even when that context has no Pluralsight tab yet.
- If direct sandbox navigation lands on a signed-in non-sandbox Pluralsight page, retry through `https://app.pluralsight.com/hands-on` and then return to the sandbox URL.
- Print sanitized Playwright diagnostics on extraction failure instead of hiding the failed step behind a generic `make` error.
- Prefer `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` for macOS CDP launch, matching the launchd agent, with `open -a "Google Chrome"` retained as fallback.

## Verification Needed

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — passed.
- `node --check scripts/playwright/acg_credentials.js` — passed.
- `shellcheck scripts/lib/acg/scripts/plugins/acg.sh scripts/lib/acg/scripts/lib/cdp.sh scripts/etc/playwright/vars.sh` — passed.
- `bats scripts/tests/lib/acg.bats` — passed, 11 tests.
- Live `./scripts/k3d-manager acg_get_credentials` with the same patch temporarily applied in k3d-manager — passed; wrote `/Users/cliang/.aws/credentials`.
- `aws sts get-caller-identity --query 'Arn' --output text` — passed:

```text
arn:aws:iam::905293745314:user/cloud_user
```

Post-subtree verification on k3d-manager:

```text
$ node --check scripts/lib/acg/playwright/acg_credentials.js
```

```text
$ shellcheck scripts/lib/acg/scripts/plugins/acg.sh scripts/lib/acg/scripts/lib/cdp.sh scripts/lib/acg/scripts/vars.sh
```

```text
$ bats scripts/tests/lib/acg.bats
1..11
ok 1 _acg_write_credentials writes [default] profile to ~/.aws/credentials
ok 2 _acg_write_credentials sets file permissions to 600
ok 3 _acg_write_credentials creates ~/.aws directory if missing
ok 4 acg_import_credentials parses label format (Pluralsight UI copy)
ok 5 acg_import_credentials parses export format
ok 6 acg_import_credentials succeeds with AKIA key and no session token
ok 7 acg_import_credentials returns 1 on empty/unparseable input
ok 8 acg_import_credentials --help exits 0
ok 9 acg_get_credentials --help exits 0
ok 10 _acg_extend_playwright: returns 0 when node script succeeds
ok 11 _acg_extend_playwright: returns 1 when node script fails
```

```text
$ git diff --check
```

```text
$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.9(1)-release
```

Final live `make up` verification remains pending after this subtree sync.
