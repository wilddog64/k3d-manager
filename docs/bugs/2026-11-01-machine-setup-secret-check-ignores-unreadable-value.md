# Bug: a locked login Keychain reads as "ok" in machine setup and as "not in Keychain" in platform-ops

**Status:** OPEN
**Priority:** P3
**Severity:** low — misleading output; on 2026-11-01 `make platform-ops` skipped two Keychain-backed Secrets while machine setup had reported both items ok
**Approval:** operator, 2026-11-01 ("file as you ranked and dispatch to Luna")
**Filed:** 2026-11-01
**Detected by:** Claude, comparing the M5 machine-setup report with the `make platform-ops` output
**Affected:** `bin/k3dm-machine-setup`, `scripts/plugins/argocd.sh` (`_argocd_keychain_value` callers)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-11-01-rotators-outside-platform-ops-miss-release-deploy.md`

## Observed failure

On the M5 hub, `make machine-setup ROLE=hub` reported `secret:k3dm-platform-ops-slack-url:k3dm ok` and
`secret:platform-ops-git-writer:k3dm ok`. Shortly after, `make platform-ops` in the operator's tmux printed:

    INFO: [argocd] platform-ops-git-writer not in Keychain (platform-ops-git-writer/k3dm) — optional CVE git-writer PAT; skipping ...
    INFO: [argocd] k3dm-platform-ops-slack-url not in Keychain

## Root cause

- `bin/k3dm-machine-setup` `secret_present` runs `security find-generic-password -s <service> [-a <account>]` without
  `-w`. That succeeds when the item exists, whether or not its value can be read.
- `platform-ops` reads the value with `_argocd_keychain_value` and prints "not in Keychain" whenever the value comes back
  empty, which includes a locked login Keychain.
- From an SSH session, the login Keychain is locked. Captured read-only on 2026-11-01, on m4-air.local (Claude's
  session) and on m5-air.local over SSH, macOS 26.5.1:

      $ security show-keychain-info ~/Library/Keychains/login.keychain-db
      security: SecKeychainCopySettings /Users/cliang/Library/Keychains/login.keychain-db: User interaction is not allowed.
      rc=36

  Unlocked case, captured by the operator on m5-air.local in a local Terminal, 2026-11-01:

      $ security show-keychain-info ~/Library/Keychains/login.keychain-db
      Keychain "/Users/cliang/Library/Keychains/login.keychain-db" no-timeout

  The stub prints this line for the unlocked case and exits 0. The `no-timeout` word reflects this Keychain's
  lock setting, so the code must key on the exit code, not on that text.

## Fix

1. `bin/k3dm-machine-setup`: when the role's secrets manifest has at least one entry, add one report line
   `keychain:login` before the secret lines. It reports `ok` when `security show-keychain-info` on the login Keychain
   exits 0, and `locked (reads will fail in this session; run from a local Terminal)` when it exits non-zero, through
   `record_failure` in setup and check modes. Secret lines keep their existence-only check.
2. `scripts/plugins/argocd.sh`: where an `_argocd_keychain_value` read comes back empty, check whether the item exists
   (no `-w`). If it exists, log `<service> present in Keychain but unreadable (login Keychain locked?)` as a WARN instead
   of "not in Keychain". Keep the existing skip behaviour.
3. No value is ever read by machine setup, and no value is printed by either tool.

## Files

- `bin/k3dm-machine-setup`
- `scripts/plugins/argocd.sh`
- `scripts/tests/bin/machine_setup.bats`
- `scripts/tests/bin/machine_setup_acceptance.bats`
- `scripts/tests/plugins/argocd_keychain_unreadable.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not add `-w` or `-g` to any `security` call in `bin/k3dm-machine-setup` (its acceptance suite forbids it).
- Do not unlock the Keychain or prompt for its password.
- Do not edit `scripts/lib/foundation/`.

## Acceptance

```yaml
must:
  M1: machine setup prints keychain:login ok when show-keychain-info exits 0 and keychain:login locked when it exits 36 (paired), and locked makes the run exit nonzero
  M2: platform-ops logs "present in Keychain but unreadable" when the value read is empty and the item exists, and keeps "not in Keychain" when the item does not exist (paired)
must_not:
  N1: machine setup never calls security with -w or -g and never prints a secret value
  N2: neither tool unlocks the Keychain, prompts for a password, or prints a secret value in any message
evidence:
  E1:
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: >-
      You will see bats runs with a security stub (the fixture first asserts HOME and the stub are under the test
      tmpdir) whose show-keychain-info output and exit code come from the captured rc-36 text above and the operator's
      unlocked capture, each with host and date in a comment. The locked case prints keychain:login locked and exits 1;
      the unlocked case prints ok. For platform-ops, the stub returns an empty value with the item present, then absent,
      and the two messages differ. A call log shows no -w or -g from machine setup and no unlock-keychain call.
    what: bats scripts/tests/bin/machine_setup.bats scripts/tests/bin/machine_setup_acceptance.bats scripts/tests/plugins/argocd_keychain_unreadable.bats
  E2:
    proves: [M1]
    kind: live
    intent: You will see make machine-check ROLE=hub on the M5 over SSH print keychain:login locked, and from a local Terminal print ok.
    what: operator on the M5, Claude reads the report
interface:
  - bin/k3dm-machine-setup (role hub; --check; scratch HOME; security on PATH)
  - scripts/plugins/argocd.sh argocd_sync_git_writer_secret, _argocd_sync_notifications_slack_secret_untraced, _argocd_keychain_value
```
