# Bugfix: v1.16.0 — `acg_restart.js` is orphaned: sandbox auto-restart regressed to a manual click

**Repo for the fix:** `lib-foundation` (upstream) — **NOT** `k3d-manager`
**Upstream file:** `scripts/lib/acg/acg.sh`
**Then:** subtree-pull into `k3d-manager` branch `k3d-manager-v1.16.0` and add the stub in `scripts/plugins/acg.sh`
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- **Do NOT edit `scripts/lib/foundation/**` directly in k3d-manager** — it is a subtree.
  The fix lands in the lib-foundation repo first, then arrives here via subtree pull.
- Read IN FULL before editing:
  - `scripts/lib/acg/acg.sh` (upstream path) — specifically `_acg_extend_playwright` (~line 417)
    and `acg_check_ttl` (~line 439), which are the invocation patterns to copy.
  - `scripts/lib/acg/playwright/acg_restart.js` — the script being wired up. Do NOT modify it.

---

## Problem

The ACG sandbox restart automation exists and works, but **nothing calls it**.

`scripts/lib/acg/playwright/acg_restart.js` implements the full recovery flow — connect over
CDP, detect page state, click **Delete Sandbox**, confirm the alertdialog, click **Start
Sandbox** — and it has a dedicated Playwright suite (`tests/acg-restart.spec.js`) plus an
HTML fixture. But:

```
$ grep -rn 'acg_restart' --include='*.sh' .     # → no matches
$ git log --oneline --all -S'acg_restart' -- '*.sh'   # → empty
```

There is no `acg_restart()` in `acg.sh`, and no stub in `k3d-manager`'s
`scripts/plugins/acg.sh`. A shell entrypoint was **never** committed. The JS arrived with the
lib-acg → lib-foundation absorption (`0a7b6dd0` / `aed8c560`); its sibling `acg_extend.js` got
wired via `_acg_extend_playwright`, but `acg_restart.js` did not.

**Root cause:** incomplete absorption — the runtime tree was imported without its shell binding.

**User-visible symptom:** when the sandbox TTL expires, `_acg_check_credentials` correctly
detects the dead sandbox but its remediation text tells a **human** to go click Start Sandbox:

```
ERROR: [acg] AWS credentials invalid or expired.
ERROR: [acg]   1. Start a new sandbox at https://app.pluralsight.com/...
ERROR: [acg]   2. Run: acg_get_credentials
```

So an expired sandbox became a hard human-in-the-loop blocker on every cold rebuild. It also
makes the documented `acg_get_credentials` "stale tab" trap far more damaging: with the sandbox
expired, `acg_get_credentials` re-scrapes the dead page, **exits 0**, logs
`Credentials written… Access key: AKIA****`, and `aws sts get-caller-identity` still fails
`InvalidClientTokenId` — a silent false success.

**Verified 2026-07-20 (Claude, live):** invoking the orphaned script by hand fully recovered a
dead sandbox with zero manual clicks —

```
$ node playwright/acg_restart.js "https://app.pluralsight.com/hands-on/playground/cloud-sandboxes" --provider aws
INFO: Connected via CDP to existing browser session.
INFO: Clicking Delete Sandbox...
INFO: Confirming deletion...
INFO: Waiting for Start Sandbox button (up to 180s)...
INFO: Clicking Start Sandbox...
INFO: Sandbox restarted. Ready for credential extraction.
RESTART_OK
```

followed by `acg_get_credentials` → `aws sts get-caller-identity` returning a valid new account.
**The automation is not broken — only unreachable.**

---

## Fix

Two changes upstream in `scripts/lib/acg/acg.sh`, mirroring the existing
`_acg_extend_playwright` / `acg_extend_playwright` pattern exactly.

### Change 1 — add the private runner + public wrapper

Insert immediately AFTER the closing `}` of `_acg_extend_playwright` (~line 437) and BEFORE
`function acg_check_ttl()`:

```bash
_acg_restart_playwright() {
  local sandbox_url="${1:?usage: _acg_restart_playwright <sandbox_url> [provider]}"
  local provider="${2:-aws}"

  local playwright_script="${_LIB_ACG_ROOT}/playwright/acg_restart.js"

  if ! command -v node >/dev/null 2>&1; then
    _err "[acg] node is required — install Node.js"
    return 1
  fi

  _info "[acg] Restarting ACG ${provider} sandbox at ${sandbox_url}..."
  local output exit_code
  output=$(node "$playwright_script" "$sandbox_url" --provider "$provider" 2>&1)
  exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    _info "[acg] acg_restart failed: ${output}"
    return 1
  fi

  echo "$output"
}

function acg_restart() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: acg_restart [sandbox_url] [provider]

Delete the expired ACG sandbox and start a fresh one via Playwright/CDP automation,
then extract credentials. Recovers from an expired sandbox with no manual clicks.

Arguments:
  sandbox_url   Pluralsight sandbox URL (default: the built-in sandbox list URL)
  provider      aws | gcp | azure (default: aws)
HELP
    return 0
  fi

  local sandbox_url="${1:-${_ACG_SANDBOX_URL}}"
  local provider="${2:-aws}"

  _acg_restart_playwright "${sandbox_url}" "${provider}" || return 1
  acg_get_credentials || return 1
  _acg_check_credentials
}
```

### Change 2 — make the expired-credential error point at the automation

**Exact old block** (inside `_acg_check_credentials`, ~line 43):

```bash
    printf 'ERROR: %s\n' "[acg] If the sandbox was removed (expired TTL):" >&2
    printf 'ERROR: %s\n' "[acg]   1. Start a new sandbox at ${_ACG_SANDBOX_URL}" >&2
    printf 'ERROR: %s\n' "[acg]   2. Run: acg_get_credentials" >&2
    printf 'ERROR: %s\n' "[acg]   3. Re-run: make up" >&2
```

**Exact new block:**

```bash
    printf 'ERROR: %s\n' "[acg] If the sandbox was removed (expired TTL), recover automatically:" >&2
    printf 'ERROR: %s\n' "[acg]   Run: acg_restart      # deletes the dead sandbox, starts a new one, re-extracts creds" >&2
    printf 'ERROR: %s\n' "[acg] Then re-run: make up" >&2
    printf 'ERROR: %s\n' "[acg] If the sandbox is still running: update ~/.aws/credentials from the ACG console." >&2
```

Then DELETE the now-duplicated trailing line that already reads:

```bash
    printf 'ERROR: %s\n' "[acg] If the sandbox is still running: update ~/.aws/credentials from the ACG console." >&2
```

so the "still running" hint appears exactly once.

### Change 3 — k3d-manager side, AFTER the subtree pull

In `scripts/plugins/acg.sh`, add the stub alongside the existing ones:

- Add to the alias list (after the `acg_teardown` alias line):
  ```bash
  _acg_stub_alias_function acg_restart __acg_stub_acg_restart
  ```
- Add to the wrapper list (after the `acg_teardown` wrapper line):
  ```bash
  function acg_restart()               { __acg_stub_acg_restart "$@"; }
  ```

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| lib-foundation | `scripts/lib/acg/acg.sh` | Add `_acg_restart_playwright` + `acg_restart`; retarget the expired-credential error text at `acg_restart` |
| k3d-manager | `scripts/lib/foundation/**` | Subtree pull only — no hand edits |
| k3d-manager | `scripts/plugins/acg.sh` | Add `acg_restart` stub alias + wrapper |

---

## Rules

- **Appearance gates (lib-foundation, after edit):**
  - `grep -c '^_acg_restart_playwright()' scripts/lib/acg/acg.sh` → **`1`**
  - `grep -c '^function acg_restart()' scripts/lib/acg/acg.sh` → **`1`**
  - `grep -c 'acg_restart.js' scripts/lib/acg/acg.sh` → **`1`**
- **Disappearance gate:** `grep -c '1. Start a new sandbox at' scripts/lib/acg/acg.sh` → **`0`**
- **Duplicate gate:** `grep -c 'If the sandbox is still running' scripts/lib/acg/acg.sh` → **`1`**
- **k3d-manager gates (after subtree pull):**
  - `grep -c 'acg_restart' scripts/plugins/acg.sh` → **`2`**
  - `./scripts/k3d-manager acg_restart --help` prints the usage block and exits 0
- `shellcheck -S warning scripts/lib/acg/acg.sh` — 0 warnings (record baseline + after)
- `npm run check` in `scripts/lib/acg/` — passes (proves `acg_restart.js` still parses; it must NOT be modified)
- `git show --stat` — lib-foundation commit touches exactly ONE file
- Do NOT modify `playwright/acg_restart.js` or `tests/acg-restart.spec.js`

---

## Definition of Done

- [ ] `_acg_restart_playwright` + `acg_restart` added to upstream `scripts/lib/acg/acg.sh`
- [ ] `_acg_check_credentials` error text points at `acg_restart`; "still running" hint appears exactly once
- [ ] All appearance/disappearance/duplicate gates recorded with real output
- [ ] `shellcheck -S warning` — 0 warnings (baseline + after)
- [ ] `npm run check` passes
- [ ] lib-foundation committed and pushed; version bumped per lib-foundation convention
- [ ] k3d-manager: subtree pull committed, `scripts/plugins/acg.sh` stub added
- [ ] `./scripts/k3d-manager acg_restart --help` exits 0 (record output)
- [ ] memory-bank updated with both commit SHAs and task status **(separate commit)**

**Commit message — lib-foundation (exact):**
```
fix(acg): wire acg_restart shell entrypoint to orphaned acg_restart.js
```

**Commit message — k3d-manager (exact):**
```
fix(acg): expose acg_restart stub after lib-foundation subtree pull
```

### Live verification — Claude runs this, NOT the agent

Claude has already proven `acg_restart.js` recovers a dead sandbox end-to-end. After the
wiring lands, Claude re-verifies via `./scripts/k3d-manager acg_restart` on the next expiry.

---

## What NOT to Do

- Do NOT edit `scripts/lib/foundation/**` inside k3d-manager by hand — upstream first, then subtree pull.
- Do NOT modify `playwright/acg_restart.js`, `tests/acg-restart.spec.js`, or the HTML fixture — the automation already works.
- Do NOT change `acg_get_credentials`, `acg_provision`, `acg_teardown`, or `acg_extend`.
- Do NOT add auto-restart into `make up` / `bin/cluster-up` in this fix — deleting a sandbox is destructive and must stay an explicit operator call. Auto-invocation is a separate decision.
- Do NOT add or edit BATS tests.
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0` (and the lib-foundation feature branch).
