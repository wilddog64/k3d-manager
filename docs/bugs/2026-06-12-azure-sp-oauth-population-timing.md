# Bug: Azure SP OAuth reprovision budget too small — deadline + cap allow ~2–3 cycles but worst case needs 5–6

**Date:** 2026-06-12
**Branch (lib-acg):** `feat/v0.1.7`
**Spec repo:** k3d-manager `k3d-manager-v1.6.5`
**Files:** `playwright/lib/sandbox.js` (fix), `playwright/diag/azure-field-timing.js` (new diagnostic)

---

## Problem

Pluralsight's Azure Service-Principal sometimes provisions **without a usable secret** — the
clientId/subscription/tenant fields fill but the SP secret never lands. The only recovery is
to **delete the sandbox and reprovision**, and under certain conditions this must repeat
**5–6 times** before a good SP is issued. (Confirmed by operator: a clean run often succeeds
on the first try, but the bad case genuinely needs 5–6 reprovision cycles.)

`_waitForCredentials` already implements the delete+reprovision recovery (Azure-only,
`sandbox.js` lines 217–247), but its budget is too small to ever reach 5–6 cycles:

| Constant | Value | Effect |
|----------|-------|--------|
| `deadline` | `420000` (420s) | total wall-clock for the whole wait loop |
| delete trigger | `60000` (60s) | wait on partial creds before deleting |
| delete→restart wait | `180000` (180s) | `_findScopedButton('Start Sandbox', …, 180000)` after delete |
| cap | `deleteCycleCount < 3` | max delete cycles |

**Root cause (arithmetic):** one cycle costs ~60s (partial wait) + ~180s (delete+reprovision)
≈ **240s**. A single 420s deadline fits only **~1.5 cycles** before `while (Date.now() <
deadline)` exits — so `deleteCycleCount < 3` is almost never even reached; the **deadline is
the real limiter**. The outer `acg-credential-test` restarts once (one more 420s window), so
end-to-end the flow attempts only **~2–3 reprovisions**. When the bad case needs 5–6, failure
is mathematically guaranteed — no path through the current code can reach 6 cycles. This is
why the Azure flow has churned across three releases: the previous fixes tuned mechanics
around a budget that can't span the worst case.

**Secondary suspicion (still worth measuring):** the 60s partial-creds trigger may also be
too aggressive on the *good* runs — if the SP secret normally lands at 70–110s, the code
deletes a sandbox that was about to succeed, manufacturing the multi-cycle path. The probe
below captures both: per-field population timing AND per-cycle counts.

We cannot size the deadline/cap correctly without **real data on (a) how long the SP secret
takes when it does land, and (b) how many reprovision cycles the bad case actually needs.**
A single clean run is insufficient — it only samples the happy path. We need per-cycle
instrumentation across repeated real runs.

---

## Reproduction

```bash
# lib-acg repo, with Chrome CDP running on 9222 and a Pluralsight session active
make credential-test PROVIDER=azure
```

Symptom under failure:
```
INFO: Azure SP credentials not populated after 60s — deleting sandbox and starting fresh (cycle 1/3)...
INFO: Waiting for Azure sandbox deletion (up to 180s)...
... repeats up to 3 cycles ...
ERROR: Credential extraction still failing after restart.
```

---

## Part 1 — Instrumentation (gather data across cycles, not one clean run)

A single clean observation is **not enough** — it samples whichever outcome happened that
run, usually the happy path. We must capture the **bad case** (5–6 reprovisions) and count
cycles. Two complementary instruments:

### 1a — Read-only CDP probe — `playwright/diag/azure-field-timing.js` (NEW)

Standalone, read-only. Connects to existing Chrome over CDP (does **not** launch a browser,
does **not** delete/restart/navigate), finds the Pluralsight tab, polls Azure-scoped copyable
inputs once per second. Records, relative to a `t0` at first poll:

- elapsed time each Azure field first becomes non-empty (clientId / clientSecret /
  subscription / tenant / username / password)
- elapsed time all four SP fields are simultaneously non-empty
- transitions back to empty (a reprovision wiped the panel) — so the probe also **counts
  reprovision cycles it witnesses** and the secret-population time within each cycle
- final summary table

Logs only field **labels and value lengths** — never secret values (secret hygiene).

**Connection + scan mirror the production extractor exactly:**
- CDP URL: `http://127.0.0.1:9222` (honor `PLAYWRIGHT_CDP_HOST` / `PLAYWRIGHT_CDP_PORT`)
- Page selection: first context page whose hostname ends with `.pluralsight.com`
- Field selector: `input[aria-label="Copyable input"]`
- Azure scoping + label detection: copy `_scanAzurePage`'s walk-up logic from
  `playwright/providers/azure.js` (12-ancestor scope excluding AWS/GCP; 6-then-20 label walk)
- Run budget: default 1800s, 1s poll, `--deadline <sec>`; exit 0 when all four SP land

### 1b — Per-cycle logging in the production delete-cycle — `playwright/lib/sandbox.js`

Add structured per-cycle log lines (no behavior change yet) so **every real run** records
how many cycles it needed and the timing of each. At the existing delete-cycle (line ~226)
and on success (the `vals.every(...) return` at line 215), emit:

```
AZURE-TIMING cycle=<n> partialAt=<ms> deletedAt=<ms> reason=secret-empty
AZURE-TIMING success cycle=<n> allFourAt=<ms>
```

This turns ordinary usage into a data collector — over a handful of real
`make credential-test PROVIDER=azure` runs we get the true cycle-count distribution.

### Run procedure (capture the BAD case, not just one run)

1. Chrome CDP up on 9222, active Pluralsight session.
2. Run `make credential-test PROVIDER=azure` **repeatedly** (≥5–8 runs), optionally with the
   1a probe attached in a second terminal. Keep going until at least one run exhibits the
   5–6-cycle bad case.
3. Collect from each run: cycles needed, per-cycle duration, secret-population time.
4. Record the distribution in the "Measured Data" section below before touching Part 2.

### Measured Data (fill in — required before Part 2)

| Run | Outcome | Cycles needed | Secret landed at (in final cycle) | Total wall-clock |
|-----|---------|---------------|-----------------------------------|------------------|
| 1   |         |               |                                   |                  |
| 2   |         |               |                                   |                  |
| …   |         |               |                                   |                  |

**Observed worst-case cycles:** ___  **p95 secret-population time:** ___

---

## Part 2 — Resize the reprovision budget (informed by Part 1 data)

**Do NOT change any constant until the Measured Data table is filled.** The fix is to make
the budget span the observed worst case. Three constants move together; size them from data:

### Change A — raise the cycle cap — `sandbox.js` line ~221

**Exact old block:**

```js
      if (
        providerLabel === 'Azure' &&
        partialCredsFirstSeen > 0 &&
        Date.now() - partialCredsFirstSeen > 60000 &&
        deleteCycleCount < 3
      ) {
```

**Exact new block (`<MAX_CYCLES>` = observed worst-case + 2 margin; `<TRIGGER_MS>` from 1a
secret-population p95 + margin, or keep `60000` if data shows the secret never lands without
a reprovision):**

```js
      if (
        providerLabel === 'Azure' &&
        partialCredsFirstSeen > 0 &&
        Date.now() - partialCredsFirstSeen > <TRIGGER_MS> &&
        deleteCycleCount < <MAX_CYCLES>
      ) {
```

### Change B — raise the wait-loop deadline so the cap is reachable — `sandbox.js` line ~203

The deadline must exceed `<MAX_CYCLES> × (TRIGGER + 180s reprovision)`. With the current 420s
it caps out at ~1.5 cycles regardless of `<MAX_CYCLES>`.

**Exact old block:**

```js
  const deadline = Date.now() + 420000;
```

**Exact new block (`<DEADLINE_MS>` = `<MAX_CYCLES>` × ~240000 + margin):**

```js
  const deadline = Date.now() + <DEADLINE_MS>;
```

### Change C (consider) — outer restart count — `bin/acg-credential-test`

The outer `_do_restart` fires once. If Part 1 shows the inner loop now spans the worst case on
its own, leave it. If not, document here whether the outer restart needs a counter. **Decide
from data; do not change blindly.**

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/diag/azure-field-timing.js` | NEW — read-only CDP probe; per-field + per-cycle timing |
| `playwright/lib/sandbox.js` | Part 1b: per-cycle `AZURE-TIMING` logs. Part 2: raise cap (`<3`→`<MAX_CYCLES>`) + deadline (`420000`→`<DEADLINE_MS>`), retune trigger |
| `bin/acg-credential-test` | Part 2 Change C only, if data shows it is needed |

---

## Rules

- `node --check playwright/diag/azure-field-timing.js` — must pass
- `node --check playwright/lib/sandbox.js` — must pass (Part 1b and Part 2)
- `shellcheck -S warning bin/acg-credential-test` — must pass (only if Change C applied)
- Probe (1a) is **read-only**: no `click`, no delete, no restart, no navigation
- No credential values in any output — labels and lengths only (probe and `AZURE-TIMING` logs)
- Part 1b logging must NOT change delete-cycle behavior — log lines only
- Part 2 must not be committed until the "Measured Data" table is filled in this file

---

## Definition of Done

### Part 1a (probe — separate commit)
- [ ] `playwright/diag/azure-field-timing.js` created; mirrors production CDP connect + Azure scan
- [ ] Read-only — no mutation of page/sandbox state
- [ ] Logs per-field first-populated elapsed times, all-four-populated time, and witnessed
  reprovision-cycle count (panel-empty transitions)
- [ ] No secret values in output
- [ ] `node --check` passes; committed and pushed to `feat/v0.1.7`

### Part 1b (per-cycle logging — same or separate commit)
- [ ] `AZURE-TIMING` per-cycle + success log lines added in `_waitForCredentials`
- [ ] No behavior change — verified by reading the diff (only `console.error` additions)
- [ ] `node --check playwright/lib/sandbox.js` passes; committed and pushed

### Data gate
- [ ] ≥5 real runs collected; at least one run reproduced the 5–6-cycle bad case
- [ ] "Measured Data" table filled; worst-case cycles + p95 secret time recorded

### Part 2 (fix — separate commit, after data gate)
- [ ] Change A: cap `deleteCycleCount < <MAX_CYCLES>` (worst-case + 2)
- [ ] Change B: `deadline` raised to span `<MAX_CYCLES>` cycles
- [ ] Change C: outer restart decision documented (changed only if data requires it)
- [ ] `node --check playwright/lib/sandbox.js` passes (+ shellcheck if Change C)
- [ ] Committed and pushed to `feat/v0.1.7`
- [ ] memory-bank in k3d-manager updated with all commit SHAs and task status

**Commit message (Part 1a, exact):**
```
feat(diag): add read-only Azure SP credential field-population timing probe
```

**Commit message (Part 1b, exact):**
```
chore(sandbox): add AZURE-TIMING per-cycle logging to _waitForCredentials
```

**Commit message (Part 2, exact — after data):**
```
fix(sandbox): resize Azure reprovision budget (cap + deadline) to span measured worst case
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed targets
- Do NOT commit to `main` — work on `feat/v0.1.7` in lib-acg
- Do NOT change cap/deadline/trigger before the Measured Data table is filled
- Do NOT make the probe (1a) mutate sandbox state — it must be read-only
- Do NOT let Part 1b logging alter delete-cycle timing or control flow
