# Bug: the ACG watcher runs too rarely to hit the extend window, and reads an expired sandbox as ~22 h left

**Status:** FIXED
**Filed:** 2026-10-06
**Branch:** `fix/acg-watch-interval-and-expired-ttl`
**Severity:** High. The launchd watcher lets the sandbox expire overnight and then reports it as
healthy.
**Files:** `scripts/lib/acg/playwright/acg_extend.js`, `scripts/lib/acg/tests/providers/acg_extend.test.js`,
`scripts/lib/acg/acg.sh`, `scripts/tests/lib/acg.bats`, `CHANGE.md`, `memory-bank/progress.md`

## Symptom

The launchd agent `com.k3d-manager.acg-watch` ran cleanly after the #62 fix, and the sandbox still
expired unattended. The log (k3d-manager, 2026-10-06, times UTC):

```
[acg-watch] 2026-10-06T04:42:57Z extend run
INFO: Calculated remaining TTL: ~102 minutes
INFO: Extension window not open yet (102m remaining). Skipping extension.
[acg-watch] 2026-10-06T08:12:59Z extend run
INFO: Calculated remaining TTL: ~1331 minutes
INFO: Extension window not open yet (1331m remaining). Skipping extension.
```

Nobody touched the sandbox between the two runs. At 04:42Z (21:42 PDT) 102 minutes remained, so it
shut down at about 23:24 PDT. The 08:12Z (01:12 PDT) run is after that.

## Root cause

### 1. The interval is longer than the extend window

`acg_extend.js` extends only when 65 minutes or less remain (`remainingMins > 65` → skip). The launchd
job runs every `StartInterval` 12600 s (3.5 h), and `acg_watch` sleeps 12600 s between runs. A run that
lands with more than 65 minutes left skips, and the next run comes 210 minutes later, after the
sandbox is gone. A run lands inside the 65-minute window only by luck.

### 2. A shutdown time from yesterday is read as later today

The page shows only a time of day: `Auto Shutdown at 11:24 PM`. The code builds today's date at that
time. At 01:12, today's 11:24 PM is in the future, so the code computes +1332 minutes (the log shows
1331). The existing date-wrap only handles the opposite case, where the computed time is in the past
and the next day's time is under 6 hours away (`12:30 AM` seen at 11:59 PM).

A sandbox never has more than 6 hours left, so a computed time more than 6 hours ahead is yesterday's
shutdown, and the sandbox has expired.

## Fix spec

### File 1 — `scripts/lib/acg/playwright/acg_extend.js`

**1a.** Add this function directly above `async function _findExtendButton` (search for that line; put
one blank line between the new function and it):

```js
// The page shows the shutdown time of day without a date. A sandbox never has more than 6 hours
// left, so resolve the time to the instant within 6 hours of now: a time just past midnight is
// tomorrow, and a time more than 6 hours ahead is yesterday's shutdown (already expired).
function _remainingMinsFromShutdown(hours, mins, now) {
  const windowMs = 6 * 60 * 60 * 1000;
  const dayMs = 24 * 60 * 60 * 1000;
  const shutdownTime = new Date(now.getTime());
  shutdownTime.setHours(hours, mins, 0, 0);
  let deltaMs = shutdownTime.getTime() - now.getTime();
  if (deltaMs < 0 && deltaMs + dayMs < windowMs) {
    deltaMs += dayMs;
  } else if (deltaMs > windowMs) {
    deltaMs -= dayMs;
  }
  return Math.floor(deltaMs / 60000);
}
```

If `_findExtendButton` is not declared as `async function _findExtendButton`, stop and report; do not
guess a location.

**1b.** In `extendSandbox`, replace this block exactly:

```js
          const shutdownTime = new Date();
          shutdownTime.setHours(hours, mins, 0, 0);
          
          // Midnight/Date-wrap fix: the UI shows times without a date, so "12:30AM" for a
          // sandbox expiring tomorrow is constructed as today's 12:30AM (in the past).
          // Only wrap to tomorrow when the resulting next-day time is ≤ 6 hours away —
          // that covers the legitimate near-midnight case (e.g. 11:59PM→12:30AM = 31 min)
          // while correctly treating truly-expired sandboxes (2:02PM expired → next-day
          // 2:02PM is ~22h away) as expired rather than wrapping them.
          if (shutdownTime < now) {
            const minsUntilNextDay = Math.floor(
              (shutdownTime.getTime() + 24 * 60 * 60 * 1000 - now.getTime()) / 60000
            );
            if (minsUntilNextDay > 0 && minsUntilNextDay < 360) {
              shutdownTime.setDate(shutdownTime.getDate() + 1);
            }
          }
          
          const remainingMs = shutdownTime.getTime() - now.getTime();
          remainingMins = Math.floor(remainingMs / 60000);
```

with:

```js
          remainingMins = _remainingMinsFromShutdown(hours, mins, now);
```

(The original block has lines containing only trailing spaces; match them as they are in the file.)
After the edit, `const now = new Date();` above it is still used and stays. `grep -c minsUntilNextDay`
on the file must print 0.

**1c.** Add `_remainingMinsFromShutdown,` to `module.exports`, keeping the list alphabetical (it goes
between `_normalizeSandboxUrl,` and `_safeButtonLabels,`).

No other change to `acg_extend.js`. The 65-minute window, the Ghost State block and every selector stay
as they are. Note: an expired sandbox now yields a negative `remainingMins`, which already routes to
the existing expired-sandbox path (`_isSandboxExpired`) exactly as a same-day expiry does today. That
is intended; do not change that path.

### File 2 — `scripts/lib/acg/tests/providers/acg_extend.test.js`

Add `_remainingMinsFromShutdown,` to the `require` destructuring (alphabetical, after
`_normalizeSandboxUrl,`). Append a new block at the end of the file:

```js
describe('acg_extend remaining TTL from the shutdown time of day', () => {
  const at = (h, m) => new Date(2026, 9, 6, h, m, 0, 0);

  test('reads a shutdown later today as the time left', () => {
    expect(_remainingMinsFromShutdown(23, 24, at(21, 42))).toBe(102);
  });

  test('reads a shutdown just past midnight as tomorrow', () => {
    expect(_remainingMinsFromShutdown(0, 30, at(23, 59))).toBe(31);
  });

  test('reads a shutdown earlier today as expired', () => {
    expect(_remainingMinsFromShutdown(14, 2, at(16, 0))).toBe(-118);
  });

  test('reads yesterday evening shutdown seen after midnight as expired, not ~22h left', () => {
    expect(_remainingMinsFromShutdown(23, 24, at(1, 12))).toBe(-108);
  });

  test('keeps a shutdown up to 6 hours ahead as the time left', () => {
    expect(_remainingMinsFromShutdown(4, 0, at(22, 30))).toBe(330);
    expect(_remainingMinsFromShutdown(19, 0, at(13, 0))).toBe(360);
  });
});
```

### File 3 — `scripts/lib/acg/acg.sh`

Each run already skips unless 65 minutes or less remain, so running every 30 minutes is safe and
guarantees at least one run inside the window.

- In `_acg_watch_write_plist`: `<integer>12600</integer>` → `<integer>1800</integer>`.
- In `acg_watch`: `local interval="${1:-12600}"` → `local interval="${1:-1800}"`.
- In `acg_watch`: `extending every $((interval / 3600))h)` → `checking every $((interval / 60))m)`.
- `acg_watch` HELP heredoc: replace
  `Background sandbox TTL watcher. Extends the ACG sandbox every 3.5 hours` with
  `Background sandbox TTL watcher. Checks the ACG sandbox every 30 minutes and`
  and replace the next line `while the EC2 instance is alive. Stops automatically when the instance` with
  `extends it once 65 minutes or less remain, while the EC2 instance is alive.`
  `Stops automatically when the instance`
  (that is: two lines become three; the line after, `is gone (after acg_teardown).`, stays).
  Replace `Default interval: 12600 seconds (3.5 hours).` with `Default interval: 1800 seconds (30 minutes).`
- `acg_watch_start` HELP heredoc: replace
  `Install a launchd job that extends the ACG sandbox TTL every 3.5 hours,` with
  `Install a launchd job that checks the ACG sandbox every 30 minutes and extends it once 65 minutes or less remain,`
  and `macOS only. The job fires automatically at StartInterval=12600s and` with
  `macOS only. The job fires automatically at StartInterval=1800s and`.
- `acg_watch_start` final message: `Extends TTL every 3.5h — log:` → `Checks TTL every 30m — log:`.

After the edit, `grep -cE '12600|3\.5 ?h' scripts/lib/acg/acg.sh` must print 0.

### File 4 — `scripts/tests/lib/acg.bats`

Add two tests at the end of the file:

1. **`the launchd watcher plist runs every 30 minutes`**
   - `_acg_watch_write_plist` (HOME is already a temp dir from `setup`).
   - `grep -F '<integer>1800</integer>' "${_ACG_WATCH_PLIST_PATH}"`
   - `run grep -F '12600' "${_ACG_WATCH_PLIST_PATH}"` then `[ "${status}" -ne 0 ]`.
2. **`acg_watch defaults to a 30-minute interval`**
   - Stub `sleep() { printf '%s\n' "$1" >>"${BATS_TEST_TMPDIR}/sleep-args"; }` and
     `_acg_get_instance_id() { printf '\n'; }` (empty, so the loop stops after the first sleep).
   - `run acg_watch`; assert `[ "${status}" -eq 0 ]` and
     `[ "$(head -n1 "${BATS_TEST_TMPDIR}/sleep-args")" = "1800" ]`.

### File 5 — `CHANGE.md`

Under `## [Unreleased]` → `### Fixed`, add a prose entry: the launchd ACG watcher ran every 3.5 hours
but `acg_extend.js` only extends inside the last 65 minutes, so a run usually skipped with more than 65
minutes left and the next one came after the sandbox had expired. The watcher and `acg_watch` now check
every 30 minutes. Separately, the page shows the shutdown as a time of day only, so a shutdown at
11:24 PM seen at 1:12 AM was read as about 22 hours away; since a sandbox never has more than 6 hours
left, a time more than 6 hours ahead is now read as yesterday's, already expired. Reference this spec.

### File 6 — `memory-bank/progress.md`

1. On the `fix/sudo-system-path-resolution` line, replace
   `[x] PR #63 (CI green, Copilot 0 findings; awaiting operator merge) [ ] subtree-pull.` with
   `[x] PR #63 merged \`8b97c0b\` [x] subtree-pulled into k3d-manager (\`c848d37c\`).` and change its
   leading `- [ ]` to `- [x]`.
2. Directly below it add:
   `- [ ] \`fix/acg-watch-interval-and-expired-ttl\` (2026-10-06) — launchd watcher every 3.5 h misses the 65 m extend window; yesterday's shutdown time read as ~22 h left. Spec \`docs/bugs/2026-10-06-acg-watch-misses-extend-window-and-reads-expired-as-22h.md\`.`

Flip this file's **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix RED: add File 2's tests first and run `npx jest tests/providers/acg_extend.test.js` from
      `scripts/lib/acg` against the unmodified `acg_extend.js`: the new block fails (the function does
      not exist). Then add File 4's two tests and run them against the unmodified `acg.sh`: both fail.
      Paste both outputs.
- [ ] After the fix: jest full suite (`npm test` in `scripts/lib/acg`) green and `npm run check` clean;
      paste counts.
- [ ] Mutation A: in `_remainingMinsFromShutdown`, delete the `else if (deltaMs > windowMs)` branch
      (the two lines and its closing brace). Exactly the "yesterday evening" test goes red (the 360 case
      still passes). Restore from a `$TMPDIR` snapshot; prove with `cmp`.
- [ ] Mutation B: change `deltaMs > windowMs` to `deltaMs >= windowMs`. The 360 test goes red. Restore
      and prove with `cmp`.
- [ ] Mutation C: in `acg.sh` set the plist back to `12600`. The plist test goes red. Restore and prove
      with `cmp`.
- [ ] `make bats` green; paste pass/fail counts.
- [ ] `shellcheck scripts/lib/acg/acg.sh` shows no new findings vs `HEAD`.
- [ ] Changes left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT run `launchctl`, `acg_watch_start`, `acg_extend.js` against a real browser, or anything live.
  The operator is running `make up` against the real sandbox right now.
- Do NOT change the 65-minute extend window, the Ghost State block, `_isSandboxExpired`, any selector,
  or the wrapper writer.
- Do NOT edit any file outside the six listed. Do NOT touch other unstaged changes.
- No commit, push, PR, merge, or `--no-verify`. Do NOT switch branches or touch `main`.
