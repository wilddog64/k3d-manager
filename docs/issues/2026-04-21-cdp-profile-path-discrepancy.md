# CDP launcher profile path discrepancy

## What I observed

- `scripts/etc/playwright/vars.sh` still points `PLAYWRIGHT_AUTH_DIR` at `~/.local/share/k3d-manager/playwright-auth`
- `scripts/plugins/acg.sh` writes the Chrome CDP launchd plist with that same `playwright-auth` path
- `scripts/plugins/antigravity.sh` launches Chrome with `--user-data-dir=~/.config/acg-chrome-profile`
- `make up` stopped before cluster validation and logged Chrome CDP startup failure

## Actual output

```text
[make] Running bin/acg-up...
INFO: [acg-up] Step 1/12 — Getting k3s-aws credentials...
INFO: [acg] Chrome CDP not available on port 9222 — launching Chrome...
make: *** [up] Error 1
```

## User report

The user reports that Chrome CDP can start in the background and should use `~/.local/share/k3d-manager/profile/`, and that this setup was working yesterday.

## Root cause status

Not resolved yet. The repository currently shows a path mismatch between the shared Playwright auth dir, the CDP launchd plist, and the Antigravity launcher path.

## Follow-up

- Re-verify which profile path is intended for CDP startup
- Confirm whether the background launch path should be changed to `~/.local/share/k3d-manager/profile/`
- Check whether the current launch flow is using the wrong launcher helper for `make up`
