# Active Context — lib-foundation

## Current State: `feat/v0.3.21` (as of 2026-05-30)

**v0.3.11 SHIPPED** — PR #17 merged to main (`2625683`) 2026-03-25. Tagged v0.3.11, GitHub release created. `enforce_admins` restored.
**v0.3.12 SHIPPED** — PR #18 squash-merged to main (`91340d62`) 2026-03-25. Tagged v0.3.12, GitHub release created. `enforce_admins` restored. Antigravity IDE install + Playwright MCP config helpers.
**v0.3.13 SHIPPED** — PR #19 squash-merged to main (`e870c6d9`) 2026-03-25. Tagged v0.3.13, GitHub release created. `enforce_admins` restored. Fix `_antigravity_browser_ready` curl probe (`_run_command --soft`).
**v0.3.14 SHIPPED** — PR #20 squash-merged to main (`bbbaf053`) 2026-03-27. Tagged v0.3.14, GitHub release created. `enforce_admins` restored. 5 deferred Copilot PR #51 findings: agy binary detection, curl fast-fail, NUL audit loops, doc fix, CHANGE.md versioning.
**feat/v0.3.18 ACTIVE** — `_copilot_auth_check` rewrite; PR #25 open.
**v0.3.20 SHIPPED** — PR #29 merged to main (`2f46d4be`) 2026-05-30. Sudo no-TTY fallback + BATS mock fix. Unreleased (in [Unreleased] section of CHANGE.md).
**feat/v0.3.21 COMPLETE** — commit `f7a9178` merged and pushed to `origin/feat/v0.3.21`; `scripts/lib/core.sh` now consults optional `_cluster_provider_is_extra_supported` hooks in both provider validation case blocks, the contract BATS coverage was extended, and `CHANGE.md` records the change under `[Unreleased]`; next step is the k3d-manager consumer-side registration spec.

---

## Purpose

Shared Bash foundation library. Contains:
- `scripts/lib/core.sh` — cluster lifecycle, provider abstraction, `_resolve_script_dir`
- `scripts/lib/system.sh` — `_run_command`, `_run_command_resolve_sudo`, `_detect_platform`, package helpers, BATS install
- `scripts/lib/agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`

Consumed by downstream repos via git subtree pull.
API reference: `docs/api/functions.md`

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.3.3 | released | See `docs/releases.md` |
| v0.3.4 | **SHIPPED** | PR #11 merged (`dbfafe9`) — doc fixes + upstream lib sync; tagged + released 2026-03-22 |
| v0.3.5 | **SHIPPED** | PR #10 merged (`2f895a99`) — doc-hygiene hook; 2026-03-23 |
| v0.3.6 | **SHIPPED** | PR #12 merged (`d8b4c48`) — code-fence exclusion + CoreDNS Check 4; 2026-03-23 |
| v0.3.7 | **SHIPPED** | PR #13 merged (`071c270`) — system.sh if-count cleanup; 2026-03-24; tagged v0.3.7 retroactively |
| v0.3.8 | **SHIPPED** | PR #14 merged (`a669a63`) — tab indentation enforcement in `_agent_audit`; 2026-03-24; tagged v0.3.8 retroactively |
| v0.3.9 | **SHIPPED** | PR #15 merged (`fb09921`) — release history backfill + memory-bank reconciliation; 2026-03-24; no tag (docs-only) |
| v0.3.10 | **SHIPPED** | PR #16 merged (`c5662c9`) — `.clinerules` fix; 2026-03-24; no tag (docs-only) |
| v0.3.11 | **SHIPPED** | PR #17 merged (`2625683`) — YAML IP check in `_agent_audit`; 2026-03-25; tagged v0.3.11 |
| v0.3.12 | **SHIPPED** | PR #18 merged (`91340d62`) — Antigravity IDE + MCP helpers; 7 BATS; 2026-03-25; tagged v0.3.12 |
| v0.3.13 | **SHIPPED** | PR #19 merged (`e870c6d9`) — `_antigravity_browser_ready` curl probe fix; 2026-03-25; tagged v0.3.13 |
| v0.3.14 | **SHIPPED** | PR #20 merged (`bbbaf053`) 2026-03-27 |
| v0.3.15–v0.3.17 | **SHIPPED** | PRs #21–#24 merged; v0.3.17 at `108924b9` 2026-05-01 |
| v0.3.18 | **IN PROGRESS** | branch `feat/v0.3.18`; PR #25 open |
| v0.3.20 | **SHIPPED** | PR #29 merged to main (`2f46d4be`) 2026-05-30; unreleased |

---

## v0.3.18 Open Items

- [x] **Bugfix: `_copilot_auth_check` K3DM_ENABLE_AI gate** — DONE (`f0e29d9`, `eede5c3`). Spec: `docs/plans/v0.3.18-bugfix-copilot-auth-preflight.md`. Removed `K3DM_ENABLE_AI` gate; checks env tokens → `~/.config/github-copilot/apps.json` → `gh auth status`; clear error on failure. New `scripts/tests/lib/copilot_auth.bats` (6 tests).
- [ ] **Copilot review non-interactive permissions** — OPEN. `docs/issues/2026-05-02-copilot-review-noninteractive-permissions.md`. `_copilot_review` still emits a non-interactive Copilot call without the CLI permission mode the help text describes as required.

---

## Pre-v0.3.18 Open Items

- [x] **PR #10 doc-hygiene hook** — staged-only `_agent_audit` BATS test added in commit `bdd60e7`; spec `docs/plans/v0.3.5-agent-audit-staged-only-test.md`. Branch: `feat/doc-hygiene-hook`.
- [x] **Doc hygiene staged-content read** — commit `d00bccb` implements `_dh_grep` index reader per `docs/plans/v0.3.5-doc-hygiene-staged-content-read.md`; branch pushed `feat/doc-hygiene-hook`.
- [x] **Doc hygiene staged-mode follow-ups** — commit `aeb1396` localizes `_DHC_STAGED`, gates staged file existence via `git cat-file`, and replaces staged-mode BATS per `docs/plans/v0.3.5-doc-hygiene-copilot-pr10-round2.md`.
- [ ] **k3d-manager subtree pull** — pull v0.3.5 into k3d-manager (PR #10 now merged)
- [x] **v0.3.6: Check 2 code-fence exclusion** — commit `7751068` adds `_dh_strip_fences`, optional `_dh_grep --strip-fences`, and 3 BATS tests per `docs/plans/v0.3.6-doc-hygiene-codefence-exclusion.md`.
- [x] **v0.3.6: CoreDNS Check 4** — commit `c352c1b` adds YAML-only warn on `<svc>.<ns>.svc(.cluster.local)` + 4 BATS tests per `docs/plans/v0.3.5-doc-hygiene-coredns-check.md`.
- [x] **v0.3.6: indented fence fix** — commit `02e7418` updates `_dh_strip_fences` to handle indented fences + adds indented BATS per `docs/plans/v0.3.6-doc-hygiene-indented-fence-fix.md`.
- [x] **v0.3.11: YAML hardcoded IP check** — commit `11e653b` adds staged `.yaml/.yml` IP detection to `_agent_audit` per `docs/plans/v0.3.11-agent-audit-yaml-ip-check.md`.
- [x] `rigor-cli` — repo bootstrapped (commit `a1c034f`), bash 3.2 fix (`8ae57bc`), gist installer (`310fd16`); lib-foundation spec: `docs/plans/v0.3.10-rigor-cli-init.md`; rigor-cli specs tracked in that repo (`plans/v0.1.1-mapfile-compat.md`, `plans/v0.1.1-gist-install-script.md`).
- [x] **v0.3.12: Antigravity helpers** — commit `ae0e8b9` adds `_ensure_antigravity_ide`, `_ensure_antigravity_mcp_playwright`, `_antigravity_browser_ready` per `docs/plans/v0.3.12-ensure-antigravity.md`.
- [x] **v0.3.13: antigravity browser probe fix** — commit `9350ecd` switches `_antigravity_browser_ready` to `_run_command --soft -- curl` per `docs/plans/v0.3.13-antigravity-browser-ready-fix.md`.
- [x] **v0.3.14: k3d-manager Copilot PR #51 deferred findings** — `e52b819` fixes all 5 upstream gaps per `docs/plans/v0.3.14-copilot-pr51-deferred-fixes.md`:
  - `_ensure_antigravity_ide` now detects `agy` binaries first
  - `_antigravity_browser_ready` fails fast when `curl` missing
  - `_agent_audit` tab scan iterates staged files via NUL-delimited loop
  - `docs/api/functions.md` explains `PLAYWRIGHT_MCP_VERSION` pinned MCP default
  - `CHANGE.md` versions the v0.3.12/v0.3.13 release notes
- [ ] `shopping-carts` as consumer (future)

---

## Key Contracts (must not change without coordinating all consumers)

- `_run_command [--prefer-sudo|--require-sudo|--interactive-sudo|--probe '<subcmd>'|--quiet|--soft] -- <cmd>`
- `_detect_platform` → `mac | wsl | debian | redhat | linux`
- `_cluster_provider` → `k3d | k3s | orbstack`
- `_resolve_script_dir` → absolute canonical path of calling script's real directory
- `_DCRS_PROVIDER` — global temp set by `_deploy_cluster_resolve_provider` (no command substitution — preserves TTY)
- `_RCRS_RUNNER` — global temp set by `_run_command_resolve_sudo`

---

## Consumers

| Repo | Integration | Status |
|---|---|---|
| `k3d-manager` | git subtree at `scripts/lib/foundation/` | subtree pull to v0.3.13 pending |
| `rigor-cli` | git subtree at `scripts/lib/foundation/` | subtree pull to v0.3.13 pending |
| `shopping-carts` | git subtree (planned) | future |

---

## Engineering Protocol

- **Tests**: always run with `env -i PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin" HOME="$HOME" TMPDIR="$TMPDIR" bash --norc --noprofile -c 'bats scripts/tests/lib/'`
- **shellcheck**: run on every touched `.sh` file before commit
- **No bare sudo**: always `_run_command --interactive-sudo` for install helpers, `--prefer-sudo` for non-interactive
- **All changes originate here** — never edit consumer subtree copies directly
- **Release flow**: PR → merge → tag → GitHub release → consumers run `git subtree pull`

## Lessons Learned

- `local -n` nameref requires bash 4.3+ — use global temp vars (`_RCRS_RUNNER`, `_DCRS_PROVIDER`) for output from helpers
- Command substitution `$()` creates a subshell — `[[ -t 0 && -t 1 ]]` is always false inside; use global temp vars instead
- `--prefer-sudo` silently drops to non-root when password sudo required — use `--interactive-sudo` for install helpers
- `git subtree add --squash` creates a merge commit that blocks GitHub rebase-merge — use squash-merge with admin override in consumers
- BATS must run with `env -i` — ambient `SCRIPT_DIR` causes false passes
