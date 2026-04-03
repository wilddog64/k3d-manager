# Issue: BATS Source Install 404 on Linux

## Discovery
During v0.6.4 Linux k3s validation, running the BATS suite on Ubuntu failed during the auto-installation of BATS from source.

## Root Cause
The function `_install_bats_from_source` in `scripts/lib/system.sh` has a hardcoded default version of `1.10.0`.
GitHub returns a **404 Not Found** for this version because the tag does not exist in the bats-core/bats-core repository.

## Impact
Fully automated testing fails on Linux environments where BATS is not pre-installed via a package manager.

## Technical Details
- **File**: `scripts/lib/system.sh`
- **Line**: ~1050 (inside `_install_bats_from_source`)
- **URL attempted**: `https://github.com/bats-core/bats-core/releases/download/v1.10.0/bats-core-1.10.0.tar.gz`
