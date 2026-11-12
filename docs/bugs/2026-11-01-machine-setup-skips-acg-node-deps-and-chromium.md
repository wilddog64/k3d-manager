# Bug: `make machine-setup` installs no ACG Node packages or Playwright Chromium, so a new hub cannot run the ACG browser automation

**Status:** OPEN — redo on v1.43.16 (operator, 2026-11-09; was v1.43.15). The 2026-11-01 Codex run exited 0 but was never landed; its base fell ~200 changed lines behind `bin/k3dm-machine-setup`, so the task was abandoned and the fix is to be redispatched fresh. The old function is kept below as a reference.
**Priority:** P3
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (Automated hub setup omits ACG Node packages and Playwright Chromium, but manual installation (`npm install && npx playwright install chromium`) works around the failure); Claude proposed P3. Higher stands until the operator decides.
**Triage:** passed over (v1.43.16 was not cut; this does not count as a pass-over: it was picked 2026-11-09) — grooming 2026-11-12, operator. Priority: operator kept Claude's P3 over Argon's P2.
**Waiting on:** operator decision — since 2026-11-12
**Intent approved:** operator, 2026-11-08 ("approve machine-setup intents")
**Severity:** low — one manual `npm install` per checkout clears it; found on the M5 hub
**Approval:** operator, 2026-11-01 (hub migration gap, filed as found)
**Filed:** 2026-11-01
**Detected by:** operator + Claude, `make credential-test` in lib-foundation on the M5 (`m5-air.local`)
**Affected:** `bin/k3dm-machine-setup`
**Branch:** `k3d-manager-v1.43.16` (operator, 2026-11-09)

## Observed failure

On the M5, 2026-11-01, `make credential-test` in the lib-foundation checkout printed
`ERROR: [acg] Playwright-managed Chromium not found — run 'npm install' ...` and failed. The checkout had no
`scripts/lib/acg/node_modules`, so `require("playwright")` threw `MODULE_NOT_FOUND`. `cdp.sh`'s resolver hides
that error with `2>/dev/null`. After `npm install && npx playwright install chromium` in that directory, the same
target passed (credentials validated with `sts:GetCallerIdentity`).

## Root cause

`bin/k3dm-machine-setup` has no step for the Node packages or the Playwright browser that `scripts/lib/acg` needs.
Neither its install pass nor its `--check` pass mentions `npm`, `node_modules` or `playwright`. A new hub works only if
someone ran `npm install` there by hand.

## Fix

Add a machine-setup item for `scripts/lib/acg` in the k3d-manager checkout. On install, it runs `npm ci` and
`npx playwright install chromium` there. In `--check`, it reports `ok` when
`require("playwright").chromium.executablePath()` resolves to an existing file, and `missing` otherwise. A missing
item fails `--check` for the hub role, like the other required items. Do the same for a lib-foundation checkout at
`../lib-foundation` only if one exists. Its absence is not an error.

## Files

- `bin/k3dm-machine-setup`
- `scripts/tests/bin/machine_setup.bats`
- `scripts/tests/bin/machine_setup_acceptance.bats` (the complete-hub fixture)
- `CHANGELOG.md`

## What NOT to do

- Do not run `npm install` or download a browser in tests; stub `npm`, `npx` and `node` from a real capture (host and date in a comment).
- Do not edit `scripts/lib/acg/` (subtree; the resolver's swallowed error is a lib-foundation fix, upstream first).

## Acceptance

```yaml
must:
  M1: --check on a hub whose scripts/lib/acg has no resolvable Playwright Chromium reports the item missing and exits 1
  M2: --check on a complete hub with a resolvable Chromium reports the item ok and exits 0 (paired control)
  M3: the install pass runs npm ci and npx playwright install chromium in scripts/lib/acg
must_not:
  N1: a missing ../lib-foundation checkout never fails --check
  N2: tests never invoke a real npm, npx or network download
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: You will see BATS with a scratch HOME and repo root (asserted not the real ones) and captured npm/npx/node stubs show --check fail on a missing Chromium (red on the pre-fix script, which never checks it), pass on a complete hub, the install pass call npm ci and playwright install in scripts/lib/acg, and no lib-foundation checkout cause no failure.
    what: bats scripts/tests/bin/machine_setup.bats scripts/tests/bin/machine_setup_acceptance.bats
  E2:
    proves: [M2]
    kind: live
    intent: You will see make machine-setup --check on the M5 report the ACG Chromium item ok.
    what: operator run on the M5
interface:
  - bin/k3dm-machine-setup --role hub [--check]
  - scripts/lib/acg/node_modules (playwright chromium.executablePath)
```

## Prior attempt (2026-11-01, abandoned 2026-11-08)

Reference only: the Codex run's `bin/k3dm-machine-setup` addition, written against base `15549a06`. Re-check it against the current script before reusing any of it; its tests were not reviewed.

```bash
ensure_acg_chromium() {
  [[ "$role" == hub ]] || return 0
  local dir label browser
  for dir in "$REPO_ROOT/scripts/lib/foundation/scripts/lib/acg" "$REPO_ROOT/../lib-foundation/scripts/lib/acg"; do
    label=acg:chromium
    [[ "$dir" == "$REPO_ROOT/scripts/lib/foundation/scripts/lib/acg" ]] || { label=acg:lib-foundation-chromium; [[ -d "$REPO_ROOT/../lib-foundation" ]] || continue; }
    if [[ "$mode" == dry-run ]]; then report "$label" 'planned (npm ci; npx playwright install chromium)'; continue; fi
    if [[ "$mode" == setup ]]; then
      if (cd "$dir" && log_install npm ci && log_install npx playwright install chromium); then report "$label" installed
      else record_failure "$label" 'missing (see machine-setup.log)'; fi
    else
      browser="$(cd "$dir" && node -e 'console.log(require("playwright").chromium.executablePath())' 2>/dev/null)" || browser=''
      if [[ -n "$browser" && -f "$browser" ]]; then report "$label" ok; else record_failure "$label" missing; fi
    fi
  done
}

ensure_acg_chromium
```
