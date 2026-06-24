# Progress — lib-foundation

## v0.4.0 Track (branch: `feat/v0.4.0`) — Absorb lib-acg

- [x] **Phase 0: finalize lib-acg standalone** — DONE (2026-06-22). lib-acg PR #46 merged; tagged `v0.1.9` (gravestone release) on `7708ae31`; GitHub release published; `enforce_admins` restored. Migration source SHA = `7708ae31b4cd17c1cf81209f07adc88866301b37`.
- [x] **Phase 1: import lib-acg runtime tree as `scripts/lib/acg/`** — imported `0a7b6dd`, **VERIFIED WITH GAPS** (Claude, 2026-06-22). Spec: `docs/plans/v0.4.0-phase1-import-acg-module.md` (committed `716379f`). Core rewiring correct (clean tree-copy, `cdp.sh`/`gcp.sh` guarded `../system.sh` bootstrap, `acg.sh` flattened paths, line-188 dispatcher NOTE deferred to Phase 2, `package.json` check extended, independent `acg` CI job, docs). Codex added a legitimate but unsolicited finding doc `docs/issues/2026-06-22-acg-cluster-cidr-audit-allowlist.md` (CloudFormation CIDRs trip `_agent_audit`) — kept. Two spec omissions found → see follow-up below.
- [x] **Phase 1 follow-up: root entry points + missing playwright config** — DONE (`e6cecef`, 2026-06-22). Spec: `docs/plans/v0.4.0-phase1-followup-root-entrypoints.md`. Imported `scripts/lib/acg/playwright.config.js`, moved `bin/acg-credential-test` + `bin/acg-extend-test` to repo-root `bin/`, added root `Makefile`, repointed `REPO_ROOT` to `../scripts/lib/acg`, fixed the `acg` CI shellcheck path, and updated docs/CHANGE. Validation passed (`npm ci`, `npm run check`, `npm test`, `shellcheck -S warning bin/acg-credential-test bin/acg-extend-test`, `make help`, `make lint`, `make test`, `git diff --check`). The first Playwright run hit a sandbox-only `EPERM` mkdir on `scripts/lib/acg/test-results`; the rerun with elevated access passed and is documented in `docs/issues/2026-06-22-lib-foundation-playwright-test-results-permission.md`.
- [x] **Phase 1 follow-up REGRESSION FIX: keep bin/ module-local** — DONE (`cf3ad7a`, 2026-06-22). The `e6cecef` repo-root `bin/` hoist regressed the live Playwright sandbox-delete flow ("Element is outside of the viewport") on `make credential-test PROVIDER=aws`. Root cause isolated by a byte-for-byte lib-acg copy experiment: both layouts resolve `REPO_ROOT` to the same absolute path, so the only runtime difference is the **working directory at launch** (repo root vs `scripts/lib/acg`). Running from the module dir — matching upstream lib-acg exactly — works. Reverted the hoist: `bin/` back to `scripts/lib/acg/bin/` (`REPO_ROOT=".."`), Makefile `cd`s into the module, CI shellcheck override dropped, docs/CHANGE realigned, added `.gitignore` (node_modules/, test-results/, etc.). **Live `make credential-test PROVIDER=aws` PASSED.** All CI gates green locally (`make lint`, `make check`, `npm test` 10/10). PR pending.
- [x] **PR #32 hardening (Copilot findings) — DONE (`cbe203f`, Claude applied directly per user "review, address, resolve")** — spec `docs/bugs/2026-06-22-acg-cdp-env-and-creds-injection-hardening.md`. All 12 Copilot findings addressed (2 Makefile in `f3f2fbd`; 10 imported-code in `cbe203f`): threaded `PLAYWRIGHT_CDP_HOST/PORT` through `cdp.sh`/`acg.sh`/`acg_extend.js`/`acg_restart.js`/`acg_session_check.js`; replaced `gcp.sh` `source <creds>` with allowlisted no-eval parser (A03); `output.js` `chmodSync` for existing creds files; fixed `vars.sh` stale paths. Gates green (`npm run check`, `npm test` 10/10, `shellcheck -S warning`); **CI green on `cbe203f`**; all 12 Copilot threads replied + **resolved (0 unresolved)**. Defaults unchanged (127.0.0.1:9222). Triage doc `docs/issues/2026-06-22-copilot-pr32-review-findings.md`. **MERGE GATE MET (2026-06-22):** live `make credential-test PROVIDER=aws` re-run PASSED both scenarios (sandbox-exists reuse + sandbox-delete/restart), final `sts:GetCallerIdentity OK` — CDP hardening did not regress the live flow. lib-foundation `main` has NO branch protection (404 "Branch not protected"), so no enforce_admins to disable; PR #32 mergeable on user approval. GCP/`PLAYWRIGHT_CDP_PORT`-override paths still not live-exercised (low risk; defaults unchanged).
- [ ] **FOLLOW-UP (pre-existing, NOT a PR #32 regression): `acg-credential-test:277` calls undefined `_sts_valid`** — exits 127 → `! _sts_valid` always true → forces an unnecessary sandbox delete/restart on every happy-path run even when freshly-extracted creds are valid (real validation is the inline `aws sts get-caller-identity` at line 292). Verbatim from lib-acg `7708ea31`. One-line fix: replace `_sts_valid` with `AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity >/dev/null 2>&1`. Candidate to bundle with the agy-cli/Antigravity CDP retarget or fix standalone.
- [ ] **Phase 2: rewire k3d-manager** — drop old acg subtree, repoint stub, one subtree left. Separate spec on next k3d-manager branch.
- [ ] **Phase 3: archive lib-acg repo** — README banner + GitHub archive (do not delete).

## v0.3.20 Track (branch: `feat/v0.3.20`)

- [x] **Bugfix: `_run_command_resolve_sudo` TTY fallback** — DONE (`2f46d4be`). Spec: `docs/bugs/2026-05-29-sudo-no-tty-fallback.md`. Adds `sudo -n` fallback when stdin/stdout TTY not available. PR #29 merged to main.
- [x] **BATS mock sudo flag-stripping** — DONE. Test fix ensures `sudo` mock in `system.bats` properly strips flags before execution (pattern: `while [[ $# -gt 0 && "$1" == -* ]]; do shift; done; "$@"`).

## v0.3.21 Track (branch: `feat/v0.3.21`)

- [x] **Feature: extensible cluster-provider validation via optional consumer hook** — DONE (`f7a9178`). Spec: `docs/bugs/2026-06-12-cluster-provider-extensibility-libfoundation.md`. `scripts/lib/core.sh` now consults optional `_cluster_provider_is_extra_supported` hooks in both `_cluster_provider()` case blocks, `scripts/tests/lib/core.bats` now covers the no-hook, hook-accepts-extra-provider, and base-provider-with-hook contract cases, and `CHANGE.md` records the Unreleased changelog note.

## v0.3.18 Track (branch: `feat/v0.3.18`)

- [x] **Bugfix: `_copilot_auth_check` K3DM_ENABLE_AI gate** — DONE (`f0e29d9`). Spec: `docs/plans/v0.3.18-bugfix-copilot-auth-preflight.md`. Assigned to Codex.
- [x] **`_copilot_review` combined fix: `--allow-all-tools` + malformed `--deny-tool` patterns** — DONE (`713c18e`). Branch: `fix/copilot-deny-tool-patterns`. Combined spec: `docs/bugs/2026-05-02-copilot-review-noninteractive-combined-fix.md`. Supersedes deny-tool-only spec. Fixes both missing `--allow-all-tools` (non-interactive mode) and 4 patterns missing `)`. Commit: `fix(system): add --allow-all-tools and close malformed --deny-tool patterns in _copilot_review`

---

## Overall Status

**v0.3.3 SHIPPED** — PR #8 squash-merged (b9f1fda), tagged, GitHub release created 2026-03-16.
**v0.3.4 SHIPPED** — PR #11 merged to main (`dbfafe9`), tagged v0.3.4, GitHub release created 2026-03-22.
**v0.3.5 SHIPPED** — PR #10 squash-merged to main (`2f895a99`) 2026-03-23.
**v0.3.6 SHIPPED** — PR #12 merged to main (`d8b4c48`) 2026-03-23. Tagged v0.3.6, released.
**v0.3.7 SHIPPED** — PR #13 merged to main (`071c270`) 2026-03-24. Tagged v0.3.7 retroactively, GitHub release created.
**v0.3.8 SHIPPED** — PR #14 merged to main (`a669a63`) 2026-03-24. Tagged v0.3.8 retroactively, GitHub release created.
**v0.3.9 SHIPPED** — PR #15 merged to main (`fb09921`) 2026-03-24. No tag (docs-only, no version bump).
**v0.3.10 SHIPPED** — PR #16 merged to main (`c5662c9`) 2026-03-24. No tag (docs-only, `.clinerules` fix).
**v0.3.11 SHIPPED** — PR #17 merged to main (`2625683`) 2026-03-25. Tagged v0.3.11, GitHub release created. `enforce_admins` restored.
**v0.3.12 SHIPPED** — PR #18 squash-merged to main (`91340d62`) 2026-03-25. Tagged v0.3.12, GitHub release created. `enforce_admins` restored.
**v0.3.13 SHIPPED** — PR #19 squash-merged to main (`e870c6d9`) 2026-03-25. Tagged v0.3.13, GitHub release created. `enforce_admins` restored.
**v0.3.14 SHIPPED** — PR #20 squash-merged to main (`bbbaf053`) 2026-03-27. Tagged v0.3.14, GitHub release created. `enforce_admins` restored.
**v0.3.15 SHIPPED** — PR #21 merged to main. Tagged v0.3.15.
**v0.3.16 SHIPPED** — PR #22 merged to main. Tagged v0.3.16.
**v0.3.17 SHIPPED** — PR #24 merged to main (`108924b9`). Tagged v0.3.17, GitHub release created 2026-05-01.
**v0.3.18 IN PROGRESS** — branch `feat/v0.3.18`. PR #25 open.
**v0.3.20 SHIPPED** — PR #29 merged to main (`2f46d4be`) 2026-05-30. No tag (unreleased, in [Unreleased] section of CHANGE.md). Sudo no-TTY fallback + BATS mock fix.

## v0.3.14 — Shipped

**Dependency:** k3d-manager PR #51 (Copilot) deferred 5 findings here. Fix these before k3d-manager can subtree-pull v0.3.14.

- [x] **`_ensure_antigravity_ide` binary detection** — commit `e52b819` adds `agy`-first detection so macOS installs succeed post-brew
- [x] **`_antigravity_browser_ready` curl fast-fail** — commit `e52b819` hard-fails when `curl` missing before the polling loop
- [x] **`agent_rigor.sh` tab-scan NUL-delimited loop** — commit `e52b819` rewrites the tab scan to iterate staged `.sh` files via `-z` for filenames with spaces
- [x] **`docs/api/functions.md` @latest inaccuracy** — commit `e52b819` documents the `PLAYWRIGHT_MCP_VERSION` env var + pinned version, not `@latest`
- [x] **`CHANGE.md` version labels** — commit `e52b819` marks the shipped v0.3.12/v0.3.13 entries with release dates

## v0.3.13 — Shipped

- [x] **`_antigravity_browser_ready` curl probe fix** — PR #19 merged (`e870c6d9`); `_run_command --soft -- curl --max-time "${CURL_MAX_TIME:-30}"` replaces `_curl` probe; BATS stubs updated to target `_run_command`; Copilot `--max-time` finding addressed

## v0.3.12 — Shipped

- [x] **`_ensure_antigravity_ide` + MCP helpers** — Antigravity IDE install + Playwright MCP config helpers; Copilot PR #18 findings addressed in `9f28d88` (apt-get update, mktemp template, PLAYWRIGHT_MCP_VERSION, _curl wrapper, 7 BATS)

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

### v0.3.6 — SHIPPED (`d8b4c48`)

- [x] **Check 2 code-fence exclusion** — commit `7751068` adds `_dh_strip_fences`, `_dh_grep --strip-fences`, and 3 BATS covering fenced + tilde blocks (`docs/plans/v0.3.6-doc-hygiene-codefence-exclusion.md`).
- [x] **CoreDNS Check 4** — commit `c352c1b` adds warn-only `<svc>.<ns>.svc(.cluster.local)` detection and 4 BATS per `docs/plans/v0.3.5-doc-hygiene-coredns-check.md`.
- [x] **Indented fence fix** — commit `02e7418` updates `_dh_strip_fences` for indented fenced blocks + indented BATS (`docs/plans/v0.3.6-doc-hygiene-indented-fence-fix.md`).
- [x] `rigor-cli` — repo bootstrapped (commit `a1c034f`, branch feat/init); mapfile compat fix (`8ae57bc`) + gist installer (`310fd16`).
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
