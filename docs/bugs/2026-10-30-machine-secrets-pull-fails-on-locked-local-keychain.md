# Bug: secrets pull fails on a locked local keychain, and setup has no way to skip secret prompts

**Status:** LIVE-VERIFIED 2026-10-30 — `67391f97` (Luna, amended by Claude); E3 live on the M5 at `deef0217`: 15 records copied, every secret ok, no prompt
**Fix commit:** 67391f97
**Live evidence:** 2026-10-30 · run machine-setup-role-hub-from-m4 · env m5-air · scenario secrets-pull-with-unlocked-local-keychain · commit deef0217 · proves E3
**Priority:** P3
**Approval:** operator, 2026-10-30 ("go ahead", after the M5 pull run)
**Filed:** 2026-10-30
**Detected by:** operator (first live `make machine-setup ROLE=hub FROM=m4-air.local` on the M5)
**Affected:** `bin/k3dm-machine-secrets` `pull`; `bin/k3dm-machine-setup` secret prompts; `Makefile` `machine-setup`
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/plans/v1.43.12-machine-secrets-copy.md` (Part 2, E6)

## Observed failure

The operator ran setup on the M5 from an ssh session (`ttys000`, from the M4). The pull worked on the
old Mac: it unlocked the M4 keychain and exported all 15 records. Every import on the M5 then failed
with `the login keychain is locked; run this in a terminal on the Mac itself, not over SSH`, because an
ssh session on the M5 sees its login keychain locked. Setup then offered `[y/N]` for each missing item.
The operator answered `y`; every setup command failed harmlessly (keychain write denied, `APPROVERS`
unset, no Argo CD admin password, no Vault shards). Had the keychain been writable, `k3dm-webhook-setup`
would have rotated the live webhook token that the M4 still uses.

## Root cause

1. `pull` unlocks the **remote** keychain (`export --unlock`) but never checks the **local** one, so a
   locked local keychain fails every record after the remote password has already been sent.
2. Setup has no option to answer every secret prompt with N. On a new Mac, `y` runs commands that mint
   or rotate credentials against a hub that is not there yet.

## Fix

### `bin/k3dm-machine-secrets pull`

Before reading the remote password, check the local target keychain (`--keychain PATH`, else
`$HOME/Library/Keychains/login.keychain-db`) with `security show-keychain-info`. If its output contains
`User interaction is not allowed`, the keychain is locked:

- prompt once on `/dev/tty`: `Login password for this Mac's keychain: ` (silent read, same pattern as the
  remote password; no tty → error `a terminal is required to unlock this Mac's keychain`);
- unlock with the password on stdin: `printf '%s\n' "$pw" | security unlock-keychain "$target"`; never
  pass it with `-p` or in any argv;
- on unlock failure, exit non-zero with `could not unlock this Mac's keychain`, before any ssh;
- `unset` the password afterwards.

An unlocked local keychain gets no prompt.

### `bin/k3dm-machine-setup` and `Makefile`

- New option `--secrets ask|skip` (default `ask`). Any other value: usage error, exit 2.
- `skip`: never print the `[y/N]` prompt and never run a manifest setup command; each missing item is
  reported `missing (skipped: SECRETS=skip)`. The `FROM` pull still runs.
- `Makefile` `machine-setup` forwards `$(if $(SECRETS),--secrets "$(SECRETS)")`.

### Docs

`docs/howto/machine-setup.md`: say that the pull unlocks this Mac's keychain when it is locked (ssh
sessions), name `SECRETS=skip`, and recommend `SECRETS=skip` with `FROM=` on a new Mac.

**As landed (Claude's review, 2026-10-30).** Three amendments: the local password prompt goes to
`/dev/tty` like the remote one (Luna's went to stderr); the M1 test's fixture was `svc`/`acct`, which
export filters out because it is not in the hub manifest, so the test never passed outside the Codex
sandbox, where it skipped. It now uses a listed record. Its mid-test `! grep` for the password was a
no-op in bats and now ends with `|| false`. Outside the sandbox: 72 ok, 0 skipped; shellcheck clean.
Mutation checks on temp copies turned a test red for each guard: no local unlock, always prompt,
unlock failure ignored, password passed with `-p`, no skip branch, no value check, no Make forward,
and default `skip`.

**Live check E3 (2026-10-30).** The operator ran `make machine-setup ROLE=hub FROM=m4-air.local
SECRETS=skip` on the M5 at `deef0217`. All 15 records were exported and copied, every `secret:` line
read `ok`, and no `[y/N]` prompt appeared. The local keychain was already unlocked, so no local prompt
(M2). Setup then failed later in the agent stage (Hermes credentials missing), which is outside this bug.

## Files

- `bin/k3dm-machine-secrets`
- `bin/k3dm-machine-setup`
- `Makefile`
- `scripts/tests/bin/machine_secrets.bats`
- `scripts/tests/bin/machine_setup.bats`
- `docs/howto/machine-setup.md`
- `CHANGELOG.md` (one `### Fixed` line under `[Unreleased]`)

## What NOT to do

- Do not use real ssh, and do not lock or unlock the login keychain, in tests. Use throwaway keychains
  (`security create-keychain` in `$BATS_TEST_TMPDIR`) and the existing fake ssh and `tty_run` helpers.
- Do not pass any password with `-p` or in argv, and do not print it.
- Do not change export, the record format, `import --in FILE`, or the manifest.
- Do not create a PR, commit to `main`, or skip hooks with `--no-verify`.
- Write the must_not tests first and show them red against the pre-fix code on a temp copy.
- `security create-keychain` fails inside the Codex sandbox (rc 206); mark those tests `skip` there and
  say so — Claude runs them outside.

## Acceptance

```yaml
must:
  M1: pull with a locked local target keychain prompts once on the terminal for this Mac's password, unlocks that keychain, and imports every streamed record.
  M2: pull with an unlocked local target keychain does not prompt for this Mac's password.
  M3: make machine-setup ROLE=<role> SECRETS=skip passes --secrets skip, and setup with --secrets skip on a terminal prints no [y/N] prompt, runs no manifest setup command, and reports each missing item as missing (skipped: SECRETS=skip).
  M4: setup with --secrets skip and --from still runs the pull.
  M5: The machine-setup how-to names SECRETS=skip and the local keychain unlock.
must_not:
  N1: The local keychain password never appears in any argv (security or ssh) or in output.
  N2: A failed local unlock exits non-zero before ssh is invoked.
  N3: --secrets with a value other than ask or skip exits 2.
  N4: Without --secrets, setup still prompts [y/N] for a missing item on a terminal (ask is the default).
evidence:
  E1: {proves: [M1, M2, N1, N2], kind: offline, what: "bats scripts/tests/bin/machine_secrets.bats with a locked throwaway keychain, fake ssh and wrapper security logging argv; real-keychain tests run by Claude outside the sandbox"}
  E2: {proves: [M3, M4, N3, N4], kind: offline, what: "bats scripts/tests/bin/machine_setup.bats under script(1) with the stub k3dm-machine-secrets"}
  E3: {proves: [M1, M3], kind: live, what: "operator on the M5 over ssh: make machine-setup ROLE=hub FROM=m4-air.local SECRETS=skip copies all 14 items; make machine-check ROLE=hub shows them ok"}
interface:
  - bin/k3dm-machine-secrets pull --from HOST --role ROLE [--keychain PATH]
  - bin/k3dm-machine-setup --role ROLE [--from HOST] [--secrets ask|skip]
  - make machine-setup ROLE=<role> [FROM=<host>] [SECRETS=skip]
```
