# Bug: Azure SP OAuth credentials populate slowly; 60s partial-creds threshold may delete-and-restart prematurely

**Date:** 2026-06-12
**Branch (lib-acg):** `feat/v0.1.7`
**Spec repo:** k3d-manager `k3d-manager-v1.6.5`
**Files:** `playwright/lib/sandbox.js` (fix), `playwright/diag/azure-field-timing.js` (new diagnostic)

---

## Problem

Azure Service-Principal credentials (clientId, clientSecret, subscription, tenant) populate
into the Pluralsight sandbox panel **gradually** — some fields land early, the SP secret
lands last. `_waitForCredentials` has an Azure-only recovery path that deletes the sandbox
and restarts it if credentials are only **partially** populated for more than **60s**
(`sandbox.js` lines 217–247).

**Suspected root cause:** the 60s threshold is a guess, not measured. If the SP secret
normally lands at, say, 70–110s, the code deletes the sandbox *right before it would have
succeeded*, then pays the full deletion (up to 180s) + fresh-provision cost — up to 3 times.
This turns a slow-but-working flow into a multi-cycle failure and is the likely reason the
Azure path has churned across three releases.

We cannot fix the threshold correctly without **real per-field population timing data**.
This spec covers (1) a diagnostic probe to capture that data, then (2) the threshold fix
informed by it.

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

## Part 1 — Diagnostic probe (gather data first)

### New file — `playwright/diag/azure-field-timing.js`

A standalone, read-only probe. It connects to the existing Chrome over CDP (does **not**
launch its own browser, does **not** delete or restart anything), finds the Pluralsight tab,
and polls the Azure-scoped copyable inputs once per second. It records, relative to a `t0`
captured at first poll:

- the elapsed time at which **each** Azure field first becomes non-empty (by detected label:
  clientId / clientSecret / subscription / tenant / username / password)
- the elapsed time at which **all** four SP fields are simultaneously non-empty
- a final summary table

It logs only field **labels and value lengths** — never the secret values themselves
(secret hygiene; same posture as the production extractor).

**Connection + scan mirror the production extractor exactly:**
- CDP URL: `http://127.0.0.1:9222` (honor `PLAYWRIGHT_CDP_HOST` / `PLAYWRIGHT_CDP_PORT`)
- Page selection: first context page whose hostname ends with `.pluralsight.com`
- Field selector: `input[aria-label="Copyable input"]`
- Azure scoping + label detection: copy `_scanAzurePage`'s walk-up logic from
  `playwright/providers/azure.js` (12-ancestor scope check excluding AWS/GCP; 6-then-20
  ancestor label detection)

**Run budget:** default 600s deadline, 1s poll, configurable via `--deadline <sec>`.
Exit 0 and print the summary when all four SP fields land; exit non-zero on deadline.

### Run procedure

1. Ensure Chrome CDP is up on 9222 with an active Pluralsight session.
2. Start a **fresh** Azure sandbox (the running sandbox, if any, must be deleted first so we
   measure provisioning from t0). Either click Start in the browser, or let the operator
   trigger it — the probe only observes.
3. In a second terminal: `node playwright/diag/azure-field-timing.js`
4. Capture the full summary table. Repeat 3–5 times to get a distribution.

---

## Part 2 — Threshold fix (informed by Part 1 data)

**Do NOT change the threshold until Part 1 data is captured.** Once we have the observed
distribution of "time until all four SP fields populate", set the threshold to
**observed p95 + 30s margin** (and document the sample in this file).

### Change (placeholder — exact value TBD from data) — `sandbox.js` line 220

**Exact old block:**

```js
      if (
        providerLabel === 'Azure' &&
        partialCredsFirstSeen > 0 &&
        Date.now() - partialCredsFirstSeen > 60000 &&
        deleteCycleCount < 3
      ) {
```

**Exact new block (value `<TBD_MS>` filled from measurement):**

```js
      if (
        providerLabel === 'Azure' &&
        partialCredsFirstSeen > 0 &&
        Date.now() - partialCredsFirstSeen > <TBD_MS> &&
        deleteCycleCount < 3
      ) {
```

Open question for the data to settle: if SP population is reliably slow-but-eventual, the
delete-cycle may be the wrong mechanism entirely — a longer plain wait may beat
delete+reprovision. Record the recommendation in this file after measuring.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/diag/azure-field-timing.js` | NEW — read-only CDP probe; logs per-field population timestamps |
| `playwright/lib/sandbox.js` | Part 2 only, after data — tune the `60000` Azure partial-creds threshold |

---

## Rules

- `node --check playwright/diag/azure-field-timing.js` — must pass
- `node --check playwright/lib/sandbox.js` — must pass (if Part 2 applied)
- Probe is **read-only**: no `click`, no delete, no restart, no navigation
- Probe must never log credential values — labels and lengths only
- Part 2 must not be committed until measured data is recorded in this file

---

## Definition of Done

### Part 1 (probe)
- [ ] `playwright/diag/azure-field-timing.js` created; mirrors production CDP connect + Azure scan
- [ ] Read-only — no mutation of page/sandbox state
- [ ] Logs per-field first-populated elapsed times + all-four-populated elapsed time
- [ ] No secret values in output
- [ ] `node --check` passes
- [ ] Committed and pushed to `feat/v0.1.7`

### Part 2 (fix — separate commit, after data)
- [ ] Measurement sample (≥3 runs) recorded in this file
- [ ] Threshold set to observed p95 + 30s (or alternative mechanism justified here)
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.7`
- [ ] memory-bank in k3d-manager updated with both commit SHAs and task status

**Commit message (Part 1, exact):**
```
feat(diag): add read-only Azure SP credential field-population timing probe
```

**Commit message (Part 2, exact — after data):**
```
fix(sandbox): retune Azure partial-credential threshold from measured SP population timing
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `feat/v0.1.7` in lib-acg
- Do NOT change the threshold before the measurement data is captured and recorded here
- Do NOT make the probe mutate sandbox state — it must be read-only
