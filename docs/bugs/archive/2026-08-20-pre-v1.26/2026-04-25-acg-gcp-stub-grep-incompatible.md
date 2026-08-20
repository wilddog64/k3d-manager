# Bug: acg.sh and gcp.sh stubs incompatible with dispatcher grep-based discovery

**Branch:** `k3d-manager-v1.2.0`
**Introduced by:** Phase 4 commit `99b2e143`

## Root Cause

The dispatcher (`_load_plugin_function` in `scripts/lib/foundation/scripts/lib/system.sh`)
uses `grep -Eq "^function <name>..."` to locate which plugin file defines a given function
before sourcing it. The Phase 4 stubs replaced the full `acg.sh` and `gcp.sh` with files
that only contain `source` directives — no function definitions. Grep finds no match,
and the dispatcher returns "Function not found in plugins."

Reproducer:
```
./scripts/k3d-manager acg_get_credentials --help
# Error: Function 'acg_get_credentials' not found in plugins
```

## Fix

Replace both stubs with self-loading wrapper functions. Each wrapper:
1. Calls a private loader that sources aws.sh (acg only) + the lib-acg plugin file.
2. The sourced file defines the real function, overriding the wrapper.
3. Forwards `"$@"` to the now-real implementation.

This satisfies the dispatcher's grep (it finds `function acg_get_credentials() {` in the
stub) and sources correctly on first call.

---

## Before You Start

1. `git pull origin k3d-manager-v1.2.0`
2. Read this spec in full before touching any file.
3. Read these files:
   - `scripts/plugins/acg.sh` (current broken stub)
   - `scripts/plugins/gcp.sh` (current broken stub)
   - `scripts/lib/acg/scripts/plugins/acg.sh` (source of truth for public function names)
   - `scripts/lib/acg/scripts/plugins/gcp.sh` (source of truth for public function names)

**Work repo:** k3d-manager only. **Branch:** `k3d-manager-v1.2.0`

---

## File 1: `scripts/plugins/acg.sh` — replace entirely

```bash
#!/usr/bin/env bash
# scripts/plugins/acg.sh — stub: delegates to lib-acg subtree

_acg_stub_load() {
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/plugins/aws.sh"
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/lib/acg/scripts/plugins/acg.sh"
}

function acg_import_credentials()   { _acg_stub_load; acg_import_credentials "$@"; }
function acg_get_credentials()      { _acg_stub_load; acg_get_credentials "$@"; }
function acg_provision()            { _acg_stub_load; acg_provision "$@"; }
function acg_status()               { _acg_stub_load; acg_status "$@"; }
function acg_extend_playwright()    { _acg_stub_load; acg_extend_playwright "$@"; }
function acg_extend()               { _acg_stub_load; acg_extend "$@"; }
function acg_watch()                { _acg_stub_load; acg_watch "$@"; }
function acg_watch_start()          { _acg_stub_load; acg_watch_start "$@"; }
function acg_watch_stop()           { _acg_stub_load; acg_watch_stop "$@"; }
function acg_chrome_cdp_install()   { _acg_stub_load; acg_chrome_cdp_install "$@"; }
function acg_chrome_cdp_uninstall() { _acg_stub_load; acg_chrome_cdp_uninstall "$@"; }
function acg_teardown()             { _acg_stub_load; acg_teardown "$@"; }
```

---

## File 2: `scripts/plugins/gcp.sh` — replace entirely

```bash
#!/usr/bin/env bash
# scripts/plugins/gcp.sh — stub: delegates to lib-acg subtree

_gcp_stub_load() {
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/lib/acg/scripts/plugins/gcp.sh"
}

function gcp_get_credentials() { _gcp_stub_load; gcp_get_credentials "$@"; }
function gcp_login()           { _gcp_stub_load; gcp_login "$@"; }
function gcp_revoke()          { _gcp_stub_load; gcp_revoke "$@"; }
```

---

## Rules

1. `shellcheck -S warning scripts/plugins/acg.sh scripts/plugins/gcp.sh` — zero warnings.
2. `bats scripts/tests/ --recursive` — same pass count as before (288 pass, 2 pre-existing ArgoCD failures allowed).
3. `./scripts/k3d-manager acg_get_credentials --help` — must exit 0.
4. `./scripts/k3d-manager gcp_get_credentials --help` — must exit 0.
5. Do NOT run `--no-verify`.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/plugins/acg.sh` and `scripts/plugins/gcp.sh`.
- Do NOT modify anything under `scripts/lib/acg/`.
- Do NOT commit to `main`.

---

## Definition of Done

- [ ] `scripts/plugins/acg.sh` contains `_acg_stub_load` and all 12 `function acg_*() {` wrappers
- [ ] `scripts/plugins/gcp.sh` contains `_gcp_stub_load` and all 3 `function gcp_*() {` wrappers
- [ ] `shellcheck -S warning` passes on both files
- [ ] `bats scripts/tests/ --recursive` — 288 pass (2 pre-existing ArgoCD failures are acceptable)
- [ ] `./scripts/k3d-manager acg_get_credentials --help` exits 0
- [ ] `./scripts/k3d-manager gcp_get_credentials --help` exits 0
- [ ] Committed to `k3d-manager-v1.2.0` with exact message:
      `fix(phase4): replace source-only stubs with grep-compatible wrapper functions`
- [ ] Pushed to `origin/k3d-manager-v1.2.0` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with the commit SHA
- [ ] Report back: commit SHA + paste the memory-bank lines updated
