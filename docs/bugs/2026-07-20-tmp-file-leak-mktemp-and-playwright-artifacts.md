# Bug: `/tmp` leak — orphaned `playwright-artifacts-*` dirs + on-kill `tmp.*` files

**Filed:** 2026-07-20
**Severity:** low (disk hygiene; no correctness impact)
**Status:** SPEC — unassigned

---

## Branches (multi-repo, upstream-first)

| Repo | Branch | Why |
|---|---|---|
| lib-foundation | `feat/v0.4.6` from `origin/main` | Change 1 lives in the ACG subtree — **must land upstream first**, then subtree-pull into k3d-manager. Do NOT hand-edit `scripts/lib/foundation/**`. |
| k3d-manager | `k3d-manager-v1.16.0` | Change 2 (shell `mktemp` traps) + the Change-1 subtree pull + the `scripts/plugins/acg.sh` side (none needed here). |

`feat/v0.4.5` just merged (`03312ae`); the next upstream branch is `feat/v0.4.6`. Create it with the mistrack guard:
```bash
git -C ~/src/gitrepo/personal/lib-foundation fetch origin
git -C ~/src/gitrepo/personal/lib-foundation checkout -b feat/v0.4.6 origin/main
git -C ~/src/gitrepo/personal/lib-foundation push -u origin feat/v0.4.6
```

---

## Before You Start

**Branch (all work repos):** lib-foundation → `feat/v0.4.6` (from `origin/main`); k3d-manager → `k3d-manager-v1.16.0` (existing).

1. Machine check: `hostname && uname -n`.
2. Read `memory-bank/activeContext.md` + `memory-bank/progress.md` in k3d-manager.
3. `git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.16.0` and read THIS spec in full.
4. Read the target files before editing:
   - lib-foundation: `~/src/gitrepo/personal/lib-foundation/scripts/lib/acg/acg.sh`
     (find `_acg_extend_playwright` and `_acg_restart_playwright`).
   - k3d-manager: `scripts/plugins/shopping_cart.sh` (lines ~242, ~266, ~970) and
     `scripts/plugins/argocd.sh` (lines ~734, ~905, ~1085).
5. Capture the shellcheck baseline for EVERY file you will edit **before the first edit**:
   `shellcheck -S warning <file>` and record 0 (or the pre-existing count).
6. **Do this as a SEPARATE Codex session** — do not bundle with any other in-flight spec.

---

## Problem

`$TMPDIR` (`/private/tmp` on this machine) accumulates two families of orphaned entries created by k3d-manager tooling:

1. **`playwright-artifacts-*` dirs — the dominant leak (44 of 54 swept on 2026-07-20).**
   Created by every ACG Playwright run (`acg_extend.js`, `acg_restart.js`, and siblings) via `chromium.connectOverCDP()`. Playwright stages per-run artifacts (traces/downloads/HAR) in a `playwright-artifacts-XXXXXX` dir and removes it only when the **browser process itself exits**. Our scripts connect over CDP and deliberately keep Chrome alive (`acg_extend.js:411` — *"close() on a connectOverCDP browser disconnects Playwright without closing Chrome"*), so the `browser.close()` in the existing `finally` blocks (`acg_extend.js:409-414`, `acg_restart.js:467-471`) **disconnects without triggering artifact-dir removal**. The dir leaks on every run — even the clean-exit path.

2. **`tmp.*` files/dirs — on-kill leak (10 of 54 swept).**
   Created by bare `mktemp` (macOS default template `tmp.XXXXXXXX`) in the plugins. Most sites already `rm -f` on the happy path but have **no `trap`**, so they leak whenever the run is interrupted (SIGINT/SIGKILL/sandbox death — frequent during k3s-aws rebuilds).

**Root cause:**
- (1) Playwright's `connectOverCDP` artifact dir is not cleaned by a disconnect-style `close()`; nothing sweeps it afterward.
- (2) Unguarded `mktemp` — no `trap 'rm -f' RETURN/EXIT` around the happy-path cleanup.

NOT in scope / NOT ours (do not touch): `TemporaryDirectory.*` and `powerlog` (macOS system), and the loose `pp.log` / `reg.txt` / `sc.out` / `prom-pf.log` (operator's own ad-hoc redirects — zero repo matches).

---

## Reproduction

```bash
# Before: count orphans
find /private/tmp -maxdepth 1 -name 'playwright-artifacts-*' | wc -l   # grows by ≥1 per ACG run
find /private/tmp -maxdepth 1 -name 'tmp.*' | wc -l                    # grows on interrupted runs
```
Run any ACG flow (`./scripts/k3d-manager acg_extend` or a k3s-aws `make up` that extends the sandbox), then re-count — `playwright-artifacts-*` increments even on success.

---

## Fix

### Change 1 — lib-foundation subtree: sweep stale `playwright-artifacts-*` in the ACG shell wrappers

**File:** `scripts/lib/acg/acg.sh` (in lib-foundation; vendored to `scripts/lib/foundation/scripts/lib/acg/acg.sh`).

Add a best-effort sweep helper and call it at the top of each `_acg_*_playwright` wrapper. A shell-side sweep is chosen over a JS-side fix because it is robust to SIGKILL (a `finally` block is not) and does not depend on Playwright internals. It only removes dirs older than 2h, so a concurrent run's live artifacts are never touched.

**New helper (place near the other `_acg_*` private helpers, before `_acg_extend_playwright`):**

```bash
_acg_sweep_stale_artifacts() {
  # Best-effort: Playwright's connectOverCDP leaves playwright-artifacts-* dirs that
  # a disconnect-style browser.close() never removes. Sweep ones older than 2h so a
  # concurrent run's live artifacts are never touched. Never fails the caller.
  local tmpdir="${TMPDIR:-/tmp}"
  find "${tmpdir%/}" -maxdepth 1 -name 'playwright-artifacts-*' -type d -mmin +120 \
    -exec rm -rf {} + 2>/dev/null || true
}
```

**Then add `_acg_sweep_stale_artifacts` as the first line inside `_acg_extend_playwright` and `_acg_restart_playwright`** (and any other `_acg_*_playwright` wrapper that calls `node …`), immediately after the `local` declarations, before the `command -v node` check. Exact insertion for `_acg_restart_playwright`:

```bash
_acg_restart_playwright() {
  local sandbox_url="${1:?usage: _acg_restart_playwright <sandbox_url> [provider]}"
  local provider="${2:-aws}"

  _acg_sweep_stale_artifacts

  local playwright_script="${_LIB_ACG_ROOT}/playwright/acg_restart.js"
  ...
```

(Mirror the same one-line insertion in `_acg_extend_playwright` after its `local` block.)

**Do NOT** modify the `playwright/*.js` files — the `finally`/`close()` handling there is already correct; the leak is framework behavior the shell sweep covers.

### Change 2 — k3d-manager plugins: add `trap` to unguarded bare-`mktemp` sites

Add an SC2064-safe `trap 'rm -f "…"' RETURN` immediately after each unguarded `mktemp` so the file is removed even on interrupt. Pattern (single-quoted body, value interpolated) matching the existing guard at `scripts/plugins/vault.sh:1113`.

**Sites to guard** (each already `rm -f`s on the happy path — add the trap, keep the existing `rm -f`):

| File | Line | Var |
|---|---|---|
| `scripts/plugins/shopping_cart.sh` | ~242 | `_netrc` (GHCR PAT check) |
| `scripts/plugins/shopping_cart.sh` | ~266 | `_netrc` (Vault PAT check) |
| `scripts/plugins/shopping_cart.sh` | ~970 | `_k3sup_installer` |
| `scripts/plugins/argocd.sh` | ~734 | `rendered` |
| `scripts/plugins/argocd.sh` | ~905 | `secretstore_render` |
| `scripts/plugins/argocd.sh` | ~1085 | `netrc` |

**Exact old block — `shopping_cart.sh` GHCR PAT (~line 242):**
```bash
  local _netrc
  _netrc=$(mktemp) && chmod 0600 "${_netrc}"
```
**Exact new block:**
```bash
  local _netrc
  _netrc=$(mktemp) && chmod 0600 "${_netrc}"
  # shellcheck disable=SC2064
  trap 'rm -f "'"${_netrc}"'" 2>/dev/null || true' RETURN
```
Apply the identical pattern (with the site's own var name) to the other five sites. Keep every existing `rm -f` in place — the trap is belt-and-suspenders for the interrupt path.

**Already-guarded — do NOT touch:** `vault.sh:1098-1099` (trap at 1113 covers both header files). Leave `_seed_vault_header_file` (`shopping_cart.sh:553`) alone — it deliberately returns the temp path to its caller; the caller owns cleanup (note for a follow-up, not this spec).

---

## Files Changed

| Repo | File | Change |
|---|---|---|
| lib-foundation | `scripts/lib/acg/acg.sh` | add `_acg_sweep_stale_artifacts` + one-line call in each `_acg_*_playwright` |
| k3d-manager | `scripts/plugins/shopping_cart.sh` | 3× `trap … RETURN` after bare `mktemp` |
| k3d-manager | `scripts/plugins/argocd.sh` | 3× `trap … RETURN` after bare `mktemp` |
| k3d-manager | `scripts/lib/foundation/**` | subtree pull of the lib-foundation change (vendored only — no hand-edit) |

---

## Rules

- `shellcheck -S warning <file>` on every changed file — run **BEFORE the first edit** (baseline) and after; 0 new warnings. In lib-foundation, `npm run check` in `scripts/lib/acg/` must still pass (JS untouched, must still parse).
- `bats scripts/tests/plugins/shopping_cart.bats` and `bats scripts/tests/plugins/argocd.bats` — unchanged pass counts.
- `./scripts/k3d-manager _agent_audit` → exit 0.
- **lib-foundation commit touches exactly one file** (`scripts/lib/acg/acg.sh`); no `CHANGE.md` / version bump (stamped separately at release — see `57dd60e`).
- **Subtree-pull scope gate (k3d-manager):** after the pull, `git diff --stat HEAD~1 -- . ':(exclude)scripts/lib/foundation'` → EMPTY.
- **Push verification (both repos):** after each push, `git log origin/<branch> --oneline -1` — a local commit is not done.
- `git diff --cached --name-only` before the memory-bank commit — only the two memory-bank files staged.
- Verification gate for the sweep: `grep -c '_acg_sweep_stale_artifacts' scripts/lib/foundation/scripts/lib/acg/acg.sh` → `3` (1 def + 2 call sites) after the subtree pull.
- Verification gate for the traps: `grep -c "trap 'rm -f" scripts/plugins/shopping_cart.sh` increases by 3; same for `argocd.sh` by 3.

---

## Definition of Done

- [ ] lib-foundation `feat/v0.4.6` commit (one file, no `CHANGE.md`); SHA confirmed on `origin/feat/v0.4.6`
- [ ] subtree pull committed on `k3d-manager-v1.16.0`; scope gate EMPTY; SHA on `origin/k3d-manager-v1.16.0`
- [ ] shopping_cart.sh + argocd.sh trap commit; shellcheck 0 baseline AND after; bats unchanged
- [ ] `grep -c '_acg_sweep_stale_artifacts' …/acg.sh` → `3`; trap grep counts +3 each file
- [ ] memory-bank updated with all SHAs and task status **(separate commit, also pushed)**

**Commit messages (exact):**
- lib-foundation: `fix(acg): sweep stale playwright-artifacts temp dirs in acg shell wrappers`
- k3d-manager (traps): `fix(plugins): trap-guard bare mktemp sites so temp files survive no interrupt`
- k3d-manager (subtree): `chore(subtree): pull lib-foundation acg artifact sweep`

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT hand-edit `scripts/lib/foundation/**` — fix upstream, then subtree-pull.
- Do NOT modify `playwright/*.js` — the finally/close handling is already correct.
- Do NOT touch `vault.sh:1098-1099` (already trap-guarded) or `_seed_vault_header_file`.
- Do NOT delete `TemporaryDirectory.*`, `powerlog`, or the operator's `pp.log`/`reg.txt`/`sc.out`/`prom-pf.log`.
- Do NOT commit to `main`.
