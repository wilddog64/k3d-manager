# Progress — lib-foundation

## Overall Status

**v0.3.3 SHIPPED** — PR #8 squash-merged (b9f1fda), tagged, GitHub release created 2026-03-16.
**v0.3.4 SHIPPED** — PR #11 merged to main (`dbfafe9`), tagged v0.3.4, GitHub release created 2026-03-22.
**feat/v0.3.5 ACTIVE** — branch cut from main 2026-03-22.

---

## What Is Complete

- [x] GitHub repo + CI + branch protection (v0.1.0)
- [x] `core.sh` + `system.sh` extracted from k3d-manager (v0.1.0)
- [x] `_resolve_script_dir` — portable symlink-aware locator + BATS (v0.1.1)
- [x] Drop Colima support (v0.1.2)
- [x] `agent_rigor.sh` — `_agent_checkpoint`, `_agent_audit`, `_agent_lint`, pre-commit hook, 13 BATS (v0.2.0)
- [x] k3d-manager subtree wired at `scripts/lib/foundation/` (k3d-manager v0.7.0)
- [x] `_run_command` if-count refactor — `_run_command_resolve_sudo` extracted, both < 8 if-blocks (v0.3.0)
- [x] Bash 3.2 compat — `_RCRS_RUNNER` global temp (v0.3.0)
- [x] Route bare `sudo` in install helpers through `_run_command --interactive-sudo` (v0.3.1)
- [x] Fix `_ensure_cargo` WSL redhat branch (v0.3.1)
- [x] AGENTS.md, GEMINI.md, CLAUDE.md, copilot-instructions.md overhaul (v0.3.1)
- [x] Sync `deploy_cluster` helpers from k3d-manager; TTY fix (`_DCRS_PROVIDER` global); BATS 36 tests (v0.3.2)
- [x] Repo flipped **public** (v0.3.2)
- [x] API reference — `docs/api/functions.md` (v0.3.3)
- [x] README releases table split — top 3 + `docs/releases.md` full history (v0.3.3)

---

## What Is Pending

### v0.3.4 — SHIPPED (`dbfafe9`)

- [x] **Fix `docs/api/functions.md`** — 12 Copilot findings from PR #8 resolved in commit `7bb60c2`; spec `docs/plans/v0.3.4-api-doc-fixes.md`.
- [x] **Upstream lib sync** — `system.sh` TTY fix (`_run_command_resolve_sudo` + remove `_run_command_has_tty`); `agent_rigor.sh` if-count allowlist + staged-only audit; `statusline.sh` cost display fix.
- [x] **PR #11 Copilot review** — 8 findings addressed in `08cfbc8`, all threads resolved.
- [x] **Retro** — `docs/retro/2026-03-22-v0.3.4-retrospective.md`

### v0.3.5 — SHIPPED (`2f895a99`)

- [x] **PR #10 doc-hygiene hook** — `doc_hygiene.sh` + pre-commit hook + BATS 14 tests; staged-only `_agent_audit` BATS test (`bdd60e7`); spec `docs/plans/v0.3.5-agent-audit-staged-only-test.md`.
- [x] **Doc hygiene staged-content read** — commit `d00bccb` adds `_dh_grep` index reader + new BATS (spec `docs/plans/v0.3.5-doc-hygiene-staged-content-read.md`).
- [x] **Doc hygiene staged-mode follow-ups** — commit `aeb1396` localizes `_DHC_STAGED`, adds staged `git cat-file` guard, and replaces staged-mode BATS per `docs/plans/v0.3.5-doc-hygiene-copilot-pr10-round2.md`.
- [x] **PR #10 merged** — squash-merged to main (`2f895a99`) 2026-03-23.

### v0.3.6 — active

- [x] **Check 2 code-fence exclusion** — commit `7751068` adds `_dh_strip_fences`, `_dh_grep --strip-fences`, and 3 BATS covering fenced + tilde blocks (`docs/plans/v0.3.6-doc-hygiene-codefence-exclusion.md`).
- [x] **CoreDNS Check 4** — commit `c352c1b` adds warn-only `<svc>.<ns>.svc(.cluster.local)` detection and 4 BATS per `docs/plans/v0.3.5-doc-hygiene-coredns-check.md`.
- [x] **Indented fence fix** — commit `02e7418` updates `_dh_strip_fences` for indented fenced blocks + indented BATS (`docs/plans/v0.3.6-doc-hygiene-indented-fence-fix.md`).
- [ ] `rigor-cli` — separate repo (planned, no spec yet)
- [ ] Consumer integration: `shopping-carts`

---

## Known Constraints

| Item | Notes |
|---|---|
| `SCRIPT_DIR` dependency | `system.sh` sources `agent_rigor.sh` via `$SCRIPT_DIR` at load time |
| Contract stability | `_run_command`, `_detect_platform`, `_cluster_provider` — signature changes require all-consumer coordination |
| Clean env testing | BATS must run with `env -i` — ambient `SCRIPT_DIR` causes false passes |
| bash 3.2 compat | No `local -n`, no `declare -A`, no `mapfile` in lib code |
| `--interactive-sudo` for installs | Install helpers use `--interactive-sudo`; `--prefer-sudo` is for non-interactive contexts only |
| Global temp vars | `_RCRS_RUNNER` (sudo runner), `_DCRS_PROVIDER` (deploy provider) — never use `$()` for functions that check TTY |
