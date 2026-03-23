# Active Context — lib-foundation

## Current State: `feat/v0.3.6` (as of 2026-03-23)

**v0.3.4 SHIPPED** — PR #11 merged to main (`dbfafe9`), tagged v0.3.4, GitHub release created 2026-03-22.
**v0.3.5 SHIPPED** — PR #10 squash-merged to main (`2f895a99`) 2026-03-23. No tag (no CHANGELOG entry). `enforce_admins` restored.
**feat/v0.3.5 DONE** — retro written `docs/retro/2026-03-23-v0.3.5-retrospective.md`. Next work on `feat/v0.3.6`.

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
| v0.3.6 | **active** | Check 2 code-fence exclusion + CoreDNS Check 4 |

---

## Open Items

- [x] **PR #10 doc-hygiene hook** — staged-only `_agent_audit` BATS test added in commit `bdd60e7`; spec `docs/plans/v0.3.5-agent-audit-staged-only-test.md`. Branch: `feat/doc-hygiene-hook`.
- [x] **Doc hygiene staged-content read** — commit `d00bccb` implements `_dh_grep` index reader per `docs/plans/v0.3.5-doc-hygiene-staged-content-read.md`; branch pushed `feat/doc-hygiene-hook`.
- [x] **Doc hygiene staged-mode follow-ups** — commit `aeb1396` localizes `_DHC_STAGED`, gates staged file existence via `git cat-file`, and replaces staged-mode BATS per `docs/plans/v0.3.5-doc-hygiene-copilot-pr10-round2.md`.
- [ ] **k3d-manager subtree pull** — pull v0.3.5 into k3d-manager (PR #10 now merged)
- [x] **v0.3.6: Check 2 code-fence exclusion** — commit `7751068` adds `_dh_strip_fences`, optional `_dh_grep --strip-fences`, and 3 BATS tests per `docs/plans/v0.3.6-doc-hygiene-codefence-exclusion.md`.
- [x] **v0.3.6: CoreDNS Check 4** — commit `c352c1b` adds YAML-only warn on `<svc>.<ns>.svc(.cluster.local)` + 4 BATS tests per `docs/plans/v0.3.5-doc-hygiene-coredns-check.md`.
- [x] **v0.3.6: indented fence fix** — commit `02e7418` updates `_dh_strip_fences` to handle indented fences + adds indented BATS per `docs/plans/v0.3.6-doc-hygiene-indented-fence-fix.md`.
- [ ] `rigor-cli` — separate repo, lib-foundation as git subtree; CLI: `checkpoint|audit|lint`
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
| `k3d-manager` | git subtree at `scripts/lib/foundation/` | on v0.3.2; v0.3.3 pull pending |
| `rigor-cli` | git subtree (planned) | separate repo, future |
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
