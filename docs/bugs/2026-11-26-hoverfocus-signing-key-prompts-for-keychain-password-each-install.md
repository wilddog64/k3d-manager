# Bug: HoverFocus local signing key prompts for the login Keychain password on each keyboard install

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** HoverFocus v0.0.3 F2 (`7b42f63`, unreleased; `packaging/signing-identity.sh`)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (Argon)
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone; batched at grooming 2026-11-29)
**Prior art:** none (exact-slug glob: no `docs/bugs/*hoverfocus*keychain*`; related, different cause: `2026-11-26-hoverfocus-bundle-ignores-codesign-failure.md`, the SSH locked-Keychain case; `make find-similar-docs` not run)
**Severity:** low — install works after the password; "Always Allow" stops it, but a new user meets a password dialog naming a key "id" with no explanation
**Filed:** 2026-11-26, Claude, during F2b live B-EL2 on m2 (operator: "the installation should handle application smoothly", same day)
**Component:** HoverFocus `packaging/signing-identity.sh:47` (key import), `Makefile` `bundle` target

## Symptom

On m2 (macOS 26.5.1, 2026-11-26), each `make install` at the keyboard (12:38, 12:43) showed "codesign wants to access key
"id" in your keychain" and waited for the login password. Signing then succeeded and the grant was kept.
Workaround confirmed the same day: entering the password with **Always Allow** once, then `make install` at the keyboard
ran with no prompt (operator screenshot, 12:46).

## Cause (likely; prove before dispatch)

`signing-identity.sh` imports the key with `security import ... -T "$CODESIGN_PATH"`, which sets the classic access list,
but does not set the key's partition list (`security set-key-partition-list -S apple-tool:,apple: ...`), which macOS 10.12+
also checks for `codesign`. The key's label is "id" (from the temporary `id.p12`), which makes the dialog unclear.

## Fix options (for triage)

1. Set the partition list at identity creation (needs the login password once; prompt for it at the keyboard, never store it).
2. Document "choose Always Allow" (proven workaround) in the README and the `make install` output.
3. Give the key a readable label ("HoverFocus Local Signing key").

Live proof on the deployed macOS before dispatch (Prove external behaviour rule).
