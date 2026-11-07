# Bug: acg_extend refuses on the new hub ("Auth dir is empty") because it checks a profile directory the session no longer lives in

**Status:** LANDED — fix in the subtree: both scripts resolve `PLAYWRIGHT_AUTH_DIR` or `pw-profile` (lib-foundation `bb7f1f2`, synced `c22646e1`). The unused `scripts/playwright/acg_extend.js` was removed 2026-11-06; nothing called it. Live E2 open: read the pre-flight extend in the next M5 `/cluster-up aws` log.
**Priority:** P2
**Waiting on:** live check
**Severity:** medium — on the M5 every sandbox extend fails (acg-up pre-flight and the 30-minute ACG watcher), so a sandbox dies at its first deadline; the M4 works only because a stale `profile/` dir from before October still exists there
**Approval:** operator, 2026-11-01 (session goal: finish v1.43.13 items; hub-migration gaps are filed as found); dispatch go: operator, 2026-11-01 ("go ahead to dispatch hub fixes")
**Filed:** 2026-11-01
**Detected by:** Claude, job `87c78389` on the M5
**Affected:** lib-foundation `scripts/lib/acg/playwright/acg_extend.js` (`AUTH_DIR`, `_isFirstRun`, line ~16/47/168), `acg_restart.js` (`AUTH_DIR`, line 29); k3d-manager's copy `scripts/playwright/acg_extend.js`. Fix upstream in lib-foundation, then subtree-pull.
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-01-hub-has-no-ec2-ssh-key-acg-up-fails.md` (same run)

## Observed failure

Job `87c78389` (M5), right after a successful manual login (`credential-test`: `ACG_SESSION_OK path=manual-login`):

```
INFO: [acg] acg_extend failed: ERROR: Auth dir is empty (/Users/cliang/.local/share/k3d-manager/profile).
ERROR: Run acg_get_credentials <sandbox-url> first to bootstrap the Pluralsight session.
```

## Root cause

The Chrome session lives in `PLAYWRIGHT_AUTH_DIR` (default `~/.local/share/k3d-manager/pw-profile`, `cdp.sh` lines
28/56/139). `acg_extend.js` and `acg_restart.js` still hard-code `~/.local/share/k3d-manager/profile`. They use it for
the "first run" guard and for the `launchPersistentContext` fallback. The extend itself connects over CDP, so the
guard checks a directory the extend never uses. On the M4 that directory is non-empty (left from before the
`pw-profile` move), so the guard passes by accident. The M5 never had one.

## Fix

1. `acg_extend.js` and `acg_restart.js` resolve the profile like `cdp.sh`:
   `process.env.PLAYWRIGHT_AUTH_DIR || ~/.local/share/k3d-manager/pw-profile`.
2. The first-run guard runs only on the persistent-context fallback path. When CDP on 9222 is reachable, the extend
   proceeds without checking the directory.
3. Subtree-pull into k3d-manager. Make `scripts/playwright/acg_extend.js` match, or remove it if nothing calls it
   (`acg.sh` calls the lib copy).

## Files

- lib-foundation `scripts/lib/acg/playwright/acg_extend.js`, `acg_restart.js`, their tests under `scripts/lib/acg/tests/`
- k3d-manager subtree pull; `scripts/playwright/acg_extend.js`
- `CHANGELOG.md`

## What NOT to do

- Do not create or copy a `profile/` directory on the M5 as the fix.
- Do not delete the M4's stale `profile/` directory in the fix or its tests.
- Tests use a scratch HOME (asserted not to be the real one) and a stub CDP endpoint; no real Chrome or Pluralsight.

## Acceptance

```yaml
must:
  M1: with CDP reachable and no ~/.local/share/k3d-manager/profile directory, acg_extend proceeds past the guard
  M2: the profile dir is PLAYWRIGHT_AUTH_DIR when set, else ~/.local/share/k3d-manager/pw-profile, in both acg_extend.js and acg_restart.js
must_not:
  N1: with CDP unreachable and an empty profile dir, acg_extend still exits non-zero with the bootstrap message (paired control for M1)
  N2: neither script reads or writes ~/.local/share/k3d-manager/profile
evidence:
  E1:
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: You will see the lib-foundation node tests in a scratch HOME pass the guard with a stub CDP and no profile dir (red on the pre-fix script), fail with CDP down and an empty pw-profile, and resolve PLAYWRIGHT_AUTH_DIR.
    what: npm test in scripts/lib/acg (lib-foundation)
  E2:
    proves: [M1]
    kind: live
    intent: You will see on the M5 /cluster-up aws log the pre-flight extend reach the sandbox page instead of "Auth dir is empty".
    what: Claude reads the job output on the M5
interface:
  - node scripts/lib/acg/playwright/acg_extend.js <sandbox-url>
  - node scripts/lib/acg/playwright/acg_restart.js
  - env PLAYWRIGHT_AUTH_DIR; CDP http://localhost:9222
```

## Dispatch (2026-11-01)

Fixed upstream only: lib-foundation `docs/bugs/2026-11-01-acg-new-hub-ec2-key-import-and-extend-profile.md`
Part B (branch `fix/acg-hub-ec2-key-and-extend-profile`). k3d-manager's own `scripts/playwright/acg_extend.js`
is handled after the subtree pull.
