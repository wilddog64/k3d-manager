# Bug: `Makefile` default ACG sandbox URL is stale — 404s and misreports as "no sandbox"

**Branch:** `k3d-manager-v1.18.0` (never implemented) — re-dispatched on `k3d-manager-v1.41.0`, see **Recurrence — 2026-10-06** at the end
**Files:** `Makefile` (ONLY) — superseded by the Recurrence section's file list

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "stale ACG sandbox URL default" item on branch `k3d-manager-v1.18.0`.
- `git pull origin k3d-manager-v1.18.0` — work on that branch, never `main`.
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
- [ ] Committed and pushed to `k3d-manager-v1.18.0`
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
- Do NOT commit to `main` — work on `k3d-manager-v1.18.0`

---

## Claude-only (do NOT delegate)

Live verification requires driving the CDP Chrome session against a real sandbox. Agents do
not touch the browser automation or provision sandboxes.

---

## Recurrence — 2026-10-06 (v1.41.0)

**Status:** OPEN — this section supersedes the original Fix, Rules, DoD and branch above.

The v1.18.0 fix never landed: `git log -S` shows `Makefile` still has the line it was created
with in `1a8307c6`. It surfaced again on 2026-10-06, when the in-process watcher left behind by
`make up` showed `bash bin/cluster-up https://app.pluralsight.com/cloud-playground/cloud-sandboxes`
in `ps`, and while adding `make acg-watch` (`docs/bugs/2026-10-06-acg-watch-make-targets.md`),
which needed a target-specific `URL =` reset so the stale default would not reach the watcher.

**Impact is lower than in July.** lib-foundation now rewrites the legacy path to
`hands-on/playground` (`playwright/lib/sandbox.js:68`, `acg_extend.js:23`, `acg_restart.js:246`),
so `make up` and `make creds` work. What is left is a dead URL shown as the default in
`Makefile`, `make help` ("Default URL:"), `docs/howto/makefile.md` and three `docs/howto/acg.md`
examples, and a dependency on that rewrite surviving every lib-foundation change.

### Fix (v1.41.0)

#### 1. `Makefile` line 16

Old:

```makefile
URL ?= https://app.pluralsight.com/cloud-playground/cloud-sandboxes
```

New:

```makefile
URL ?= https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
```

Do NOT remove or change `acg-watch acg-watch-check: URL =` (line ~227). It still matters:
`acg_watch_start` should receive an empty argument so lib-foundation's own default applies, and
`acg-watch-check` must keep falling back to `ACG_SANDBOX_LIST_URL`
(`scripts/tests/bin/makefile_acg_watch.bats` tests 1, 4 and 5).

#### 2. `docs/howto/makefile.md` line 252

Old:

```
| `URL` | `https://app.pluralsight.com/cloud-playground/cloud-sandboxes` | Sandbox URL passed to `bin/cluster-up` and `bin/cluster-refresh` |
```

New:

```
| `URL` | `https://app.pluralsight.com/hands-on/playground/cloud-sandboxes` | Sandbox URL passed to `bin/cluster-up` and `bin/cluster-refresh` |
```

#### 3. `docs/howto/acg.md` — three examples

Line 20, old → new:

```
./scripts/k3d-manager acg_get_credentials "https://app.pluralsight.com/cloud-playground/cloud-sandboxes/<sandbox-id>"
./scripts/k3d-manager acg_get_credentials "https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/<sandbox-id>"
```

Lines 68–69, old:

```
# Example cloud playground URL
./scripts/k3d-manager acg_extend_playwright "https://app.pluralsight.com/cloud-playground/cloud-sandboxes"
```

new:

```
# Example sandbox list URL
./scripts/k3d-manager acg_extend_playwright "https://app.pluralsight.com/hands-on/playground/cloud-sandboxes"
```

Line 92, old → new:

```
make acg-restart URL="https://app.pluralsight.com/cloud-playground/cloud-sandboxes/<sandbox-id>" PROVIDER=aws
make acg-restart URL="https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/<sandbox-id>" PROVIDER=aws
```

#### 4. `CHANGELOG.md` — under `## [Unreleased]` → `### Fixed`, as the first bullet

```
- The Makefile's default `URL` still pointed at Pluralsight's retired
  `cloud-playground/cloud-sandboxes` route, so `make help`, `docs/howto/makefile.md` and the
  `docs/howto/acg.md` examples showed a dead address, and `make up` / `make creds` worked only
  because lib-foundation rewrites that path. The default and the examples now use
  `hands-on/playground/cloud-sandboxes`. Filed 2026-07-19 for v1.18.0 and never implemented. See
  `docs/bugs/2026-07-19-makefile-stale-acg-sandbox-url-default.md`.
```

#### 5. New test `scripts/tests/bin/makefile_default_url.bats`

Copy the real `Makefile` into `${BATS_TEST_TMPDIR}/work` (as `makefile_acg_watch.bats` does) and
run make with `env -u URL` so an exported `URL` in the operator's shell cannot mask the default:

1. `env -u URL make --no-print-directory -C "${WORK}" help` exits 0 and its output contains the
   exact line `  Default URL: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes`
   (assert with `grep -Fx` on the output, e.g. `printf '%s\n' "$output" | grep -Fx '...'`).
2. `run grep -c 'cloud-playground' "${WORK}/Makefile"` → `status` 1 and `output` `0`.
3. `env -u URL make --no-print-directory -C "${WORK}" help URL=https://example.test/sb` output
   contains the exact line `  Default URL: https://example.test/sb` (a command-line override
   still wins).

Never a bare `! grep` (use `run` or `|| false`).

### Rules

- `bats scripts/tests/bin/makefile_default_url.bats` and
  `bats scripts/tests/bin/makefile_acg_watch.bats` both pass; paste the output.
- RED check: the new test file must FAIL (tests 1 and 2) against the pre-change Makefile. Prove it
  on a temp copy (`git show HEAD:Makefile > "$TMPDIR/..."`), never by `git checkout`/`git stash`
  of the working tree.
- Disappearance gate: `grep -c 'cloud-playground' Makefile docs/howto/makefile.md docs/howto/acg.md`
  → `0` for each file.
- Do NOT touch `scripts/lib/foundation/` (subtree; the legacy-path rewrite there stays — it keeps
  warm tabs on the old route working), `docs/howto/gemini.md`, `docs/api/functions.md`, archived
  docs, or `memory-bank/`.
- Do NOT run `make up`, `make creds`, `make acg-restart`, `make acg-watch*`, or `make -n` on any
  target. Only run `make help` inside the BATS temp copy.

### Definition of Done (v1.41.0)

- [ ] `Makefile` line 16 uses `hands-on/playground`; the `acg-watch acg-watch-check: URL =` line is unchanged
- [ ] `docs/howto/makefile.md` row + three `docs/howto/acg.md` examples updated
- [ ] `CHANGELOG.md` `### Fixed` entry
- [ ] `scripts/tests/bin/makefile_default_url.bats`: 3 tests `ok`; RED shown; `makefile_acg_watch.bats` still 7/7
- [ ] `git show --stat` lists exactly: `Makefile`, `docs/howto/makefile.md`, `docs/howto/acg.md`,
      `CHANGELOG.md`, `scripts/tests/bin/makefile_default_url.bats`
- [ ] Commit on `k3d-manager-v1.41.0` with exactly:
      `fix(makefile): point ACG sandbox URL default at the current Pluralsight route`
- [ ] `git push origin k3d-manager-v1.41.0`; report the SHA and `git rev-parse origin/k3d-manager-v1.41.0`.
      If commit or push is denied by the sandbox, stop, leave the changes in the working tree and
      report that — do not retry with other flags.

### What NOT to Do (v1.41.0)

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the five listed.
- Do NOT commit to `main`.
