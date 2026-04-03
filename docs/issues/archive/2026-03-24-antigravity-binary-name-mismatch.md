# Issue: `_ensure_antigravity_ide` Fails on macOS due to Binary Name Mismatch

## Summary
The `_ensure_antigravity_ide` function in `scripts/lib/system.sh` (sourced from `lib-foundation`) fails to verify a successful installation of Antigravity on macOS.

## Root Cause
The function uses `_command_exist antigravity` to check if the IDE is installed. However, when installed via Homebrew (`brew install --cask antigravity`), the binary is linked as `agy`, not `antigravity`.

## Evidence
Terminal output from a macOS install attempt:
```
==> Moving App 'Antigravity.app' to '/Applications/Antigravity.app'
==> Linking Binary 'agy.wrapper.sh' to '/opt/homebrew/bin/agy'
🍺  antigravity was successfully installed!
ERROR: Cannot install Antigravity IDE: no supported package manager found or install failed
```

Running `agy --version` succeeds:
```
$ agy --version
1.107.0
135ccf460c67c4b900dc10aa71c978f27d78601c
arm64
```

## Recommended Fix
Update `_ensure_antigravity_ide` in the `lib-foundation` repository to check for both `antigravity` and `agy` commands.

```bash
function _ensure_antigravity_ide() {
   if _command_exist antigravity || _command_exist agy; then
      return 0
   fi
   # ... rest of function
}
```
