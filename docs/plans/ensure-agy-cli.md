# Task Spec: `_ensure_agy_cli` — install the standalone Antigravity agent CLI

**Repository:** `wilddog64/lib-foundation`
**Branch:** `feat/ensure-agy-cli`
**Files:** `scripts/lib/system.sh`, `scripts/tests/lib/system.bats` (tests added to existing suite)

---

## 1. Context & Goal

There are **two different binaries** that present as `agy`:

| Source | Installs | Binary | Purpose |
|--------|----------|--------|---------|
| `brew install --cask antigravity` (existing `_ensure_antigravity_ide`) | Antigravity **IDE** desktop app | IDE-flavored `agy` | interactive IDE / Playwright MCP |
| `curl -fsSL https://antigravity.google/cli/install.sh \| bash` | standalone **agent CLI** | `~/.local/bin/agy` (~142MB Go binary) | scriptable `agy --print` agent CLI |

`_ensure_antigravity_ide` installs the **IDE**, not the standalone CLI. This spec adds a distinct helper, `_ensure_agy_cli`, that installs the **standalone agent CLI** via the official installer and verifies the binary.

> **Scope note (read before implementing):** This helper is **independent of the lib-acg ACG flow.** The ACG Pluralsight session check has been decoupled from the LLM agent (lib-acg `v0.1.8`, deterministic Playwright — no `agy`). `_ensure_agy_cli` exists for general/future `agy` CLI provisioning, **not** because any current automation requires it. It must not be wired into any existing flow as part of this task.

> **Supply-chain note:** this is a `curl | bash` installer from `antigravity.google`. The URL is the official Google Antigravity CLI installer. There is no pinned version (the installer fetches latest). This is acceptable for a developer-tooling helper but must be called only on explicit intent — never run implicitly during unrelated `make`/CI paths.

---

## 2. Proposed Change — `scripts/lib/system.sh`

Add a new function near `_ensure_antigravity_ide` (≈ line 831). Use existing helpers (`_command_exist`, `_info`, `_err`, `_run_command`).

**Exact new block:**
```bash
function _ensure_agy_cli() {
   if _command_exist agy; then
      return 0
   fi
   if [[ -x "${HOME}/.local/bin/agy" ]]; then
      _info "agy CLI present at ${HOME}/.local/bin/agy — ensure ~/.local/bin is on PATH"
      return 0
   fi

   if ! _command_exist curl; then
      _err "curl is required to install the Antigravity agent CLI (agy)"
   fi

   _info "Installing standalone Antigravity agent CLI (agy) from antigravity.google..."
   _run_command -- bash -c 'curl -fsSL https://antigravity.google/cli/install.sh | bash'

   if _command_exist agy || [[ -x "${HOME}/.local/bin/agy" ]]; then
      _info "agy CLI installed (verify ~/.local/bin is on PATH)"
      return 0
   fi
   _err "agy CLI install failed — expected binary at ${HOME}/.local/bin/agy"
}
```

Notes:
- Installs to `~/.local/bin` (user scope) — **no sudo**; do not add `--prefer-sudo`/`--require-sudo`.
- Idempotent: returns early if `agy` is on PATH or the binary already exists.
- Distinct from `_ensure_antigravity_ide` — do not modify or merge that function.

---

## 3. Verification & Validation Gates

1. `bash -n scripts/lib/system.sh` — must pass.
2. `shellcheck -S warning scripts/lib/system.sh` — zero new warnings.
3. `./run-tests.sh` (or repo BATS entrypoint) — green, including the new suite.

---

## 4. BATS coverage — `scripts/tests/lib/system.bats` (added to existing suite)

Do **not** hit the network. Mock `_command_exist`, `curl`/`bash`, and `_run_command`.

```bash
@test "_ensure_agy_cli is a no-op when agy is already on PATH" {
  _command_exist() { [ "$1" = "agy" ]; }
  run _ensure_agy_cli
  [ "$status" -eq 0 ]
}

@test "_ensure_agy_cli succeeds when ~/.local/bin/agy exists" {
  _command_exist() { return 1; }
  HOME="$(mktemp -d)"; mkdir -p "$HOME/.local/bin"; : > "$HOME/.local/bin/agy"; chmod +x "$HOME/.local/bin/agy"
  run _ensure_agy_cli
  [ "$status" -eq 0 ]
}

@test "_ensure_agy_cli errors when curl is missing and agy absent" {
  _command_exist() { [ "$1" = "agy" ] && return 1; [ "$1" = "curl" ] && return 1; return 1; }
  HOME="$(mktemp -d)"
  run _ensure_agy_cli
  [ "$status" -ne 0 ]
  [[ "$output" == *"curl is required"* ]]
}
```

(Adapt mocks to the repo's existing `system.bats` harness conventions.)

---

## 5. Files Changed

| File | Change |
|------|--------|
| `scripts/lib/system.sh` | add `_ensure_agy_cli` |
| `scripts/tests/lib/system.bats` | **extended** — idempotency + install + missing-curl cases |
| `CHANGE.md` | add `[Unreleased]` → `### Added` entry for `_ensure_agy_cli` |

---

## 6. Definition of Done

- [ ] All §3 gates pass.
- [ ] `CHANGE.md` updated.
- [ ] Committed and pushed to `feat/ensure-agy-cli`.
- [ ] `memory-bank` (if present in this repo) updated with the commit SHA.

**Commit message (exact):**
```
feat(system): add _ensure_agy_cli — install standalone Antigravity agent CLI
```

---

## 7. What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify or merge `_ensure_antigravity_ide`.
- Do NOT wire `_ensure_agy_cli` into any existing flow (see §1 scope note).
- Do NOT add sudo — this is a user-scope install.
- Do NOT hit the network in BATS — mock everything.
- Do NOT commit to `main` — work on `feat/ensure-agy-cli`.
