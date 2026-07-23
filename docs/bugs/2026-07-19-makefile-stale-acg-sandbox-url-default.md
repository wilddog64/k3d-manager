# Bug: `Makefile` default ACG sandbox URL is stale — 404s and misreports as "no sandbox"

**Branch:** `k3d-manager-v1.16.0`
**Files:** `Makefile` (ONLY)

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "stale ACG sandbox URL default" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `Makefile` — line 7 (`URL ?=`) and every target that consumes `$(URL)`
  - `scripts/playwright/acg_credentials.js` — lines ~200-255, the tab-discovery and
    SPA-navigation logic
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`Makefile:7` defaults to a route Pluralsight no longer serves:

```makefile
URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes
```

The live route is `https://app.pluralsight.com/hands-on/playground/cloud-sandboxes`.

Measured 2026-07-19, `make creds` with the default URL against a **running** sandbox:

```
INFO: Found existing Pluralsight session via CDP — reusing existing Chrome instance.
INFO: Found existing sandbox tab: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Navigating to https://app.pluralsight.com/cloud-playground/cloud-sandboxes...
INFO: Sandbox route not active (https://s2.pluralsight.com/404.html) — retrying directly via targetUrl...
WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway
ERROR: page.waitForSelector: Timeout 15000ms exceeded.
  - waiting for locator('input[aria-label="Copyable input"]') to be visible
make: *** [creds] Error 1
```

Re-running with `URL=https://app.pluralsight.com/hands-on/playground/cloud-sandboxes`
succeeded on the first attempt and wrote valid credentials.

### Why this is worse than a plain 404

`acg_credentials.js:205` accepts **both** URL forms when *discovering* an existing tab:

```js
p.url().includes('cloud-playground/cloud-sandboxes') || p.url().includes('hands-on/playground/cloud-sandboxes')
```

So the script correctly reports `Found existing sandbox tab`, then SPA-navigates to the
stale `targetUrl` and lands on the 404. The operator sees a healthy session followed by a
credential-selector timeout — which reads as **"no sandbox is running"** when a sandbox is
running fine. This misdiagnosis cost a full teardown/rebuild cycle on 2026-07-19 and led to
an unnecessary request for manual intervention.

The failure is loud (`Error 1`), so this is a wrong-diagnosis bug, not a silent one.

---

## Fix

### Change 1 — `Makefile`: update the default URL

**Exact old block (line 7):**

```makefile
URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes
```

**Exact new block:**

```makefile
URL ?= https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
```

Do NOT change `acg_credentials.js`. The dual-form matching at line 205 is deliberate and
must keep accepting both, so a warm tab on either route is still discovered.

---

## Files Changed

| File | Change |
|------|--------|
| `Makefile` | `URL ?=` default → `/hands-on/playground/cloud-sandboxes` |

---

## Rules

- **Disappearance gate:** `grep -c 'cloud-playground/cloud-sandboxes' Makefile` → **`0`**
- **Presence gate:** `grep -c 'hands-on/playground/cloud-sandboxes' Makefile` → **`1`**
- **Unchanged gate:** `grep -c 'cloud-playground/cloud-sandboxes' scripts/playwright/acg_credentials.js`
  must still be **`1`** — the JS dual-form match must NOT be edited.
- `make -n creds` — prints the new URL, exits 0
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] `Makefile:7` uses the `hands-on/playground` route
- [ ] `acg_credentials.js` untouched (gate recorded)
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(makefile): point ACG sandbox URL default at the current Pluralsight route
```

---

## What NOT to Do

- Do NOT edit `scripts/playwright/acg_credentials.js` — the dual-form URL match is
  intentional and keeps warm tabs on the old route discoverable.
- Do NOT "fix" this by making the script fall back to a hardcoded URL on 404. The default
  should simply be correct.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the single listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

Live verification requires driving the CDP Chrome session against a real sandbox. Agents do
not touch the browser automation or provision sandboxes.
