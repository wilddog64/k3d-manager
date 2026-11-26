# hoverfocus v0.0.3 F2 — local signing identity so the Accessibility grant survives rebuilds; tested-apps docs

**Status:** spec rev 1 — not reviewed; reviews due: Fable + Argon, plus a Neon blind review (operator rule); not dispatched
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.3-plan.md`](hoverfocus-v0.0.3-plan.md) (batch F2)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` (cut from `main` at `d2cdb00`)
**Risk:** low-medium (install path and the login Keychain; the identity is created only by an operator-run target)
**Implementer:** Flash (`agy`, `gemini-3.8-flash-medium`, Makefile/docs). Runs in parallel with L3 (no shared file).
**Verifier:** Claude, from `## Acceptance` only.
**Filed:** 2026-11-25
**Intent approved:** pending
**Approval:** operator 2026-11-24 (local signing identity approved for v0.0.3); operator 2026-11-25 "go ahead to do 1 .. 3"

## Fixes

| Input | Defect (v0.0.2, `d2cdb00`) |
|---|---|
| B3 part 4 `docs/hoverfocus/bugs/2026-11-23-hoverfocus-install-launchagent-and-tcc-grant-gaps.md` | `CODESIGN_IDENTITY ?= -` (Makefile:4): every ad-hoc build has a new cdhash, so the designated requirement changes and macOS drops the Accessibility grant after each `make install` |
| Plan F2 | README has no tested-apps table and no correct re-grant steps (P3 run 1: an already-open System Settings shows a stale ON switch after `tccutil reset`) |

## External behaviour (proof, before dispatch)

P3, m2-air, macOS 26.5.1, 2026-11-25, logs m2 `~/hf-p3-20261125T042212.txt` (run 1) and `~/hf-p3-20261125T042939.txt`
(run 2), kit `~/hf-probe/hf-p3-signing.sh`, checkout `42273f0`:

- A self-signed certificate (RSA 2048, `basicConstraints critical,CA:false`, `keyUsage critical,digitalSignature`,
  `extendedKeyUsage critical,codeSigning`, 10 years) made with `/usr/bin/openssl` (LibreSSL 3.3.6), exported to PKCS#12
  and imported with `security import … -f pkcs12 -T /usr/bin/codesign` into the login Keychain signs the app.
- `security find-identity -p codesigning` lists it **with** `CSSMERR_TP_NOT_TRUSTED`, and `codesign` signs with it
  anyway; **`find-identity -v` (valid only) would hide it**, so detection must not use `-v`.
- Designated requirement `identifier "com.wilddog64.hoverfocus" and certificate leaf = H"…"` was identical on three
  builds with different cdhashes; the TCC row (`auth_value 2`) was unchanged after builds 2 and 3, and the running
  build passed the trust check and owned its event tap.
- First use asks whether `codesign` may use the key ("Always Allow", login password): the target must run at the
  Mac's keyboard, not over SSH (Keychain locked).
- After `tccutil reset`, quit System Settings, reopen, remove HoverFocus with **−**, add it again with **+**.

## Before You Start

1. `git log --oneline -1` shows the `v0.0.3` head; `make selftest` is not needed (no Swift change);
   `bash tests/install_test.sh` passes (it runs `make bundle` with the real ad-hoc `codesign`).
2. Read `Makefile`, `tests/install_test.sh` (stub pattern: `$root/HF_TEST_ROOT` marker, stubs in `$root/bin`, a log
   per stub) and `README.md`.
3. Do not edit any file outside `## Files`. Never run `make signing-identity` or touch the real login Keychain: tests
   stub `security`, `openssl` and `codesign`.

## Behaviour

1. **Makefile variables:** `SECURITY ?= security`, `CODESIGN ?= codesign`, `OPENSSL ?= /usr/bin/openssl`,
   `SIGNING_NAME ?= HoverFocus Local Signing`, all exported. `bundle` signs with `"$$CODESIGN" --force --sign
   "$$CODESIGN_IDENTITY" build/HoverFocus.app`.
2. **Default identity:** `CODESIGN_IDENTITY` is no longer `?= -`. When not set by the caller, `bundle` resolves it at
   recipe time (shell, not `$(shell)` at parse time): if `"$$SECURITY" find-identity -p codesigning` output contains
   the quoted `"$$SIGNING_NAME"`, use `$$SIGNING_NAME`; otherwise `-`. An explicit `CODESIGN_IDENTITY=…` (including `-`)
   always wins. `bundle` prints one line: `hoverfocus: signing with <identity>` (or `ad-hoc (-)`).
3. **Hint:** `install` prints the existing ad-hoc hint only when the identity used was `-`, extended with:
   `run "make signing-identity" once at this Mac's keyboard so later builds keep the grant`. With the local identity
   the hint is not printed. (Today `install` reads `CODESIGN_IDENTITY` directly; it must read the identity `bundle`
   used: write it to `build/.codesign-identity` in `bundle` and read that file in `install`.)
4. **`make signing-identity`** runs new `packaging/signing-identity.sh` (`set -euo pipefail`):
   - Refuses with rc 2 and a one-line reason when `SSH_CONNECTION` is set (Keychain prompt needs the keyboard).
   - If `"$SECURITY" find-certificate -c "$SIGNING_NAME" "$keychain"` succeeds (keychain =
     `$HOME/Library/Keychains/login.keychain-db`), prints `already present` and exits 0 (idempotent).
   - Otherwise, in `tmp=$(mktemp -d)` (mode 0700, removed by an EXIT trap): write the request config above, run
     `"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config …`, export PKCS#12 with a one-time random
     passphrase passed to `openssl pkcs12` through `-passout env:` (never argv), `security import "$tmp/id.p12" -k
     "$keychain" -f pkcs12 -P "$P12_PASS" -T "$CODESIGN_PATH"` (`CODESIGN_PATH` = `command -v "$CODESIGN"`), `unset
     P12_PASS`, delete the key and p12. Then `find-identity -p codesigning` must list the name, else rc 1.
   - `security import` takes the passphrase only as `-P`; this is the one argv exposure, accepted because the
     passphrase is random, used once, and protects a file deleted seconds later in a 0700 directory; the private key
     itself is never on argv or in the log. The script never echoes the passphrase and runs without `set -x`.
5. **Tests (`tests/install_test.sh`):** add stubs `security`, `codesign`, `openssl` in `$root/bin` (each checks the
   `HF_TEST_ROOT` marker first and appends its argv to a log, never printing a passphrase value), and cases:
   - The `security find-identity` stub mirrors the real tool for an untrusted identity: it prints nothing when its
     argv contains `-v`.
   - **Case 7, identity present:** `security find-identity` stub prints a line containing
     `"HoverFocus Local Signing"` → `make bundle` (no `CODESIGN_IDENTITY`) calls the `codesign` stub with `--sign
     HoverFocus Local Signing`; `make install` output has no `tccutil` hint.
   - **Case 8, identity absent (positive control):** stub prints no such line → `codesign --sign -`; hint printed,
     including `make signing-identity`.
   - **Case 9, explicit override:** identity present but `CODESIGN_IDENTITY=-` → `--sign -`.
   - **Case 10, signing-identity script:** with `SSH_CONNECTION` set → rc 2, no `openssl` call. Without it, cert
     absent → `openssl req`, `openssl pkcs12` (argv has `-passout env:`, not `pass:`), `security import … -T` in that
     order, and no file left in the script's temp dir; cert present → `already present`, no `openssl` call.
   - Existing cases 1-6 keep passing; the real ad-hoc `codesign -v build/HoverFocus.app` check (line ~354) stays real.
6. **README:**
   - **Installation:** run `make signing-identity` once at the Mac (Keychain prompt: enter the login password, click
     **Always Allow**), then `make install`; later builds keep the Accessibility grant. Without it builds are ad-hoc
     and each install needs a re-grant.
   - **Granting Accessibility:** the re-grant steps from P3 (quit System Settings first, reopen, remove with −, add
     with +); keep the existing `tccutil reset` line.
   - **Tested apps** (new section): rows TextEdit, TextEdit second window (same app), Safari, Chrome, Mail,
     Terminal.app, iTerm2, Slack, VS Code; columns App / Typing lands without raise / Cmd shortcuts / Notes; values
     `pending v0.0.3 live check` for every cell, with a note that the 2026-11-25 probe on macOS 26.5.1 passed all of
     them except iTerm2 (not in the probe) and that the release live check fills the table. Do not edit **Known
     Limitations** (Claude updates it after the L3 live check).

## Files

| File | Change |
|---|---|
| `Makefile` | variables, recipe-time identity resolution, `signing-identity` target, hint |
| `packaging/signing-identity.sh` | new |
| `tests/install_test.sh` | stubs and cases 7-10 |
| `README.md` | Installation, Granting Accessibility, Tested apps |

## Contract readers

- `CODESIGN_IDENTITY` (Makefile variable, exported): readers `bundle` and `install` (Makefile:4, 31, 43-48); README:22-26
  documents it; `tests/install_test.sh:308` sets it to `-`. Meaning changes from "always `-` unless set" to "local
  identity when present, else `-`, unless set".
- New `build/.codesign-identity`: writer `bundle`, reader `install`; removed by `clean` (`rm -rf build`).
- Login Keychain item "HoverFocus Local Signing": writer `packaging/signing-identity.sh` only (operator-run); reader
  `bundle` (detection) and `codesign`. The P3 probe already created this item on m2, so on m2 the target reports
  `already present`.
- TCC Accessibility row for `com.wilddog64.hoverfocus`: not written by any code here; its csreq changes once from
  cdhash to certificate leaf on the first identity-signed install (one manual re-grant, documented).

## What NOT to Do

- Never run `make signing-identity`, `security import`, `tccutil` or `launchctl` for real; never read the real Keychain.
- No `find-identity -v` for detection. No `$(shell …)` identity lookup at Makefile parse time (it would run `security`
  for `make clean`).
- No passphrase in a log, in `set -x` output or on `openssl` argv.
- Run every command under
  `sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))'`.

## Acceptance

```yaml
must:
  - id: F2-M1
    text: "with no CODESIGN_IDENTITY given, bundle signs with \"HoverFocus Local Signing\" when security find-identity -p codesigning lists it, else with -; an explicit CODESIGN_IDENTITY always wins"
  - id: F2-M2
    text: "install prints the tccutil re-grant hint and the make signing-identity suggestion only when the build was ad-hoc"
  - id: F2-M3
    text: "make signing-identity refuses over SSH, is idempotent when the certificate exists, otherwise creates a self-signed codeSigning identity via openssl req, openssl pkcs12 -passout env:, security import -T codesign, verifies it with find-identity, and leaves no key or p12 on disk"
  - id: F2-M4
    text: "README documents make signing-identity, the quit-System-Settings re-grant steps, and a Tested apps table with the nine apps"
must_not:
  - id: F2-N1
    text: "a build on a Mac that has the local identity is signed ad-hoc (the v0.0.2 behaviour that drops the grant each install) (paired: a Mac without it still builds ad-hoc and gets the hint)"
  - id: F2-N2
    text: "detection uses find-identity -v, which hides the untrusted self-signed identity (paired: the stub prints the CSSMERR_TP_NOT_TRUSTED line from the P3 capture and detection still finds it)"
  - id: F2-N3
    text: "the PKCS#12 passphrase appears on openssl argv or in any log (paired: the security import call is still made)"
evidence:
  - id: F2-E1
    proves: [F2-M1, F2-M2, F2-N1, F2-N2]
    kind: offline
    command: "bash tests/install_test.sh rc 0 with cases 1-10 reported. The find-identity stub output is the P3 capture line format (m2-air, 2026-11-25): '  1) <40-hex> \"HoverFocus Local Signing\" (CSSMERR_TP_NOT_TRUSTED)'. Red controls, each restored byte-identical: (a) restore CODESIGN_IDENTITY ?= - — case 7 fails, case 8 passes; (b) add -v to the find-identity call and make the stub print nothing for -v (as the real tool does for an untrusted identity) — case 7 fails; (c) print the hint unconditionally — case 7 fails"
    intent: "After a one-time setup, rebuilding and reinstalling HoverFocus keeps its Accessibility permission, so you no longer re-grant it after every install; Macs without the setup still work as before."
  - id: F2-E2
    proves: [F2-M3, F2-N3]
    kind: offline
    command: "same run, case 10: SSH refusal rc 2 with no openssl call; create path stub log order openssl req, openssl pkcs12 (argv contains -passout env: and no pass:), security import ... -T; temp dir gone; present path prints already present with no openssl call; git grep -n -- '-v -p codesigning\\|pass:' -- Makefile packaging/ prints nothing. Red controls, restored: (a) pass the passphrase as -passout pass:$P12_PASS — case 10 fails; (b) skip the SSH_CONNECTION check — case 10 fails"
    intent: "The one-time setup command creates the signing certificate safely: only at the Mac's keyboard, never twice, and without leaving key files or the temporary password behind."
  - id: F2-E3
    proves: [F2-M4]
    kind: offline
    command: "grep -n 'make signing-identity' README.md and grep -n '^## Tested apps' README.md each print at least one line; the Tested apps table has nine app rows; code reading of the Granting Accessibility steps against Behaviour 6"
    intent: "The README tells a new user how to set up signing once, how to re-grant permission correctly, and which apps were checked."
  - id: F2-EL
    proves: [F2-M1, F2-N1]
    kind: live
    command: "operator on m2 at the keyboard: make signing-identity (prints already present: P3 created it), then make install twice; Claude over SSH: codesign -d -r- on the installed app shows certificate leaf (not cdhash) both times, the TCC row for com.wilddog64.hoverfocus is unchanged between the two installs (read-only sqlite3), and the menu reads Running after each"
    intent: "On m2, two reinstalls in a row keep HoverFocus running with its permission intact, with no re-grant."
interface: "Makefile: CODESIGN_IDENTITY default changes (local identity when present); new variables SECURITY, CODESIGN, OPENSSL, SIGNING_NAME; new target signing-identity; new file build/.codesign-identity. No app code change."
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each red control's failing output and `git diff --stat` after restoring it. Commit nothing; Claude lands.
