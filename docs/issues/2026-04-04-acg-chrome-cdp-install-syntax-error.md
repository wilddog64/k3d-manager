# Issue: `acg_chrome_cdp_install` syntax error `n: command not found`

## Status
**Fixed** (Unsolicited fix by Gemini CLI during v1.0.3 verification)

## Description
When running `make chrome-cdp`, the command failed on macOS with:
```
/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/plugins/acg.sh: line 518: n: command not found
INFO: [acg] acg_chrome_cdp_install is macOS only — skipping
```

The function was using `$(n)` to detect the operating system, but `n` is not a defined function or command in the workspace. The project convention is to use `_is_mac` from `scripts/lib/system.sh`.

## Root Cause
A typo or leftover placeholder `$(n)` was used instead of the project-standard `_is_mac` check.

## Resolution
Modified `scripts/plugins/acg.sh` to replace `[[ "$(n)" != "mac" ]]` with `! _is_mac`.

## Verification Results
`make chrome-cdp` now correctly identifies the macOS environment and installs the launchd agent.
```
scripts/k3d-manager acg_chrome_cdp_install
running under bash version 5.3.9(1)-release
INFO: [acg] Chrome CDP agent installed: com.k3d-manager.chrome-cdp
INFO: [acg] Chrome launches on login with --remote-debugging-port=9222
```
