# Bug: `make dr-drill-publish` fails with an opaque `Permission denied` / exit 255 when the M2 peer no longer authorizes this Mac's SSH key

**Status:** Fixed (`65156ec3`, `ade1b7e4`; offline-verified, live `make dr-drill-publish` on M5 pending operator run)
**Priority:** P2
**Severity:** medium — DR drill results cannot be published from a Mac whose key was regenerated, and the error gives no hint about the cause or the remedy
**Filed:** 2026-11-04
**Detected by:** operator running `make dr-drill-publish` on `m5-air.local` (2026-11-04)
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-03-webhook-post-provision-tunnel-port-and-provider-apps.md` (same stale-key class on the Hostinger tunnel)

## Evidence

On `m5-air.local`, after `ssh-add ~/.ssh/id_ed25519` succeeded (`Identity added ... cliang@m5-air.local`):

```text
❯ make dr-drill-publish
cliang@m2-air.local: Permission denied (publickey,password,keyboard-interactive).
make: *** [dr-drill-publish] Error 255
```

Diagnosis (read-only, 2026-11-04):

- `bin/dr-drill-publish` runs `ssh -o BatchMode=yes -o ConnectTimeout=10 "$DR_DRILL_HOST" ...` with `DR_DRILL_HOST=m2jump` (`HostName m2-air.local`, user `cliang`).
- M5's current key is `SHA256:ASp9NdzijFI3Z3wuZm7m/a6UJHx6+HkrpEA9ROrlEIk` (`~/.ssh/id_ed25519`, regenerated 2026-10-31) and was loaded in the agent.
- `~cliang/.ssh/authorized_keys` on `m2-air.local` held only the older M5 key `SHA256:xaXRRpHQtnvEGyVF2KgCXLuhSsvbjx68Kv1gK+F789I`, so key auth was refused.
- Operator workaround: appended M5's current public key to M2's `authorized_keys`; `ssh m2jump hostname` from M5 then returned `m2-air.local` and `~/.k3dm/dr-drill` listed `20261104T141556Z.json`.

The failure is environmental (stale peer key), but the script turns it into a bare `Error 255` from `make`, which sent the operator to debug the agent and passphrase instead. `bin/dr-drill-publish` should name the failing host, the local key fingerprint, and the remedy.

## Files

- `bin/dr-drill-publish`
- `scripts/tests/bin/dr_drill_publish.bats`
- `CHANGELOG.md`

## Fix scope

1. **`bin/dr-drill-publish`:**
   - Wrap the two M2 `ssh` calls (listing and `cat`) in a small helper `_m2_ssh` that runs the same `ssh -o BatchMode=yes -o ConnectTimeout=10 "$DR_DRILL_HOST" ...` command and captures its stderr.
   - When `ssh` exits `255` and stderr contains `Permission denied`, print to stderr and exit non-zero (keep exit status `1`, not `255`):
     - `[dr-drill-publish] cannot authenticate to ${DR_DRILL_HOST}: its authorized_keys does not accept this host's key`
     - the fingerprint(s) from `ssh-add -l`, or `ssh-keygen -lf ~/.ssh/id_ed25519.pub` if the agent is empty
     - the remedy: `ssh-copy-id -i ~/.ssh/id_ed25519.pub ${DR_DRILL_HOST}` from a host that is already authorized, or append the public key to `~/.ssh/authorized_keys` on that host
   - Any other `ssh` failure keeps today's behaviour (original stderr, original exit path).
   - Do not add `-o StrictHostKeyChecking=no`, `-o PreferredAuthentications`, or any option that weakens authentication, and do not touch or write any `authorized_keys`.
2. **`scripts/tests/bin/dr_drill_publish.bats`:**
   - Keep all existing tests intact and passing.
   - Add tests for `M1`, `M2`, `N1`, `N2` below using the existing `$STUB_BIN/ssh` stub pattern (a stub that prints `Permission denied (publickey,password,keyboard-interactive).` to stderr and exits `255`).
3. **`CHANGELOG.md`:**
   - Add a `Fixed` bullet under `## [1.43.14] - Unreleased` for the actionable `dr-drill-publish` M2 authentication error.

## Acceptance

```yaml
must:
  - id: M1
    req: when the stubbed M2 ssh exits 255 with "Permission denied", bin/dr-drill-publish exits non-zero (1), prints the DR_DRILL_HOST name, a key fingerprint line, and the ssh-copy-id remedy to stderr
  - id: M2
    req: when the stubbed M2 ssh succeeds, bin/dr-drill-publish behaves exactly as before (existing tests stay green; positive control for N1)
must_not:
  - id: N1
    req: on an authentication failure, bin/dr-drill-publish never runs git clone, git push, or curl (nothing is published or pushed)
  - id: N2
    req: bin/dr-drill-publish never adds StrictHostKeyChecking=no, PasswordAuthentication or any other authentication-weakening ssh option, and never writes to any authorized_keys file
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: >-
      BATS in scripts/tests/bin/dr_drill_publish.bats prove M1 and N1 fail (red) on pre-fix code and M1, M2, N1, N2 pass (green) on fixed code; N2 is a grep assertion over the script text.
    what: env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/bin/dr_drill_publish.bats
```

## Rules

- Touch only the 3 files listed under `## Files`. Do not create or modify any other files, and do not touch `memory-bank/`.
- Do not run `git add`, `git commit`, or `git push`. Leave changes in the working tree.
- Never weaken, skip, or delete any existing test in `scripts/tests/bin/dr_drill_publish.bats`.
- Run and paste the output of:
  - `bats scripts/tests/bin/dr_drill_publish.bats`
  - `shellcheck bin/dr-drill-publish`
  - `git --no-pager diff --check`
