# Bug: HoverFocus `make bundle` ignores a failed `codesign` and records the local identity anyway

**Status:** LIVE-VERIFIED — fix `a4244b6` on HoverFocus v0.0.3 (F2b, Luna), Claude-verified offline; live B-EL1 + B-EL2 PASS on m2 2026-11-26 (SSH install refuses at [bundle]; two keyboard installs keep the grant)
**Priority:** P2
**Introduced by:** HoverFocus v0.0.3 F2 (`7b42f63`, unreleased)
**Should have been caught by:** offline test
**Introducing change reviewed:** yes (Argon)
**Classified:** Argon + Fable blind reviews 2026-11-26: confirmed, P2
**Live evidence:** 2026-11-26 · run operator-m2-make-install-ssh-and-keyboard · env m2 · scenario ssh-install-refuses-keyboard-install-keeps-grant · commit a4244b6 · proves fix
**Fix commit:** a4244b6 (wilddog64/hoverfocus, branch v0.0.3)
**Prior art:** none (exact-slug glob: no `docs/bugs/*hoverfocus*`; `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md` is unrelated; `make find-similar-docs` retrieval unavailable, cluster context missing)
**Severity:** medium — defeats F2's purpose: every install from SSH silently produces an ad-hoc build, the Accessibility grant stops matching, HoverFocus stops working, and the reset hint is suppressed
**Filed:** 2026-11-26, operator: "I consider these are bugs. the installation should handle application smoothly" (U2 E2 setup on m2)
**Component:** HoverFocus `Makefile` `bundle` target (lines 35-50) and the `install` hint (line 63)

## Symptom (m2, macOS 26.5.1, 2026-11-26)

`make install` was run from an SSH session. `build/.codesign-identity` reads `HoverFocus Local Signing`, but the installed
app is `Signature=adhoc`, `Identifier=hoverfocus` (the linker signature), designated requirement `cdhash H"…"`.
HoverFocus then reported "Needs Accessibility permission" while System Settings showed it enabled (and the switch would
not turn off). The ad-hoc reset hint was not printed because the identity file claimed a real identity.

## Cause (proved on m2, 2026-11-26)

- Over SSH the login Keychain is locked: `security show-keychain-info` → "User interaction is not allowed".
- `codesign --force --sign "HoverFocus Local Signing"` on a copy of the bundle → `errSecInternalComponent`, rc 1.
- The `bundle` recipe is one `sh -c` line chain with `;` and no `-e` (no `.SHELLFLAGS`), so the failure is ignored and
  `echo "$$id" > build/.codesign-identity` still runs. The stub `codesign` in F2's offline tests always succeeds.

## Fix options (for triage)

1. Fail closed: stop with a clear message ("login Keychain is locked: run `security unlock-keychain` or run make install
   at this Mac's keyboard") when signing with the local identity fails; write `.codesign-identity` only after success.
2. Verify after signing (`codesign -dv` shows `Authority=HoverFocus Local Signing`) before recording the identity.
3. Fall back to ad-hoc explicitly, record `-`, and print the reset hint (works, but loses the grant every SSH install).

Test: a stub `codesign` that exits 1 for the named identity; red on `7b42f63` (identity file written, rc 0).
Recommended target: v0.0.3, since F2 introduced it there and is unreleased.
