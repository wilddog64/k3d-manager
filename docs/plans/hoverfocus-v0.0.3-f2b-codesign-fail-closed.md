# hoverfocus v0.0.3 F2b — `make bundle` fails closed when signing fails

**Status:** LANDED `a4244b6` on v0.0.3 (Luna `hf003-f2b`, 2026-11-26), Claude-verified offline (cases 1-12 green; red controls run by Claude: old Makefile fails 11a, old script fails 12); live B-EL1/B-EL2 pending on m2. Spec rev 1 — from blind reviews of the bug doc by Argon (dispatch `hf003-p2sign-review-argon`) and Fable
(2026-11-26): both confirmed the diagnosis, agreed P2 and option 1 (fail closed), no silent ad-hoc fallback.
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.3-plan.md`](hoverfocus-v0.0.3-plan.md); fixes
[`2026-11-26-hoverfocus-bundle-ignores-codesign-failure.md`](../bugs/2026-11-26-hoverfocus-bundle-ignores-codesign-failure.md)
(P2, introduced by F2 `7b42f63`).
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` (head `4a3940f`)
**Risk:** low-medium (install path; no Keychain writes)
**Implementer:** Luna (codex, `gpt-6-luna`).
**Verifier:** Claude, from `## Acceptance` only.
**Filed:** 2026-11-26
**Intent approved:** operator, 2026-11-26
**Approval:** operator 2026-11-26 "intents approved"; "let's have Argon/Fable review P2 bug" then "dispatch to Luna after review complete"

## Problem (self-contained; the worker cannot read the bug doc)

In `Makefile` `bundle` (lines 36-51) the signing step is one shell line chained with `;`:
`"$$CODESIGN" --force --sign "$$id" build/HoverFocus.app; echo "$$id" > build/.codesign-identity`. Make runs it without
`-e`, so when `codesign` fails the echo still runs, the recipe exits 0, and `build/.codesign-identity` claims the
identity. `install` then copies the unsealed, linker-signed app (`Identifier=hoverfocus`, designated requirement a
one-build `cdhash`) over the working one, macOS's Accessibility grant stops matching, and the ad-hoc re-grant hint
(Makefile:63-70, keyed on that file) is suppressed. Before F2 (`7b42f63`) `codesign` was its own recipe line and a
failure stopped make.

## External behaviour (proof, before dispatch)

- m2, macOS 26.5.1, 2026-11-26, Claude over SSH: `security show-keychain-info ~/Library/Keychains/login.keychain-db` →
  "User interaction is not allowed" (Keychain locked); `codesign --force --sign "HoverFocus Local Signing"` on a copy of
  the bundle → `errSecInternalComponent`, rc 1. `security find-identity -p codesigning` still lists the identity
  (`CSSMERR_TP_NOT_TRUSTED`) in the same session, so detection selects it and signing then fails.
- `/usr/bin/make` on these Macs is GNU Make 3.81 (Fable, `make --version`): `.ONESHELL` and `.SHELLFLAGS` do not exist
  there and would be silently ignored.
- Not proven: whether `security unlock-keychain` over SSH is enough for `codesign` to use the key (partition list). The
  failure message must not promise it (see Behaviour 2).

## Before You Start

1. Read `Makefile` (whole), `packaging/signing-identity.sh`, `tests/install_test.sh` (stubs at 100-200, `reset_scratch`
   at 242, cases 7-10 at 486-715) and `README.md` (Building, Installation, Granting Accessibility Permissions).
2. `git log --oneline -3`; confirm HEAD is `4a3940f`.
3. Run the existing suite once before changing anything and record its rc:
   `sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))' env SWIFT_BUILD_FLAGS=--disable-sandbox bash tests/install_test.sh`

## Behaviour

1. **`bundle` checks `codesign`'s exit status explicitly**, for every identity value (auto-detected, explicit name,
   explicit `-`): `if ! "$$CODESIGN" --force --sign "$$id" build/HoverFocus.app; then … exit 1; fi`. Use an explicit
   `if` (or `set -e` inside that recipe line); never `.ONESHELL` or `.SHELLFLAGS`. Keep the existing
   `rm -f build/.codesign-identity` before signing; write `build/.codesign-identity` only after success.
2. **On failure** remove `build/HoverFocus.app` (no half-built bundle left) and print to stderr, then exit 1:
   - for a named identity:
     `hoverfocus: signing with "<id>" failed. If this is an SSH session, the login Keychain is probably locked: run make install at this Mac's keyboard, or build ad-hoc with make install CODESIGN_IDENTITY=- (HoverFocus then needs its Accessibility permission granted again).`
   - for `-`: `hoverfocus: ad-hoc signing failed.`
   The message states "probably", never that the Keychain is locked, and does not tell the user to run
   `security unlock-keychain` (unproven).
3. **Because `install` depends on `bundle`**, a signing failure stops `make install` before `rm -rf
   "$$APPDIR/HoverFocus.app"`: the installed app and LaunchAgent plist are untouched.
4. **Unchanged:** a Mac without the identity (detection finds nothing) still signs with `-`, records `-`, prints the
   re-grant hint at install and exits 0; an explicit `CODESIGN_IDENTITY=-` still skips `security find-identity` and
   succeeds; a successful named-identity build behaves exactly as today.
5. **`packaging/signing-identity.sh:21`** decides "already present" with `find-certificate`, so a certificate whose
   private key is missing reports success while `bundle` never finds a usable identity. Change the check to
   `"$SECURITY" find-identity -p codesigning "$keychain"` output containing the quoted `"$SIGNING_NAME"` (same match as
   `Makefile:38`; no `-v`, which hides the untrusted self-signed identity). A certificate without its key then proceeds
   to create the identity as when nothing exists.
6. **README:** in Installation, after "later builds keep the Accessibility grant", add one sentence: signing with the
   local identity needs the login Keychain unlocked, so run `make install` at the Mac's keyboard; over SSH it stops with
   a message rather than installing an unsigned build; `CODESIGN_IDENTITY=-` builds ad-hoc (needs a re-grant).
7. **Tests** in `tests/install_test.sh`:
   - Make the `codesign` stub switchable: when `$root/codesign.fail` exists **and** the `--sign` value is not `-`, log
     the args and exit 1; a second switch file `$root/codesign.fail-any` fails every identity including `-`. Add both
     files to `reset_scratch`'s rm list and to every snapshot `find` exclusion (lines 267, 326, 397, 446, 461, 489, 502
     and any others).
   - **case 11a:** identity stub present + `codesign.fail` → `make bundle` rc ≠ 0, `build/.codesign-identity` absent,
     `build/HoverFocus.app` absent, stderr contains `signing with "HoverFocus Local Signing" failed` and `probably`, and
     does not contain `unlock-keychain`.
   - **case 11b:** same failure through `make install` with a previously installed `$APPDIR/HoverFocus.app` containing a
     marker file and an existing agent plist → rc ≠ 0, marker and plist unchanged (byte-compare), no `launchctl` call
     logged.
   - **case 11c:** explicit `CODESIGN_IDENTITY="Some Identity"` + `codesign.fail` → rc ≠ 0, file absent.
   - **case 11d:** `CODESIGN_IDENTITY=-` + `codesign.fail-any` → rc ≠ 0, stderr `ad-hoc signing failed`.
   - **case 11e (positive control):** identity stub present, no fail file → rc 0, file reads `HoverFocus Local Signing`
     (case 7 already covers this; assert it again in 11's scratch so 11a's red cannot come from a broken setup).
   - **case 12 (signing-identity.sh):** `security` stub where `find-certificate` succeeds but `find-identity` lists no
     `HoverFocus Local Signing` → the script does not print `already present` and proceeds to the `openssl req` call;
     paired: both present → `already present`, rc 0 (case 10's existing sub-case).

## Files

| File | Change |
|---|---|
| `Makefile` | `bundle` signing block only |
| `packaging/signing-identity.sh` | the "already present" check |
| `tests/install_test.sh` | switchable stub, cases 11a-11e, 12 |
| `README.md` | one Installation sentence |

## Contract readers

- `build/.codesign-identity`: writer `bundle` (Makefile:49-51, now only after success); reader `install` (Makefile:63);
  removed by `clean`. Meaning unchanged when present; now absent after a failed build.
- `bundle` exit status: readers `install` (prerequisite, Makefile:53) and `tests/install_test.sh` cases 7-9 (expect 0 on
  success, unchanged). New: non-zero on signing failure.
- `CODESIGN_IDENTITY`, `SIGNING_NAME`, `SECURITY`, `CODESIGN`: unchanged names and defaults (Makefile:4-12).
- Login Keychain item "HoverFocus Local Signing": still written only by `signing-identity.sh` (operator-run); its
  "already present" reader changes from `find-certificate` to `find-identity -p codesigning`.

## What NOT to Do

- Never run `make signing-identity`, `codesign`, `security`, `tccutil` or `launchctl` for real; tests use the stubs.
- No `.ONESHELL`, `.SHELLFLAGS`, `$(shell …)` or `find-identity -v`. No automatic ad-hoc fallback.
- Do not change `install`'s agent-loading block (a separate P3 covers it) or any Swift source.
- Run every command under the `sandbox-exec` profile in Before You Start step 3.

## Acceptance

```yaml
must:
  - id: B-M1
    text: "when codesign fails for any identity value, make bundle exits non-zero, build/.codesign-identity and build/HoverFocus.app are absent, and stderr carries the Behaviour 2 message (named: contains 'probably' and CODESIGN_IDENTITY=-, never unlock-keychain)"
  - id: B-M2
    text: "a signing failure during make install leaves the installed HoverFocus.app and agent plist byte-identical and calls no launchctl"
  - id: B-M3
    text: "signing-identity.sh reports already present only when find-identity -p codesigning lists the identity"
  - id: B-M4
    text: "README Installation says signing needs the Keychain unlocked (install at the keyboard) and names CODESIGN_IDENTITY=- as the ad-hoc opt-in"
must_not:
  - id: B-N1
    text: "a failed codesign leaves make bundle at rc 0 with the identity recorded (red on 4a3940f) (paired: a successful sign still exits 0 and records the identity, case 11e/7)"
  - id: B-N2
    text: "a failed sign during make install replaces the installed app (red on 4a3940f) (paired: a successful install still replaces it, case 1)"
  - id: B-N3
    text: "a Mac without the local identity, or an explicit CODESIGN_IDENTITY=-, stops building (paired positive controls: cases 8 and 9 still pass)"
  - id: B-N4
    text: "signing-identity.sh says already present when only the certificate exists (red on 4a3940f) (paired: both present still says already present)"
evidence:
  - id: B-E1
    proves: [B-M1, B-M2, B-N1, B-N2, B-N3]
    kind: offline
    command: "the sandbox-exec install_test.sh run rc 0 with cases 1-12 PASS; then revert only Makefile to 4a3940f (git show 4a3940f:Makefile > Makefile) and rerun: 11a, 11b and 11c fail, cases 1-10 and 11e pass; restore."
    intent: "If signing fails, for example over SSH, the install stops with a clear message and your working HoverFocus stays installed, instead of being silently replaced by a build that loses its permission."
  - id: B-E2
    proves: [B-M3, B-N4]
    kind: offline
    command: "same run, case 12 PASS; revert only packaging/signing-identity.sh to 4a3940f and rerun: case 12 fails; restore."
    intent: "The one-time setup no longer claims signing is ready when the key is missing."
  - id: B-E3
    proves: [B-M4]
    kind: offline
    command: "grep -n 'CODESIGN_IDENTITY=-' README.md and grep -niE 'keychain' README.md show the new Installation sentence; grep -nE 'ONESHELL|SHELLFLAGS|find-identity -v' Makefile packaging/ prints nothing"
    intent: "The README tells you to install at the Mac's keyboard, and how to build ad-hoc on purpose."
  - id: B-EL1
    proves: [B-M1, B-M2]
    kind: live
    command: "operator runs make install over SSH on m2 (Keychain locked): rc non-zero with the message; Claude over SSH: codesign -dv of ~/Applications/HoverFocus.app and the binary mtime unchanged from before the run"
    intent: "On m2, installing over SSH now refuses cleanly and leaves the working app alone."
  - id: B-EL2
    proves: [B-N1]
    kind: live
    command: "operator runs make install at m2's keyboard: prints signing with HoverFocus Local Signing; Claude: codesign -dvv shows Authority=HoverFocus Local Signing and Identifier=com.wilddog64.hoverfocus; operator grants Accessibility once (tccutil reset first); a second make install at the keyboard keeps HoverFocus Running with no re-grant (also closes F2-EL)"
    intent: "Installing at the keyboard signs properly, and after one grant, reinstalls keep HoverFocus's permission."
interface: "Makefile: bundle exits non-zero when signing fails (new); build/.codesign-identity written only after success; packaging/signing-identity.sh idempotence check uses find-identity -p codesigning"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each red control's failing output and `git diff --stat` after restoring it. Commit nothing; Claude lands.
