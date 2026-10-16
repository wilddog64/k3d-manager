# `acg-credential-test` treats a broken `aws` CLI as invalid credentials and destroys a working sandbox

**Date:** 2026-09-12
**Status:** OPEN — measured on a live run, fix not yet written.
**Branch (all work):** `fix/acg-prism-monogram-selector`
**Severity:** high — a local toolchain fault triggers an unnecessary **destructive** action
(sandbox delete + restart) against a sandbox whose credentials were in fact valid.

## Problem

`scripts/lib/acg/bin/acg-credential-test` validates extracted credentials with:

```bash
if ! AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity >/dev/null 2>&1; then
  printf 'WARN: sts:GetCallerIdentity failed — restarting sandbox for fresh credentials...\n' >&2
  _do_restart "$@"
```

`>/dev/null 2>&1` discards everything and the test keys only on exit status, so these three
outcomes are indistinguishable:

1. STS rejected the credentials (the case the restart is designed for).
2. The `aws` binary could not start at all — missing, wrong version, broken dynamic link.
3. A network or endpoint failure.

Only case 1 justifies deleting the user's sandbox. Cases 2 and 3 do not, and case 2 makes
the restart *guaranteed to fail again*, because a CLI that cannot start will not start after
a restart either. The script then restarts once, re-extracts, re-probes, and exits 1 —
having destroyed a working sandbox for nothing.

## Observed, live, 2026-09-12

`make credential-test PROVIDER=aws` extracted credentials successfully, then:

```
WARN: sts:GetCallerIdentity failed — restarting sandbox for fresh credentials...
INFO: Deleting and restarting sandbox to recover fresh credentials...
...
ERROR: sts:GetCallerIdentity failed — credentials invalid after all attempts.
make: *** [credential-test] Error 1
```

The credentials were **not** invalid. Verified independently with a stdlib SigV4 call to
`sts.amazonaws.com` using the same `~/.aws/credentials`:

```
STS RESULT: VALID
  identity: arn:aws:iam::<account>:user/cloud_user
```

The `aws` CLI on this host cannot start at all:

```
ImportError: dlopen(.../_awscrt.abi3.so):
  Library not loaded: /opt/homebrew/opt/aws-c-s3/lib/libaws-c-s3.1.0.dylib
```

`awscli` 2.36.44's bottle links `libaws-c-s3.1.0.dylib`; the installed `aws-c-s3` is 1.1.0,
which ships only `libaws-c-s3.1.1.0.dylib`. `brew reinstall awscli` does not help — it
refetches the same bottle, and `brew outdated` lists neither formula.

So a Homebrew ABI mismatch deleted a live ACG sandbox.

## Required change

### 1. Preflight the CLI before using its exit status as a verdict

Add a check that distinguishes "tool unusable" from "credentials rejected". Before the
first probe:

```bash
_aws_cli_usable() {
  local _probe_err
  _probe_err="$(aws --version 2>&1)" || {
    printf 'ERROR: the aws CLI is present but cannot run — credential validation is impossible.\n' >&2
    printf 'ERROR: %s\n' "${_probe_err}" >&2
    return 1
  }
  return 0
}
```

If `_aws_cli_usable` fails: report clearly, **exit non-zero without restarting anything**,
and say that the extracted credentials were written to `~/.aws/credentials` but could not be
validated locally. Never call `_do_restart` on this path.

### 2. Keep the probe's error text instead of discarding it

Replace `>/dev/null 2>&1` on both probes with capture, so the failure reason survives:

```bash
_sts_probe_err="$(AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity 2>&1 >/dev/null)"
_sts_rc=$?
```

Restart only when the failure looks like a credential rejection — `InvalidClientTokenId`,
`ExpiredToken`, `AuthFailure`, `SignatureDoesNotMatch`, `AccessDenied`, `UnrecognizedClientException`.
On any other non-zero result, print the captured stderr and exit non-zero **without**
restarting. When the reason is unrecognized, the safe default is "do not destroy", because
the restart is irreversible and the diagnosis is uncertain.

### 3. Same treatment for the Azure path

`_az_sp_valid` has the same shape and the same latent bug. Apply the equivalent guard so a
broken or missing `az` CLI cannot trigger a destructive recovery.

### 4. Tests — `scripts/tests/lib/acg.bats`

With `aws` stubbed on `PATH`:

1. Stub `aws` exiting non-zero on `--version` → the script exits non-zero, prints the
   "cannot run" error, and `_do_restart` is **never** called (assert via a sentinel file).
2. Stub `aws` succeeding on `--version` and emitting `InvalidClientTokenId` on
   `sts get-caller-identity` → `_do_restart` **is** called exactly once.
3. Stub `aws` succeeding on `--version` and failing with a network error
   (`Could not connect to the endpoint URL`) → exits non-zero and `_do_restart` is **never**
   called.

## Out of scope — operator action

Repairing the host `aws` CLI is not this script's job. Current options, none automated here:

- `brew reinstall --build-from-source awscli` — rebuilds against the installed `aws-c-s3 1.1.0`.
- Install the official AWS CLI v2 pkg from Amazon and drop the Homebrew formula.
- Wait for Homebrew to ship an `awscli` bottle rebuilt against `aws-c-s3 1.1`.

## Definition of done

- [ ] A CLI that cannot execute never triggers `_do_restart`.
- [ ] Both STS probes retain and surface their error text.
- [ ] Restart happens only on recognized credential-rejection error codes.
- [ ] `make lint`, `make shellcheck-lib`, `make bats` green including the three new cases.
- [ ] Only `bin/acg-credential-test` and `scripts/tests/lib/acg.bats` modified.

## What NOT to do

- Do NOT create a PR, merge, or commit to `main`. Do NOT use `--no-verify`.
- Do NOT run `brew`, install, upgrade, or otherwise modify the host toolchain.
- Do NOT run `make credential-test` / `restart-test` / `extend-test`, launch Chrome, touch
  port 9222, or delete an ACG sandbox. Use stubs on `PATH` — that is the whole point here.
- Do NOT print, echo, or log credential values.
