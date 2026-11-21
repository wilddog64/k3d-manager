# Bug: password-bundle Keychain and input errors give no next step (locked Keychain on show, vague recipient error, stale enroll hint)

**Status:** OPEN — filed 2026-11-21
**Priority:** P3 (usability: every failure has a manual workaround; no data or service impact)
**Introduced by:** ddd9329e (v1.45.0 plan 2, password_bundle.sh first landed)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-21
**Prior art:** exact-slug glob none; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing on the M4, 2026-11-21); grep `docs/bugs` for keychain found `2026-11-08-find-similar-docs-rc36-hint-skips-locked-keychain.md` (read, same rc-36 cause in a different tool; its capture is reused below) and `2026-10-30-machine-secrets-pull-fails-on-locked-local-keychain.md` (read, same cause; its LIVE-VERIFIED unlock pattern is reused below)
**Approval:** operator, 2026-11-21: "go ahead to file it" (after Claude proposed filing one doc for the three messages and fixing inside v1.45.0, since plan 2 is a v1.45.0 feature)
**Intent approved:** pending
**Filed:** 2026-11-21
**Detected by:** operator, enrolling m2-air for the travel bundle, 2026-11-21
**Branch:** `k3d-manager-v1.45.0`

## Symptom

Three failures on 2026-11-21 left the operator without a next step:

1. `make password-bundle-show` on m4-air, from an SSH session, printed
   `security command failed (36): security find-generic-password -a identity -s k3dm-password-bundle-age -w` and
   `make: *** [password-bundle-show] Error 1`. The same bundle opened on m2-air, so the bundle and recipients were fine;
   the M4's own Keychain refused the read. Claude confirmed the item exists (lookup without `-w`, rc 0).
2. `make password-bundle-add-laptop NAME=m2-air` (no `KEY`) printed only `Invalid recipient name or key.`, which does not
   say which value is wrong or what a valid key looks like.
3. `make password-bundle-enroll` ends with `On the hub: make password-bundle-add-recipient NAME=<laptop> KEY=...`. Since
   revision 2 (`39a24a59`) the one-step command is `make password-bundle-add-laptop`; `add-recipient` alone leaves the
   new laptop unable to decrypt until a `FORCE=1` publish.

## Cause

- `password_bundle_show` (`scripts/plugins/password_bundle.sh:110`) and `password_bundle_enroll` (`:21`, `:25`) pass any
  `security` failure through. rc 36 is `errSecInteractionNotAllowed`. It has two causes that need different fixes, and
  `security show-keychain-info` tells them apart without reading an item. Real capture on m4-air over SSH, 2026-11-08
  (`docs/bugs/2026-11-08-find-similar-docs-rc36-hint-skips-locked-keychain.md:28-33`):
  - With the login Keychain locked for the session, `show-keychain-info` gives rc 36 and every `-w` read gives rc 36.
  - After `security unlock-keychain`, `show-keychain-info` gives rc 0 (`no-timeout`), and a read that still gives rc 36
    is the item's access control.

  `bin/k3dm-machine-secrets:80-91` already detects the locked case from the `User interaction is not allowed` output and
  unlocks with a `/dev/tty` prompt and the password on stdin (LIVE-VERIFIED 2026-10-30).
- `password_bundle_add_recipient` (`:35`) checks `NAME` and `KEY` in one test with one message.
- The enroll hint (`:29`) predates revision 2.

## Workaround

- **Locked Keychain:** run `security unlock-keychain ~/Library/Keychains/login.keychain-db` in that session, then retry.
- **Item access:** run the command once in Terminal at the Mac's own screen and choose Always Allow.
- **Bad input:** pass both `NAME=` and a complete `KEY=age1…` (62 characters).

## Fix

All in `scripts/plugins/password_bundle.sh`:

1. A private helper `_password_bundle_keychain_hint <rc>`, called when a `security` read of the identity fails in
   `password_bundle_show`, and in `password_bundle_enroll` for any rc other than 0 and 44. On rc 36 it runs
   `security show-keychain-info "${K3DM_PASSWORD_BUNDLE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"`.
   - **Locked** (output contains `User interaction is not allowed`) **and stdin is a terminal:**
     1. Print `Login Keychain is locked; unlocking it.` to stderr.
     2. Read the password with `read -r -s` from `/dev/tty` and pipe it on stdin to `security unlock-keychain <keychain>`,
        following the `bin/k3dm-machine-secrets:82-91` pattern; unset the variable straight after.
     3. Retry the identity read once. If the unlock fails, print `Could not unlock the login Keychain.` and return 1.
   - **Locked and stdin is not a terminal** (launchd, pipes): print
     `Login Keychain is locked; run: security unlock-keychain ~/Library/Keychains/login.keychain-db, then retry.` and
     return 1. No prompt and no wait.
   - **Not locked:** print
     `Keychain refused this read; run this command once in Terminal on this Mac's screen and choose Always Allow.` and
     return 1.

   Any other rc keeps today's behaviour (return 1; enroll keeps `Unable to read Keychain identity.`).
2. `password_bundle_add_recipient`: test `NAME` and `KEY` separately.
   - Bad `NAME`: `Invalid NAME: use 1-32 lowercase letters, digits or hyphens.`
   - Bad `KEY`: `Invalid KEY: pass the full age1... public key that password-bundle-enroll printed.`

   Validation rules are unchanged.
3. Enroll's last line: `On the hub: make password-bundle-add-laptop NAME=<laptop> KEY=<key>`.
4. `docs/howto/service-password-travel-bundle.md`: one sentence on the locked-Keychain prompt and the Always Allow case.
5. `CHANGELOG.md`, open v1.45.0 Fixed section: one line.

## Contract readers

Found by grep 2026-11-21. No env var, path or Keychain item name changes. `K3DM_PASSWORD_BUNDLE_KEYCHAIN` is new, read
only by the helper, and defaults to today's login Keychain.

- `scripts/tests/plugins/password_bundle.bats:178-190` (N7) asserts no file change and no install on bad input. `:187`
  matches the old `Invalid recipient name or key.` text, so change it to the new `Invalid NAME` / `Invalid KEY` messages;
  the rest of N7 is unedited and must pass. Re-grep 2026-11-21: no other reader of the old text in `scripts/`, `bin/` or
  `docs/` (the plan doc at `docs/plans/v1.45.0-service-password-travel-bundle.md:43` names the command, not the
  message).
- The launchd plist runs `password_bundle_publish`, which reads no Keychain item, so it is unaffected. The non-terminal
  branch still guards any future unattended caller.
- `docs/howto/service-password-travel-bundle.md:3` names both commands already. Only the new sentence is added.

## What NOT to Do

- Never read, print or log the identity or the Keychain password; never pass the password in argv (`-p`); no `set -x`
  (the functions already `set +x`).
- No change to `bin/k3dm-machine-secrets`, `prior_art.py` or any other Keychain caller; no shared-library refactor.
- Tests use the existing `security` stub. Never call the real `security` binary from bats.

## Acceptance

```yaml
interface:
  - "password-bundle-show and -enroll: rc 36 + locked Keychain + terminal → unlock prompt then one retry; + no terminal → 'Login Keychain is locked; run: security unlock-keychain …' rc 1; rc 36 + unlocked → 'Always Allow' message rc 1"
  - "password-bundle-add-recipient / -add-laptop: separate 'Invalid NAME' and 'Invalid KEY' messages"
  - "password-bundle-enroll last line names make password-bundle-add-laptop"
must:
  - id: M1
    text: "show with the identity read stubbed to rc 36 and show-keychain-info stubbed to 'User interaction is not allowed' rc 36, stdin not a terminal: exits non-zero, stderr names 'security unlock-keychain', and unlock-keychain is never called"
  - id: M2
    text: "show with the same locked stubs under a pseudo-terminal (python3 pty) with a password fed on it: unlock-keychain is called once with the password on stdin (not argv), the identity read is retried once, and show prints the decrypted output"
  - id: M3
    text: "show with the identity read stubbed to rc 36 and show-keychain-info rc 0: exits non-zero with the 'Always Allow' message and never calls unlock-keychain"
  - id: M4
    text: "add-recipient with a bad NAME and a valid KEY prints 'Invalid NAME'; with a valid NAME and an empty or truncated KEY prints 'Invalid KEY'; recipients file unchanged in both"
  - id: M5
    text: "enroll's printed hint names 'make password-bundle-add-laptop' and not 'password-bundle-add-recipient'"
  - id: M6
    text: "the howto and CHANGELOG describe the locked-Keychain prompt"
must_not:
  - id: N1
    text: "the Keychain password or the identity appears in argv logs, stdout or stderr (paired: M2's stub argv log shows unlock-keychain called and the fed password string absent from the log)"
  - id: N2
    text: "a non-36 failure (rc 44, rc 1) triggers show-keychain-info or an unlock prompt (paired: M1's rc 36 run does call show-keychain-info)"
  - id: N3
    text: "a valid NAME and KEY are rejected (paired: N7's existing valid-recipient positive control and M6 add-laptop still pass)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    kind: offline
    command: "bats scripts/tests/plugins/password_bundle.bats; Claude also runs make test outside the sandbox. New tests red on the pre-fix plugin. Mutants, each red: drop the terminal check so the non-terminal path prompts (M1); skip the retry after unlock (M2); treat rc 0 from show-keychain-info as locked (M3); restore the single combined message (M4); pass the password with -p (N1)."
    intent: "You will see tests showing a locked Keychain now tells you to unlock it, or asks for your password when you are at a terminal, and that a bad NAME or KEY says which one is wrong."
  - id: E2
    proves: [M2]
    kind: live
    command: "operator, over SSH to m4-air with the login Keychain locked for that session: make password-bundle-show prompts once for the login password and then prints the bundle"
    intent: "You will see the M4 ask for your login password over SSH and then open the bundle, instead of failing with 'security command failed (36)'."
  - id: E3
    proves: [M6]
    kind: offline
    command: "reviewer reads the howto sentence and the CHANGELOG line"
    intent: "You will see the guide explain what to do when the Keychain is locked."
```

## Files

- `scripts/plugins/password_bundle.sh`
- `scripts/tests/plugins/password_bundle.bats`
- `docs/howto/service-password-travel-bundle.md`
- `CHANGELOG.md`

## Worker definition of done

- `bats scripts/tests/plugins/password_bundle.bats` green; `git diff --check` clean.
- Commit on the task branch, push, report the SHA.
