# `make up` smoke test did not bring up CDP on macOS

## What I tested

- Ran `make up`
- Ran `open -a 'Google Chrome' --args --remote-debugging-port=9222 --password-store=basic --user-data-dir="$HOME/.local/share/k3d-manager/profile"`
- Polled `http://localhost:9222/json` for readiness

## Actual output

```text
[make] Running bin/acg-up...
INFO: [acg-up] Step 1/12 — Getting k3s-aws credentials...
INFO: [acg] Chrome CDP not available on port 9222 — launching Chrome...
make: *** [up] Error 1
```

```text
not ready
```

## Root cause

On this macOS host, `open -a 'Google Chrome' --args ...` appears to reuse the existing Chrome app instead of starting a fresh process with the CDP flags, so port 9222 never becomes available.

## Follow-up

- Re-test in the intended Linux ACG sandbox, where the new headless launch path should apply
- If macOS must also support background CDP startup, switch the launch path to a process invocation that guarantees the flags are honored
