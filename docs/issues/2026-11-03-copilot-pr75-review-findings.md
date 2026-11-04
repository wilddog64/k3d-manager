# Copilot Review Findings — PR #75

**Date:** 2026-11-03
**PR:** https://github.com/wilddog64/lib-foundation/pull/75

## Finding 1 — `scripts/tests/lib/acg.bats:620` (`openssl` lookup in `_acg_real_duplicate_key`) and `_acg_imported_key_fingerprint` error handling

### Flagged
- Inline comment (`4462944629` on `scripts/tests/lib/acg.bats:620`): `_acg_real_duplicate_key` looked up `openssl` unconditionally even when `kind == ed25519`, and suggested `skip` guards if `ssh-keygen`/`openssl` are missing.
- Review overview notes on `scripts/lib/acg/acg.sh`:
  - Add an explicit `openssl` presence check (and actionable `[acg]` error) for the RSA imported-key fingerprint path.
  - Treat an empty parsed fingerprint as a non-zero parse failure with a specific error instead of returning `0` with empty stdout.

### Fix Applied

In `scripts/tests/lib/acg.bats`:
- Moved `real_openssl="$(command -v openssl)"` into the `else` (`rsa`) branch of `_acg_real_duplicate_key` so the `ed25519` test path does not require `openssl`.
- Kept tests unskipped per `AGENTS.md` ("Never weaken, skip, or delete a test").

In `scripts/lib/acg/acg.sh` (`_acg_imported_key_fingerprint`):
- Added `command -v openssl >/dev/null 2>&1 || { printf 'ERROR: [acg] openssl is required to verify RSA key fingerprint\n' >&2; return 1; }` in the `ssh-rsa` branch.
- Added `[[ -n "${_fingerprint}" ]] || { printf 'ERROR: [acg] Failed to parse public key fingerprint from %s\n' "$1" >&2; return 1; }` before emitting `_fingerprint`.

### Root Cause
`_acg_real_duplicate_key` resolved `openssl` at the top of the helper before branching on `kind`, and `_acg_imported_key_fingerprint` piped directly through `awk` without asserting non-empty parsed output.

### Process Note
When a helper branches by key/tool type, resolve type-specific external binaries inside the branch that uses them, and ensure parser functions fail closed (`return 1`) when `awk` extracts an empty token.
