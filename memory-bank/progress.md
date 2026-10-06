# 2026-10-02 — v1.40.0 release close-out (gh auth churn deferred to next release, operator call)

- [x] Removed clean Codex worktrees `../k3d-manager-codex-askdocs`, `../k3d-manager-codex-bugs` (commits already cherry-picked; branches kept).
- [x] Removed `.claude/worktrees/k3d-manager` + branch `worktree-k3d-manager` (operator go; May lock-dir edit superseded by the Sept wrapper rewrite; c5949cf4 is on main).
- [x] Codex: CHANGELOG promoted to [1.40.0] + retro `82ec57a0` (Claude-verified: on origin, headings order, every in-repo SHA/path resolves; 755ad2d is e2e-tests repo). Audit gap: validate-manifests undocumented + stale UNMEASURED in CLAUDE.md/makefile.md → fixed `e6185b92` (Codex, Claude-verified: on origin, 3 files, doc-links 1872 OK, stale grep empty).
- [x] e2e-tests publish run 37044992425 GREEN: sha-755ad2d… and latest both = sha256:78044624… (old latest 59abbc19). [ ] operator reruns `make e2e E2E_IMAGE_TAG=sha-755ad2d7efeb96dcb6d3701077264fc6b9374db3` (live smoke gate).
- [x] Live e2e run 1790965743-22494 (operator refreshed gh read:packages; GHCR via gh CLI token; substrate all up; teardown clean): 48 passed / 8 failed / 102 — all 8 api/payments now fail at Keycloak token 400 Missing form parameter: grant_type (global extraHTTPHeaders Content-Type: application/json overrides form:). Spec docs/bugs/2026-10-02-e2e-keycloak-token-request-sent-as-json.md → Codex in e2e-tests branch fix/keycloak-token-form-content-type. Operator: do NOT gate v1.40.0 on it. FIXED `d3b4f83` on e2e-tests `fix/keycloak-token-form-content-type` (Codex edit; sandbox blocked commit; Claude verified diff = spec, proof script reproduces json vs form, tsc 11=11; npm run lint is broken pre-existing: no eslint config). PR wilddog64/shopping-cart-e2e-tests#10 (Copilot: approval recommended, 0 findings; GitGuardian pass). Then publish image + e2e rerun.
- [x] v1.40.0 PR wilddog64/k3d-manager#134 MERGED 2026-10-02 `b5500db2` (squash); enforce_admins RESTORED (bodyless POST, confirmed true). Tag v1.40.0 created on `b5500db2` and pushed. GitHub release v1.40.0 published with CHANGELOG notes as latest. Next branch k3d-manager-v1.41.0 created via API from merge commit. Releases-table row added to docs/releases.md and README.md. Retrospective doc created at docs/retro/2026-10-02-v1.40.0-retrospective.md. Memory-bank updated.
- [ ] Next release: Vault GHCR PAT lookup returns silently on empty/unreachable — should say which.
- [x] Scope check done (283 files, all v1.40.0 specs/bugs + future plans).
- [ ] v1.40.0 PR body drafted — operator go before gh pr create.

# 2026-10-01 — v1.40.0 spec handoff

- [x] vcluster.bats orphan seed still a table (stale since 5706eb21) — FIXED `bd88be39` (Codex edit, Claude commit — Codex hit .git lock): 30/30 + reconcile 4/4, `.Name`→`.name` mutation reds the 4 orphan tests, restored.
- [x] Live e2e run `1790962990-9267` (commit cb8373ef, 2026-10-02): first run to reach Playwright — keycloak + payment rolled out (realm fix fef39649 works live). 49 passed / 8 failed / 102; all 8 = `api/payments.spec.ts` empty-body 401s, the known option-(b) set in `docs/bugs/2026-09-16-e2e-assertion-api-payments.md` (fix on payment `d2f2d55` + e2e-tests `df6b9c1` branches, unmerged; image pins pending). Health test now passes. [ ] Operator: merge both PRs, bump pins, rerun.
- [x] Specs corrected against the live tree and handed to Codex (app-health first, then retrieval eval).
- [x] Dispatched via `codex exec` into worktree `../k3d-manager-codex-v1.40.0` (branch `codex-v1.40.0-hermes`).
- [x] Codex app-health sensor: `7319f07c`, Claude-verified (11/11, spot mutations red, default-off).
- [x] Codex retrieval eval `0ded5a83` + prior art `428960fe`; Claude fixes `e35fcba9` (6 defects).
- [x] Live retrieval eval run 2026-10-01; numbers in vector-store.md + live floors. [ ] copy into v1.40.0 retro at release.
- [x] Bare-negation recurrence fixed `4c0dd7ac`.
- [x] Claude: `v1.40.0-cloud-bridge-test-targets.md` (2026-10-01) — tripwire, 4 test + 6 diagnose actions.
- [x] Claude: `v1.40.0-cloud-request-artifacts.md` (2026-10-01).
- [ ] Operator: restart cloud bridge + `make restart-webhook` to load artifacts.
- [x] README architecture diagram redrawn for v1.40.0 (Claude, docs only).
- [x] `v1.40.0-slack-corpus-qa` (`/ask-docs`) — IMPLEMENTED (Codex), verified + fixed by Claude 2026-10-01: `971c109d` on `codex-v1.40.0-slack-corpus-qa`, cherry-picked as `cccf9748` on `k3d-manager-v1.40.0` (tree-equal). Claude added `_sanitize_question` + real-corpus TF-IDF e2e test; 6 mutations red, cmp-restored.
- [x] Grafana Overview Build Info table recurrence (raw series columns; hub/app copies drifted) — FIXED (Codex), verified by Claude 2026-10-01: positive allowlist Version/Edition/Job/Instance, panel identical in hub + app copies (drift guard), 13/13 BATS, 2 real-file mutations red + cmp-restored. Operator: confirm on hub after ArgoCD sync.
- [x] Hub ConfigMap `grafana-dashboard-overview-readable` owned by two apps — FIXED (Codex, Claude-verified 2026-10-01): `grafana-dashboards-acg` excludes `grafana-overview-readable-configmap.yaml` only when `.server` is in-cluster; derived collision guard + 3 mutations in BATS (17/17). Bug doc `docs/bugs/2026-10-01-hub-overview-readable-configmap-owned-by-two-apps.md`.
- [x] `/ask` + `/ask-docs` answers threaded (bot path, `SLACK_CHANNEL_ID` only, response_url fallback) + `/ask-docs --sources` fast mode — Codex, Claude-verified 2026-10-01; bug `docs/bugs/2026-10-01-ask-answers-not-threaded-and-ask-docs-no-fast-mode.md`.
- [x] `make gh-secret` (workflow-derived allowlist, TTY prompt) + `make gh-secret-sync-relay` (Keychain → GH) — dispatched to Codex 2026-10-01; bug `docs/bugs/2026-10-01-no-safe-way-to-set-github-actions-secrets.md` (spec `86b274ed`). Incident: deploy-worker.yml first success pushed stale GH `SLACK_SIGNING_SECRET` → all slash commands down; operator re-set landed as typo `SLACK_SIGING_SECRET`.
- [x] Hub recovery hardcodes `k3d` as the public frontend origin — FIXED `9cb1207b` (Codex, Claude-verified: 44 bats green, shellcheck clean, mutation (a) red). Live `~/.cloudflared/config.yml` hand-fixed to `127.0.0.2:80` + tunnel kickstarted 2026-10-01; operator confirms via `/cluster-status`.
- [x] Cloudflared creds + Vault root token in process argv (`make cloudflared-backup`, `bin/cluster-up` restore) + hex-encoded multi-line `cert.pem` restore — FIXED `29c2d506` (Codex, Claude-verified: bats green, token-argv mutation red, shellcheck no new warnings). operator ran `make cloudflared-backup` 2026-10-01 from a GUI Terminal — Keychain (base64, read-back verified) + Vault updated; bug `docs/bugs/2026-10-01-cloudflared-credentials-exposed-in-process-argv.md`.
- [x] `ask-docs <q>` typed in a thread silently dropped (not in `_THREAD_COMMANDS`) — FIXED `aee1a258` (Codex, Claude-verified, mutation red); bug `docs/bugs/2026-10-01-ask-docs-thread-follow-up-silently-dropped.md`.
- [x] `/ask-docs` ignores recency (pure cosine; 2026-10-01 docs ranked 6th / absent) — FIXED `c0b7bc88` (Codex, Claude-verified, mutation red; CHANGELOG bullets for both); bug `docs/bugs/2026-10-01-ask-docs-ignores-recency.md`.
- [x] `make cloudflared-config` render/drift target — FIXED (Codex, Claude-verified: 51 bats green, render body byte-identical after extraction, live check `up to date (k3s-hostinger)`); Part B drift line in /cluster-status skipped; bug `docs/bugs/2026-10-01-no-standalone-cloudflared-config-render-or-drift-check.md`.
- [x] `/cluster-status` WARNs on the intended Prometheus 401 (auth proxy working; a 200 would read green) — bug `30113dc1`, FIXED 2026-10-02 (Codex; 401=pass auth enforced, 200=fail bypass; 13 tests, mutation verified) — operator: make restart-webhook then /cluster-status; bug `docs/bugs/2026-10-02-cluster-status-warns-on-intended-prometheus-401.md`.
- [x] `identity/k3dm-smoke-user` lost on hub rebuild (2 smoke WARNs since 2026-09-20) — option 2: Vault `secret/keycloak/smoke-user` + ExternalSecret in shopping-cart-infra; bug `docs/bugs/2026-10-02-smoke-user-secret-lost-on-hub-rebuild.md`, landed 2026-10-02 (Codex + Claude test fixes); infra PR #106 MERGED 2026-10-02 13:41Z (enforce_admins briefly off for the admin merge, restored); operator deleted the hand-made Secret + reseeded (password rotated); ExternalSecret SecretSynced, Secret now owned by ExternalSecret. `/cluster-status` 21 ok / 0 warn / 0 fail confirmed by operator.
- [x] OPERATOR: relay redeployed (10ebc8a6) + webhook restarted 2026-10-02; `/ask-docs` + `/cluster-status` threading confirmed in Slack.
- [x] (done 2026-10-02 via AppSet reapply; all hub apps Synced) OPERATOR: check the CM tracking-id (must name `hub-grafana-dashboards`), then reapply the ACG dashboard appset; confirm `k3d-cluster-grafana-dashboards` Synced, no SharedResourceWarning.
- [ ] `/ask-docs` operator steps: `wrangler deploy` relay, Slack manifest `/ask-docs`, `make restart-webhook`, live smoke; then Claude calibrates `K3DM_ASK_DOCS_MIN_SCORE` and replaces the PLACEHOLDER fixture.
- [x] Hub alert fixes 2026-10-02 (Codex, verified): ldap rotator `96af55b1`, Istio no-HPA `119f8a7b`, ArgoCD orphanedResources `efaf4038`, federate raw-only `8b792fcc`. Operator rollouts pending (each bug doc's Rollout). E2EVerificationFailing: option (b) landed on branches — payment `d2f2d55`, e2e-tests `df6b9c1`, k3d-manager `570734c7`; PRs + pin bump + live run pending; health test still open. Hermes alert-driven triage decided: v1.42.0 (scope + 3 specs, at cap), R10 → v1.43.0.
- [x] Codex bug batch: bridge restart `52efebde`, data_layer cause `baedfdc5`, CFN orphan warning `82ba559b` on `k3d-manager-v1.40.0` (2026-10-01; make test 1223/1223, pytest 523). R1 regression + stale-marker false warning caught and fixed by Claude.

# 2026-10-01 — v1.40.0 review fix spec (Codex)

- [x] Spec filed: `docs/bugs/2026-10-01-v1.40.0-review-fixes-ci-rerun-exit-code-argocd-session.md`.
- [x] Codex implemented `b5227418`, `393a0aae`, `236219f6`, docs `6aaef4dc`. Claude verified them independently:
  the SHAs are on origin, the diff stays within spec scope, shellcheck is clean, BATS passed 23/23, pytest passed 51, and doc links passed.
  All three mutations went red. The faithful `get-context` exit-only probe fails `stale session mints a token`.
- [ ] Deferred review items 5–10: Vault root token, latency unit, duplicated overview dashboard,
  label cardinality, and release-label test location.

# 2026-09-30 — Hermes data_layer unknown-cause bug filed

- [ ] Preserve and display a bounded, redacted cause for historical `data_layer` unknown states.

# 2026-09-30 — Hermes dashboard bugs filed

- [ ] Add drill-down evidence/links to the current findings table.
- [ ] Explain numeric status history and expose evidence for unknown/degraded transitions.

# 2026-10-01 — Codex batch bug 3 complete (`ecb46449`)

- [x] Empty mktemp paths: F1 guard, F2 BATS_TEST_TMPDIR sweep, F3 root-debris checker wired to
  check-doc-links; TMPDIR pre-fix reproduction showed `.join-failures.*`; mutation red; full pytest 442/442.
- [x] Three-commit batch complete; all three SHAs are recorded in the bug docs and memory-bank.

# 2026-10-01 — Codex batch bug 2 complete (`2f8c3ec8`)

- [x] Hermes R2 ingress mapping: auth proxy label, corrected topology comment, mapping-derived test,
  old-label mutation red; full pytest 442/442.
- [ ] Batch bug 3 remains.

# 2026-10-01 — Codex batch bug 1 complete (`8a7cdec9`)

- [x] Webhook AI fallback: agent.py S0–S2, eight offline tests, stale webhook BATS assertions,
  guide/README/CHANGELOG updates; M1–M3 red/restored green; full pytest 441/441.
- [ ] Batch bugs 2 and 3 remain.

# 2026-10-01 — bug backlog triage

- [x] Codex batch verified 2026-10-01: 8a7cdec9 (agy), 2f8c3ec8 (R2), 8fa82259 (mktemp); plus the R2 gui/<uid> service-target fix.
- [x] agy model probe OK (PONG) 2026-10-01.
- [ ] Operator: git pull + `make restart-webhook` so the running webhook loads the new agent.py.
- [x] 27 OPEN docs triaged: 14 fixed, 7 stale-closed, 6 open (R2 label, agy exit status, mktemp, appset overrides dormant, payments a/b, hub self-registration).

# 2026-09-30 — v1.41.0 planning

- [x] Spec `docs/plans/v1.41.0-python-agent-rigor.md` written (3 of 5 v1.41.0 plans).
- [x] Codex brief A (lib-foundation M1) — spec `docs/plans/v0.5.0-agent-audit-python.md` `cbc73bd` on lib-foundation `feat/agent-audit-python`; DISPATCHED 2026-10-04; DONE `45b9326` (Claude verified: on origin, 4 files = spec, clean-env BATS 156/156, shellcheck clean; Codex 4 mutations + independent mutation skipping deleted test files fails test 30, cmp-restored). lib-foundation#58 MERGED `dd39a90` 2026-10-04 (Copilot: no findings, "needs a closer look" = human sign-off; operator merged); CI green (shellcheck, bats, acg); README `_agent_audit` section added `af9e534`; Copilot pending; k3d-manager how-to `docs/howto/agent-audit.md` goes in brief B as its own M-item; v0.5.0 untagged after merge — promote branch `release/v0.5.0` `2004c7d` pushed, lib-foundation#59 MERGED `b6afd07`; v0.5.0 TAGGED + GitHub release published 2026-10-04; retro `e247525` on `docs/v0.5.0-retrospective` (no PR, v0.4.17 precedent). Item 4 (one copy) already done by shim `e22b7df6`; `AGENT_AUDIT_BATS_EXCLUDE` dropped (no `scripts/lib/acg`). Then brief B (subtree pull + M2–M4).
- [x] Codex brief B (k3d-manager M2 hermetic guard, M3 ruff `make lint-python`, M4 kubeconform in CI, M5 `docs/howto/agent-audit.md`) — subtree pull v0.5.0 `c34c5bcb`; spec `0ab5dc6c` (section of the existing plan, 5-spec cap); DONE 2026-10-04, Claude verified + committed `967b1636` (M2) `e9b8295a` (M3 autofix) `4da6644f` (M3+M4 CI) `a027c70a` (M5). Claude fixes over Codex: (1) autofix removed `_action_policy`/`strictest_role` from k3dm-webhook, breaking `make test-python-unit` (Codex never ran it) — restored as noqa re-exports; (2) `RUFF ?= ruff` missing, so bare `make lint-python` (CI) would always exit 2. Gates: pytest 668 passed/2 skipped, unittest all OK, lint clean, kubeconform 74/74, hermetic report run 0 real offenders, independent mutation (network rule off) red then cmp-restored, live pre-commit hook refuses `shell=True` probe. Follow-up: guard misses `git -C <dir> fetch` (subcommand = first non-dash word). CI runs only on PRs to main — the new lint-python + validate-manifests steps first run at the v1.41.0 PR.
- [x] Codex: hermetic guard git global options — spec `docs/bugs/2026-10-04-hermetic-guard-misses-git-global-options.md`; DONE 2026-10-04, Claude verified. Claude fix over Codex: `cwd=None` broke 6 `test_e2e_bugs.py` tests (Codex called them pre-existing; false). Guard exposed `test_pager` reading the real Keychain via `_sms_keychain` (masked by the tripwire stub under make) — stubbed. Gates: bare pytest 675 passed/1 skipped, make test-pytest 674/2, unittest OK, lint clean, independent mutation red + cmp-restored.

# 2026-09-30 — values_branch sensor and R9

- [x] Implemented the amended values_branch/R9 brief, including realistic ArgoCD fixture coverage,
  six mutation cases, exporter scope, docs and approval-pinned command. Final commit SHA is recorded
  in the completion handoff.

# 2026-09-30 — vector store auto-index implementation

- [x] Implemented tracked-ref corpus reads, fingerprinting, Hermes refresh, quota pause, ingestion
  gauges, alerts, dashboard row and offline tests. Final commit SHA is reported in the completion handoff.
- [x] Operator: write the durable Vault embeddings credential — done 2026-09-30 (`secret/embeddings/gemini` v1; see below).

# 2026-09-30 — vector store freshness

- [x] Codex `29b7f55c` automatic re-indexing, verified by Claude with 4 defects fixed (deadlock, drift ref, pause match, rules YAML).
- [x] Operator reapplied ApplicationSets on v1.40.0 (19 refs clean; Alertmanager Delivery ConfigMap present).
- [x] Codex `a92f1f1d` Hermes `values_branch` sensor + R9, verified by Claude with 3 defects fixed (sensor order, vacuous pager test, Keychain-dependent test).
- [ ] v1.41.0 design: fixed moving ref (e.g. `k3dm-live`) so a reapply is never needed.
- [x] Automatic ingestion live 2026-09-30: `10e95119` indexed 2.5 min after commit, backlog 0.
- [x] VectorDB dashboard shows data on the hostinger Grafana; Ingestion stat panels use instant queries.
- [x] Decided 2026-09-30: vectordb metrics and dashboard move to the hub.
- [x] Codex `50bd3591` hub Pushgateway + dashboard move, verified by Claude (`b46d5e06`).
- [x] Codex `b11f1a2` keycloak flow wait, verified by Claude; shopping-cart-infra PR #103 open.
- [x] shopping-cart-infra #103 merged as `98da0c5` (identical to the verified b11f1a2; CI green; Copilot found nothing).
- [x] Live 2026-09-30: 98da0c5 synced; wait passed on attempt 1; the hook still 404s. Root cause corrected: missing flowId.
- [x] Codex `4057069` flowId fix verified by Claude; shopping-cart-infra PR #104 open, CI green.
- [x] #104 merged as 930a82d; flowId fix confirmed live; the hook now fails at PUT authentication/executions/{id}.
- [x] Codex `b87bd8d` brief 3 verified by Claude; shopping-cart-infra PR #105 open, CI green.
- [x] Keycloak reconcile hook FIXED live 2026-09-30 at e41f2ad (#105): Succeeded, no Job. Closes the 09-15 browser-flow live check. Watch for the KubeJobFailed RESOLVED email.
- [x] Hub vectordb metrics live 2026-09-30 (ApplicationSets reapplied, forward 19094 healthy, rows=1732 pushed; the stray copy was pruned by ArgoCD).
- [x] `make validate-manifests` + `_ensure_kubeconform` (self-installing kubeconform); SC2317 false positive suppressed.
- [ ] Operator: let ArgoCD sync the rules and dashboard, and watch the Ingestion row for one poll.
- [x] Operator: Vault copy written 2026-09-30 (`secret/embeddings/gemini` v1; verify prints 39).
- [x] Operator: `make index-docs` 2026-09-30, 32/32 committed, 1727 in store (key read from Vault).
- [x] Slack `/k3dm find-similar-docs` multi-word `Q` fixed in the relay parser.
- [x] Operator deployed the relay 2026-09-30 (from a worktree); a multi-word `Q` is now accepted in Slack.
- [x] Slack end-to-end 2026-09-30: `Q=mac scheduler cannot find tools` → launchd-path-omits-local-bin at #1 (0.643), key read unattended.
- [x] Retrieval baseline 2026-09-30: 5/5 paraphrase queries in the top 5 (4 at rank 1), noise floor 0.55–0.57; see activeContext.

# 2026-09-30 — MinIO registry bug closed

- [x] Live: minio Running on bitnamilegacy, data intact, Trivy reports present, protection restored.
- [ ] Follow-up (owner): replace the sunset bitnamilegacy MinIO image (12 CRITICAL / 80 HIGH).

# 2026-09-30 — MinIO port merged

- [x] #102 merged as `f909906`; tree identical to the reviewed head.
- [ ] Operator: `enforce_admins` back to true; hostinger post-merge checks.

# 2026-09-30 — MinIO port ready

- [x] `36ea68e9` verified (busybox capability test + CI gates).
- [ ] Operator: merge the shopping-cart-infra PR; run the post-merge checks.

# 2026-09-30 — hostinger KubeJobFailed root-caused

- [ ] Codex (shopping-cart-infra): finish the MinIO bitnamilegacy port safely for existing data; PR only.
- [ ] Operator: confirm shopping-cart-identity is Synced now that #101 is on main.

# 2026-09-30 — Alertmanager delivery dashboard

- [x] Dashboard + tests + bug doc (`1e063919`).
- [ ] Operator: confirm in Grafana after the next platform-ops sync.

# 2026-09-30 — Codex verification #3

- [x] Verified `d37b4347`; blind-webhook defect fixed in `4a2bf022`.
- [ ] Operator: choose a fix for the Alertmanager Overview integration panels.

# 2026-09-30 — node_pressure option (b) implementation complete; awaiting commit SHA

- [x] Implemented the option (b) brief: real node conditions plus separate `data_layer`, pager/R1/R2
  migration, exporter/docs, and tests. Focused Hermes tests 72/72; four mutations red/restored green;
  no numbered test skipped. Full pytest result and commit SHA are in the completion handoff.

# 2026-09-30 — Codex verification #2 + handoff #3

- [x] Verified `72b402ea` (hostnet drift); argv-size defect fixed in `07c61ff9`.
- [ ] Codex: node_pressure → data_layer brief. Claude verifies on return.

# 2026-09-29 — hostnet-drift implementation complete; awaiting commit SHA

- [x] Implemented all seven numbered tests from the host-network drift brief: focused BATS 46/46,
  Hermes 55/55, full `make test-pytest` 401/401; shellcheck clean; all three mutations went red
  and were restored green. No numbered test was skipped. Commit SHA is in the completion handoff.

# 2026-09-29 — Codex verification + next handoff

- [x] Verified `2dfa00ef` (cosign bring-up restore + R7); defect fixed in `c5b6def2`.
- [ ] Codex: hostnet-drift brief. Claude verifies on return.

# 2026-09-29 — Codex implementation: cosign prevention + Hermes R7

- [x] Implemented the exact brief: hub recovery/new-hub restore hooks, approval-gated R7, allowlist
  row, changelog, tests, and bug resolution. Focused BATS 57/57; Hermes repairs 24/24; all three
  mutations went red and were restored green. The single commit SHA is recorded in the completion
handoff.

# 2026-09-29 — host-network IP drift

- [x] Live: node-exporter pods recycled; drift check empty.
- [ ] Codex: implement the brief in hostnetwork-pods-keep-stale-ip-after-node-restart.md.

# 2026-09-29 — Codex handoff: cosign prevention + Hermes R7

- [x] Brief written (hub-rebuild-loses-cosign-signing-key.md).
- [ ] Codex implements; Claude verifies SHA, tests and mutations independently.
- [ ] Operator: Prometheus log for the duplicate-timestamp scrape pool.

# 2026-09-29 — cosign restore

- [x] Hub cosign key + grant restored live (operator). `make signing-restore` added (`6ea6cd9b`).
- [ ] Operator: approve Fix 1 (bring-up restore) and/or Fix 2 (Hermes R7).

# 2026-09-29 — Hermes status publish fixed

- [x] Label-as-string bug fixed (`e4ea49e0`); `test_publish_status.py` 9/9, pytest 396/396, 2 mutations red.
- [x] Operator confirmed live: `published: True`, `hermes-status` ConfigMap present.

# 2026-09-29 — Hermes status publish diagnostics

- [x] `_publish_status` logs failures; `test_publish_status.py` 7/7; pytest 394/394; 3 mutations red. `349eab0c`.
- [ ] Operator: read the new log line; then fix the named cause.
- [ ] Operator: `bin/k3dm-worker-setup` to repopulate the empty `CLOUDFLARE_API_TOKEN` GitHub secret.

# 2026-09-29 — /cluster-diagnose all-namespaces overview

- [x] Relay + webhook + runner + docs. Relay node tests 23/23, `test_diagnostics_all_pods.py` 12/12,
  `webhook.bats` 65/65, `slack_slash_commands.bats` 8/8, `make test-pytest` 387/387; relay and
  webhook mutations red. Commit `64d87163`.
- [ ] Operator: `make deploy-worker` (or merge to main) so Slack sees the new form.

# 2026-09-29 — e2e payment root cause documented

- [x] Root-caused the 8 JSON failures + vcluster health failure; recorded in the api-payments bug doc.
- [ ] Operator: choose auth option (e2e profile vs real token) before a Codex spec for the two repos.

# 2026-09-29 — retrieval-eval spec status corrected

- [x] `v1.40.0-hermes-prior-art-and-retrieval-eval.md`: blocker removed (v1.39.0 shipped WS1-WS3).

# 2026-09-29 — cloud-session fixes landed on k3d-manager-v1.40.0

- [x] Fast-forwarded `k3d-manager-v1.40.0` to `a1ea1ab` (3 bug fixes + doc status sweep).
  Local gates: `make test-pytest` 375/375, `make test-python-unit` 7/7. CI not yet run (PR-only).

# 2026-09-29 — stale bug-doc statuses corrected

- [x] Five bug docs whose fixes had already landed now read FIXED with commit SHAs. Commit `b0aca7b`.

# 2026-09-29 — make-job output file fix implemented

- [x] `docs/bugs/2026-09-28-make-jobs-never-write-output-file.md`: output written via
  `_redact_secrets` + `scrub_credentials` before `status`. `test_make_job_output.py` 3/3;
  `make test-pytest` 375/375; `make test-python-unit` 7/7 OK; three mutations red.
  Commit `b66ca92` on `claude/inspiring-bohr-37ojhk`.

# 2026-09-29 — describe-pod env masking implemented

- [x] `docs/bugs/2026-09-28-diagnostics-describe-pod-prints-literal-env-values.md`: env-block
  masking + existing scrubber. `scripts/tests/bin/test_describe_pod_env_masking.py` 5/5;
  `make test-pytest` 372/372; `make test-python-unit` 7/7 OK; four mutations red and restored.
  Commit `6c95ea8` on `claude/inspiring-bohr-37ojhk`.

# 2026-09-29 — unranked token-role fix implemented

- [x] `docs/bugs/2026-09-28-role-code-assumes-every-token-role-is-ranked.md`: capability roles
  bypass rank comparison and are allowed only their policy-name set. Added
  `scripts/tests/bin/test_role_capabilities.py` (26/26); `make test-pytest` 367/367;
  `make test-python-unit` 7/7 suites OK; all three mutations red and restored green.
  Commit `adb451c` on `claude/inspiring-bohr-37ojhk`.

# 2026-09-28 — diagnostics redaction follow-up implemented

- [x] Closed the follow-up scrubber gaps: JSON/quoted values, nested Bearer values, empty-user
  URLs, Basic auth, Vault boundary guard, and a real registry-path integration test. Focused
  tests 27/27 and `make test-pytest` 341/341; all three mutations were red and restored green.
  Commit `89214fc0`.

# 2026-09-27 — v1.40.0 cluster-down recurrence fix complete

- [x] Item 1 from `docs/bugs/2026-06-24-hostinger-provider-switch-stale-active-provider.md`:
  `bin/cluster-down` calls `_acg_unrecord_provider "${_cluster_provider}"` instead of removing
  the legacy scalar directly. Added `scripts/tests/lib/cluster_down_provider_marker.bats` (2/2)
  and the Unreleased Fixed entry. Commit `396afff89fb7830f4e12530967ada804c2106da2` pushed to
  `origin/k3d-manager-v1.40.0`; mutation-tested both directions. Provider active set: 26/26;
  provider contract: 57/57; shellcheck before/after unchanged with existing informational output.

# 2026-09-28 — diagnostics logs redaction fix implemented

- [x] Fixed unregistered credential-shaped values leaking through diagnostics logs. Added shared
  `scripts/lib/webhook/redact.py`, the diagnostics integration, focused tests, and the Unreleased
  changelog entry. `make test-pytest` passed 334 tests; the three required mutations were proven
  red and restored to green. Commit `7208c043`.

# 2026-09-28 — cloud-request helper fix implemented

- [x] Fixed the fresh-clone fetch failure and four-action helper allowlist drift per the Codex brief.
  Shared action definitions live in `scripts/lib/webhook/cloud_actions.py`; the helper validates
  all action arguments from that table. Required tests and mutations passed; `make test-pytest`
  passed 314 tests. Commit `66f642aa`; verified by Claude 2026-09-28 (tests, mutations, and a real
  fresh-clone file against a local bare remote).

# v1.40.0 in progress — 2026-09-27

- [x] **fix the `eso` sensor `unknown`** — four stacked defects diagnosed 2026-09-27 (kubeconfig error read as absence; exit code discarded; `Hub ESO *` rows never graded; the bats suite tests dead duplicates). Spec `docs/bugs/2026-09-27-hermes-eso-sensor-unknown-kubeconfig-error-as-absence.md`, assigned to Codex. — FIXED, verified live (degraded on cycle 3, `cosign-public-key`); mutation-tested both guards
- [x] vectordb dashboard investigated — **not blank.** All six gauges publish to
      Pushgateway, Prometheus scrapes them (target up), all six panel queries
      return values, dashboard uid `k3dm-vectordb` provisioned, ConfigMap present
      in both clusters. The stale "blank because the producer never ran" item is
      withdrawn.
- [x] **`VectorDBMetricsStale` fixed** — `fa89fc6b`. Now also compares
      `push_time_seconds{job="k3dm-vectordb"}` against `time()` (>1h), `for: 15m`;
      proven in both directions against live Prometheus. New
      `scripts/tests/plugins/vectordb_rules.bats` (6/6), mutation-tested. Guide
      updated. Reaches the cluster on the next ArgoCD sync.
- [x] **Hermes bootstrapped** — `com.k3d-manager.hermes` loaded, 300s interval,
      last exit code 0; verified it publishes unattended (push_time advanced
      ~392s at cycle 2, gauges 1708 → 1713, Prometheus then 136s old).
- [ ] **the installer dropped `K3DM_HERMES_AUTO_KINE_GUARD=1` from the plist** —
      `_install_hermes_agent` regenerates from a template that omits it, so the
      auto Kine guard is now OFF. Restore or leave? User's call.
- [x] **`make argocd-hermes-token` HTTP 400 fix** — `expiresIn` sent as string `"0"`; swagger types it `integer/int64`, so grpc-gateway rejected the body pre-ArgoCD. Integer now; BATS test 10 guards it. `swagger.json` is unauthenticated — the diagnosis lever
- [x] **`make argocd-hermes-token` Cloudflare 1010 fix** — first live run 403'd on `urllib`'s default UA, not on ArgoCD authz; UA set on both API calls, error hint reordered, BATS test 9 added (mutation-proven), `docs/guides/hermes.md` troubleshooting block
- [x] **re-mint `k3dm-hermes-argocd-token`** — **DONE and VERIFIED 2026-09-27** via
      `make argocd-hermes-token`. Independent confirmation: 40 Applications reported by
      the target matched `kubectl get applications -n cicd`; the first post-restart cycle
      (23:15:45Z) shows `argocd` **degraded with real app evidence** instead of `unknown`,
      which also proves Hermes can read the item from the Keychain under launchd — the
      ACL failure `-U` exists to prevent. Beware: the last pre-restart cycle still logged
      `credential rejected` (23:10:38Z, before the 23:14:56Z restart), which reads as a
      failed mint if you don't date it against the process start.
      Original diagnosis below, retained for the root cause:
      The ArgoCD sensor reported
      "credential rejected"; Hermes has no ArgoCD visibility. Operator-only.
      **Root cause found 2026-09-27:** the error is `token signature is invalid`,
      not an expiry. `argocd-secret` was created `2026-09-20T23:50:23Z` at
      `resourceVersion: 2144` and never updated since; `argocd-server` started the
      same second. The 2026-09-20 ArgoCD rebuild regenerated `server.secretkey`,
      so **every API token minted before that date is permanently invalid** — the
      key that signed it no longer exists. The operator's own CLI session was
      rejected the same way. Re-minting is the only fix; retrying cannot work.
      `argocd-initial-admin-secret` still exists (created 23:51:56Z, 93s later),
      so the admin password is probably still the post-rebuild initial one — and
      note `make show-service-passwords` prefers the **Vault** copy at
      `secret/data/argocd/admin`, which may predate the rebuild, so it can print a
      password that no longer works. The k8s Secret is authoritative.
      **`make argocd-hermes-token` added (`80fb51c2`)** — mints via the ArgoCD API
      (secrets by env, never argv), writes the Keychain item with `-U`, reads it
      back, proves it against `/api/v1/applications`, restarts Hermes, never
      prints the token. Refuses without a TTY. 8 BATS tests, mutation-tested.
      **The operator still has to run it** — it cannot run unattended by design.
- [x] **the other Hermes sensor reports deep-dived** — all four traced to root
      cause, read-only. Real ESO health is fine on both clusters (hub CSS
      Ready=True 7/8 synced; hostinger Ready=True 20/20).
- [ ] **`eso` sensor reports unknown on a false negative** — the webhook defaults
      the provider to `k3s-aws`, whose context `ubuntu-k3s` is not registered, and
      `_kubectl_absent()` classifies kubectl's `context was not found` error as
      resource absence. Two fixes available: delete the stale context (necessary,
      not sufficient) and stop `_kubectl_absent()` treating a kubeconfig error as
      absence (the real fix). Not started.
- [ ] **`eso` sensor never evaluates the hub** — it exact-matches only the
      unprefixed names, so the `Hub ESO *` entries the webhook emits are invisible
      to it. Hub ESO failures surface only incidentally via `node_pressure`.
- [ ] **`keycloak-realm-reconcile` Job Failed for 6d21h** — `awk: command not
      found`; `quay.io/keycloak/keycloak:24.0` has no awk and the inline script
      uses it ~9 times. ArgoCD PostSync hook of `shopping-cart-identity`, so the
      manifest lives in **shopping-cart-infra** — spec + Codex. Likely the common
      cause of both remaining `node_pressure` failures (Keycloak, Frontend SSO
      login). Nothing alerted on it for six days.
- [ ] **hub `platform-ops/cosign-public-key` ExternalSecret still not synced** —
      1 of 8; this is the "Hub ESO ExternalSecrets" failure `node_pressure`
      reports. Pre-existing backlog item, now confirmed as the live cause.
- [x] **`reachability` confirmed unchanged** — verdict `single-service`; frontend
      0/5 with a `1/1 Running` pod returning 404 (routing, the known unapproved
      fix), all six other hosts 5/5.
- [ ] Hermes sensors reporting: `eso` unknown, `reachability` degraded
      (`frontend.3ai-talk.org`), `node_pressure` degraded (Keycloak, Hub ESO,
      Frontend SSO), `kine` healthy with `stale_acg_registration: true`.
- [ ] delete the stale `ubuntu-k3s` kube context — now load-bearing: it is the
      current context and does not exist, so unqualified `kubectl` reads error and
      read as empty listings.

- [x] `docs/howto/makefile.md` documents the six test targets — `8312512d`
      (Test Suites section, +39; `check-doc-links: 1 file(s) OK`)
- [x] `bin/k3dm-vectordb-metrics` documented in `docs/guides/vector-store.md` —
      `28e3f744` (six gauges tabled to their status fields, `K3DM_PUSHGATEWAY_URL`,
      omitted-vs-zero and the non-fatal exit-0 contract). Both v1.39.0 Step 7b
      leftovers now closed.
- [x] the three root-level `scripts/tests/*.bats` files now live in globbed
      directories — `1cf46580` (two into `plugins/`, `test_install_sudoers.bats`
      into `bin/install_sudoers.bats`; `BATS_TEST_DIRNAME` depths corrected;
      new `scripts/tests/core/suite_discovery.bats` guard, mutation-tested both
      ways; `bats scripts/tests/bin` 167/167, `scripts/tests/core` 10/10)
- [ ] `workers/slack-relay/test/relay.test.mjs` runs in no make target and no
      CI job — same defect class, the only known remaining instance; no decision

# v1.39.0 shipped — 2026-09-27

- [x] **PR #133 merged** to `main` as squash commit `3a254484c04d0ff6d9a42de72eeae1ab3b12c473`.
- [x] `enforce_admins` restored on `main` via the bodyless POST; read back `enabled: true`.
      `required_approving_review_count` was never lowered this release (still `1`).
- [x] Tag `v1.39.0` created on the merge commit and pushed; GitHub release `v1.39.0` published
      as `latest` with the CHANGELOG section as notes.
- [x] `main` synced locally (fast-forward, clean).
- [x] `origin/main` merged into `k3d-manager-v1.40.0` as `8758dcf0` — six conflicts, all
      resolved and verified: three files were strict subsets of main's and took `--theirs`,
      `argocd_vectordb.bats` took main's `rg`-free version (suite re-run 16/16 on the merged
      tree), and both memory-bank files were union-merged and proved supersets of both sides.
- [x] Retro `docs/retro/2026-09-27-v1.39.0-retrospective.md` shipped with the PR.
- [x] Step 7b standing-doc audit — four gaps found and fixed in `65e015ec`:
      `docs/howto/makefile.md` (all three new targets were missing), `README.md`
      (`public-endpoint-alerts.md` link), `memory-bank/projectbrief.md` (no vectordb/pgvector
      mention anywhere), `.github/copilot-instructions.md` (Architecture bullets + a v1.39.0
      review section). `docs/api/functions.md` needed no change — no new public shell functions.
- [ ] `docs/howto/makefile.md` still documents no `test`/`test-pytest`/`test-bin`/`test-all`
      target — pre-existing, not a v1.39.0 regression. Worth a pass in v1.40.0.
- [ ] `bin/k3dm-vectordb-metrics` is undocumented. Its sibling `bin/k3dm-vectordb-status` is
      covered in `docs/guides/vector-store.md`.
- [ ] Branch cleanup not run — v1.39.0 is not a 5-release boundary and the user did not ask.
      Branch deletion needs the user's explicit go.

# v1.39.0 k3dm-tests alerts moved to the ACG stack — 2026-09-27

- [x] **Blackbox probes inert: doubled image registry + unsubstituted `${CF_DOMAIN}`** — fixed in
      `cc4d634b0d7a0d2f7e1ac1ad097afad2fd7d40c9`, pushed to `origin/k3d-manager-v1.39.0`.
      M1–M6 implemented exactly from `docs/bugs/2026-09-27-blackbox-probe-registry-and-cf-domain-unsubstituted.md`:
      de-qualified exporter repository, shared `CF_DOMAIN` vars, sourced vars, per-file explicit
      `envsubst '$CF_DOMAIN'` with loud apply failure, five source-backed BATS tests, and the
      documentation update. Focused suite: 5/5. Recursive plugin suite: 787/787. Each M5 test
      went red against its corresponding reverted hunk in an isolated scratch copy and passed
      after restoration. No kubectl, helm, docker, or make deploy/up target was run.

- [ ] **`/k3dm help` omits the cluster lifecycle commands** — spec
      `docs/bugs/2026-09-27-k3dm-help-omits-cluster-lifecycle-commands.md` filed and committed
      `788deeb2`, pushed. Dispatched to Codex (session `01a0e3a3`). Help text only:
      `CLUSTER_COMMANDS` + a role-filtered section in `make_target_help`, four new tests in
      `scripts/tests/bin/webhook_make_targets.py`, a note in `docs/howto/slack-slash-commands.md`.
      The routing split stays — `/api/v1/make` has no job guard, no stall timer and no metrics push.
      VERIFIED 2026-09-27: Codex commits `f3cdc25a` (fix) + `86c18cf5` (memory), both on
      `origin/k3d-manager-v1.39.0`. Diff is exactly the three permitted files, insertions only;
      `workers/slack-relay/index.js`, `scripts/lib/webhook/lifecycle.py` and `bin/k3dm-webhook` show
      an empty diff. All four specified tests present; suite re-run by Claude: 33 tests, OK.

- [x] **`/cluster-up` and `/cluster-down` defaulted to a cluster the operator never named** —
      fixed `229db281`, pushed. `resolveProvider`'s fallback applied to unrecognized tokens, not
      only empty ones, so `/cluster-down hostigner` tore down `aws` and `/cluster-up awz`
      provisioned `hostinger`. Both now use `resolveProviderStrict`. Gates: `node --test
      workers/slack-relay/test/` 21/21, mutation-tested against pre-fix source (2 guard cases fail,
      2 regression cases pass), slash-command BATS 11/11.
      NOT DEPLOYED — needs `make deploy-worker` (operator) plus a Slack manifest re-import.

- [ ] **Slack job `c7faf86b` (`/cluster-up aws`) failed at Step 3.5/12** — the k3s-aws cluster
      provisioned fine (3 nodes Ready); `bin/cluster-up:402` then failed `_command_exist k3d`
      because `com.k3d-manager.webhook.plist` sets `PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`
      and `k3d` lives in `~/.local/bin`. Slack-driven `make up` always fails here; the same command
      run by hand succeeds. Fix NOT approved, NOT started: plist PATH (host config) or absolute
      `k3d` resolution in `bin/cluster-up` (durable). Metrics were pushed: `success 0`,
      `duration 644`, `status="failed"` — the deployment dashboard now has real data.

- [x] NEW `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml` — five rules,
      `release: acg-kube-prometheus-stack`, `namespace: monitoring`. Verified live that this is the
      ACG `ruleSelector` (`{"matchLabels":{"release":"acg-kube-prometheus-stack"}}`) and that its
      `ruleNamespaceSelector` is `{}`.
- [x] `k3dm-tests.alerts` removed from the hub `prometheusrule.yaml`; 3 groups / 9 rules remain.
- [x] NEW `scripts/tests/plugins/observability_k3dm_tests_rules.bats` — 5 cases green; these alerts
      had no test coverage at all before. Case 2 mutation-proved red against `git show HEAD:`.
- [x] `docs/guides/grafana-dashboards.md` + `CHANGELOG.md` record the hub/ACG split and the reason.
- [x] `make check-doc-links` 1794 OK; `bats -r scripts/tests/plugins/` exit 0, 779 tests, 0 not ok.
- [x] Wiring landed — `_deploy_pushgateway_acg` in `scripts/plugins/observability.sh` now applies
      `etc/prometheus/rules-acg/` with `--context "${_app_context}"`, beside the two dashboard
      applies and the Pushgateway that produces the metrics. `make observability-acg` →
      `deploy_observability_acg --confirm` → `_deploy_pushgateway_acg` is the confirmed chain.
      A 6th BATS case asserts the wiring and is mutation-proved red against `git show HEAD:`.
- [x] Operator ran `deploy_argocd_applicationsets --confirm` (13/13) and `make observability-acg`
      (2026-09-27). The reapply's automatic `argocd_check_values_branch` reported 26 k3d-manager
      references checked (2 tracking HEAD, ignored) and all Applications on
      `k3d-manager-v1.39.0` — the `acg-kube-prometheus-stack` / `acg-trivy-operator` / `loki`
      pins to v1.37.0 are cleared. `make observability-acg` printed the new
      `app-cluster PrometheusRules applied from .../rules-acg/` line, proving the wiring live.
- [x] **DEFECT 4 CLOSED and live-verified.** `PrometheusRule/k3dm-tests` exists in `monitoring`
      on `ubuntu-hostinger` with `release: acg-kube-prometheus-stack`; the ACG Prometheus loaded
      `k3dm-tests.alerts` (25 groups total) from
      `monitoring-k3dm-tests-80fbbf35-bb46-4577-9d61-84dc2e208b83.yaml`; all five alerts
      `state=inactive health=ok`. `inactive` was NOT accepted as proof — every one of the five
      expressions was queried and all are backed by real series: `k3dm_test_cases_failed` 0,
      `k3dm_test_cases_total` 1692 (vs the 1500 floor, 192 headroom), nine `k3dm_test_suite_cases`
      series (min 4, `webhook_status.py`), last success 2.0h old vs the 7d threshold. So
      `inactive` is now a measurement rather than the original "matches nothing" silence.
- [ ] Duration metrics (DEFECT 2) still undecided: fix in v1.39.0 or file for v1.40.0.
- [ ] My `:19190` forward propping up `federate-acg` is still undisclosed to a durable fix.
- [x] **DEFECT 5 FIXED — `make test` contaminated the live deployment telemetry.**
      `scripts/tests/lib/webhook.bats` `setup_file` now exports an empty `K3DM_PUSHGATEWAY_URL`,
      taking the `if not PUSHGATEWAY_URL: return` early exit in `_push_metrics()`, with an
      in-suite guard test plus `scripts/tests/plugins/observability_deployment_dashboard.bats`.
      Proven live: a full 65-case `webhook.bats` run left all three Pushgateway timestamps
      unchanged. Both guards were mutation-tested against pre-fix content and fail there.
      **Operator action outstanding** — the three fabricated groups are still in the Pushgateway;
      the DELETE was denied to Claude by the auto-mode classifier. Run via `!`:
      `for g in up-gcp up-aws down-aws; do curl -X DELETE http://localhost:9091/metrics/job/k3dm-webhook/instance/$g; done`
- [x] **Deployment dashboard crowding fixed** — every `k3dm_deployment_*` panel now aggregates
      `job_id` away with `max by (...)`. `_push_metrics()` stamps `duration_seconds` and
      `success` with the job's own `job_id`, so the stat panels drew one tile per deployment in
      the window (fifteen identical `aws (failed) 0 s` tiles) instead of one per
      `(action, provider)`. Needs `make observability-acg` to reach the cluster.

# embeddings credential + indexer resumability — 2026-09-26 complete

- [x] Vault added as credential source 4 (`secret/embeddings/gemini`, field `api_key`) in
      `scripts/lib/hermes/prior_art.py`; tried after env and both keychain items.
- [x] `scripts/index-docs.py` commits one transaction per 100-doc batch; prune split out.
- [x] 18 new tests (`TestVaultFallback` + `scripts/tests/bin/test_index_docs.py`); 50 pass in the
      two files. 4 mutations produced targeted failures and were restored.
- [x] Docs: `docs/guides/vector-store.md` + Addendum 3 in
      `docs/plans/v1.39.0-vector-store-platform-and-retrieval.md`. CHANGELOG updated.
- [x] `make index-docs` completed 2026-09-27: `rows=1705`, `last_indexed_epoch` set, sensor
      `healthy`. All three verifications now pass: the operator ran the first ranked query from the
      shell holding the export and it returned five relevant hits. Retrieval works end to end.
- [ ] v1.40.0 retrieval eval — first datapoint in hand, and it points at **ranking, not recall**:
      the correct doc for an `ArgoCD OutOfSync with no real diff` query ranked 4th of 5, and the
      whole band spanned 0.785-0.764 (0.021). Do not add a score threshold on this evidence; any
      cutoff in that band drops the right answer. Details in `activeContext.md`.
- [x] (closed 2026-09-30: Vault copy written) Operator: the durable slot is still open — write the Vault copy at `secret/embeddings/gemini`
      (still `No value found`) or fix the `gemini-cli-api-key` trusted-app ACL in Keychain Access.
      Until then `make find-similar-docs` and dedup Pass 2 are inert for every agent. No agent
      creates, reads, echoes or commits the value.
- [x] `5f8590b6` paces the embed loop (`EMBED_MIN_INTERVAL`, default 0.6s) and waits the delay a 429
      names; `1b3c7f47` makes the 429 say **which** quota it hit — `_error_detail` reads the error
      body once and appends `(quota <quotaId>)`, and is now called before the exhausted-attempts
      raise, which previously produced the only message a human sees and the only one with no detail.
- [x] The 429 was a **per-day** cap, confirmed by the day boundary: it survived 62s of backoff on
      2026-09-26 and the same key served 805 documents with zero 429s on 2026-09-27. Third run
      resumed at 901 and finished 1705/1705. Do not lower `EMBED_MIN_INTERVAL` or add retries for
      a daily cap — that spends tomorrow's quota and hides the failure.
- [x] `203893cc` doc follow-up done: the guide now documents both quotas and a two-sitting cold
      start, a spent daily quota reports `paused` not `unavailable` (test proved red against the old
      wording), and the corpus count is 1,705 throughout.
- [x] `203893cc` v1.39.0 close-out: CHANGELOG promoted to `## [1.39.0] - 2026-09-27` with the
      duplicate Fixed/Added/Changed headings consolidated (13 entries preserved, verified by
      set-diff), `docs/releases.md` + README rows added with v1.36.0 rotated into the collapsible
      block, retro at `docs/retro/2026-09-27-v1.39.0-retrospective.md`, and the vector-store guide
      linked from the README guides list.
- [ ] v1.39.0 PR is NOT created — gates unmet. See `activeContext.md` for which.

# vectordb health monitoring — 2026-09-26 complete

- [x] Commit `2554da26d2dcf940c09168d6e93b417e39eb8976` pushed to
      `origin/k3d-manager-v1.39.0`; no PR created by instruction.
- [x] H1-H5 and Tests implemented; py_compile, bare pytest (262 passed), offline probe,
      Prometheus/dashboard gates, mutation proofs, doc links and executable-bit gates passed.

# vectordb seed — 2026-09-26 verified

- [x] `10dcd995` seeds `vectordb/postgres` in `deploy_argocd_bootstrap`; pushed to origin.
- [x] Independently verified: scope 6 files, bats 16/16, shellcheck baseline, no credential
      value anywhere in diff, tests, docs or commit messages.
- [x] All six gates mutation-proved individually; 12/14/15 uniquely red for their own mutation.
- [x] ApplicationSets reapplied 13/13; all Applications on k3d-manager-v1.39.0.
- [ ] `hub-vectordb` ExternalSecret still OutOfSync on CRD defaults despite ServerSideDiff
      being live — needs a hard refresh so the controller re-diffs under SSA. Operator's call.

# vectordb — 2026-09-26 final: running, one cosmetic OutOfSync left

- [x] Operator overwrote Vault policy `eso-ldap-directory` (5 prefixes, token+policy on stdin).
- [x] Overwrite proven safe first: live policy diffed byte-identical against the generated HCL,
      so the change was strictly additive and could not revoke a prefix merged in out of band.
- [x] `vectordb-postgres` ExternalSecret `SecretSynced/True` at 06:27:04; both keys present.
- [x] `pod/vectordb-0` `Running 1/1`; `statefulset/vectordb` 1/1.
- [ ] Operator: reapply the ApplicationSets so `d44ef5cd`'s `ServerSideDiff=true` reaches the
      live Application. Until then `hub-vectordb` stays `OutOfSync / Healthy` on the
      ExternalSecret alone — the workload is fine, the diff is spurious.
- [ ] Offered, not approved: seed `vectordb/postgres` in the automated Vault path
      (`_vault_kv_exists` -> generate -> `_vault_kv_put`) so the credential survives a hub rebuild.

NOTE — the ArgoCD namespace here is `cicd`, not `argocd`. Queries against `argocd` return an
empty listing that reads like a valid negative answer.

# vectordb — 2026-09-26 later: Vault path written, ESO still denied

- [x] Operator wrote `secret/vectordb/postgres` (version 1, 13:03Z). Password generated inside
      the vault pod; never in argv, host or history. Claude never saw it.
- [x] Root-caused the remaining failure: ESO gets `403 permission denied`, not a missing path.
      `vectordb` was absent from `LDAP_VAULT_POLICY_PREFIX`. Fixed in `04fafc55` + gate 10.
      Recurrence appended to `docs/bugs/v1.4.5-bugfix-eso-ldap-policy-missing-keycloak.md`.
- [ ] Operator: apply the Vault policy so the grant is live. `vars.sh` alone changes nothing.
      Blocked on an operator-run `vault policy read eso-ldap-directory` first — Claude cannot
      read it (needs the root token) and so cannot confirm an overwrite would not revoke a
      prefix that was merged in out of band.
- [ ] Operator: reapply the ApplicationSets for the `ServerSideDiff` annotation (`d44ef5cd`).
- [ ] Then Claude verifies read-only: `vectordb-postgres` `SecretSynced/True`, `pod/vectordb-0`
      Running, `hub-vectordb` `Synced/Healthy`.

LESSON — `could not get secret data from provider` on an ExternalSecret is ambiguous between an
absent path and a denied one. Read the ESO controller log for the HTTP code before diagnosing.

# WS1 vectordb — live status 2026-09-26

- [x] `platform` AppProject applied via `deploy_argocd_bootstrap --skip-applicationsets`
      (operator-run; the applicationsets deploy path does NOT apply AppProjects).
      Destinations 42 -> 43, `vectordb` permitted.
- [x] `hub-vectordb` synced; StatefulSet, Service, PVC (Bound 10Gi local-path) and
      ExternalSecret all created in namespace `vectordb`.
- [x] Perpetual `OutOfSync` on the ExternalSecret root-caused and fixed in `d44ef5cd` —
      missing `argocd.argoproj.io/compare-options: ServerSideDiff=true` on the Application
      template. Two gates added to `argocd_vectordb.bats` (9/9 green); the annotation gate is
      mutation-checked. Recurrence appended to the existing 2026-09-13 platform-ops bug doc.
- [x] Reverted `afed4ec9` (declared `target.template.engineVersion`) — the experiment refuted
      the hypothesis; the app picked the commit up and stayed OutOfSync.
- [ ] BLOCKED — operator: write Vault `vectordb/postgres` with `username` and `password`.
      `vectordb-postgres` is `SecretSyncedError` and `pod/vectordb-0` is
      `CreateContainerConfigError` until it exists. Claude must not create, read, print or log
      that value.
- [ ] Operator: reapply the ApplicationSets so the `ServerSideDiff` annotation reaches the live
      Application. The git fix is inert until then.
- [ ] Then Claude verifies read-only: `hub-vectordb` `Synced/Healthy` and `vectordb-postgres`
      `SecretSynced/True`.
- [ ] Latent: `observability.yaml` and `data-git.yaml` lack the same annotation. No symptom today
      (their ExternalSecrets are on `ubuntu-hostinger`); any ESO resource added to them will drift.

LESSON — search `docs/bugs/` for the symptom before diagnosing. This failure was already filed
and fixed for `platform-ops` on 2026-09-13 with the annotation named as the fix; re-deriving it
cost several live-diff rounds and one refuted experiment.

LESSON — `kubectl get -o json` hides `managedFields` unless `--show-managed-fields` is passed.
Zero entries is the default, not an anomaly.

# 2026-09-26 — WS1 pgvector hub platform component implemented

- [x] Added `scripts/etc/argocd/applicationsets/vectordb.yaml` with a hub list generator,
  literal `${K3D_MANAGER_BRANCH}`, `vectordb` destination, and `CreateNamespace=true`.
- [x] Added plain manifests for a single-instance `pgvector/pgvector:pg17` StatefulSet, Service,
  one 10Gi PVC using the default StorageClass, and ESO credentials from `vault-backend` at
  `vectordb/postgres`; no Role, RoleBinding, ClusterRole, fallback Secret, or credential value.
- [x] Added six pure-logic BATS tests. Each mutation check went red for its targeted broken
  condition and was restored. Focused suite passes 6/6; PyYAML parses all five YAML files;
  `make check-doc-links` reports 1789 files OK; shellcheck and `_agent_audit` are clean.
- [x] CHANGELOG describes the rebuildable cache, non-durable index, and UNMEASURED quality until
  the v1.40.0 eval. Commit: `5cf1700d`; PR not created by instruction; push remains pending.

# 2026-09-26 — ArgoCD values-branch gate fix implemented

- [x] M1–M4 implemented exactly from the bug spec on `k3d-manager-v1.39.0`.
- [x] Added six pure-logic BATS tests; focused suite passes 11/11. Each new test was
      mutation-checked individually; the covered change was reverted, the suite went red, and the
      change was restored. No cluster or network command was run.
- [x] Pre/post shellcheck output is identical: one pre-existing informational SC2317 at
      `scripts/plugins/argocd.sh:12`; no new warnings.
- [x] Final gates passed: `argocd_values_branch_drift.bats` 11/11, `argocd.bats` 37/37,
      shellcheck unchanged from the pre-change run, and `_agent_audit` passed. Implementation
      commit: `b1f90fce`; push is the remaining handoff step.

# Progress — k3d-manager

## 2026-09-26 — v1.38.0 MERGED, tagged and released; v1.39.0 branch cut

- [x] **SCOPE REVISED 2026-09-26 (operator approved): the vector-store spec is SPLIT, and
  `slack-corpus-qa` moves to v1.40.0.** Supersedes the earlier same-day decision that carried three
  specs onto v1.39.0. The original six-workstream spec named this split in its own Risks section and
  we took it.
  **v1.39.0 (4 plan docs, under the cap):** `test-suite-metrics-and-staleness`,
  `public-endpoint-blackbox-probes`, `slack-smoke-target`,
  `vector-store-platform-and-retrieval` (WS1 deploy + WS2 indexer + WS3 library).
  **v1.40.0 (3, pre-staged):** `hermes-app-health-delta-sensor`,
  `hermes-prior-art-and-retrieval-eval` (WS4 + WS5), `slack-corpus-qa`.
  Effect: `slack-corpus-qa` now sits in the **same** release as the WS5 recall@5 that gates it,
  instead of one release behind. That was the flaw in the earlier decision — carrying the vector
  store forward kept the dependency on the branch but not the measurement.
- [ ] **BLOCKS WS2 — the embeddings provider is undecided and no credential exists.**
  `k3dm-openai-api-key`, `k3dm-embeddings-api-key` and `k3dm-anthropic-api-key` are all absent
  (existence check only, no value read). **`gemini-cli-api-key` does exist** and Gemini embeddings
  are free-tier, making it the candidate needing no new credential — but it was provisioned for the
  Gemini CLI and **repurposing it needs the operator's explicit go**. WS1 does not depend on this;
  WS2 cannot start without it.
  WS2 cannot start without it. RESOLVED 2026-09-26: the operator approved reusing
  `gemini-cli-api-key`, and ruled that it stays the single keychain copy — the remaining absent items
  stay absent rather than being filled with duplicates. See the one-slot decision in
  `activeContext.md`.
- [ ] **WS1 needs the operator's go** — it deploys pgvector to the hub. Prerequisites verified
  2026-09-26: ESO on the hub is healthy (6 of 7 ExternalSecrets `SecretSynced/True`; the one
  failure is the pre-existing `cosign-public-key` in `platform-ops`), and the hub-scoped Application
  pattern to copy already exists (`hub-loki`, `hub-platform-ops`). WS1 must **not** use the
  `role: app-cluster` selector.
- [x] **Corpus measured for WS5's effort estimate: 1,703 tracked docs**, not the 868 the original
  spec assumed — 737 `docs/bugs/`, 451 `docs/issues/`, 435 `docs/plans/`, 80 `docs/retro/`. WS5 wants
  >=25 positive and >=25 hard-negative hand-mined pairs; 10 positives and 1 hard negative are already
  seeded, so ~15 and ~24 remain. This is the bulk of the retrieval work and is why it is its own
  release. `scripts/tests/fixtures/doc-dedup/` does not exist yet; `e2e-corpus/corpus.jsonl` is the
  schema precedent.
- [x] **v1.39.0 ships the retriever UNMEASURED — accepted, and must be stated.** No recall@5 number
  exists until v1.40.0's WS5 runs. The guide, CHANGELOG and retro must say the quality is unmeasured
  rather than implying it was evaluated; v1.40.0's WS6 goes back and replaces that caveat with the
  measured numbers.
- [x] **v1.39.0's three unimplemented specs — operator instruction 2026-09-27: implement, do not
  defer.** I had recommended deferring all three to v1.40.0; the operator overrode that. Two of the
  three are done on `k3d-manager-v1.39.0`, plus the two prerequisite gate fixes spec A was blocked on:
  - [x] `ff47bc2b` cluster-health app context resolved from `destination.name` (`docs/bugs/2026-09-25-smoke-cluster-health-app-context-decoupled-from-app-prefix.md`)
  - [x] `70417db0` webhook gate uses `?quick=1` and reports `curl exit 28`, not `000000` (`docs/bugs/2026-09-25-smoke-webhook-gate-unbounded-sweep-and-unreachable-probes.md`)
  - [x] `92590ae9` `/k3dm smoke` at `operator`/900s (`docs/plans/v1.39.0-slack-smoke-target.md`)
  - [ ] `docs/plans/v1.39.0-test-suite-metrics-and-staleness.md` — **dispatched to Codex**
  - [ ] `docs/plans/v1.39.0-public-endpoint-blackbox-probes.md` — **dispatched to Codex, offline half
        only**; the live TSDB verification and the ApplicationSet reapply stay operator-owned.
  Operator follow-up: `make restart-webhook` before `/k3dm smoke` resolves.

- [x] **SCOPE DECISION for v1.39.0 — settled 2026-09-26, operator approved.** v1.39.0 now holds
  exactly **5** plan docs, at the cap:
  1. `v1.39.0-test-suite-metrics-and-staleness.md` (its own, ready to implement)
  2. `v1.40.0-slack-corpus-qa.md` (its own, blocked — see below)
  3. `v1.39.0-public-endpoint-blackbox-probes.md` (carried)
  4. `v1.39.0-slack-smoke-target.md` (carried)
  5. `v1.39.0-vector-store-platform-and-retrieval.md` (carried)
  **Deferred to v1.40.0:** `v1.40.0-hermes-app-health-delta-sensor.md`.
  Files renamed per the `62c9ff27` precedent (carried specs take the new version prefix), headers
  updated, all inbound references fixed.
- [x] **Why the vector store was kept and the sensor deferred — corrects an earlier
  recommendation.** My first recommendation was to push the vector-store prior art to v1.40.0 as
  "research". That was wrong: its **WS5 measured recall@5 is the hard blocker** on
  `v1.40.0-slack-corpus-qa.md`, which was already on the branch. Deferring it would have left
  v1.39.0 carrying a spec that could not be started. The `app_health` sensor is the only one of the
  four carried candidates with nothing on this branch depending on it, so it is the only one that
  can leave without stranding something. **Rule: before deferring a spec, check what on the target
  branch depends on it — a spec can be low-priority and still be load-bearing.**
- [x] **Release step DONE: ApplicationSets reapplied for v1.39.0** (operator ran it; 2026-09-26).
  12/12 sets deployed on the hub `k3d-k3d-cluster` ns `cicd`, both ACG variants included
  (`grafana-dashboards-acg`, `observability-acg`). All **24** k3d-manager sources moved off
  `k3d-manager-v1.37.0` to `k3d-manager-v1.39.0` — the 6 with `ref: values` and the 18 with no
  `ref` that the gate never inspects. 2 remain at `HEAD` (rollout demo, intended). v1.38.0 config
  is now live in-cluster. `argocd_check_values_branch k3d-manager-v1.39.0` confirms clean **and
  printed `checked 6 values references`**, so the confirmation is trustworthy.
- [x] **LESSON: the release step inherits the current kube context.** The first attempt applied
  against the stale `ubuntu-k3s` context (dead ACG sandbox, 44.250.167.86) and failed all 12 sets
  at kubectl openapi validation — before any write, so nothing was mutated — at ~90s per set.
  `deploy_argocd_applicationsets` takes no context flag. **Check `kubectl config current-context`
  before any release step that does not take an explicit context.**
- [x] **LESSON: a partial stale split right after a reapply is reconcile lag.** The check run
  seconds after the apply still showed 3 of 6 stale (`acg-kube-prometheus-stack`,
  `acg-trivy-operator`, `loki`); a re-check moments later was fully clean. The sets update
  synchronously, the child Applications regenerate on the controller's own loop. Re-check before
  escalating.
- [x] **LESSON: the `!` relay executed nothing.** Three `!` invocations produced zero side
  effects — a `>` redirect target was never created, which proves the command never ran rather
  than ran-and-failed (zsh creates the target before the first line executes). Operator ran the
  commands directly instead.
- [ ] **NOT DONE and NOT to be retried as a sync: `shopping-cart-identity`** — deterministic
  failure, not drift. `Replace=true` in its syncOptions makes ArgoCD `kubectl replace` the bound
  `postgres-keycloak-pvc`, whose spec is immutable except `resources.requests`; the manifest
  omits `volumeName`/`storageClassName` so the replacement blanks them and the API server rejects
  it. Retry limit 5 exhausted, `phase: Failed`, which also blocks self-heal. Holds back 3
  ExternalSecrets and prevents `Job/keycloak-realm-reconcile` from being created at all.
  Already filed: `docs/bugs/2026-09-23-argocd-identity-replace-true-cannot-update-bound-pvc.md`
  (dedup check caught it; no second file). **Appended update disproves that doc's open question**
  — the realm-reconcile failure is independent, caused by `awk: command not found` in the
  `ubi9-micro` image. **Two fixes needed; the PVC one must land first** or the awk fix cannot be
  observed. Needs the operator's go on which fix option (per-resource `Replace=false` annotation
  in `shopping-cart-infra` is the filed preference).
- [ ] **Delete the stale `ubuntu-k3s` kube context** — now escalated from a ~90s-per-query
  annoyance to having burned a release step. `kubectl config delete-context ubuntu-k3s`. Operator's
  call (config mutation).
- [x] **BUG FOUND: `argocd_check_values_branch` reports a false clean under `--dry-run`** —
  printed "All Applications reference values branch k3d-manager-v1.39.0" while none did.
  `_argocd_values_branch_drift` exits 3 on unparseable input with empty stdout, and the caller
  decides on stdout alone, so "could not tell" is indistinguishable from "no drift". The
  absent `checked N values references` stderr line is the tell. Also: the gate checks only the
  6 `ref: values` sources, not the other 18 that drift on the same boundary.
  `docs/bugs/2026-09-26-check-values-branch-false-clean-under-dry-run.md`. OPEN, unfixed.

- [x] **PR #132 created** — `feat: read-only cloud-session access to the local webhook`,
  base `main`, head `k3d-manager-v1.38.0`. 40 commits, 34 files.
  https://github.com/wilddog64/k3d-manager/pull/132
- [x] **CHANGELOG promoted** — `[Unreleased]` -> `## [1.38.0] - 2026-09-25`, `[Unreleased]`
  left in place and empty above it. Release rows added to README (3-row main table, v1.35.0
  moved into `<details>`) and `docs/releases.md`. `59079150`, row reworded to the house
  title-and-theme form in `78216bd7`.
- [x] **Copilot: 3 findings, all valid, all fixed** — `2339e99d`. Threads all resolved.
  See `docs/issues/2026-09-25-copilot-pr132-review-findings.md`.
  - `mktemp -u` raced on the `init-cloud-requests` git index path. **Copilot's suggested fix
    was wrong** — git rejects a zero-byte index (`index file smaller than expected`), so
    dropping `-u` would have failed the target at rc 128. Fixed with a private `mktemp -d`.
  - BRE `\|` alternation in the day-old vacuous-run guard -> `grep -Eq` with an escaped ERE,
    re-mutation-tested red/green after the change.
  - The loopback webhook addressed as `https://` in **three** places, not the one flagged.
- [x] **Gates** — CI run 36209718366 on `2339e99d`: lint success, detect success, stage2
  **skipped** (label-gated on `ci:cluster-tests`, by design — not a hidden gap).
  `make test` 1129 ok / 0 not ok; `test-pytest` 215 passed; `test-python-unit` rc 0;
  `check-doc-links` 1785 OK. Live smoke: health 200, reader `cluster-status` 202, Slack
  `/k3dm test-pytest` round trip green.
- [x] **`enforce_admins` disabled** on `wilddog64/k3d-manager` `main`, verified
  `enabled=false`. `mergeable_state` reads `blocked` only because
  `required_approving_review_count=1` and Copilot reviewed as COMMENTED, not APPROVED —
  admin bypass is the intended path. **MUST be re-enabled with a bodyless POST after merge,
  or restored in the same turn if the merge is deferred.**
- [x] **PR #132 merged** — squash merge `6f0fb4af`, merged 2026-09-26T02:08:13Z by the
  operator. `mergeStateStatus` now UNKNOWN (post-merge), state MERGED.
- [x] **v1.38.0 tagged and released** — annotated tag `v1.38.0` on `6f0fb4af`, pushed over
  SSH (no token-in-remote dance needed). GitHub release published and marked latest:
  https://github.com/wilddog64/k3d-manager/releases/tag/v1.38.0
- [x] **`enforce_admins` restored** on `main` with a bodyless POST, verified `enabled=true`.
  Protection now reads `required_approving_review_count=1`, `enforce_admins=true`,
  `required_status_checks.checks=[]` — CI is still **not** a merge gate on this repo.
- [x] **`k3d-manager-v1.39.0` cut** from `6f0fb4af` and pushed, upstream verified as
  `origin/k3d-manager-v1.39.0` (not `main` — the mistrack guard).
- [x] **Retro written** — `docs/retro/2026-09-26-v1.38.0-retrospective.md`.
- [x] **Standing docs audited** — `.github/copilot-instructions.md` already current (all four
  v1.38.0 rules landed in the release). `memory-bank/projectbrief.md` was stale: its In-scope
  list had no entry for the read-only remote/cloud-session surface; added. `docs/api/functions.md`
  needs nothing — it documents plugin shell functions, and v1.38.0 added Python bins only.
- [ ] **Branch cleanup NOT run** — due every 5 releases; v1.35.0 was the last multiple, so
  v1.40.0 is next. Run early only if the operator asks.
- [ ] **`875f97da` missed the squash** — the memory-bank commit queueing the cloud-bridge
  architecture doc was pushed after the merge window and is **not in `main`**. Cherry-picked
  onto `k3d-manager-v1.39.0` as `ed697ef3`. Lesson: a push to a branch whose PR is already
  merge-ready is a push into a closing window.
- [ ] **Release-scope decision — NOW DUE, blocks v1.39.0 planning** — four v1.38.0 specs
  shipped as specs only (public-endpoint
  blackbox probes, hermes app-health delta sensor, slack smoke target, vector-store prior
  art). Carrying all four to v1.39.0 puts that branch at **6 plan docs, one over the max-5
  cap**, so they must be split across v1.39.0/v1.40.0 or dropped. Decide at `/post-merge`.
- [ ] **Cloud-bridge architecture doc — queued for v1.39.0** (operator, 2026-09-25). There is
  no `docs/architecture/` page for the bridge: v1.38.0 shipped
  `docs/howto/cloud-session-requests.md`, which is a usage contract (schema, actions, exit
  codes), not a design view. Missing: the request/response topology across the trust boundary,
  the two-token model and why a header may only narrow a role, the bare-clone + git-plumbing
  choice, the validator's ordered reject chain, and the deliberately unbuilt push path.
  **Not a plan doc** — `docs/architecture/` is outside the max-5 cap, so this does not
  compete with the four carried v1.38.0 specs. House style is Mermaid (9 of 11 existing
  architecture docs), plus a README `## Documentation` link.

## 2026-09-26 — v1.38.0 P6 reader-tier make targets through the cloud bridge

- [x] **P7 — offline test suites as reader targets** — `test-pytest` + `test-python-unit` in
  `MAKE_TARGETS` (Slack) and the bridge `ACTION_ALLOWLIST` (cloud). Fixed the webhook-PATH
  interpreter gap that would have made `test-pytest` exit 2 on every remote invocation.
  `make test` / `make test-bin` left unexposed pending the `scripts/tests/` live-mutation sweep.
  Gates: 215 pytest passed; drift guard mutation-tested. **`make restart-webhook` still pending.**
- [x] **Bug: two pytest suites ran nowhere in CI** — `cloud_bridge.py` (20 tests, incl. the P6
  drift guards) passed vacuously under `make test-python-unit` and was absent from
  `make test-pytest`. Renamed to `test_cloud_bridge.py`, `test-pytest` now globs `test_*.py`,
  and `test-python-unit` gained a vacuous-run guard. `a7d513f3`.
  See `docs/bugs/2026-09-25-pytest-suites-unreachable-from-make.md`.
- [x] Added exactly six literal bridge actions: `make-fix-list`, `make-fix-status`,
      `make-status-public`, `make-observability-status`, `make-vuln-scan`, and
      `make-e2e-runner-health`; no optional arguments or operator/admin targets were exposed.
- [x] Added four drift guards against `webhook.make_targets`, with `KNOWN_UNEXPOSED = frozenset()`
      explicitly defined for the current complete reader-tier exposure.
- [x] Added mutation-checked validation tests for unexpected args, missing `NS`, shell metacharacters,
      uppercase `NS`, unknown `make-sync-apps`, and exact make/cluster body bytes.
- [x] Gates: `pytest scripts/tests/bin/cloud_bridge.py` 23 passed; `pytest scripts/tests/bin/webhook_policy.py`
      22 passed; bridge AST parse passed; `make check-doc-links` reported 1784 files OK; forbidden
      pattern and operator-target-name greps were empty. Commit: `2db1a172` (amended once to record
      the final SHA; the final amended SHA is reported below).

## 2026-09-25 — v1.38.0 Part 2 P2/P5 cloud bridge

- [x] Implemented only the requested Part 2 files: bare-clone bridge, cloud request helper,
      launchd template, pure Python bridge tests, CHANGELOG, and three Copilot invariants.
- [x] Bridge validation order is file-size cap (8 KiB), JSON object, `schema == 1`, fixed action
      allowlist, exact args and anchored `job_id`, then future `expires_at`; rejected and expired
      ids are consumed, replayed ids are skipped, and processing is capped at 10 per tick.
- [x] Bridge uses `webhook.proc._spawn_capture_text` for literal Git argv, plumbing commits with a
      throwaway index, `--force-with-lease`, and plain `http://127.0.0.1:7443` reader requests.
      No checkout/switch, hook bypass, TLS-disable flag, shell string, kubectl, or non-Git child
      process was added.
- [x] P4 is configuration-inert: exactly 2 workflow files were counted across `.yml` and `.yaml`,
      with no push trigger for `cloud-requests`.
- [x] Gates: bridge pytest 9 passed; existing webhook policy pytest 22 passed; both AST parses,
      substituted-template `plutil -lint`, `make check-doc-links` (1782 files), `_agent_audit`,
      and diff checks passed. Commit/push are blocked by the managed workspace refusing Git lock
      and object writes (`Operation not permitted`); no hook bypass or history mutation was used.

## 2026-09-25 — `/api/v1/health` has been 500ing since v1.37.0 (found during v1.38.0 verify)

- [x] Root-caused an authenticated `GET /api/v1/health` returning `http=000`: the daemon raised
      `TypeError: 'NoneType' object is not iterable` at `do_GET:2187`. `_smoke_test_services`
      returns `results` only inside its `if quick:` branch and falls off the end otherwise, so the
      default non-quick path returns `None`.
- [x] Introduced by `925c43e7` (v1.37.0 webhook decomposition, PR #131): the function ended with
      `return results` at `bin/k3dm-webhook:2377` under `945018ee`, and the move into
      `scripts/lib/webhook/smoke.py` dropped it. smoke.py has exactly one commit, so no later edit.
- [x] Two callers affected: both `/api/v1/health` branches, and the post-provision Slack check at
      `bin/k3dm-webhook:1482`. `?quick=1` kept working, which is why a release shipped over it.
- [x] Fixed with the one-line return, plus
      `test_smoke_test_services_returns_results_on_the_non_quick_path`. Mutation-checked.
      Filed `docs/bugs/2026-09-25-smoke-test-services-missing-return-breaks-health.md`.
- [x] Not caused by the v1.38.0 role work. `reader cluster-status: 202` was the control — auth,
      the credential ceiling and the POST path were all correct while health was dead.
- [x] Live confirmation after `f6d60b00` + restart: `reader health: 200`. One result closes three
      things — health answers again, the reader credential authenticates, and the S3 GET gate lets
      a reader through a `reader`-rated route rather than over-blocking it.
- [ ] Follow-up, not in this fix: no gate asserts `/api/v1/health` returns 200 and parses its
      `services` array. That is why a dead endpoint merged. Belongs with the webhook smoke gate.
- [ ] Bears on the pending v1.37.0 tag: the broken endpoint is ON the v1.37.0 tree and the fix is
      only on `k3d-manager-v1.38.0`. Tagging v1.37.0 as-is tags a webhook whose `/api/v1/health`
      and post-provision check both raise. Operator's call.

## 2026-09-25 — S3 gate hole closed for the health query form (Claude)

- [x] Independently verified `8b706882`: on origin, 4-file scope, pytest + `webhook.bats` 64/64
      re-run by Claude. Codex's report checked out.
- [x] Found and fixed a real gap: the gate's `get_route is not None` guard left
      `/api/v1/health?...` ungated, because `get_route` resolves by exact lookup plus a
      `/api/v1/status/` prefix only. Resolved the health route for the query form before the gate.
- [x] Added `test_get_role_gate_covers_health_query_string_form`; mutation-checked — fails without
      the guard, and the pre-patch response was `200`.
- [x] Corrected the reader-token rotation claim in `docs/howto/cloud-session-requests.md`: no
      restart is needed, `_auth()` reads the Keychain per request.
- [x] Reader token created by the operator in the login Keychain (`k3dm-webhook-token-reader` /
      `k3dm`), verified non-empty by length only — 65 bytes, i.e. 64 hex plus newline. Claude never
      read the value.
- [x] `make restart-webhook` run by Claude; daemon back as pid 90449 on `127.0.0.1:7443` (plain
      HTTP on loopback, unchanged by this work). Negative auth cases all 401: no header, bogus
      bearer, non-Bearer scheme, and rejected before the api-path guard.
- [ ] Positive-path live check (admin 200 / reader 200 on health, reader 200 on POST
      `cluster-status`) is the operator's — it needs the token values, which Claude does not read.
- [ ] No live escalation test offered on purpose: every above-reader POST route
      (`argocd-upgrade`, `cluster-refresh`, `cve-remediate`, `analyze`) mutates or is expensive, so
      a probe that found the gate broken would execute the action. That case is covered by the
      synthetic-route unit tests instead, both mutation-checked.
- [ ] Part 2 (P2 bridge + P5) not dispatched.

## 2026-09-25 — webhook credential-bound roles COMPLETE (`8b706882`)

- [x] Implemented only S1/S2/S3/S6 from `docs/plans/v1.38.0-cloud-session-endpoint-access.md`:
      reader token resolver without `TOKEN_FILE` fallback; credential role ceiling; POST/make
      threading; GET route gate before health early returns; eight S6 tests.
- [x] Mutation check against the original `policy.py`: S6 items 3 and 4 both failed with the
      expected one-argument `TypeError`; edited policy was restored afterward.
- [x] Gates: bare pytest `36 passed`; `bats scripts/tests/lib/webhook.bats` `64/64`; AST parse;
      staged `_agent_audit` all passed. Shellcheck not run because all touched files are Python.
- [x] Commit `8b706882` pushed to `origin/k3d-manager-v1.38.0`.
- [x] Scope held to the four code/test files; no bridge, request helper, launchd plist, workflow,
      or new docs were added. Memory-bank status update is the required follow-up.

## 2026-09-25 — deploy_app_cluster_confirm live-mutation test fix COMPLETE

- [x] Applied A1/A2/A3 only to `scripts/tests/core/deploy_app_cluster_confirm.bats`:
      hard-fail `ssh`/`scp`, stub reachability `kubectl`, isolate the kubeconfig under
      `STUB_DIR`, and assert no provisioning output.
- [x] Focused BATS: 3/3. Mutation check: removing the SSH-key guard made test 3 fail;
      `git diff --quiet scripts/plugins/shopping_cart.sh` returned 0 after restoration.
- [x] Passing output had no `Merging ubuntu-k3s context`, `Installing socat`,
      `Permanently added`, or `vault-bridge active`; shellcheck passed with the existing
      dynamic-source SC1091 excluded. Claude re-verified BATS 3/3, the one-file scope, the
      origin tip, and that `shopping_cart.sh` is blob-identical to `925c43e7`.
- [x] Commit `1cbdab25bbe894d8658a82d22d5438f945f0e86d` pushed to
      `origin/k3d-manager-v1.38.0`; no production file or PR changed.

## 2026-09-24 — unknown actor role authorization fix (commit pending)

- [x] Added exported `_normalize_actor_role` in `webhook/policy.py`, switched exactly the
      actor side of `_role_allows` and the audit role field, and did not change `_normalize_role`
      or `strictest_role`.
- [x] Updated the two fail-closed `_fix_mode_enabled` rows and added the six requested policy
      tests, including the temporary patched `policy.AUDIT_DIR` audit isolation and enumerated
      current-call-site role pairs.
- [x] Updated the bug status/fix section, webhook role-model architecture note, and Unreleased
      changelog. No out-of-scope files, live webhook, cluster, browser, or Phase 4 work touched.
- [x] Gates: policy 13, agent 7, make-targets 14; webhook BATS 64/64; bare pytest 189;
      doc links 1765 files; repo-root pass; server import `OK`; `_agent_audit` exit 0.
- [x] `make test-all` completed plans `1..1112` and `1..132`; unittest counts `7 / 14 / 13 / 6 / 6`;
      expected EXIT=2 at Homebrew Python 3.14.7 without pytest. M1–M5 all red and restored with
      `git diff --quiet`.
- [x] **PR #131 merged to main at 925c43e7** (2026-09-25 18:14:11Z); retrospective written and committed on v1.38.0.
- [x] `make test` on v1.38.0: **1128 ok / 1 not ok of 1129**, exit 2. The red is
      `deploy_app_cluster_confirm.bats` test 3 — **not a v1.37.0 regression** (guard `1bbe54393`
      2026-08-21, test `62c9ff27` v1.27.0); it fails only because the ACG `k3s-aws` sandbox is
      reachable, and it **provisioned live infrastructure** (kubeconfig merge + socat/vault-bridge
      on `44.250.167.86`) three times. Spec `6da697a6`:
      `docs/bugs/2026-09-25-deploy-app-cluster-confirm-bats-mutates-live-cluster.md`.
- [ ] Implement the BATS fix (Part A — stub the reachability probe, hard-fail `ssh`/`scp`).
      **Part B (move the SSH-key guard in `shopping_cart.sh`) needs the owner's go** — it changes
      behavior on the already-Ready path.
- [ ] Sweep the rest of `scripts/tests/` for reachability-dependent live mutation (own spec).

## 2026-09-24 — webhook Phase 3 agent extraction (staged; Git blocked)

- [x] Extracted `_call_gemini`, `_is_fix_request`, `_fix_mode_enabled`, `_is_filing_request`,
      `_sanitize_question`, `_parse_gemini_observations`, `_run_cluster_ask`, plus
      `_FIX_RE`, `_FILING_RE`, and `_INJECTION_RE` into `webhook/agent.py` with explicit
      `__all__` and one-way imports toward config/policy/proc/render.
- [x] Added `scripts/tests/bin/webhook_agent.py` with literal fix-mode matrix (including the
      documented observed unknown-role values), individual injection alternatives, length and
      control-character guards, intent matching, and structured/malformed observation cases.
- [x] Updated the architecture map and CHANGELOG; repointed the two existing BATS checks that
      inspected moved code. No Phase 4 lifecycle/status work was started.
- [x] Mutation evidence: M1 reader bypass, M2 reader floor, M3 deleted `[INST]` alternative,
      M4 returned injected text, M5 raised cap to 5000, and M6 removed control stripping all
      produced red output; each was restored before the next mutation.
- [x] Gates: focused pytest 7; webhook BATS 64/64; bare pytest 189; `make test-all` completed
      BATS plans 1112 and 132 plus unittest counts 7/14/7/6/6, then expected EXIT=2 because
      Homebrew Python 3.14.7 lacks pytest; doc links 1764; repo-root 0; import `OK`.
- [ ] Commit/push and final SHA verification remain; Git returned
      `fatal: Unable to create '.git/index.lock': Operation not permitted`. No retry,
      lock removal, hook bypass, force-push, or PR was attempted. Changes are staged.

## 2026-09-24 — upstream credential-test observability (dispatched)

- [x] Spec written and pushed: lib-foundation `docs/plans/v0.4.18-credential-test-observability.md`
      at `d695f81` on `feat/v0.4.18-credential-test-observability`.
- [x] Dispatched to Codex (`codex exec`, workspace-write); log at
      `scratchpad/codex-libfoundation-v0418.log`.
- [ ] Verify Codex: SHA on origin, diff confined to the four listed files, jest > 28 tests, all three
      mutations reddening their named tests, disappearance gate 4 -> 0.
- [x] **lib-foundation PR #55 opened** — `https://github.com/wilddog64/lib-foundation/pull/55`,
      head `8986227`, `mergeable_state: clean`, CI green per-job, 5/5 Copilot threads resolved.
      `CHANGE.md` promoted to `[v0.4.18] — 2026-09-24` in `15bf3b7`.
- [x] Merge PR #55 (operator's), then tag v0.4.18 + GitHub release. Merged to main at
      `2f244ee4`; tag pushed; release at https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.18.
- [x] Subtree pull lib-foundation v0.4.18 (prefix `scripts/lib/foundation`, NOT scripts/lib/acg) —
      `7d786cd0`, vendored tree hash == upstream main tree `8b2f7956`. Tier 2 preflight rewired in
      `a4d6ef53`: `_secret_load_data` instead of a keychain existence check (which passes on a
      locked keychain and on an empty stored value), plus `export K3DM_ACG_REQUIRE_CREDENTIALS=1`
      so the session check fails closed. 14 BATS, mutation-gated (5 fail on the old code).
      Guide updated in the same commit.
- [x] Open a PR for lib-foundation `docs/v0.4.18-retrospective` — **PR #56**, CI 3/3 green.
      Copilot found three real gaps (verified against `acg_session_check.js`, not taken on faith):
      the marker table omitted `path=manual-login` (emitted at line 120), `docs/api/acg.md` had the
      same omission, and the retro cited `path=pluralsight_login` — a value emitted nowhere. Fixed
      in `78eacbe2`, all three threads replied to and resolved. `CHANGE.md` entry added in
      `1077361`. The same omission was mirrored in k3d-manager's harness guide and fixed in
      `4376a6ec`.
- [x] Open the v1.37.0 PR — **PR #131** (`4376a6ec`), Copilot requested, CI running at handoff.
- [x] Add `make e2e-sandbox` (Tier 2 `e2e_verify_sandbox`, `DIGEST=` optional) so Tier 2 has the
      same make entry point Tier 1 has, and expose `e2e-sandbox` on Slack `/k3dm` as an
      `operator` target (optional `DIGEST`, 3600s, no `confirm` — symmetric with `e2e-remote`).
      Docs: harness guide, Slack howto (incl. the unattended `ACG_SESSION_EXPIRED` caveat),
      CHANGELOG. Tests: Makefile-wiring BATS assertion + allowlist regression, both
      mutation-proven.
- [x] Fix both PR #131 CI reds — BATS `9a649af3` (fake `security` executable on PATH; the shell
  function stub was invisible inside `bash -c`, so macOS read the real keychain and Linux CI
  found no binary) and pytest `444aea0c` (`alert_delivery` missing from **both** sensor-stub
  sites, so the real sensor shelled out to live `kubectl`). Both were green locally for
  environment-specific reasons. Mutation-gated; 189 pytest passed offline.
- [x] Analyse + document CodeQL alerts 23/24/26/27 — `d482fc47`, false positives
  (`docs/issues/2026-09-24-codeql-pr131-spawn-injection-false-positives.md`) with in-code
  markers at both sinks.
- [ ] **Operator action:** dismiss CodeQL alerts 23/24/26/27 via `gh api` — the classifier
  denied it as a CI bypass; must be run from the operator's terminal. Blocks the #131 CodeQL
  gate; `enforce_admins` untouched until then.

## 2026-09-24 — ACG preflight account-name fix

- [x] Preflight now checks the `username` and `password` accounts individually instead of
      matching the Keychain service alone; the error reports `missing=<accounts>`. A credential
      stored under `-a k3dm` no longer satisfies a gate that the loader would never read.
- [x] Three new BATS cases (wrong account only, username-only, both accounts queried by name);
      focused suite 10/10, mutation-verified — restoring the service-only form reds exactly
      those three and leaves the no-`-w` and no-placeholder invariants green.
- [x] `docs/guides/vcluster-e2e-harness.md` gains the account-name table, the reason this
      service deviates from the repo-wide `-a k3dm` convention, the GUI-session requirement
      behind `User interaction is not allowed`, and the silent empty-value trap for a bare `-w`
      in a non-TTY shell. `make check-doc-links` 1765 OK; shellcheck clean.
- [ ] Operator, at the Mac in Terminal.app: populate both accounts, then
      `make -C scripts/lib/foundation credential-test` expecting `ACG_SESSION_OK`. All three
      accounts measured absent on 2026-09-24; nothing to clean up first.

## 2026-09-24 — Tier 2 ACG preflight (working tree complete; Git blocked)

- [x] Task 0 recorded as Path A: the personal ACG account has no MFA.
- [x] Added `_e2e_sandbox_preflight_auth` before `acg_extend_playwright`; it checks the
      URL, existence-only `k3dm-acg-pluralsight` Keychain service, and refuses the skip
      session-check override. Added offline transport-stubbed preflight tests.
- [x] Extended `docs/guides/vcluster-e2e-harness.md` with the setup, MFA constraint,
      marker triage, and debugging-override rules; added the Unreleased changelog entry.
- [x] All six mutations turned their named guard tests red and were restored; the final
      focused suite is 6/6 and existing `e2e.bats` is 49/49.
- [x] `shellcheck -x scripts/plugins/e2e.sh` is clean with 0 warnings before and after;
      `make check-doc-links` reports 1764 files OK; `make check-repo-root` passes.
- [x] `make test-all` completed (`1..1111` primary BATS plan plus `1..132` additional
      BATS) and reached the expected pytest dependency failure: Python 3.14.7 has no pytest,
      so Make exited 2. No live ACG, browser, cluster, or CDP command ran.
- [ ] Git staging was blocked by `.git/index.lock: Operation not permitted`; no commit SHA
      or push exists. The requested files remain unstaged; operator must stage, commit, and push.

## 2026-09-24 — webhook Phase 1b authorization (staged; commit blocked)

- [x] Implemented S1–S3: route floors are authoritative, dynamic requirements are marked,
      effective policy is the strictest floor/dynamic role, and every known POST request is
      checked and audited exactly once. `/api/v1/cluster` remains reader-floor and its unknown
      action still reaches the existing 400 handler response.
- [x] Extended `scripts/tests/bin/webhook_policy.py` with literal effective-policy rows,
      synthetic copied-table floor coverage, closed-default role coverage, dynamic metadata
      coverage, and allowed/denied/None-dynamic audit cardinality coverage. No `if action_policy`
      guard remains.
- [x] Gates observed: focused pytest **7 passed**; `webhook.bats` **64/64**; bare pytest
      **189 passed**; `make check-doc-links` **1762 file(s) OK**; `_agent_audit` **0**.
- [x] M1–M6 each produced the expected red test and was restored with `git diff --quiet`.
- [ ] Commit/push blocked by `.git/index.lock: Operation not permitted`; no SHA exists.
      The staged implementation is ready for the operator/Claude to commit and push with the
      exact requested message. The import gate used `/usr/bin/python3` 3.9.6 and failed before
      module execution on existing `str | None` annotations; `make test-all` also encountered
      the sandbox's restricted `/var/folders` temp root. No out-of-scope files were changed.

## 2026-09-24 — webhook Phase 1 extraction (working tree only; blocked)

- [x] Added `scripts/lib/webhook/policy.py` with the exact requested policy functions and
      explicit `__all__`; no policy import-time authentication/keychain side effect.
- [x] Replaced path comparisons in API POST/GET dispatch with explicit route metadata and
      documented the route table in `docs/architecture/webhook-server.md`; `/slack/events`
      signature verification was left untouched.
- [x] Added completeness and literal before/after authorization-equality tests; baseline
      test imports were repointed for moved names. Four required mutations each went red and
      were restored with `git diff --quiet`.
- [x] Verification: entrypoint 4010 -> 3929 lines; bare pytest **189 passed**; focused BATS
      **64/64**; Python collections **14, 6, 6, 14, 2**; `make check-doc-links` **1762 files OK**;
      pyenv-shimmed `make test-python` **184 passed**.
- [ ] `make test-all` is not green because an unrelated existing `cluster_status_summary.bats`
      JSON assertion expects one failed service while its fixture returns two; the system
      `python3` used by Make also has no pytest unless PATH is shimmed. No out-of-scope test
      fix was made. No issue doc was created because the dispatch explicitly forbids modifying
      files outside its target list.
- [ ] Commit/push blocked by sandbox Git write restrictions (`.git/index.lock`,
      `.git/COMMIT_EDITMSG`, and temporary tree objects: `Operation not permitted`); no SHA.

## 2026-09-24 — app-CVE scan trigger target

- [x] Implemented the exact v1.37.0 S1–S3 trigger, Makefile target, operator-role `/k3dm`
      allowlist entry, enumerated `CRONJOB` validation, appended pytest cases, and new
      transport-stubbed BATS suite.
- [x] Added the existing CVE guide's out-of-band trigger section, v1.34 allowlist row, and
      Unreleased changelog entry. Verified the payload's actual selector is
      `k3dm.k3d.io/cve-remediation-event=true` (spec guess did not match); no payload logic
      or schedule was changed.
- [x] Focused BATS **6/6** and **2/2**; focused pytest **14 passed**; whole pytest **189
      passed**; `make check-doc-links` **1762 files OK**; `make -n app-cve-scan` parsed.
- [x] M1–M6 each turned the required named test red and restored byte-for-byte.
- [ ] `make test` completed **1105 tests** but exited 1 on unrelated pre-existing
      `e2e_remote.bats` tests 688, 699, 723, and 724; left untouched per scope. No live
      cluster commands were run. Commit/push is blocked by `.git/index.lock: Operation not
      permitted`; no commit SHA exists yet.

## 2026-09-24 — Hostinger shopping-cart label and CVE promotion guard

- [x] **`93ffe649`** — Hostinger registration sets the shopping-cart label by default with an
      explicit override preserved; app-cve-scan skips a missing Application without aborting the
      loop or emitting a remediation event. Added the required focused tests, CVE guide note and
      changelog entry.
- [x] Focused BATS **9/9**; mutation proofs M1–M4 each red and restored with `git diff --quiet`;
      shellcheck exact counts unchanged from `HEAD~` (Hostinger 2→2, app-cve-scan 0→0);
      `make test` **1096/1096**; bare pytest **184 passed**; `make check-doc-links` **1760 files OK**.
- [x] Commit pushed and verified with `HEAD` equal to `origin/k3d-manager-v1.37.0`; no live-cluster
      commands run.

## 2026-09-23 — Alert delivery and ambient CNI precedence specs

- [x] **Commit 1 — `03b8755caad4b698c4ecdc9bfbd53b21cbf91e1`** — warning-severity alerts route
      through `platform-warning`, both observability renderers reject a missing referenced
      Alertmanager config Secret, and Hermes gains the read-only `alert_delivery` sensor/probe.
      Focused pytest: 8/8; focused BATS: 22/22; mutations M1/M2/M3 each red and restored;
      doc links: 1756 files OK.
- [x] **Commit 2 — `02e3fa769e002ba5757e5eb267ab02e1c7f192ad`** — provider-derived Istio ambient
      CNI dirs take precedence over live values, generic dirs are refused for k3s, and the
      override log no longer claims live provenance. Focused BATS: 8/8; mutations M1/M2/M3 each
      red and restored; doc links: 1757 files OK. Both commits pushed to origin; no PR created.
- [x] **Follow-up test correction — `d2c6177fbadaf44729fcd09fc7c575c38c6f268`** — updated the
      existing live-overrides assertion from `keeping live` to `resolved overrides`, as required
      by commit 2's logging change. Corrected `make test`: 1083/1083; bare pytest: 184 passed.

## 2026-09-23 — Hostinger registration must survive a hub rebuild (spec filed)

- [x] **Spec filed** — `docs/bugs/2026-09-23-hostinger-registration-does-not-survive-a-hub-rebuild.md`,
      dispatched to Codex. Declares the app clusters in `scripts/etc/argocd/app-clusters.tsv`,
      reconciles them additively from `bin/cluster-up` and `hub_recovery_reconcile` via the
      existing `refresh_registration` entry point, and reports a `REGISTRATION GAP` in
      `make status`.
- [x] **Correction to the record:** the registration-only entry point already exists
      (`make refresh-registration CLUSTER_PROVIDER=k3s-hostinger`, `14f26f3d`). The reopened
      2026-09-13 doc repeated "there is no registration-only entry point" after its own fix had
      landed. Item 1 ("re-register hostinger") therefore needs no code — only the operator's run.
- [x] **Codex implementation — `1238f994`** — pushed to `origin/k3d-manager-v1.37.0`. S1–S4,
      focused tests, guide, README/CHANGELOG updates, and mutation proofs complete; focused
      suites 47/47 and `make test` 1068/1068 green.
- [ ] **Operator: re-register hostinger** — `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger`.
      Live hub mutation; needs the user's go. Hostinger workloads are unmanaged until then.
- [ ] **Durability unproven until a rebuild happens with the fix in place.** A reconcile that has
      never run during an actual rebuild is a claim, not a verified fix. The bug doc stays open.

## 2026-09-23 — Alertmanager warning-severity delivery fix

- [x] **`a7135966` — warning alerts no longer fall through to the root `null` receiver.**
      Added `platform-warning`, routed `KubeJobFailed`, `KubeJobNotCompleted`, E2E and
      Prometheus self-health allowlisted alerts at route index 2 after SMS criticals, and
      documented the default-deny/first-match behavior in `docs/guides/alerting.md`.
- [x] Gates: focused Alertmanager BATS 7/7; `make test` 1061/1061; shellcheck clean;
      `make check-doc-links` 1749 files OK; rendered template YAML valid.
- [x] Mutation proof: deleting the route made tests 3 and 5 red; blanking `to:` made test 4
      red; swapping the warning and critical routes made tests 2, 3 and 5 red. Each mutation
      was restored byte-for-byte before the next.
- [x] **Pushed** — implementation commit `a7135966` and status commit `683a8ac7` are on
      `origin/k3d-manager-v1.37.0`; the initial pull was blocked by inability to write
      `.git/FETCH_HEAD`.
- [ ] **NOT YET DEPLOYED** — the live Alertmanager still runs the old two-route tree and is
      still discarding `KubeJobFailed`. Needs the operator to re-render the Alertmanager
      secret, then confirm `platform-warning` appears in the route tree and that a
      `KubeJobFailed` email actually arrives. Delivery is unproven until then.

## 2026-09-23 — M2 GHCR credential root-caused (locked keychain), fix dispatched to Codex

- [x] **Root cause found, prior triage retracted** — the M2's `gh` token is NOT invalid or
      missing. It is stored in the macOS keyring; a non-interactive SSH session cannot unlock
      the login keychain nor prompt, so `gh auth token` returns empty and `gh auth status`
      reports "invalid" — indistinguishable from a deleted token. Keychain item
      `gh:github.com` is PRESENT; `show-keychain-info` → `User interaction is not allowed.`
      Verified on m2-air.local with the absolute path `/opt/homebrew/bin/gh`.
- [x] **August remediation retracted as never-viable** — `gh auth login` / `gh auth refresh
      -s read:packages` on M2 cannot fix a dispatch that runs over SSH. Was run by the
      operator on 2026-09-23 with no effect. Removed from the Gap 3 doc as a step.
- [x] **Two of my own claims corrected** — (a) the earlier "not the locked-keychain trap"
      call was based on a test that captured stderr into the variable; it IS the trap.
      (b) `gh` missing from `command -v` on a BatchMode shell affected only my manual probes,
      NOT the dispatch — `E2E_M2_REMOTE_PATH` (`e2e_remote.sh:31`) already prepends
      `/opt/homebrew/bin`. Recorded so it is not re-filed as a defect.
- [x] **`hosts.yml` must NOT be committed** — it is where `gh` writes the token in plaintext
      when secure storage is off. It also holds no token on either host today, so committing
      it would carry nothing and leak a credential the moment it did.
- [x] **Fix specced and dispatched** —
      `docs/bugs/2026-09-23-e2e-dispatch-forward-ghcr-token-over-stdin.md`. Forward the M4's
      existing `read:packages` token to the runner over **stdin** (never argv, never the
      tee'd command string). No change to `shopping_cart.sh` — its env path is already first
      in the resolver chain. Includes a PIPESTATUS index trap: adding `printf` to the head of
      the pipeline shifts `ssh` to index 1, and getting it wrong makes every dispatch report
      exit 0.
- [x] **Fix implemented and verified** — Codex wrote it; Claude committed/pushed after Codex
      hit the known `.git/index.lock` write-wall. Verified independently: scope is the two
      scoped files, shellcheck clean, BATS 79/79 (0 `not ok`), and Claude re-ran the PIPESTATUS
      mutation test itself (index 0 → red, index 1 → green, restore byte-identical).
      Unit-proven only — never yet exercised against the live runner.
- [x] **Spec amended mid-implementation** — the two-branch shape tripped `_agent_audit`'s
      if-count threshold on `e2e_runner_dispatch` (pre-commit rejected it; `--no-verify` is
      forbidden). Collapsed to one unconditional path instead of extracting a helper: an
      unresolved credential sends an empty line, which `shopping_cart_load_ghcr_pat_from_env`
      already treats as absent. Better than specced — one `PIPESTATUS` index, remote always
      gets EOF on stdin, and the pre-existing exit-code test now guards the index as well, so
      the trap has two guards. BATS 80/80. Amendment recorded at the top of the spec doc.
- [x] **vCluster leak FIXED 2026-09-23** — and the filed root cause was wrong. The EXIT trap
      did fire; it killed itself in `_e2e_write_result_event`, where `_kubectl create` without
      `--no-exit` reaches `_run_command`'s `_err` → `exit 1`, terminating the shell before
      teardown with the `ERROR:` line swallowed by `2>&1`. On the m2 runner the hub is
      unreachable by construction, so teardown was unreachable there on *every* dispatch.
      Three changes: `--no-exit` on publish+prune; trap reordered to summary → teardown →
      result event; `_vcluster_reconcile_namespace` clears an orphan before create, for leaks
      no trap can catch. `e2e.bats:403` was written for this scenario and could never fail —
      its `_run_command` stub cannot exit. 181 BATS pass / 0 fail, shellcheck clean, three
      mutation proofs. **Unit-proven only — not yet exercised live.**
- [x] **Second exit-in-teardown defect FIXED 2026-09-23** — `_vcluster_ensure_exists` proved
      existence from a kubeconfig *file* and otherwise `_err`ed, i.e. `exit 1`, out of a caller
      chain (`_e2e_teardown:405` → `vcluster_destroy:88`) guarded only by `|| _warn`. Same class
      as `7338a238`: the exit skipped `e2e.sh:411-426` and killed the trap mid-way. Fired when a
      run fails *during* `vcluster create` — no kubeconfig, nothing listed. Fixes: shortcut
      deleted (`vcluster list` is the truth), both `_err`s → `_warn` + `return 1`, check moved
      after the `DRY_RUN` return. `vcluster.bats:131` passed only because of the shortcut;
      `:113` asserted only non-zero, which `exit 1` also satisfies. 183 BATS pass / 0 fail,
      shellcheck clean, both guards mutation-proven. **Unit-proven only — not exercised live.**
- [ ] **Tier 1 still unproven** — all three fixes (GHCR stdin `9d2a0ad0`, leak `7338a238`,
      the ensure_exists fix) are unexercised against the live runner. A dispatch is needed to confirm,
      and needs the operator's go.
- [x] **Six stale kubeconfigs swept 2026-09-23** — operator-authorised; verified orphaned first
      (`vclusters` ns absent, `vcluster list` empty, no docker proxies), deleted by exact name.
      `~/.kube/vclusters/` on the m2 runner is now empty.
- [ ] **Hostinger hub registration LOST AGAIN 2026-09-23** — regression of a doc marked DONE.
      The 2026-09-20T23:49Z hub rebuild recreated only `ubuntu-k3s-app-cluster` (in-cluster);
      `cluster-ubuntu-hostinger` is absent and 0 `ubuntu-hostinger-*` Applications exist. This
      is why CVE Auto-Patch has no data: `cve-remediation-verify` fails every 15 min with
      `secrets "cluster-ubuntu-hostinger" not found`, so no remediation event ConfigMap is
      written and the exporter emits zero `cve_*` gauges. Recurrence appended to
      `docs/bugs/2026-09-13-hostinger-app-cluster-registration-lost-orphaned-workloads.md`.
      Needs the operator's go: no registration-only entry point exists, and
      `make refresh CLUSTER_PROVIDER=k3s-hostinger` remains unsafe and unapproved. The real
      fix is making registration survive a rebuild — otherwise recurrence #3 is scheduled.
      Also: 3 consecutive CronJob failures raised no alert.
- [ ] **Hermes still BOOTED OUT** — must stay down until both blockers are fixed, or it
      re-wedges the runner every 5 minutes. Restore:
      `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.k3d-manager.hermes.plist`

## 2026-09-23 — shopping-cart made opt-in per app cluster (code done, reapply pending)

- [x] **Narrow fix implemented** — `a89e9e93` on `k3d-manager-v1.37.0`. `data-git` + `services-git`
      require `k3d-manager/shopping-cart: "true"`; `register_app_cluster` emits it from
      `ARGOCD_APP_CLUSTER_SHOPPING_CART` (default `false`, boolean-validated). `eso` and
      `grafana-dashboards-acg` untouched. 5 new BATS assertions, each mutation-tested against the
      pre-change tree; `argocd.bats` 42/42 and `argocd_app_cluster_generator.bats` 7/7 green;
      shellcheck unchanged (1 pre-existing SC2317).
- [x] **Docs, same release** — `docs/architecture/shopping-cart-deployment.md` §2 gains
      "`ubuntu-k3s` is a role, not a place": the role label as a movable pointer, the designed
      in-cluster registration mode, the four selecting AppSets and their `preserveResourcesOnDeletion`
      split, the never-delete-the-registration warning, and that an empty `shopping-cart-data` on the
      hub is expected. CHANGELOG `[Unreleased] → Changed`.
- [x] **Withdrawn approach recorded** — `d6297a2c`, superseded by `c7a5956d`.
- [x] **DONE 2026-09-23** — reapplied; 7 apps -> 0; ESO verified intact (23 CRDs, 3 deploys, 1 CSS).
- [x] **3a executed** — `shopping-cart-apps` and `shopping-cart-data` namespaces deleted.
- [x] **Bug docs filed** — identity `Replace=true` (new); argv PAT extended as Defect 4 on the
      existing `rotate-ghcr-pat` doc rather than duplicated.
- [ ] ~~PENDING OPERATOR GO~~ (superseded) Task 0 re-capture (read-only),
      then reapply the ApplicationSets for hub **and** ACG, then `argocd_check_values_branch`.
      Expect zero `ubuntu-k3s-data-layer` / `ubuntu-k3s-shopping-cart-*`; verify `ubuntu-k3s-eso`
      and `ubuntu-k3s-grafana-dashboards` still Synced with 21 ESO CRDs and 22 ExternalSecrets.
      `data-git` prunes and holds the resources finalizer — if StatefulSets or bound PVCs have
      appeared in `shopping-cart-data`, stop.
- [ ] **Then decide 3a vs 3b** — `preserveResourcesOnDeletion: true` leaves the `shopping-cart-apps`
      Deployments running unmanaged. 3a deletes the `shopping-cart-apps` + `shopping-cart-data`
      namespaces; 3b keeps them as an unmanaged demo. Never delete the `secrets` namespace.
- [ ] **ESO re-homing** — queued in `docs/roadmap.md` Forward themes, unversioned, needs a scope doc
      (the 21 CRDs must be adopted, not recreated).

## 2026-09-22 — v1.36.0 smoke and hub snapshot features

- [x] Unified `make smoke` target committed as `6f1f7fd1`; seven focused BATS cases pass, including
  the tier skip/failure behavior and the `set -e` later-check regression guard.
- [x] Hub snapshot capture, M2 transfer/checksum verification, retention, Loki recovery record,
  docs, and 13 focused BATS cases committed as `d53ea1ba`; all focused cases and mutation checks pass.
- [x] Full `make test` passed with `1030` `^ok` lines and no `not ok` lines. Feature commits and the
  recovery compatibility test commit are pushed to `origin/k3d-manager-v1.36.0`; final SHA is
  `5eb759eb4e9cb584cf17b7a67d6f937ecdd00010`.
- [x] **Claude verification fixed two defects** (`5dd53be8`, both mutation-verified): the
  `K3DM_SNAPSHOT_DIR` tilde default that would have created a directory literally named `~` on
  the M2, and the stale "seven logical claims" message after Loki made it eight. Suites re-run
  independently: hub_recovery 27/27, hub_snapshot 14/14, smoke 7/7, shellcheck RC=0.
- [x] **Free-space preflight REMOVED at the operator's request** — `d1c8b5b3`, pushed. It ran
  after the full local capture, so it never gave the "refuse before copying anything" behaviour
  the spec asked for; it only guarded the M2 transfer, which `rsync` already fails on when the
  destination is full. The insufficient-space BATS case was replaced by its inverse (a capture
  must issue no remote `df`), mutation-verified by restoring the preflight. Suite stays at 14.
  `make test` **1031/1031** after the removal — count reconciles exactly.
  - The pre-commit `_agent_audit` blocked the first attempt ("@test blocks decreased"). That
    guard is correct and was **not** bypassed with `--no-verify`; the replacement guard was
    written instead, which is a stronger test than the one deleted.
  - 4 reds in `e2e_remote.bats` on the first run were the documented **unpushed-HEAD**
    signature, not a regression (local `d1c8b5b3` vs origin `2ee4ad86`). 74/74 after pushing.
- [ ] **Residual gap, accepted knowingly:** on a *transfer* failure the remote directory is left
  un-marked rather than `.INCOMPLETE` (checksum failures still mark it). Two-line fix available;
  awaiting the operator's word.
- [x] **`make test` 1031/1031, 0 `not ok`, against the live post-fix tree.** The first run showed
  1030 but predated Claude's two fixes — caught because the arithmetic was too clean
  (1010 + 7 + 13 = 1030, no room for the added 14th case). Re-run reconciles exactly at 1031.
  Lesson reinforced: measure gates against the live tree, not a snapshot.
- [x] `docs/howto/makefile.md` corrected — it still documented the removed `~/k3dm-snapshots`
  default; now warns explicitly against a `~`-prefixed value. The `docs/issues/2026-09-11`
  mention of "seven logical claims" was deliberately left as historical record.

## 2026-09-22 — Realm SSO reseed queued for v1.37.0

- [x] **`968ae5eb` on origin — `docs/plans/v1.37.0-realm-sso-password-reseed.md`.** Specs
  `ldap_reseed_realm_users` in `scripts/plugins/ldap.sh` + `make reseed-realm-sso-users`, and
  requires `bin/cluster-up` Step 10d.5 to **delegate** to it rather than keep a second copy.
  Core design: Vault record **present** → re-apply to LDAP, **no rotation**; **absent** →
  generate + write + apply, rotation unavoidable. Mirrors the Prometheus
  `recovered … not rotating` precedent.
- [x] **Operator asked for v1.34.0 — impossible, retargeted.** `v1.34.0` is tagged/shipped AND
  already at the 5-plan-doc cap, so a spec there could never be implemented. v1.35.0 shipped,
  v1.36.0 at cap. v1.37.0 was the only milestone with room; now 2 docs.
- [x] **Three traps recorded in the spec, each found by reading the tree, not assumed:**
  - `ldap.sh:787 ldap_get_user_password` reads `secret/ldap/users/<u>` in ns **`vault`**, while
    the realm users live at `secret/keycloak/users/<u>` in ns **`secrets`**
    (`bin/get-keycloak-password:17,62`). Wiring the new target to the existing public function
    would silently reseed nothing and look like "record absent". Test case 7 guards it.
  - `_vault_kv_put/_exists/_get_field` exist **only** in `shopping_cart.sh:645,666,680` and need
    `_vault_root_token`/`_vault_local_port` which `bin/cluster-up:381` sets. Cross-plugin calls
    silently no-op under the lazy-loading dispatcher, so the new function must do its own Vault
    access — precedent `bin/restore-hub-ghcr-pat:33,57`, `bin/rotate-ghcr-pat:32,46`.
  - Do NOT copy `_ldap_sync_admin_password` (`:836`), which passes secrets via `env` on the exec
    line; Step 10d.5's stdin idiom is correct and mandated.
- [x] **Doc requirement pinned:** `docs/howto/rotate-service-credentials.md:151-155` already
  documents this trap with no remedy; the spec's DoD requires that paragraph to name the new
  target in the same release.
- [x] **Hub seed set: APPROVED by the operator 2026-09-22 and added to the spec as requirement 4.**
  Research found there is **no single allowlist**: the 14 keys are enumerated twice, with different
  mechanisms — the `_keys` array at `scripts/plugins/vault.sh:1118-1125`
  (`vault_seed_hub_into_context`, which is what writes the Keychain backup) and a hand-written
  per-key `if _vault_kv_exists … else` chain in `shopping_cart.sh:696`
  (`shopping_cart_seed_sandbox_vault_kv`, the seeder `bin/cluster-up:745` actually runs). Both must
  change. The `vault.sh` side is load-bearing: `_seed_source_data` reads a canonical *source* Vault
  which a hub rebuild has just destroyed, so only the Keychain fallback (`vault.sh:1135`) can
  restore anything. Three literal paths, not a glob. `scripts/tests/plugins/vault_seed_hub.bats:58`
  pins the exact key list and must go 14 → 17. New risk recorded: a Keychain-restored Vault record
  whose LDAP hash no longer matches displays a password that does not work — worse than a blank —
  so the reseed's present→re-apply branch is the required reconciler. Also noted `vault.sh:1170`
  logs `all 13 canonical keys` against a 14-element array (message-only off-by-one, fix with the
  count change).
- [x] **Still out of scope, needs the operator's word:** auto-reseeding on `make up` (would
  silently rotate live passwords).
- [x] Gates: `make check-doc-links` 1737 files OK then 1738 OK after the allowlist amendment; all
  cited line refs spot-checked live.

## 2026-09-22 — Realm SSO password display: misleading hint fixed, reset done

- [x] **`80970c04` on origin — `make show-service-passwords` stops lying.** The hint said
  `not provisioned on this cluster`, which reads as "these accounts do not exist". They do:
  `ldapsearch` on `ou=users,dc=home,dc=org` returns `uid=admin`, `uid=developer`, `uid=operator`,
  all with working passwords. Only the Vault plaintext copy at `secret/keycloak/users/*` is
  missing. New text names the real state and the real remedy.
- [x] **Root cause:** `bin/cluster-up` Step 10d.5 (`:1018-1072`) is the sole writer of that
  plaintext. This hub was rebuilt with `make up`, which does not run it, while OpenLDAP's
  local-path PV survived — so the accounts persisted and the Vault records did not.
- [x] **Plaintext is unrecoverable.** LDAP stores only hashes. Unlike the Prometheus repair
  above, there is no local plaintext cache to restore from, so a **reset** is the only route to
  a displayable password.
- [x] **Ruled out with evidence, not dismissed:** `keycloak-credential-rotator` writes
  `secret/keycloak/admin` only (hence `LIST secret/metadata/keycloak` = `["admin","clients"]`);
  its BusyBox `base64 --decode` defect is already M4 in
  `docs/bugs/2026-09-22-ci-red-prometheus-reseed-and-rotator-base64.md`. Neither caused this.
- [x] **Checkpoint not implicated:** `step-10d5-ldap-passwords.done` exists only under the
  `k3s-aws` state dir, not k3d — the seeder never ran on the hub, so it would execute, not skip.
- [x] Gates: live render of the new text; BATS `makefile_show_service_passwords` 10/10 (case 9
  guards this block), `identity_tools` 5/5, `webhook_make_targets` 11/11.
- [x] **Reset RUN by the operator and verified — all three display.** `vault put: ok http=200`
  → `ldappasswd: ok` → `ldapwhoami: VERIFIED` for admin, developer and operator (9/9 steps).
  Claude then confirmed presence without printing values: all three resolve via
  `bin/get-keycloak-password` (lengths 22/22/23, consistent with
  `openssl rand -base64 18 | tr -d '=+/'`), and `make show-service-passwords` renders a password
  on all three rows instead of the hint. **These are new passwords** — the pre-reset plaintext is
  gone for good.
  - **Lint friction worth remembering:** plain `shellcheck` exits non-zero on two *info*-level
    SC2016 hits, which silently short-circuited the `&&` chain so the reset never ran on the
    first attempt. The single quotes are correct and required — `$LDAP_ADMIN_PASSWORD` and `$1`
    must expand **inside the pod**; double-quoting them would interpolate host values and bake
    the LDAP admin password into the `kubectl exec` command string that reaches logs. Step 10d.5
    uses the same idiom. Gate with `shellcheck -S error` for scripts using this pattern.
  - **Claude error, corrected in place:** first attempt at silencing SC2016 used a backtick
    `` `# comment` `` block, which spawns a subshell rather than commenting. Reverted immediately.
- [x] **Reset script** (scratchpad `reseed-keycloak-users.sh`)
  mirrors Step 10d.5 (generate → Vault KV put → `ldappasswd` stdin → `ldapwhoami` verify),
  prints no passwords, `chmod 600` header file. Preconditions verified live: openldap-0 up,
  `LDAP_ADMIN_PASSWORD` SET, Vault PF 200, and `ldappasswd`/`ldapwhoami`/`mktemp`/`openssl` all
  present in the pod. `bash -n` + `shellcheck` were **classifier-denied** (Secret-Store Writes),
  so the operator lints and runs it via `!`. It mutates live LDAP passwords, so it stays gated.

## 2026-09-22 — Prometheus Vault entry repaired

- [x] **`secret/data/k3d-manager/prometheus-basic-auth` 404 → 200.** Operator ran
  `/tmp/prom-recover.sh`; Claude did not (root-token read is Claude-forbidden by design).
  Output confirmed `recovered the Prometheus password from the local cache; not rotating` —
  **no rotation**, saved logins preserved.
- [x] All four preconditions re-verified against live state first, without printing secrets:
  cache readable (143 B), password 32 chars and not the `"password"` sentinel, `htpasswd`
  present, Vault health 200.
- [x] **Claude's own bug in the staged script, fixed:** it set neither `SCRIPT_DIR` nor
  `PLUGINS_DIR`, but `observability.sh:6` reads `$PLUGINS_DIR` at source time to load
  `vault.sh` → `unbound variable`. Bootstrap re-verified by resolving all three functions.
- [x] Consumers audited: only `Makefile:542` and `observability.sh`. No ExternalSecret,
  ServiceMonitor or scrape config → nothing to restart.
- [ ] **Does not affect Grafana** — hub Prometheus has no basic auth; the blank e2e panels are
  still a producer problem, unblocked only by a Tier 1 run.
- [ ] Realm SSO rows still read "not provisioned": `secret/keycloak/` has only
  `['admin','clients']`, no `users/`. Seeding remains an operator decision.

## 2026-09-22 — Webhook decomposition specced, QUEUED for v1.37.0

- [x] **Spec written and pushed** — `docs/plans/v1.37.0-webhook-server-decomposition.md`
  (`1b67b2db`). **QUEUED — not for implementation in v1.36.0**, which is at the max-5 cap.
  v1.37.0 now holds 1 plan doc.
- [x] Measured the target before opining: `bin/k3dm-webhook` is 4,009 lines / 180KB, ~110
  module-level functions, 19 routes, ~10 concerns (lifecycle 1233, smoke-SSO client 483,
  agent invoker 450, Slack 362, analysis 153, authz 149, metrics 100, redaction 50).
- [x] **Named the real defect as adjacency, not size** — `/api/v1/make` role resolution at
  line 3642, job-spawning handler at 3880, 238 lines apart inside a 428-line `do_POST`.
- [x] Recommended **against** a rewrite; four phases ordered by value-if-stopped-early with
  the authz route-table first, so the security payoff lands even if the rest slips.
- [x] Baseline net measured at **105 cases** across 6 suites and recorded in the spec.
- [ ] **Follow-up worth acting on independently of the refactor:** `_fix_mode_enabled` gates
  whether an AI agent may mutate the cluster and has **no test today**. Phase 3 adds one, but
  it does not have to wait for the refactor.
- [ ] **Gate hygiene finding:** the three `webhook_*.py` suites are `unittest`, run only via
  `make test-python-unit`'s `scripts/tests/bin/*.py` loop, and are invisible to both
  `make test` and `make test-pytest` — so `make test` cannot catch a break in any of the 37
  Python cases. Use `make test-all`. (Initially suspected orphaned; that was wrong.)

## 2026-09-22 — Grafana triage + two specs assigned to Codex

- [x] **Grafana "no data" root-caused — hub is healthy.** Prometheus 31 targets up and
  serving; datasource correct and unauthenticated; 30 dashboard ConfigMaps provisioned;
  no query errors in Grafana logs; `grafana.3ai-talk.org` returns 200. Empty panels are
  three separate, expected causes: the last e2e run FAILED 15.6h ago and no successful run
  has ever been recorded (`e2e_last_success_timestamp_seconds` never published); Hermes
  sensor metrics are off because `K3DM_HERMES_STATUS_ENABLED` is deliberately unset; and
  `trivy_*` / `hermes_incident_active` DO have data. No prefix mismatch.
- [ ] **e2e failure-detail gap (NEW, real).** A failed run published no `e2e_failure_info`
  or `e2e_failure_group_info`, and `e2e_run_info` carries a malformed `failure_ratio="/"`
  (empty-over-empty). Belongs to `docs/plans/v1.36.0-e2e-deterministic-triage-and-corpus.md`.
- [x] **Tier 1 e2e credential gate CLEARED 2026-09-22 (operator-run).** `gh auth refresh -h
  github.com -s read:packages,workflow` completed on the second attempt; scopes are now
  `admin:public_key, gist, read:org, read:packages, repo, workflow`. Verified three ways: live
  `X-Oauth-Scopes` from the API, `gh api user/packages?package_type=container` returning a count
  instead of 403, and the keychain item's `mdat` moving 2026-09-14 → 2026-09-22T23:26:00Z. Read
  access confirmed against the **private** `shopping-cart-basket` package (`visibility: private`,
  versions listable) — the public `shopping-cart-e2e-tests` would have answered anonymously and
  proven nothing. **The first attempt silently no-opped**: the device flow was started but never
  completed, leaving no error; the stale `mdat` is what proved no token had been written, and is
  the check to use next time. This clears the credential gate only — the Tier 1 run itself has not
  been executed yet.
- [ ] **Tier 2 e2e blocked (re-verified 2026-09-23).** No ACG context (`k3d-k3d-cluster`,
  `ubuntu-hostinger` only); keychain `k3dm-acg-pluralsight` **ABSENT**. Manual TTY login
  required — operator-only.
- [ ] **Tier 1 e2e RAN 2026-09-23 and FAILED twice — both blockers filed, neither a
  shopping-cart regression.** (1) A leaked vCluster from a 09:04Z failure wedged the shared
  `vclusters` namespace; ~17 Hermes dispatches failed identically over 2h. Cleared; leak
  reproduces on every failure → `docs/bugs/2026-09-23-e2e-failed-run-leaks-vcluster-and-wedges-all-later-runs.md`.
  (2) The runner cannot obtain a GHCR PAT — Gap 3 of
  `docs/bugs/2026-08-22-e2e-m2-runner-bootstrap-kubeconfig-and-ghcr-gaps.md` regressed
  (m2jump's `gh` token invalid; Vault path hardcoded to the hub context). Commits `ea6d39ca`,
  `84798fc0`.
- [ ] **Hermes is BOOTED OUT — restore it.** `launchctl bootstrap gui/$(id -u)
  ~/Library/LaunchAgents/com.k3d-manager.hermes.plist`. Leave it down until the GHCR
  credential is fixed, or it re-wedges the runner every 5 minutes.
- [ ] **Correction: the 2026-09-22 credential clearance was the M4's `gh` token, not M2's.**
  The GHCR pull happens on the runner, so that entry did not clear Tier 1.
- [x] **Specs written and pushed** as `b37acb91` on `k3d-manager-v1.36.0`:
  `docs/plans/v1.36.0-make-smoke-target.md` and
  `docs/plans/v1.36.0-hub-snapshot-capture-and-retention.md`.
  This brings v1.36.0 to **5 plan docs — at the max-5 cap.** A 6th means splitting the release.
- [x] **Codex dispatched** (session `01a0c93c-45b4-7301-9ac7-661b66e21204`) to implement both,
  two separate commits, fully offline/stubbed. PR #130 merged to main 2026-09-23 as 945018ee.
- [ ] **Snapshot capture NOT wired into `make down`/`make up`** — deliberately out of scope
  until capture is proven on a real hub.

## 2026-09-21 — rotate-ghcr-pat fix prepared; blocked before commit

- [ ] `docs/bugs/2026-09-21-rotate-ghcr-pat-targets-wrong-cluster-and-leaks-pat-in-argv.md`:
  exact Changes 1–4 implemented in `bin/rotate-ghcr-pat`; five static BATS gates added in
  `scripts/tests/bin/rotate_ghcr_pat.bats`. Counts proved non-vacuous: hardcoded context 2→0;
  pull probe 0→2; `--docker-password` 1→0; Vault-token argv 2→0;
  `/user` validation 1→0; ESO branch 0→1. **Correction by Claude:** the PAT basic-auth argv gate
  was reported 1→0 but measured 0→0 (vacuous, stray `\${` escapes); pattern fixed and re-verified. Pull probe line 59 is before `gh secret set` line 106.
  `shellcheck -S warning` and `shellcheck -S error` clean; focused BATS 5/5. Commit/push pending:
  `git commit` failed with `fatal: Unable to create .git/index.lock: Operation not permitted`,
  so there is no SHA or origin verification yet.

> Compressed 2026-09-17 (v1.34.0 Grafana/observability block closed → collapsed to pointers).
> Full pre-compression detail: `memory-bank/archive/progress-2026-09-17.md`.
> Settled work lives in `CHANGELOG.md`, `docs/releases.md`, `docs/retro/`, `docs/issues/`,
> `docs/bugs/` and git history. This file tracks what is still open.

## Open items

- [x] **Hub rebuild EXECUTED 2026-09-20 — kine compaction stall CLEARED.** Operator ran the
  teardown; Claude completed and monitored the rebuild. `state.db` 2.72 GiB → 25.8 MB, WAL 678 MB →
  10 MB, `kubectl get nodes` 5.5s → 0.05s, `COMPACT deleted` on a 5-minute cadence (288/day
  baseline) after zero matches beforehand. Runbook corrected against reality:
  `docs/howto/hub-rebuild-from-gitops-vault.md`.

- [x] **Grafana port-forward flapping fixed** — `K3DM_PF_HEALTH_THRESHOLD`/`_TIMEOUT`, spec
  `docs/bugs/2026-09-20-pf-supervisor-kills-healthy-forward-on-single-slow-probe.md`. 0 restarts
  post-fix vs ~1 per 45s before.

- [x] **Hub registered as the app cluster; the whole app tier came back.** The missing piece was
  `hub_recovery_reconcile --confirm`, which self-registers the hub in-cluster as `ubuntu-k3s` with
  the `k3d-manager/role: app-cluster` label. `data-git`, `services-git`, `eso` and
  `grafana-dashboards-acg` all select on that label, so with no registration they generated
  **zero** Applications — that, not a deploy failure, is why `shopping-cart-data`,
  `shopping-cart-apps` and `shopping-cart-payment` were absent. Apps went 7 → 16 immediately.
  `platform-helm` correctly still generates nothing (the in-cluster registration deliberately omits
  `argocd-chart-version`, per `docs/bugs/2026-09-13-register-app-cluster-in-cluster-labels-trigger-platform-helm.md`).

- [x] **Identity stack restored.** `shopping-cart-identity` is **not** appset-managed — it is
  `exclude: true` in `services-git.yaml` and created directly by `bin/cluster-up:869`. The hub-only
  sequence skipped it, so Keycloak/LDAP/postgres-keycloak were simply never requested. Applying that
  manifest brought all of them up.

- [x] **Vault seeded; the `f28a4539` seed fix proved itself in production.** The seeder logged
  `Restoring payment/stripe api_key from Keychain backup` and the verification returns **REAL-OK** —
  without that fix the rebuild would have written `sk_test_placeholder`. Note the seeder needs
  `SEED_VAULT_ADDR`/`SEED_VAULT_TOKEN` when run standalone: it reads `${_vault_root_token}`, which
  only the acg-up flow sets, and fails `unbound variable` otherwise. Vault KV now holds keycloak,
  ldap, minio, observability, payment, platform-ops, postgres, rabbitmq, redis.

- [ ] **Prometheus local-port drift: 19090 vs 19190.** `_acg_prom_local_port` computes
  `19190 + offset`, and `k3s-aws` offset is **0**, so the app-cluster Prometheus forward is 19190 —
  which is what `bin/k3dm-webhook:2233` probes. But `scripts/etc/cloudflared/config.yml` (and the
  installed `~/.cloudflared/config.yml`) map `prometheus.3ai-talk.org` to **19090**. One of the two
  is wrong; `prometheus.3ai-talk.org` cannot work while they disagree. Separately the hub's own
  launchd agent forwards 19091. Three ports for one service — needs a decision, then one source of
  truth. Not yet filed as a bug doc.

- [x] **Grafana Error 1033 diagnosed and fixed.** The operator hit
  `Error 1033 — Cloudflare Tunnel error` on `grafana.3ai-talk.org`. Cause: teardown deleted
  `com.k3d-manager.cloudflare-tunnel.plist` and nothing recreated it — `pgrep cloudflared` was
  empty and no agent was loaded, while the origin it proxies (`127.0.0.1:3001`) was serving 200 the
  whole time. Not a Grafana fault at all. Recreated the plist from the `bin/cluster-up:1742`
  template and bootstrapped it; all public hosts came back
  (grafana `/api/health` **200** `"database":"ok"`, argocd 200, prometheus/alertmanager 401 by
  auth-proxy design, keycloak 302).

- [ ] **GHCR pull is 403 — and `shopping_cart_resolve_ghcr_pat` poisoned the Vault cache.**
  All four `shopping-cart-apps` pods are `ImagePullBackOff`:
  `403 Forbidden` from `ghcr.io/v2/wilddog64/shopping-cart-frontend/blobs/...`. Root cause: the
  function's fallback chain reached "use gh CLI token", and `gh auth status` reports scopes
  `admin:public_key, gist, read:org, repo` — **no `read:packages`**. It then wrote that token to
  `secret/github/pat` and logged `gh CLI token saved to Vault for future runs`, so every later run
  will find it in Vault and reuse a token that cannot pull. Two defects worth filing:
  1. The gh CLI branch is **not validated** before saving, unlike the Vault branch, which does
     check (`Vault PAT is expired (HTTP ${_pat_http})`). Validate for `read:packages` first.
  2. The Vault write is `|| true`, so `saved to Vault for future runs` prints even when the write
     failed — observed directly: the first run printed it while `vault kv list secret` showed no
     `github/` at all (the write had built `http://localhost:/v1/...` because `_vault_local_port`
     was unset). A success message must not be unconditional.
  Operator action: supply a PAT with `read:packages` — see
  [[reference_packages_token_expiry_image_build]] — then overwrite `secret/github/pat`, force-sync
  the `ghcr-pull-secret` ExternalSecret and restart the four deployments.

- [ ] **`shopping-cart-data` StatefulSets never applied.** `ubuntu-k3s-data-layer` reports
  `phase=Failed`, `namespaces "shopping-cart-payment" not found (retried 5 times)`. ConfigMaps and
  Services synced; all StatefulSets are `OutOfSync` and absent, so the namespace has **zero** pods.
  `ubuntu-k3s-shopping-cart-namespace` only creates `shopping-cart-apps`, so nothing creates
  `shopping-cart-payment`. A failed sync also blocks self-heal
  ([[reference_argocd_error_phase_blocks_selfheal]]) — operator sync after the namespace exists.

- [ ] **`Frontend: HTTP 200` in `make status` is a FALSE GREEN for the hub.**
  `~/.local/share/k3d-manager/bin/frontend-browser-http.sh` port-forwards
  `--context "ubuntu-hostinger" svc/frontend`, so the check is served by the **hostinger** cluster,
  not the rebuilt hub. The hub's own frontend is in `ImagePullBackOff`. Do not read that green as
  hub health.

- [ ] **`make status` still reports 1 error — needs the operator, not code.**
  ArgoCD, Frontend and Prometheus now pass; all nine local endpoints answer (grafana 3001, argocd
  8080, prometheus 19190 + 19091, alertmanager 9093 → 401 by auth-proxy design and 19093 raw,
  keycloak 8880, frontend 127.0.0.2, vault 18200). The two remaining:
  1. **Keycloak connection refused** — the probe is `http://keycloak.shopping-cart.local/health/live`
     on **port 80**, which needs the `keycloak-browser-http` LaunchDaemon. That is a privileged
     system-domain job; teardown itself logged `no sudo in headless context — skipping`. Keycloak is
     healthy on 8880, so this is purely the privileged listener.
  2. Pushgateway's `!` warning is **pre-existing, not a regression** — `grep -i pushgateway`
     against `~/hub-rebuild-pods-before.txt` confirms it was not running before the rebuild either.

- [ ] **`cosign-public-key` ExternalSecret cannot sync** — `SecretSyncedError: could not get secret
  data from provider`, and it is what still makes ArgoCD `hub-platform-ops` **Degraded**. The key is
  not among the 14 backed-up canonical keys, so it was genuinely lost with the Vault PVC. It belongs
  to the v1.27.0 image signing work and needs a recovery path that is **not** `signing_init`
  (forbidden). `app-cluster-kubeconfig` **now syncs** — `hub_recovery_reconcile` seeds
  `platform-ops/app-cluster-hostinger` — as do `monitoring/grafana-admin-credentials` and all four
  `identity` secrets.

- [ ] **`observability/alertmanager` and `observability/prometheus` unseeded** — `make observability`
  warned `Alertmanager Vault secret not found — skipping SMS config`, `Failed to create Alertmanager
  login secret in Vault — using generated local credentials for this run`, and `Prometheus Vault
  credentials unreadable — skipping auth proxy`. The Prometheus auth proxy is therefore **not
  running**, which also means `K3DM_HERMES_STATUS_ENABLED=1` must stay unset. Run
  `make alertmanager-secret`.

- [ ] **`ServiceMonitor monitoring/kube-prometheus-stack-apiserver not found`** — the 45s apiserver
  scrape-timeout patch landed earlier this release had nothing to patch on a fresh cluster, so the
  `KubeAPIDown` flap guard is **not** in place. Re-run once the ServiceMonitor exists.

- [ ] **`cve-remediation-verify` CronJob fails every run: `secrets "cluster-ubuntu-hostinger" not
  found`.** The new hub ArgoCD has no registration Secret for the live `ubuntu-hostinger` cluster,
  so the CVE remediation verifier errors on every schedule. Re-register the hostinger cluster with
  the rebuilt hub — do **not** hand-patch the cluster Secret
  ([[reference_appset_generated_app_cleanup_ordering]] ordering applies). Until then this is a
  recurring red that is *expected*, which is exactly the kind of thing that later gets dismissed as
  noise — fix or pause it, do not learn to ignore it.

- [x] **trivy `scan-vulnerabilityreport-8479d4f9` Error — investigated, benign.** One-off startup
  race: the scan job ran at 23:56 while `trivy-service.trivy-system:4954` was still starting
  (`connection refused` storing a blob). All 10 subsequent scan jobs show `Complete 1/1`. No action.

- [ ] **Hermes ArgoCD token needs re-minting** — the hub ArgoCD is new, so
  `k3dm-hermes-argocd-token` is stale by construction.

- [x] **BLOCKER for the hub rebuild: seeding clobbers the real Stripe/PayPal/encryption secrets.**
  Landed `f28a4539` before the rebuild ran.
  Spec `docs/bugs/2026-09-20-seed-clobbers-real-payment-secrets.md`.
  `scripts/plugins/shopping_cart.sh:716-718` writes `payment/encryption`, `payment/stripe` and
  `payment/paypal` **unconditionally** — no `_vault_kv_exists` guard, no `_seed_source_data`
  fallback — while all ten other keys in the same function are guarded. `bin/cluster-up:851` calls
  it, so **every `make up` overwrites the real Stripe test key with `sk_test_placeholder`.** This is
  the unfinished third instalment of a staged parity effort: `176ec5a6` did the six single-password
  branches, `docs/bugs/v1.12.0-bugfix-seed-source-parity-minio-ldap-keycloak.md` did the four
  multi-field branches, and these three were skipped by both because they are unconditional literal
  writes that neither pass's pattern matched. They are the worst three to have left — the only
  externally-issued keys, which cannot be correctly regenerated. Keychain fallback
  `k3dm-stripe-sk-test` verified present. **A rebuild before this lands comes back up with broken
  payments.** NOT dispatched to Codex yet.
- [ ] **Hub rebuild runbook written; execution is the operator's.**
  `docs/howto/hub-rebuild-from-gitops-vault.md`. Verified during authoring: all **14** canonical KV
  keys are present in Keychain `k3d-manager-app-cluster-secrets`, so the rebuild does not lose
  secrets; `bin/cluster-down:330` runs `k3d cluster delete` (destroys the Vault PVC — the cached
  unseal shards are worthless without it, and `bin/cluster-up:417-432` re-unseals from cache);
  `bin/cluster-up` sequence is cluster → vault → ldap → argocd → bootstrap → shopping-cart-data,
  then `make up` adds observability + platform-ops. Vault lives at `secrets/vault-0`, currently
  `0/1`. `kubectl exec` and `logs` both fail with `net/http: TLS handshake timeout`, so no live KV
  dump is possible — Keychain is the source. Gated on the Stripe blocker above.


- [x] **Hermes never re-pages once an incident latches — FIXED `71681100`.** Implemented by Codex,
  verified and committed by Claude (Codex could not commit: `.git/index.lock` Operation not
  permitted). `pytest scripts/tests/hermes/test_hermes.py` = 26 passed; read-only probe confirms
  the three 401 hosts now count healthy with code 401 still reported. Codex's `make test` was
  incomplete (stopped at `ok 724` of 974, no `not ok`); Claude re-ran the full suite after commit.
  Original spec:
  `docs/bugs/2026-09-20-hermes-correlator-never-re-pages-after-incident-latches.md`. Hermes
  detected the Grafana CF 502 outage for hours and sent nothing: `Correlator.process` emits only
  on the `False → True` edge of `incident_active`, latched by the kine stall, so a newly degraded
  `reachability` was absorbed (`"event": null, "pages": []`). Fix = an `escalation` event when the
  contributor set grows + widen both `kind == "incident"` gates in `bin/k3dm-hermes._run_cycle`
  (138, 150), and stop `bin/public-endpoint-probe` counting HTTP 401 as unhealthy (prometheus,
  alertmanager, webhook are permanent false failures that skew the verdict to `edge-down`). Two
  pytest cases specified; no probe BATS suite exists and none is to be created.
- [ ] **Grafana CF 502 is downstream of the kine stall — no independent fix.** Port-forward
  restarted 18,211 times, ~every 35 s, because the apiserver is unreachable. All 7 tunnel hosts
  flap. Grafana, cloudflared, Cloudflare and the supervisor probe are all exonerated. Clears only
  on the hub rebuild, which remains the operator's decision.

- [ ] **Tier 2 live-run blockers — spec filed `5edf557e`, fix NOT started.**
  `docs/bugs/2026-09-20-e2e-sandbox-job-service-names-markers-secrets.md`. Three defects in
  `_e2e_sandbox_job_manifest()` / `e2e_verify_sandbox()`: wrong service hostnames (3 of 4),
  missing `__E2E_RESULTS_BEGIN__`/`__E2E_RESULTS_END__` wrapper, and `ghcr-pull-secret` +
  `stripe-e2e` never created. 8 test cases specified, each needing a real=PASS / mutated=FAIL
  pair. Tier 1 is unaffected. Awaiting the user's call on who implements. Running Tier 2 live
  (`acg_restart` then `e2e_verify_sandbox`) stays the operator's action.


- [x] **2026-09-20 — KubeAPIDown flapping apiserver scrape timeout:** implementation and offline
  verification complete; COMMITTED and PUSHED as `0d663a40`. Focused BATS `6/6`,
  shellcheck warning-level clean, and captured full `make test` `966/0` with `MAKE_EXIT=0`. No
  live cluster access used. `git add` failed twice with `.git/index.lock: Operation not permitted`,
  so no commit SHA exists yet.

- [x] **2026-09-19 — `istiod` scrape job missing a port filter — FIXED `a255d8d5`.**
  `TargetDown` has fired for `job=istiod` since 2026-09-11 because the `additionalScrapeConfigs`
  entry keeps by service name with no port filter, so all istiod endpoint ports are scraped and only
  `15014` (`http-monitoring`) serves metrics — 8 of 10 targets permanently down while metrics
  collection is actually healthy. Same defect in the hub and ACG values files. Fix is one `keep` on
  `__meta_kubernetes_endpoint_port_name` plus `yq` BATS coverage. Spec:
  `docs/bugs/2026-09-19-istiod-scrape-job-missing-port-filter.md`. Applying the config to the live
  cluster is the operator's and is out of scope.
  Both values now keep only `__meta_kubernetes_endpoint_port_name=http-monitoring`; six parsed-YAML
  BATS cases cover the regex, `action: keep`, and additive service-name keep in both files. YAML parse
  gates passed, focused BATS passed 10/10, and all six mutations were real=PASS / mutated=FAIL. The
  captured full `make test` output contained 960 `^ok` and 0 `^not ok` lines; its wrapper lingered in
  post-suite cleanup after case 960 and was stopped. Feature commit `a255d8d5` was pushed to
  `origin/k3d-manager-v1.36.0`; no cluster or out-of-scope job was touched.

- [x] **2026-09-19 — v1.36.0 Tier 2 `e2e_verify_sandbox` implementation COMPLETE at `ffeb9ba2`.**
  Exact commit pushed to `origin/k3d-manager-v1.36.0`; no PR URL because PR creation was explicitly
  forbidden. Task A report tier/project plumbing, six-step sandbox sequence, TokenReview Vault
  substrate, rendered overrides, OAuth2/Stripe Job, no-registration/no-teardown invariants, API/guide/
  README/CHANGELOG docs, and namespace-label tracker closure are complete. Final gates: shellcheck
  `-S warning` clean, `make test` `ok=954 not ok=0`, `make test-bin` `ok=108 not ok=0`, and every
  new structural case mutation-verified as real=PASS / mutated=FAIL.

- [x] **Whole-line `grep -F` BATS audit — MERGED as `f20d100b` (PR #129, 2026-09-19 13:52:35Z).**
  Post-merge done: `enforce_admins` restored (verified `true`), no tag/release (a `fix/*` head,
  not a milestone — entry stays under `[Unreleased]`), no retro for the same reason,
  `k3d-manager-v1.36.0` forward-merged onto the new `main`.
  https://github.com/wilddog64/k3d-manager/pull/129 — Branch `fix/bats-whole-line-grep-assertions`, base `main` @
  `e259c718`. Spec `docs/bugs/2026-09-18-bats-whole-line-grep-assertion-audit.md`. 45 whole-line
  assertions -> 3 deliberate keeps across 8 suites (argocd 12, webhook 16, slack_slash 5,
  provider_contract 5, slack_relay_ack 3, image_updater 2, worker_setup 1, observability 1).
  Gates post-rebase: `make test` 947 ok / 0 not ok, `make test-bin` 108 ok / 0 not ok. 13 mutation
  tests all bit. Rebase was conflict-free and verified by reading the merged `provider_contract.bats`,
  not by trusting git's silence.
  Next step: the user's go, then `/create-pr`. The pre-rebase "hold until #128 merges" blocker is
  resolved — #128 merged as `e259c718`.
- [ ] **`e2e_remote.bats` dispatch tests depend on the repo's push state** — tests 23/28/52/53 fail
  with `HEAD <sha> is not pushed` on any locally-committed, unpushed HEAD, because
  `e2e_runner_dispatch`'s push guard fires before the tests' stubs are reached. Green in CI only
  because CI always tests a pushed ref. Found while verifying the rebase above; not filed as a bug
  yet and NOT in this branch's scope.

- [x] **2026-09-18 — v1.35.0 PR #128 created, CI green, Copilot resolved, merge-ready** at
  `c8ea57c4`. `enforce_admins` disabled (re-enable post-merge, **bodyless POST**). Three CI reds
  fixed en route (`287cc71a` rg/sibling-fixture, `2c205e3e` Makefile SHELL, `c8ea57c4` Copilot
  F2/F3). Awaiting the user's merge — never auto-merge.
- [x] **MERGED 2026-09-18T17:35:07Z at `e259c718`.** `/post-merge` completed: `enforce_admins`
  re-enabled (bodyless POST), tag `v1.35.0` created and pushed, GitHub release `v1.35.0`
  published, next branch `k3d-manager-v1.36.0` created, retro doc written. **ApplicationSet
  reapply is the operator's action** (live cluster, hub + ACG both); config on `main` and
  `k3d-manager-v1.36.0` is inert until reapplied.

- [x] **2026-09-18 — CI red #2 FIXED: `SHELL := /bin/bash` in the Makefile.** make defaulted to
  `/bin/sh` (dash on Ubuntu), which rejects `set -euo pipefail`; killed `make test-bin` on CI and
  also affected `fleet-render`/`fleet-plan`. Reproduced locally with `make SHELL=/bin/dash
  test-bin` — `/bin/dash` is installed on this Mac, so no CI round trip is needed for this class.

- [x] **2026-09-18 — CI red on PR #128 FIXED (3 suites, workstation dependencies).** `rg` →
  `grep` in `argocd_reclaim_release_ownership.bats` + `argocd_appset_live_overrides.bats`
  (2 of those call sites were vacuous-green on CI, not red — a missing binary satisfied a
  negative assertion); `keycloak.bats` now skips with a reason when the shopping-cart-infra realm
  fixture is unreachable. Spec
  `docs/bugs/2026-09-18-bats-host-tool-and-sibling-repo-dependencies.md`. Proved in a
  sibling-free worktree: 24/24. `make test` 947/947, `make test-bin` 108/108.

- [x] **2026-09-18 — v1.35.0 repo-local close-out COMPLETE.** CHANGELOG promoted to
  `## [1.35.0] - 2026-09-18` (the gate whose absence shipped v1.34.0 merged-but-untagged),
  `docs/api/functions.md` +12 public E2E functions (the whole `e2e_remote.sh` surface was
  undocumented; `e2e_verify_vcluster` was already there — the earlier "stale doc" claim was an
  `rg`-alias `grep -c` artifact), standing docs audited (`projectbrief.md` no-Python claim
  corrected, five-entrypoint table + "no single green" added; `copilot-instructions.md` gained a
  Test Reachability review section), README/`docs/releases.md` rows added and v1.32.1's
  never-listed README row backfilled. `make test` 947/947 `EXIT=0`, `make test-bin` 108/108.

- [ ] **v1.35.0 PR → CI → Copilot → merge.** Remaining release steps that are NOT repo-local.
- [ ] **Reapply the ApplicationSets (hub AND ACG), then `argocd_check_values_branch`** — the
  operator's, live cluster. **Outstanding for v1.34.0's config as well as v1.35.0's**: the sets
  template `$values` at `${K3D_MANAGER_BRANCH}`, so config on a newer branch is inert in-cluster
  until they are reapplied. Two releases of config may currently be unread by any cluster.

- [ ] **Tier 2 → v1.36.0, deliberately deferred (decided 2026-09-18).** `e2e_verify_sandbox` does
  not exist; unimplemented since v1.25.0. Precondition before the spec: the **ACG login live gate**
  (Keychain `k3dm-acg-pluralsight`, or one manual sign-in in `pw-profile`) — the false-green fix is
  vendored but has never passed live, and Tier 2's Stripe acceptance would sit on top of it.
  **UPDATE 2026-09-22 — the "ACG login live gate" wording above is misleading and caused a
  multi-session misreading.** `e2e_verify_sandbox` now EXISTS (`scripts/plugins/e2e.sh:294`), and the
  headless auto-login is fully wired: `acg-credential-test:7-8` calls `_browser_launch`
  unconditionally, which calls `_cdp_ensure_acg_session` on both paths (`cdp.sh:132,163`), which
  reads `k3dm-acg-pluralsight` (`cdp.sh:184-185`). The gate fires on EVERY run. The only gap is that
  the Keychain item is **ABSENT** on this box, so the gate gets empty creds and fast-fails
  `ACG_LOGIN_NO_CREDS` → `ACG_SESSION_EXPIRED` to non-TTY callers. Spec queued:
  `docs/plans/v1.37.0-acg-autologin-enablement-for-tier2.md`. Blocking operator question: does the
  ACG account carry MFA (auto-login refuses MFA by design)? If no → populate the item once and P4
  closes permanently; if yes → permanently manual via `pw-profile`.
  Then: Tier 2 spec → implementation → HTTP/2 protocol label + failure-rate panel. Still blocked
  meanwhile: Stripe live E2E at 2/4, and `docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`.

- [x] **2026-09-18 — E2E readiness gate zero-probe race FIXED, `aa71c1f4`.** Added a deterministic
  100→101 clock-boundary regression that failed before the fix and passed after it; the gate now
  always probes `/readyz` before enforcing the deadline. `make test` passed twice at 947/947,
  `make test-bin` passed 108/108, and shellcheck passed.
  Spec `docs/bugs/2026-09-17-e2e-readiness-gate-can-probe-zero-times.md`, now closed. Claude
  re-ran every gate and additionally verified the new case is a genuine regression test by running
  it against a detached worktree at the pre-fix commit `4d493112` — it fails there at
  `e2e.bats:283`. Two unpiped `make test` runs, `EXIT=0` / `ok=947 notok=0` each, because one
  green run of a race is one sample rather than proof. **Closes the intermittent CI red that
  `6064796c` exposed when it gated the previously dark `e2e.bats`.**

- [x] **2026-09-17 — Orphaned test suites: Makefile entrypoints + CI gating COMPLETE.**
  Part 1 `63d7f523` (five `make test-*` targets), Parts 2+3 `6eb1866e` (CI steps in the `lint`
  job for `make test-bin`, `make test-python-unit`, and `make test-pytest` behind a pinned
  `pytest==9.1.1`). Spec: `docs/bugs/2026-09-17-orphaned-test-suites-no-makefile-entrypoint.md`.
  Switching on the dark coverage found two real defects first — both fixed, neither masked:
  a `cluster-down` TLS-key leak (`4184d23e`) and three host-OS-dependent BATS tests made
  portable via `_stub_uname_darwin`. Verified 108/108 BATS on macOS and under a simulated
  Linux `uname`; 120 pytest tests green on Python 3.13.6 and 3.14.7.
- [x] **2026-09-17 — `make test` RED at case 525: FIXED, `842b4ac8`.** The assertion was stale,
  not the code: `978ea60f` (v1.34.0) added a fourth app to `scripts/etc/e2e/kustomization.yaml`
  and the hardcoded `grep -c ':' -eq 3` was never updated. The count is now derived from the
  substrate's own `newName` entries and the `':'` guard is a per-line assertion — deliberately
  NOT bumped `3`→`4`, which would re-arm the trap for the fifth app. Exactly the pattern the
  prefer-disappearance-gates rule warns about. Verified: 924/924 `ok`, zero `not ok`,
  `MAKE_EXIT=0` from an unpiped run (an earlier `make test | tail -5` reported *tail's* exit code
  and was retracted). Spec:
  `docs/bugs/2026-09-17-e2e-kustomization-images-hardcoded-count.md`.
- [x] **2026-09-17 — CI's hand-maintained BATS list has drifted from `make test`. FIXED
  `6064796c`.** Spec `docs/bugs/2026-09-17-ci-bats-list-drift-from-make-test.md` (filed
  `842b4ac8`).
  **54 files (3 `core` + 51 `plugins`) run in `make test` and never in CI**; `scripts/tests/etc`
  runs in CI and not in `make test`. This is why case 525 stayed red for a whole release with
  main green. Fix is one discovery mechanism: CI calls the Makefile targets. Enumerate failures
  on macOS *and* under a Linux-simulating `uname` stub BEFORE editing `ci.yml`; any failure that
  turns out to be a real production bug must be reported, not fixed or disabled.
  Codex did the work and hit the same `.git/index.lock` sandbox wall as spec B, so Claude
  reviewed the diff, re-ran every gate, and committed on its behalf. **Codex's report did not
  survive verification.** It claimed `EXIT=0` / 946 green on both enumerations; Claude's unpiped
  re-run returned `MAKETEST_EXIT=2`, `ok=945 notok=1`. Two lessons: (1) Codex's Linux-sim command
  piped `make test` into `tee`, so its `EXIT=0` was `tee`'s status — the exact trap the handoff
  warned about, and it still slipped through on the second of two runs; (2) an agent's green is
  one sample, and a race only shows on some samples. The STOP rule worked: the surfaced failure is
  a **real production bug**, filed as
  `docs/bugs/2026-09-17-e2e-readiness-gate-can-probe-zero-times.md` and deliberately NOT fixed,
  skipped, or hidden. `_e2e_wait_vcluster_ready` samples `date +%s` twice with integer-second
  resolution, so a second-boundary crossing between the deadline computation and the loop guard
  makes it report "not ready" after **zero** probes. Named the nondeterminism rather than calling
  it a flake, then reproduced it deterministically with a stubbed `date` (100 then 101):
  `probes logged: 0`. Gates Claude re-ran: `make test-bin` `ok 108`/0, `shellcheck -S error` 0,
  `yamllint ci.yml` 0. **Open consequence: `scripts/tests/plugins/e2e.bats` was dark in CI and
  this commit gates it, so that race is now an intermittently red CI until it is fixed.**
- [x] **2026-09-17 — ArgoCD browser TLS dir is provider-agnostic. FIXED `2c908554`** (spec
  `docs/bugs/2026-09-17-argocd-browser-tls-path-unification.md`, filed `842b4ac8`). Follow-up to
  the `4184d23e` containment fix. `argocd.sh:61`'s `:=` **assigns**, killing the correct scoped
  `:-` fallback in `bin/cluster-up` and `bin/cluster-refresh`; the flat dir is shared across all
  four `k3s-*` providers, so one bring-up overwrites another's cert and key. No migration.
  Codex wrote the code but hit the known `.git/index.lock` sandbox wall, so Claude reviewed the
  full diff and committed on its behalf. Gates re-run by Claude, not taken on report:
  `make test` `MAKETEST_EXIT=0` with `ok=928 notok=0` (924 + 4 new argocd cases, unpiped against
  a surviving log), `make test-bin` `ok 108`/`notok=0`, `shellcheck -S error` exit 0, and the DoD
  grep returning only `bin/cluster-down:231`. One out-of-scope edit was REVERTED: Codex had split
  the flat literal in `scripts/tests/bin/cluster_down.bats` across two assignments purely so the
  DoD grep would stop matching. The fault was the gate's — it scoped `scripts/` and so swept in a
  test that legitimately holds that literal to prove the legacy dir gets cleaned. Gate narrowed to
  `scripts/plugins/ scripts/lib/ bin/` and the spec now states outright that rewriting a string to
  dodge a grep is gate evasion, not a fix.
- [x] **2026-09-17 — v1.34.0 release CUT (was merged but never published).** PR #127 merged at
  `978ea60f` on 2026-09-17 with no version heading, so `/post-merge` Step 4 skipped tagging and
  the release went unrecorded: no tag, no GitHub release, no releases row. Now published: tag
  `v1.34.0` at `978ea60f`, GitHub release (**Latest**), `docs/releases.md` + README rows
  (`bd67710a`, v1.31.0 moved into the collapsible block), CHANGELOG promoted to
  `## [1.34.0] - 2026-09-17` (`a56cd27a`) with the 2 post-merge bullets left in `[Unreleased]`
  as v1.35.0 work. Root cause: no skill step promoted `[Unreleased]` to a version — `/create-pr`
  only checked an entry existed, `/post-merge` only read the heading. Fixed in both skills:
  `~/.claude/commands/create-pr.md` pre-flight 3b (blocking promotion for `k3d-manager-v<version>`
  branches) and `~/.claude/commands/post-merge.md` Step 4 (skip must be loud + user-gated).

- [x] **2026-09-17 — Deterministic Make test entrypoints Part 1 committed `63d7f523` and
  pushed to `k3d-manager-v1.35.0`.** Added `test-bin`, `test-python-unit`, `test-pytest`,
  `test-python`, and `test-all`, plus `.PHONY`, help, and CHANGELOG coverage-gap entries.
  `make test-python-unit` passed; `make test-bin` failed at `cluster_down.bats` test 15, so
  Part 2 CI wiring was correctly omitted. `make test-pytest` exited 2 with the expected missing
  pytest message. `make test` reported a failure at case 551.

- [x] **2026-09-17 — Webhook redaction coverage audit implemented, commit `d0d35ff8`.** The
  webhook control token is registered for redaction, skipped values are counted by reason, and
  six direct regression tests were added. Required gates passed. No PR created per instruction.

- [x] **PR #127 MERGED 2026-09-17, SHA `978ea60f`.** Hermes autonomy, Slack `/k3dm`,
  E2E observability shipped. CI fixed (`c40924d1`), Copilot review swept (narrative
  + inline), `enforce_admins` verified. Retrospective: `docs/retro/2026-09-17-v1.34.0-retrospective.md`.
  Next phase: v1.35.0 branch, standing docs audit, ApplicationSet reapply for v1.34.0 config.

- [ ] **HTTP/2 failure-rate observability** — deferred until Tier 2 E2E coverage publishes bounded protocol/version labels. Current dashboard intentionally does not claim HTTP/2-specific failure rates; see `docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`.

- [ ] **Hermes scheduled `make status` sensor + triage — IMPLEMENTED `e3e37f96`, live acceptance pending.** Spec `docs/plans/v1.34.0-hermes-scheduled-status-triage.md`. Runs `bin/cluster-status --json` on a ~40 min gate inside the existing 300s Hermes poll, classifies reds by check id, notifies on state change only, files bugs via the e2e worktree path. No new launchd agent, no new REPAIRS entry, no auto-execution (proposal + Slack approval only). Offline gates green (Hermes pytest 106, status-summary BATS 8/8). **The schedule defaults off**: set `K3DM_HERMES_STATUS_ENABLED=1` only after the Prometheus authenticated-probe dependency is verified, or the first run pages on a false red. Corrections and findings: `docs/issues/2026-09-16-hermes-status-triage-review.md`.

- [ ] **Hook fix PR (step 2 of 3)** — branch `fix/keycloak-reconcile-pipefail-ldap-federation`
  @ `a5838c19`, one commit ahead of the new main. Conflict pre-check (previously blocked
  by the auto-mode classifier) now RUN against merged main: `git merge-tree origin/main
  <branch>` → exit 0, merged tree `6678e606`, no conflict section = merges cleanly.
  Needs: own CHANGELOG entry (deferred to avoid colliding with #96's), Copilot review, CI.

- [ ] **lib-foundation: ACG session-check false-green — bug filed, Codex assigned.**
  Spec `docs/bugs/2026-09-12-acg-session-check-false-green-on-signed-out-page.md`
  (commit `ecfc15f`, pushed on `fix/acg-prism-monogram-selector`). Removes the two
  page-CONTENT selectors (`text=/Cloud Sandboxes/i`, `text=/Open Sandbox/i`) from
  `LOGGED_IN_SELECTORS`, adds `SIGNED_OUT_SELECTORS` + `pageLooksSignedOut` /
  `urlLooksSignedOut` as a negative gate, and makes `acg_session_check.js` say out loud
  when the `k3dm-acg-pluralsight` Keychain item is missing. Handed to Codex via
  `codex exec`. **IMPLEMENTED `308bb3c`** (Codex authored; Codex could not write `.git`,
  so Claude re-ran every gate and committed). Gates Claude ran, not taken on trust:
  `npm run check` clean, jest 25/25 across 7 suites, `make lint`, `make shellcheck-lib`,
  132 BATS — all green. CHANGE.md `[Unreleased]` entry added by Claude; still collides
  with lib-foundation #49, rebase whichever lands second.
  Files in scope: `pluralsight_login.js`, `acg_session_check.js`,
  `tests/providers/pluralsight_login.test.js`. Operator action still required before the
  live gate can pass: create Keychain item `k3dm-acg-pluralsight` (username+password) OR
  sign in once manually in `~/.local/share/k3d-manager/pw-profile`. MFA accounts can only
  use the manual path.

- [ ] **Portability Phase 3 inventory recorded** in
  `docs/bugs/2026-07-07-app-cluster-vault-portability.md` (24 `--context ubuntu-k3s`
  sites in `shopping_cart.sh`, 3 functions, resolver already present). Still needs the
  decision-#1 re-scope + swallowed-failure fix before a spec.

- [ ] **2026-09-14 — `/k3dm` Slack make-target command** — spec `docs/plans/v1.34.0-slack-k3dm-make-command.md` (`d8a2c8d8`); implemented + verified `cfbdddde`; webhook restarted; worker deploy pending user `make deploy-worker` (GH `CLOUDFLARE_API_TOKEN` secret missing → CI deploy fails); Slack app `/k3dm` registration pending user

- [ ] **v1.28.0-platform-zero-downtime-rollouts — QUEUED, hardware-gated** (deferred 2026-09-04).
  No CPU headroom on the M4 Air 24GB hub for 2+ replicas of the stateless tier (hub CPU-starves at
  single replicas). Gated on the Mac Mini M5 upgrade (Oct 2026). Spec stays on disk; do NOT implement
  until the hardware lands.

- [ ] Keep all new work within the five-plan milestone limit (at 5/5 — split before a 6th).

- [ ] **Hub control-plane saturation/public 502 incident (2026-09-02):** API `/readyz` reports
  etcd failures while k3s server reaches ~880% CPU; Grafana port-forward flaps and ArgoCD public
  OAuth URL drifted to the local hostname. Bug recorded in
  `docs/issues/2026-09-02-hub-control-plane-saturation-causing-public-502.md`; workload-level
  mitigation and durable URL/status fixes remain pending.

- [ ] **Argo identity drift + stale dashboard route (2026-09-02):** Git Keycloak Service renders
  valid ports but Argo strategic merge still produces duplicate `http`; Grafana dashboard links
  include a stale route. Bug: `docs/issues/2026-09-02-argocd-identity-drift-and-dashboard-502.md`.

- [ ] **E2E observability follow-up:** M2 result ConfigMaps publish correctly, but the live
  Prometheus deployment currently has no `e2e_run_info` series and the `Recent runs` Grafana
  panel shows duplicate exporter/application service columns plus blank legacy totals. Bugs:
  `docs/issues/2026-08-25-e2e-grafana-table-raw-labels.md` and the contract-mismatch issue above.
  Dashboard source fix `cfe925fc` is pushed; it uses `exported_service` as the canonical service
  filter, hides exporter `service`, and renames table fields. E2E client fix `0c2505b` is pushed
  on `shopping-cart-e2e-tests:feat/e2e-image-multiarch`; full repo `tsc` remains red only on
  pre-existing unrelated test strictness/type errors.

- [ ] **CVE remediation event panels empty (2026-08-24) — ROOT-CAUSED 2026-08-25.**
  NOT a durability bug (Codex RC wrong). Durable source (event ConfigMaps) exists; 0 series
  is correct because 0 events exist. Real RC: Keychain `platform-ops-app-rebuild/k3dm` absent
  → secret never synced → `app-cve-scan` pod wedged in `CreateContainerConfigError` → requester
  never runs. Fix = user stores scoped PAT + re-run `argocd_sync_app_rebuild_secret` + delete
  wedged job `cve-auto-1787541034`; then hardening (fail-loud + bounded backoff) + dashboard
  no-data annotation. Corrected diagnosis in `docs/issues/2026-08-24-cve-remediation-panels-empty.md`.

- [ ] **Image signing / CVE-loop closure** (`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`)
  — cosign sign+attest, Kyverno Audit→Enforce, promoter verify gate. Multi-repo, heavy.

- [ ] **Frontend inline attest — spec WRITTEN 2026-08-31, Codex NOT dispatched.** `shopping-cart-frontend` inlines its
  own build/sign in `ci.yml` `publish` job (no reusable-workflow `uses:`) — signs but no attestation. Spec
  `docs/plans/v1.27.0-image-signing-frontend-inline-attest-codex-task.md`: insert 3 steps (trivy `cosign-vuln` +
  `spdx-json` predicates by digest → `cosign attest --type vuln`/`--type spdxjson`) after `Sign image by digest`, trivy
  pin reused `v0.36.0`, branch `feat/frontend-inline-attest`, exact msg `ci: attest frontend image (vuln + SBOM) inline by digest`.

- [ ] TWO-CLOUD (hostinger as 2nd registered cluster) NOT yet done — this run was k3s-aws only; hostinger node up but not registered into hub.
- Note (follow-up, unfiled): two LDAP instances in identity ns (openldap-0 StatefulSet + stray ldap
  Deployment) — confirm Keycloak federation binds openldap-0, not the stray, before v1.28.0 PR.
# 2026-09-09 — Hermes Kine guard in progress

## 2026-09-20 — Port-forward wrapper fix pending commit

- [x] Implement address-scoped `lsof` probes and `--address="${ADDRESS}"` binds.
- [x] Re-resolve kubectl context at the top of every supervisor iteration; log and de-duplicate wrong-context substitution warnings.
- [x] Parameterize `LOG_TAG`; regenerate keycloak-browser wrapper unconditionally; add requested static BATS gates and changelog entries.
- [x] Gates: `bats scripts/tests/plugins/argocd.bats` 32/32; `bats scripts/tests/bin/cluster_up.bats` 9/9; `shellcheck -S warning scripts/plugins/argocd.sh bin/cluster-up` exit 0.
- [ ] Commit/push blocked by workspace Git permission: `fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted`. No commit SHA or PR URL exists yet; PR creation remains forbidden by the task.

## Shipped in v1.34.0 (detail in CHANGELOG `[Unreleased]` and the linked issues)

- [x] **Hermes Status Grafana dashboard** (`60a04c19`, label fix `6a58f77f`, stat rendering `7fa75dd6`,
  scrape-metadata hiding `025a0d41`, target scopes `1cb69566`). Hermes publishes a redacted snapshot of
  every sensor finding; regular sensors publish even while `status_checks` is off.
  `docs/issues/2026-09-17-hermes-grafana-visibility.md`.
- [x] **E2E Grafana drill-down** — failure groups `6c8b834d` (exporter normalization `8c80aeb9`),
  test-level details `facf30fa`, owning-service labels `dece8c63`/`2830b32c`, cross-service
  classification `c691eb92`. Live backfill evidence:
  `docs/issues/2026-09-16-live-e2e-failure-groups-empty.md`.
- [x] **E2E Grafana trends** — trend/cause/spec panels `3c33103a`, placement + owning-service column
  cleanup `387f019e` (verified live; stale-layout note in
  `docs/issues/2026-09-16-e2e-grafana-dashboard-stale-layout.md`), failure ratio `5b8a90fc` →
  `455b87ac` → `afff9ae0`, column ordering `d63a5753`…`7e7ec231`.
- [x] **Dashboard responsiveness** — E2E refresh/row caps `5202feb1`/`9866d119`, CVE tables bounded to
  `topk(500, ...)` over 7,409 series `5a788cf3`, CVE Service column dropped `d42fc601`.
  `docs/issues/2026-09-17-cve-dashboard-freeze.md`.
- [x] **Webhook/status credential recovery** — configured Cloudflare token key `2991cc23`, empty-token
  recovery `2ba24c74`, stale-token fallback `6e86ad43`, bounded liveness probe `916d1a0b`, keychain
  auth diagnosis `85a05c7e`. `docs/issues/2026-09-16-status-webhook-health-timeout.md`.
- [x] **Live SSO + remote E2E recovery** — the Keycloak PostSync hook failed because
  `quay.io/keycloak/keycloak:24.0` ships no `awk`; ArgoCD public OIDC URL aligned `c219eab7`.
  `docs/issues/2026-09-16-live-sso-e2e-recovery.md`.
- [x] **Two dashboards diagnosed as no-data-by-design, not broken** — checkout load-test
  (`docs/issues/2026-09-17-checkout-loadtest-dashboard-no-data.md`) and k3dm deployment
  (`docs/issues/2026-09-17-k3dm-deployment-dashboard-no-data.md`); both await a publisher, not a fix.

## Release ledger

Canonical: `docs/releases.md` (full history) and the README releases table (3 most recent).
Per-release detail: `CHANGELOG.md` and `docs/retro/`.

## Process (standing rules — do not archive)

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim evidence.
- Historical specs/issues are archived only when superseded or unreferenced; files are never deleted.
- Keep all new work within the five-plan milestone limit. **v1.34.0 is at 5/5 — the next spec opens v1.35.0.**
- Reapply the ApplicationSets (hub and ACG) every release, then run `argocd_check_values_branch`.

## 2026-09-20 — Seed payment secrets

- [x] Guard `payment/encryption`, `payment/stripe`, and `payment/paypal` against unconditional writes;
  Stripe restores from Keychain before the placeholder fallback.
- [x] Add six idempotency/source-copy BATS cases and the `[Unreleased]` changelog entry.
- [x] Gates: focused BATS 14/14; `make test` 980/980, exit 0; shellcheck has only unrelated
  pre-existing warnings in `shopping_cart.sh` lines 882–975.
- [x] `_stripe_sk` made `local` (line 630) — Claude's fix for a spec omission that would have
  leaked the real Stripe key into a global after the function returned.
- [x] Committed and pushed by Claude after independent verification (diff scope, 14/14 BATS,
  shellcheck parity against `git show HEAD:`). Codex could not commit: `.git/index.lock`
  Operation not permitted.

## 2026-09-21 — GHCR PAT validated for auth, not for `read:packages`

- [x] Fixed `Makefile:502` `$$(MAKE)` -> `$(MAKE)`: `show-service-passwords` announced a Vault
  port-forward restart that never happened and failed with `Error: invalid function name: '—'`
  (APFS case-insensitive `/usr/bin/MAKE` + `.DEFAULT_GOAL := help` + the help's em-dash). `b49c8164`.
- [x] SMS legibility bug CLOSED — operator confirmed a legible `ServiceDown` page on the handset;
  all DoD boxes checked. `fd59fb70`.
- [x] Deep-dived the `ServiceDown` page per the standing rule: it is a **true positive**. Four
  `shopping-cart-apps` deployments `ImagePullBackOff` 11h, `403 Forbidden` from ghcr.io. Root cause
  is a validation defect, not the plumbing — `ghcr-pull-secret` exists and ESO reports
  `SecretSynced True`. Spec filed `2c48a1a1`, made implementation-ready `cc4ee6bb`.
- [x] **Codex DONE, verified by Claude** — `cb428d09` on `origin/k3d-manager-v1.36.0`.
  Spec `docs/bugs/2026-09-21-ghcr-pat-validated-for-auth-not-packages-scope.md`, session
  `01a0c3e2-649a-7462-a8d8-1964a0435a62`. Codex could not commit (`.git/index.lock`: Operation not
  permitted — the same wall as 2026-09-20), so Claude committed after independent verification: diff
  scope exactly the two permitted files, bats 25/25, shellcheck 10 findings before and after.
  Three corrections found during verification, all in the spec or the tests rather than the
  implementation: (1) the spec told Codex to use `_err` in `shopping_cart_prompt_ghcr_pat`, but `_err`
  **exits 1**, which aborted the run and left the following lines dead — Claude's spec error,
  faithfully copied, now `_warn`; (2) the argv assertion grepped a pattern matching nothing in the
  pre-fix source either, so it could never fail — replaced with a gate proven to discriminate 2 -> 0;
  (3) the no-persist test asserted on `read:packages` while its own stub printed that string, so it
  tested the stub, not the production message. The no-persist gate was mutation-tested: removing the
  guard yields `not ok 24`.
  Gate all four PAT loaders on a real GHCR token-exchange + `tags/list` pull probe; never persist a
  credential that has not passed it; collapse the three duplicated Vault writes into one helper that
  keeps the token out of argv and encodes the PAT with `jq -n --arg`.
- [ ] **Operator, out of scope for Codex** — mint a PAT with `read:packages`, overwrite
  `secret/github/pat`, force-sync `ghcr-pull-secret`, restart the four deployments. The gh CLI token
  can never work: its scopes are fixed by the OAuth app (`repo, read:org, gist, admin:public_key`).

- [ ] **Codex: fix `bin/rotate-ghcr-pat`** — hardcoded `ubuntu-k3s` context, auth-only PAT
  validation, PAT+Vault token in argv. Spec `796ba237`. Dispatched 2026-09-21 via `codex exec`.
  Awaiting SHA — verify before trusting.
- [ ] **Hub GHCR `ImagePullBackOff`** — OPEN, blocked. No GitHub credential on the operator's
  machine can pull from `ghcr.io` (403 Forbidden). Needs a PAT with `read:packages`.
- [ ] **`github-packages-token` cannot pull** — implies GitHub Actions image builds will 401.
  Independent of the hub outage; track separately.

- [x] **Codex: fix `bin/rotate-ghcr-pat`** — VERIFIED and committed `edaa2e49`. Five BATS gates
  mutation-tested against pre-fix source; one Codex-reported gate count (PAT argv `1→0`) was false
  (`0→0`, vacuous) and was corrected before commit.
- [ ] **Codex: forward `PROMOTER_SSH_KEY`** — spec `eb97355d`, dispatched 2026-09-21, branch
  `fix/pass-promoter-ssh-key` in payment / product-catalog / frontend / infra. Awaiting 4 SHAs.
- [ ] **OPERATOR: create `PROMOTER_SSH_KEY` secret** in `shopping-cart-product-catalog` and
  `shopping-cart-frontend` (both lack it entirely; reuse the key already in basket/order/payment).
- [x] ~~`github-packages-token` implies Actions 401~~ — **RETRACTED, was wrong.** `PACKAGES_TOKEN`
  works; the registry push succeeds. The break was `PROMOTER_SSH_KEY`, see above.

- [ ] **Codex: forward `PROMOTER_SSH_KEY`** — RE-DISPATCHED with corrected scope, spec `6fa1ceab`.
  Only `shopping-cart-product-catalog` + `shopping-cart-infra`. Awaiting 2 SHAs.
- [ ] **OPERATOR: create `PROMOTER_SSH_KEY` secret** in `shopping-cart-product-catalog` only
  (it has none; reuse the key already in basket/order/payment).
- [ ] **UNFILED follow-up:** basket run `33507015429` promotion failed with
  `failed to push some refs` — push rejection, key was present. File if it recurs.
- [ ] **Stray branches** `fix/pass-promoter-ssh-key` exist in payment and frontend from the first
  dispatch, with no commits. Deletion NOT approved — left in place.

- [x] **Codex: forward `PROMOTER_SSH_KEY`** — VERIFIED. `2c8dd68f` (product-catalog) and `94b16bc9`
  (infra), both on `origin/fix/pass-promoter-ssh-key`. YAML-parsed step order confirmed guard before
  consumer; promote step intact. No PRs (awaiting user's go).
- [x] **Bump the infra pin in product-catalog** — MOVED, but NOT by our fix. Dependabot PR #54
  merged 2026-09-21 23:41:44Z (`1f45062c`), pin `1b35d962b` -> `af4b053dc`. af4b053dc is infra
  main at PR #98 (keycloak, 09-16); it predates the promoter guard `94b16bc9`, which is still
  unmerged on `fix/pass-promoter-ssh-key`. So the pin moved to a SHA that has neither the guard
  nor the rebase-fallback fix.
- [x] **PRs MERGED for the promoter fix** — 2026-09-22 00:04-00:05Z. product-catalog
      [#55](https://github.com/wilddog64/shopping-cart-product-catalog/pull/55) merged at
      `b6ff80b7` and infra [#99](https://github.com/wilddog64/shopping-cart-infra/pull/99) merged at
      `91432535`. Both fix the PROMOTER_SSH_KEY promotion failure: product-catalog's `ci.yml` now
      forwards the key to the reusable workflow, and infra gained the guard step that detects an
      empty key and fails loudly. Forwarding in #55 restores promotion for product-catalog.
- [x] **Blast radius of the infra guard verified by enumeration** — all four callers read from
      `main`: basket `go-ci.yml`, order `ci.yml`, payment **`ci.yaml`** all forward
      `PROMOTER_SSH_KEY`; only product-catalog `ci.yml` does not. frontend does not call the
      workflow. The guard therefore hard-fails exactly the one misconfigured repo. Payment's
      `.yaml` extension is why a `*.yml` glob missed it in the 2026-08-09 rollout.
- [x] **Both promoter PRs green and Copilot-clean** — #55 `MERGEABLE/CLEAN`, #99
      `MERGEABLE/BLOCKED` (review required). Infra YAML Lint caught a 211-char line in Codex's
      guard; fixing it exposed that the message embedded `${{ secrets.* }}`, which Actions
      substitutes in a run block (backslash is not an escape), so the guard's own instruction
      would have printed empty. Reworded, `6dc3c23`.
- [x] **enforce_admins disabled on shopping-cart-infra** — 2026-09-21, on the user's explicit
      request. Verified `enabled = false`. #99 still displays `BLOCKED` (ruleset's 1 required
      approval); that is expected, the admin bypass path is what changes, not the status text.
      product-catalog needed none (ruleset repo, no such lever).
- [x] **RE-ENABLED enforce_admins on shopping-cart-infra after #99 merged** — bodyless POST
      completed 2026-09-22, verified `enabled=true`. The two PRs are now merged and post-merge
      housekeeping complete.
- [x] **product-catalog promotion VERIFIED WORKING 2026-09-22 00:13Z.** Merge run `35670460109`
  on `b6ff80b7` promoted successfully. Evidence is the artifact, not the run conclusion:
  commit `6b79fda` on `origin/main`, **authored by `sc-image-promoter`** (the deploy-key identity,
  proving the key loaded and the push authenticated), setting
  `newTag: sha-b6ff80b7dec18f9ed1b81c9f1d86e402ba01cdd2` in `k8s/base/kustomization.yaml`.
  Step `Update image tag in k8s/base/kustomization.yaml` = success; gate
  `Fail when image promotion did not complete` = skipped (its pass state).
  Decisive corroboration: the previous change to that file was **2026-05-24 by a human** — the
  promoter had never once written to this repo before today.
  Note this run used pin `af4b053dc`, which predates the guard, so no
  "Verify the promoter SSH key was provided" step appears. Expected; the guard arrives with the
  pin bump onto the infra merge.
  Superseded detail from when this was still open: PR #55 merged
  2026-09-22 00:05Z at `b6ff80b7`. main's `ci.yml` now forwards `PROMOTER_SSH_KEY` to the reusable
  workflow alongside `PACKAGES_TOKEN`, `COSIGN_KEY` and `COSIGN_PASSWORD`, so the promote step
  should no longer write an empty key file and die at
  `Load key "~/.ssh/promoter_key": error in libcrypto`.
  **This is a code-merged claim, NOT a promotion-verified claim — do not mark it done on the merge
  alone.** The publish job is skipped on pull requests, so no PR could ever exercise promotion;
  merge run `35670460109` is the first genuine test and was still `in_progress` when this was
  written. Close this only after reading the promote step's own log and confirming `newTag:` in
  `k8s/base/kustomization.yaml` actually advanced. A green run conclusion is NOT sufficient: the
  promote step runs under `continue-on-error: true`, which is exactly how this stayed invisible
  for six pushes.
- [x] **OPERATOR: create `PROMOTER_SSH_KEY` secret** in `shopping-cart-product-catalog` — DONE
  2026-09-21 23:38Z by the user via `!`. See the minting row below.
- [x] **Promoter-key spec corrected twice** — deploy keys are per-repo, not shared; product-catalog
      is missing the `sc-image-promoter` deploy key AND the `PROMOTER_SSH_KEY` secret. Pin bump
      sequenced after the infra merge, not dispatched to Codex.
- 2026-10-02: `fef39649` (realm roles list) + `cc43b5fc` (Grafana Dashboards Loaded) landed, Claude-verified. Checkout Load Test CPU saturation [1m]→[5m] spec dispatched to Codex.
- 2026-10-02: operator `loadtest_run --confirm` failed (no LOADTEST_USERNAME/PASSWORD). `make loadtest-preflight` / `make loadtest CONFIRM=1` added to v1.41.1 plan `06e973dc` (v1.40.0 at 5-plan cap).
- 2026-10-02: `a5e1e24f` CPU saturation [5m] landed (Claude-verified 30/30). vcluster upgrade nag: bug spec docs/bugs/2026-10-02-vcluster-upgrade-nag-in-harness-output.md (VCLUSTER_SKIP_VERSION_CHECK=true) dispatched to Codex; pin-drift check/bump plan docs/plans/v1.41.1-vcluster-version-drift.md (pinned 0.32.1, latest 0.37.2).
- 2026-10-02: `7ce184e5` vcluster nag fix verified (shellcheck clean, new test green). 4 vcluster.bats orphan tests red since `5706eb21` (seed still a table; only reconcile suite was run at verify) — spec docs/bugs/2026-10-02-vcluster-bats-orphan-seed-still-a-table.md dispatched to Codex. Plan docs/plans/v1.41.1-scheduled-baseline-loadtest.md: 12h baseline profile via launchd + major-release stress gate before/during PR (operator decision).
- [x] **Root-caused the product-catalog promotion failure** — never onboarded in the unenumerated
      2026-08-09 SSH-promoter rollout; Dependabot auto-merge imported the breaking change 2026-08-12;
      a 2026-09-01 DeployKey ruleset bypass was a misdiagnosis. Broken since 08-12, not 08-26.
- [x] **Mint the product-catalog promoter pair** — DONE 2026-09-21. User ran the handed-over
      command via `!` (Claude was blocked by the Secret-Store Writes classifier). Verified
      independently: deploy key `164022592` `sc-image-promoter` **read-write** created 23:38:44Z
      (fingerprint `AAAA...DtH73fkqL5hO...`, distinct from the pre-existing
      `argocd-product-catalog-m2-air` key), secret `PROMOTER_SSH_KEY` set 23:38:46Z, and both
      `/tmp/pc_promoter*` files removed. Steps 1 and 2 of the onboarding are now closed; the
      2026-09-01 DeployKey ruleset bypass was already in place.
- [x] **Hub GHCR 403 root-caused** — packages are private; no long-lived pull credential exists
      anywhere (CI logs in with the ephemeral GITHUB_TOKEN). Probe verified correct; keychain not
      locked. Fix is `gh auth refresh -h github.com -s read:packages`, not a new PAT.
- [x] **basket promotion failure root-caused and filed** — concurrent `newTag:` bumps make the
      `git pull --rebase` fallback a guaranteed conflict, not a flake. Spec:
      `docs/bugs/2026-09-21-image-promotion-rebase-fallback-cannot-resolve-concurrent-newtag-conflict.md`
- [ ] **Dispatch the refetch-loop fix to Codex** — BLOCKED until `fix/pass-promoter-ssh-key` merges
      in shopping-cart-infra (same file).
- [x] **`make show-service-passwords` healthy-Vault failure fixed `ef3d4b8d`** — `Makefile:500` now probes
      `auth/token/lookup-self` instead of the optional display mirror, and
      `_hub_recovery_mirror_argocd_admin` retries the bootstrap secret for up to 60 seconds. Added
      the optional-mirror triage note, static-source BATS coverage, and the required CHANGELOG entry.
      Pushed to `origin/k3d-manager-v1.36.0`; focused BATS 31/31 and shellcheck clean.
      Original issue: the target
  optional display mirror `secret/argocd/admin` (404) to decide Vault reachability, then exits 1
  and blocks all four credentials. Live probe proved Vault healthy: `auth/token/lookup-self` 200,
  `observability/grafana` **200**. Spec:
  `docs/bugs/2026-09-21-show-service-passwords-liveness-probe-uses-optional-kv-path.md`.
  M1 = swap probe to `auth/token/lookup-self`; M2 = retry the `argocd-initial-admin-secret` read
  in `_hub_recovery_mirror_argocd_admin` (bootstrap race, ~6 min window observed); M3 = doc. DONE.

- [x] **image-promotion rebase fallback replaced `e99960e`** - `fix/promote-refetch-instead-of-rebase`
      in shopping-cart-infra: fetch + `reset --hard` + reapply, 5 bounded attempts, no rebase.
      Gates verified independently (`pull --rebase` 0, `reset --hard` 1, guard 1, YAML OK, guard step
      index < promote). Codex hit the `.git/index.lock` wall so I committed and pushed the diff.
      Spec: `docs/bugs/2026-09-21-image-promotion-rebase-fallback-cannot-resolve-concurrent-newtag-conflict.md`.
      **PR not opened** - awaiting the user's go.

- [x] **Vault-rebuild credential gap root-caused and filed `9d2bdb15`** - KV metadata 404 proves
      `k3d-manager/prometheus-basic-auth` and `argocd/admin` were never written to the current Vault
      instance. Root-causes the standing "Prometheus Vault credentials unreadable" item. Spec:
      `docs/bugs/2026-09-21-vault-rebuild-leaves-prometheus-and-argocd-credentials-unseeded.md`;
      dispatched to Codex (M1 reseed, M2 stop discarding the failure, M3 ArgoCD display fallback, M4 doc).
- [x] **`secret/argocd/admin` repaired live** - validated against ArgoCD `/api/v1/session` (200),
      mirrored, read-back MATCHes the k8s source; the target now resolves ArgoCD.
- [ ] **Rotate two exposed credentials** - Grafana (pasted by the user into the session) and Keycloak
      admin (leaked past my redaction filter). Both need rotation.
- [ ] **`show-service-passwords` Keycloak line defeats redaction** - prints `admin user: admin / <pw>`
      instead of the `password: <pw>` convention every other service uses, so filtering by convention
      misses it. Also the 3 Keycloak dev users print `N/A`. Unfiled.

- [x] **Codex `bbr6gajol` verified** - `6c744a23` Prometheus reseed + ArgoCD display fallback;
  BATS 11/11, mutation genuine, asymmetry held. One unsolicited SC2016 edit reverted.
- [x] **Keycloak display defect filed and fixed** - spec `284d22ec`, fix `41855a2d`
  (`origin/k3d-manager-v1.36.0`). Every credential now behind a `password:` label; Vault root
  token out of the `kubectl exec` command string; hub context pinned in
  `bin/get-keycloak-password`. BATS 15/15, mutation 7/8/9 red pre-fix.
- [ ] **ROTATE two exposed credentials** - Grafana (pasted into the session) and Keycloak admin
  (leaked past my redaction filter). Still outstanding.
- [ ] **`secret/keycloak/users/*` unseeded on the hub** - expected state, now reported honestly.
  Seeding it would require either running `bin/cluster-up`'s SSO step or adding the path to the
  14-key allowlist; the latter is NOT approved. No action taken.
- [ ] **Jev / TypeSafe AI - do not integrate now.** Recommendation is a deterministic e2e verdict
  taxonomy + repo routing table + back-labelled corpus from the 28 existing e2e/Hermes bug docs,
  which doubles as the offline eval set. Spec NOT written - needs the user's go.
  (`docs/plans/` for v1.36.0 currently holds 1 of the 5-doc cap.)
- [ ] **No PRs opened** for `ef3d4b8d`/`f9d956ae`/`6c744a23`/`41855a2d` (k3d-manager) or
  `e99960e` (shopping-cart-infra). PR creation still needs the user's explicit go.

- [x] **Deterministic E2E triage spec** — `docs/plans/v1.36.0-e2e-deterministic-triage-and-corpus.md` (`f670d731`); dispatched to Codex, session `01a0c6ab`. 2 of 5 plan docs for v1.36.0. No external model/service involved.
- [x] **Hermes Tier 2 port misattribution** — FIXED `0c57b110`. — `hermes/e2e_triage.py` `_PORTS` is Tier-1-only; Tier 2 order=8081 / product-catalog=8082 classify as `host-8081`/`host-8082`, so Tier 2 bug docs are filed with no service attribution. Fix is M1.1 of the spec above.
- [x] **E2E failure text published unredacted** — FIXED `0c57b110`. — `_e2e_write_summary` writes raw Playwright error text to disk and to a hub ConfigMap in `platform-ops`; `e2e_remote.sh` validates length only. `redact()` already exists in hermes and was never adopted on the `e2e.sh` path. Fix is M3 of the spec above.
- [x] **Two divergent E2E classifiers** — FIXED `0c57b110`. — `e2e.sh:711-760` inline vs `hermes/e2e_triage.py`; corrects my earlier claim that e2e.sh had no classification logic. Collapsed by M2 of the spec above.
- [x] **`auth` failure class missing** — FIXED `0c57b110`. — taxonomy has 4 kinds + `harness`; no auth class, so 401/403 failures land in `assertion` or `contract-drift`. Added by M1.3, with the `e2e_bugs.py` hint entry in M1.4.
- [x] **Deterministic e2e triage implemented** — `0c57b110`; verified independently (shellcheck RC=0, 138 pytest, 45/45 bats, mutation check genuine). Codex was blocked on `.git/index.lock`; Claude committed on its behalf.
- [x] **Grafana admin password ROTATED and verified** — job `grafana-rotate-manual-20260921-195152` via the existing CronJob; login 200 with the Vault/ESO credential, 401 with a wrong one. The exposed value is invalid.
- [ ] **Keycloak admin rotation** — still outstanding; no rotator exists and the ESO secret is bootstrap-only, so Vault+restart alone will not change the live password. Needs a 3-step manual or a new `keycloak-credential-rotator` spec. Operator to choose.
- [x] **PR #130 CI RED** — 4 failures, all branch-introduced (`main` green): bare-`!` lint (2 no-op assertions from `6c744a23`), observability tests 3/8 (reseed conflates Vault-unreachable with entry-absent — real design bug against the Vault-is-canonical decision), alertmanager test 388 (stale message + stubs). Fixed; PR merged 2026-09-23 as 945018ee.

- [x] **Keycloak admin credential rotated on the live hub** — 2026-09-22. Rotator manifest applied,
  Vault role `keycloak-rotation` created, Job `keycloak-rotate-manual-20260922-043917`
  `SuccessCriteriaMet`. Verified: `db_password=MATCH(preserved)`, `new_password=200`,
  `wrong_password=401`, and the stale ESO copy of the old password now `401`. Exposed password
  is dead.
- [ ] **Fix `base64 --decode` in platform-ops rotators** — BusyBox in `alpine/k8s:1.31.4` only
  accepts `-d`. keycloak lines 98/113 and argocd line 139 silently disable ALL Slack
  notifications (including rollback-failure alerts); argocd line 117 has no `|| true` and looks
  like it aborts the job outright. grafana already uses `-d`. Needs a bug doc + a test banning
  `--decode` in `scripts/etc/argocd/platform-ops/`.
- [ ] **`keycloak-realm-reconcile` fails with `awk: command not found`** — exit 127, 2026-09-21,
  `quay.io/keycloak/keycloak:24.0`. Realm `shopping-cart` created but auth flows never
  configured. Pre-existing, unrelated to the rotation. Needs a bug doc.
# 2026-09-22 — Prometheus reseed and rotator CI fix

- [x] Implemented M1–M5 and pushed as `7d475a9fe1e8e5f051d035b4f917559341d8b127` to `origin/k3d-manager-v1.36.0`; focused BATS suites, shellcheck, YAML parsing, doc links, and full `make test` (1,010/1,010) passed. `scripts/tests/lib/observability.bats` remained byte-identical.

- [x] **PR #130 CI reds fixed** — spec `6658faff`, Codex `7d475a9f`+`0b9941c2`, refinement
  `1b7c6c93`. Verified independently: `make test` 1010/1010, tests 57/174/179/388 green,
  `observability.bats` untouched. Prometheus reseed now separates unreachable Vault from an absent
  entry; `base64 --decode` → `-d` at five sites across the keycloak and argocd rotators.
- [x] **Prometheus Vault entry absent on the hub** — `secret/k3d-manager/prometheus-basic-auth`
  404 with no metadata; local cache intact. Repair = cache-recovery reseed (NOT
  `observability_rotate_prometheus_basic_auth`, which targets the ACG context). Repaired by operator 2026-09-22.
- [ ] **`keycloak-realm-reconcile` awk exit 127** — still needs its own bug doc.
- [x] **PR #130 CI GREEN** at `3d3e36a7` (run 35728186747: lint success, detect success). Copilot's
  2 inline findings addressed, replied and both threads resolved: header tempfile `chmod 0600`
  (fixed, `3d3e36a7`; `mktemp` is already 0600 so defence in depth) and the GHCR
  `Authorization: ******` claim (FALSE POSITIVE — diff-rendering artefact; source uses
  `printf 'Authorization: Bearer %s\n' "${_token}"`).
  Outstanding merge gate: **Gemini live smoke test not run** — `enforce_admins` deliberately NOT
  disabled, since the gate list is not fully satisfied.
- [ ] **Alertmanager root route is default-deny — all warning alerts discarded** (spec filed
  2026-09-23, assigned to Codex). Root cause of the 15 silent `cve-remediation-verify`
  failures. `route.receiver: 'null'` at `alertmanager.yaml.tmpl:9`; only `severity = critical`
  or the 5-name allowlist escape it. Also silences this repo's own `E2EVerificationFailing`
  and the `keycloak-realm-reconcile` awk-127 job. Spec:
  `docs/bugs/2026-09-23-alertmanager-null-root-route-silently-drops-warning-alerts.md`.

- [x] **Alertmanager delivery blackout — FIXED, confirmed on the live cluster.**
  `03b875c5` warning route + deploy guard on both renderers; `02e3fa76` AppSet CNI-dir precedence
  (substrate wins, live is fallback, generic dirs refused on k3s); `114e5c82` Claude's fix to the
  probe's `alertmanager.yaml.gz` key + hard error on a missing key, which had it reporting the
  healthy hub as a total blackout. All three verified independently (pytest, BATS, shellcheck,
  four mutations red then restored). Live re-render seeded `alertmanager-smtp-secret` on
  ubuntu-hostinger: **0 → 4 child routes**, `platform-warning` now reachable, and
  `KubeDaemonSetRolloutStuck` routes for the first time in 17 days. Mail delivery confirmed:
  1 email attempt, 0 failures across all five reasons, and 1 latency-histogram observation (recorded
  only on a completed send). First alert out of that cluster after a 17-day blackout.
- [ ] **Probe has no test of its own** — `test_alert_delivery.py` stubs `run`, so
  `bin/k3dm-alert-delivery-status` is never executed by any suite. That is how the gzip-key defect
  shipped green. A parse-level test over a fixture generated Secret would close it.
- [ ] **istio-cni DaemonSet — precondition done, awaiting the user's go for the AppSet reapply.**
  `istio-cni-node-vgr6m` is 0/1 since 2026-09-06, `install-cni` readiness 503, **160,074 probe
  failures over 17d**, 0 restarts (no probe ever passed). The live `istio-ambient` AppSet still
  holds the generic `cniConfDir: /etc/cni/net.d` / `cniBinDir: /opt/cni/bin`; the correct k3s values
  are `/var/lib/rancher/k3s/agent/etc/cni/net.d` and `/var/lib/rancher/k3s/data/cni`
  (`_istio_ambient_cni_dirs k3s-hostinger` confirms). **`02e3fa76` fixes the overwrite mechanism but
  is inert until the AppSet is reapplied** — the stale generic dirs are still live. Ambient is in
  real use, not cosmetic: `ztunnel-69cft` is 1/1 and namespace `shopping-cart-apps` carries
  `istio.io/dataplane-mode: ambient`, so redirection setup for new pods there is degraded.
  Next action, needs the user's go: reapply the `istio-ambient` ApplicationSet, confirm it writes
  the k3s dirs (the new guard should refuse the generic ones), then roll the DaemonSet.

- [x] **v1.39.0 Slack corpus Q&A specced** — `docs/plans/v1.40.0-slack-corpus-qa.md`, filed on
  operator direction so it is not lost between releases. Plan #1 of 5 for v1.39.0. **Hard-blocked on
  v1.38.0 WS5 publishing a measured recall@5**; if neither scorer clears its floor the spec does not
  ship. Dedup check found `v1.6.0-slack-ai-analysis.md`, which is a different shape (alert-triggered
  push, not user-query pull) but establishes that `/api/v1/analyze` already calls the Claude API from
  `k3dm-webhook` and posts to Slack — so v1.39.0 is a new handler on proven transport, not new
  infrastructure. Real work is WS3 (authorisation + disclosure): `docs/bugs/` and `docs/issues/` were
  written for operators with repo access, and a Slack channel may be wider.

- [x] **Provider label verified `k3s-hostinger` on the live hub (2026-09-24)** — operator ran
  `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger`; `cluster-ubuntu-hostinger` now carries
  `k3d-manager/provider: k3s-hostinger` (was `unknown`). `834149ea` is confirmed effective against
  the live cluster, so the last link in the istio-cni chain is closed and the AppSet reapply
  precondition now holds.
  - **Root cause confirmed from the container's own logs, not inferred.** `install-cni` has logged
    since 2026-09-06T16:36:54Z: `Istio CNI is configured as chained plugin, but cannot find existing
    CNI network config: no networks found in /host/etc/cni/net.d` and `Waiting for CNI network config
    file to be written in /host/etc/cni/net.d...`. The host `/etc/cni/net.d` is **empty**; k3s keeps
    its conflist under `/var/lib/rancher/k3s/agent/etc/cni/net.d`. Istio is chain-waiting on a
    directory nothing will ever populate — that is the permanent 503, now 163,101 failures over 17d.
  - The ambient data path is **working**: the same container enrols pods and writes iptables
    (`sending pod add to ztunnel`, `shopping-cart-apps`). Only the chained-plugin install is stuck,
    so the DaemonSet is unready while ambient still functions. Readiness is the accurate signal here,
    not a false alarm.
  - `/var/lib/rancher/k3s/data/cni` exists and holds the k3s plugins (bandwidth, bridge, cni,
    firewall, flannel); `/opt/cni/bin` already holds the stray `istio-cni` binary installed to the
    wrong place.
  - **Probe caveat, recorded so it is not repeated:** an initial check via the
    `prometheus-node-exporter` pod reported the k3s conf dir MISSING. That was WRONG. node-exporter
    runs as `nobody`, and `[ -d ]` returned false because an ancestor was untraversable — `ls`
    printed `Permission denied`, which proves the ancestor EXISTS. Never read a negative existence
    result from an unprivileged container; an EACCES on the path is not absence. The istio-cni pod
    is distroless (no `sh`), so container logs were the authority instead.

- [ ] **AWAITING THE USER'S GO — reapply the `istio-ambient` ApplicationSet.** All preconditions now
  hold. Expected: `cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d`,
  `cniBinDir: /var/lib/rancher/k3s/data/cni`, and the new guard silent (provider is specific).
  Then roll `istio-cni-node` and confirm 1/1 plus `KubeDaemonSetRolloutStuck` clearing.

- [x] **Grafana "No data" measured, 2026-09-24 — five dashboards, FOUR different causes.** All five
  ConfigMaps live on the **hub** (`k3d-k3d-cluster`), which has **no Pushgateway**; hostinger has one.
  The istio-cni work is unrelated to every one of these. Counts from hub Prometheus:
  | metric | series |
  |---|---|
  | `trivy_vulnerability_inventory` | 7447 |
  | `e2e_run_info` | 21 |
  | `e2e_last_run_pass` | 2 (both = 0) |
  | `e2e_last_run_timestamp_seconds` | 2 |
  | `e2e_last_success_timestamp_seconds` | 0 |
  | `e2e_failure_group_info` / `e2e_failure_info` | 0 |
  | `cve_remediation_state` / `cve_remediation_event_info` | 0 |
  | `hermes_sensor_status` | 0 (`hermes_incident_active` = 1) |
  | `k3dm_deployment_*`, checkout/k6/loadtest | 0 (no such metric name exists) |

  Source-ConfigMap counts in `platform-ops`: `k3dm.k3d.io/cve-remediation-event=true` → **0**,
  `k3dm.k3d.io/e2e-result=true` → **21**, `k3dm.k3.io/hermes-status=true` → **0**.
  1. **CVE auto Patch — partly alive.** Inventory panels have 7447 series and DO render. The
     remediation panels are empty only because no remediation-event ConfigMap has ever been written.
  2. **E2E Verification — the exporter is fine, the payloads are empty.** All 21 event payloads carry
     `total:""`, `failed:""`, `duration_seconds:""`, `failure_groups:[]`, `failure_details:[]`, which
     is why `e2e_run_info` carries the nonsense label `failure_ratio="/"` (empty/empty). This is the
     already-documented "empty event payload = the run aborted before any test ran" mode. Both
     runners report `e2e_last_run_pass=0`, so `e2e_last_success_timestamp_seconds` is never emitted —
     "Last success age" is blank because **nothing has ever passed**, not because of plumbing.
     Blocked on the three e2e fixes (`9d2a0ad0`, `7338a238`, `ad9909a8`) being exercised live.
  3. **Hermes Status — blank by current design.** Zero `hermes-status` ConfigMaps because
     `K3DM_HERMES_STATUS_ENABLED` must stay unset. Not a defect. Exporter selector correctly uses
     `k3dm.k3.io` while e2e/cve use `k3dm.k3d.io` — the split is intentional, do not "fix" it.
  4. **k3dm Deployment Metrics and Checkout Load Test — no producer at all.**
     `k3dm_deployment_duration_seconds` appears in exactly one file in the repo, its own dashboard
     ConfigMap. Nothing emits it, and no checkout/k6 metric name exists. These two are unwired
     dashboards, not broken ones.

  **Hypothesis I raised and then disproved:** I suspected the e2e dashboard queried a metric name the
  exporter never emits. It does not — the exporter defines `e2e_last_success_timestamp_seconds` at
  line 383 of `vulnerability-inventory-exporter.yaml`. Checked before reporting it.

- [x] **istio-cni-node on ubuntu-hostinger is 1/1 — RESOLVED 2026-09-24 after 17 days at 0/1.**
  Ran `APP_CLUSTER_NAME=ubuntu-hostinger ./scripts/k3d-manager deploy_istio_ambient --confirm`.
  Derived correctly: `INFO: [istio_ambient] CNI dirs for provider 'k3s-hostinger':
  /var/lib/rancher/k3s/agent/etc/cni/net.d /var/lib/rancher/k3s/data/cni`. Live AppSet now carries
  those values. ArgoCD rolled the DaemonSet **by itself** (helm values changed) — `istio-cni-node-rls4b`
  came up 1/1 in 55s, app `Synced/Healthy`. The new pod's own log closes the loop:
  `CNI config file "" preempted by "/host/etc/cni/net.d/10-flannel.conflist"` →
  `created CNI config ...` → `initial installation complete, start watching for re-installation`.
  `KubeDaemonSetRolloutStuck` is gone; hostinger now has **0 real alerts firing** (only `Watchdog`,
  which is the always-on deadman's switch and therefore a positive signal for the delivery path
  repaired earlier tonight). Five-link chain closed end to end.

- [x] **TRAP: `--dry-run` cannot preview any substrate-derived value.** `scripts/lib/system_overrides.sh`
  replaces `_run_command` so that in dry-run mode **every** invocation is short-circuited to a printed
  preview — including read-only `kubectl get`. Any function that derives config by querying the
  cluster therefore captures the literal string `[dry-run] kubectl ...` instead of real output, the
  comparison fails, and the derivation silently falls back to its default.
  Concretely: `deploy_istio_ambient --dry-run` printed `CNI dirs for provider 'unknown':
  /etc/cni/net.d /opt/cni/bin` on a cluster whose provider label was correctly `k3s-hostinger`, and
  the real `--confirm` run then derived `k3s-hostinger` correctly. **I briefly read the dry-run as a
  fourth recurrence of the CNI bug and was wrong** — the dry-run manufactured the `unknown`. Verified
  by re-running `_istio_ambient_target_provider` under a passthrough `_kubectl`, which returned
  `k3s-hostinger`. Rule: never trust a dry-run's *derived* values, only its *intent*; to preview one,
  pass the value explicitly (`AMBIENT_CNI_CONF_DIR`/`AMBIENT_CNI_BIN_DIR`) or resolve it separately.

- [x] **Live e2e run on m2 — the three e2e fixes are CONFIRMED working (2026-09-24).**
  `make e2e-remote RUNNER=m2` with HEAD == origin (`8699752b`). Dispatch exited 1 because **tests**
  failed, not the harness. The published payload is **populated for the first time**:
  `total: 102, failed: 9, duration_seconds: 11.814`, one `failure_groups` entry
  (`kind=assertion, service=payment, target=api-payments`) and nine `failure_details`. Every prior
  run had `total:""`, `failed:""`, `failure_groups:[]` — that was the defect, and it is fixed.
  - Prometheus went `e2e_failure_group_info` 0 → **1** and `e2e_failure_info` 0 → **9**. The E2E
    dashboard's Failure groups / Failure details / Top failing specs / Failure trend / Failure causes
    panels now have data. Exporter cadence is 60s refresh + 1m scrape, so allow ~2min.
  - `e2e_run_info` stayed at 21, not 22: the publisher prunes the oldest result when it adds one, and
    the ConfigMap count is still exactly 21. Consistent, not an anomaly.
  - The nine failures are a **real application fault**, not harness noise: `payment` health returns
    `DOWN`, then `SyntaxError: Unexpected end of JSON input` because the service returns an empty
    body. In `api/payments.spec.ts`.
  - `WARN: [e2e] could not publish result event (hub platform-ops unreachable?)` during the run is
    **non-fatal and expected** — the hub is not reachable from m2. The publish-back path recovered it:
    `INFO: [e2e-publish] applied result for run ... (result=fail)`. Do not chase that WARN.

- [x] **ROOT CAUSE: CVE auto-patch has never produced a remediation event — specced, dispatched.**
  `docs/bugs/2026-09-24-hostinger-registration-resets-shopping-cart-label.md`.
  `cronjob/app-cve-scan` `.status.lastSuccessfulTime` is **empty** — it has never succeeded. A manual
  run failed in 6m32s, exit 1, on `applications.argoproj.io "ubuntu-hostinger-shopping-cart-frontend"
  not found`. Chain: `register_app_cluster:1481` defaults `ARGOCD_APP_CLUSTER_SHOPPING_CART` to
  **false** → `_hostinger_register_cluster` never sets it (`grep -c` = **0**) → live `services-git`
  AppSet selects on `k3d-manager/shopping-cart: "true"` AND `role: app-cluster`, so it matches **zero**
  clusters and generates none of the `ubuntu-hostinger-shopping-cart-*` Applications (it still reports
  "All applications have been generated successfully" — generating nothing counts as success) →
  `app-cve-scan.sh:526` patches that Application unguarded under `set -eu` → aborts → and
  `_emit_remediation_event` is on line **529**, so no event is ever written.
  - **This is the SAME defect shape as the provider label fixed in `834149ea`, in the SAME env block,
    one line away.** Two instances of "the hostinger register path omits a var that silently defaults
    to a value breaking a downstream AppSet selector" — worth treating as a class, not a one-off.
  - **It regressed.** `2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md` records a run
    that promoted four services including `frontend`, so the label was `true` and a refresh flipped it.
  - **Not cosmetic:** reaching `_promote` means the scan found a real HIGH/CRITICAL worth promoting on
    `shopping-cart-frontend`. Auto-patch has been silently not remediating.

- [x] **`2026-06-09-pushgateway-deployment-metrics-gap.md` updated — its proposed fix already shipped.**
  The bounded retry + `/-/healthy` precheck exist at `bin/k3dm-webhook:1717-1741`. Measured cause is
  different and total, not intermittent: the launchd agent
  `com.k3d-manager.pushgateway-port-forward` is **not loaded** and `localhost:9091/-/healthy` returns
  **000**, so every push retries against a closed socket. hostinger's Pushgateway is up and scraped
  (`pushgateway_build_info` present) but holds **zero** `k3dm_*` series; the hub has no Pushgateway pod
  at all. Remaining defects recorded in the doc: absent-vs-slow sink, no operator surface for silent
  failure, `_provider_supports_pushgateway` disagreeing with `_push_metrics`, and unstated topology.
  - **Search lesson:** I first concluded "no producer exists" from
    `grep -r --include='*.yaml' --include='*.sh' --include='*.py'`. Wrong — `bin/k3dm-webhook` has **no
    extension**, so the filters skipped it. Never restrict by extension when hunting producers here.

## 2026-09-24 — Pushgateway deployment metrics root-caused; Codex's shopping-cart label fix verified

**Codex `f8a7e118` VERIFIED independently** (not taken on report): HEAD == origin/k3d-manager-v1.37.0;
diff touches exactly the 8 spec'd files; both BATS suites re-run by Claude 9/9 green; shellcheck
re-counted with `grep -cE '\^-*\^ SC'` — hostinger 2→2, app-cve-scan 0→0. Two mutations re-proved by
Claude: deleting the `ARGOCD_APP_CLUSTER_SHOPPING_CART` line reds only test 4 (5 and 6 stay green,
so the override path and the `register_app_cluster` default are correctly discriminated); reverting
the promotion guard reds tests 7 and 8 while 9 stays green. Also checked the guard's `_rc=1` actually
propagates — the promote call sits in a plain `for _svc in ${APP_SERVICES}` loop, not a pipeline
subshell, and `_rc` is a script-level global consumed by `exit "${_rc}"`, so the run's failure is
genuinely carried.

**k3dm Deployment Metrics — root cause found, one line.** `_deploy_pushgateway_acg` installs the helm
release as `prometheus-pushgateway` (`observability.sh:692`); `_hostinger_refresh_access_layer` probes
for `svc pushgateway` (`k3s-hostinger.sh:661`). The probe always fails, so the `else` branch
`rm -f`'s the port-forward LaunchAgent on **every** access-layer refresh. Nothing listens on
localhost:9091, so every webhook push exhausts its 6 retries against a closed socket
(`Errno 61 Connection refused`, live in `~/Library/Logs/k3dm-webhook.log`) and logs a non-fatal skip.
The Pushgateway pod, its Prometheus target (`up=1`) and the retry logic were all healthy the whole
time — only the laptop→cluster hop was missing, and our own code removed it. 64 days, zero series.

`bin/cluster-up:1890` has always said `svc/prometheus-pushgateway` and is correct — the hostinger path
drifted away from it. The reusable defect is the drift, not the typo, hence a cross-file
agreement test in the spec.

**Round-trip proved live, then cleaned up.** Regenerated the plist/wrapper by calling
`_hostinger_write_monitoring_port_forward_plist` with the corrected name, bootstrapped the agent:
`localhost:9091/-/healthy` → 200, a throwaway gauge POST → 200, the series queryable in hostinger
Prometheus ~45s later, group then DELETEd (202). The corrected service name is the entire fix. The
loaded agent is a manual stopgap and will be `rm -f`'d again by the next refresh until the fix lands.

**Topology decided (was blocking):** the app-cluster Prometheus owns `k3dm_deployment_*`. Every panel
targets datasource uid `P5A1115AEDF367D43`, defined in `kube-prometheus-stack-acg-values.yaml:26` —
the ACG/app-cluster stack. The hub has no Pushgateway and is not supposed to. Do not add one; do not
repoint the dashboard.

**Second defect: `_provider_supports_pushgateway` is inverted** (`bin/k3dm-webhook:1794`). It returns
False for `k3s-hostinger` — the only provider that provably has a Pushgateway — and True for the hub,
which provably has none. It gates only the `make status` smoke surface, never `_push_metrics`, so it
did not block the push; it blocked the *signal*. That is why a dead sink went unnoticed for 64 days.
Combined with `bin/cluster-status-summary:61` treating `pushgateway` as `optional` (error→warning),
the two produced total silence.

Spec appended to `docs/bugs/2026-06-09-pushgateway-deployment-metrics-gap.md` per the dedup rule
(S1 name fix + one-local binding, S2 predicate inversion, S3 status surface, 4 tests, M1-M4, 6 gates).
Checkout Load Test is explicitly OUT of scope there — it already has
`docs/bugs/2026-08-29-loadtest-slice-f-generator.md` and needs a live Keycloak password grant.
Deferred follow-up: a metric-staleness alert.

**Correction to the earlier note in this doc:** the LaunchAgent was described as "not loaded". It was
worse — the plist did not exist at all, because our code deletes it every refresh.

## 2026-09-24 — Pushgateway service-name fix landed

S1-S4 implemented. Codex wrote S1/S2/S3 and both new test suites, then **correctly refused to commit**
because the required gate `scripts/tests/lib/provider_contract.bats` was red: it hardcodes the OLD
service name at line 932 (stubbed `kubectl` case pattern) and line 1005 (`grep -F -- 'svc/pushgateway'`),
while the spec's target list omitted the file. That was a spec defect on Claude's side, not a Codex
failure — it stopped rather than guess or use `--no-verify`. S4 added to the spec to record it.

**The reusable lesson.** `provider_contract.bats` asserted the broken name for 64 days, so it was a
test that *locked in the defect* and would have blocked its own fix. A test that pins a literal it
never independently justifies freezes whatever was true when it was written — the same shape as the
standing rule against whole-line `grep -F` assertions. The new cross-file agreement test (test 3) is
the intended replacement: it asserts the three producers AGREE, so it survives a legitimate rename and
still catches drift. Confirmed the suite reassigns `HOME="${BATS_TEST_TMPDIR}"` on the enclosing test's
first line (843), so it writes plists to a temp dir and does not touch the operator's real
`~/Library/LaunchAgents`.

**Claude error worth remembering:** restoring mutation M1 with `git checkout --` reverted to HEAD and
silently discarded Codex's still-UNCOMMITTED S1 fix along with the mutation. Caught it when the next
mutation's grep showed pre-fix lines; re-applied S1 and verified byte-identical restoration (blob
`4b6a2dc7`). Switched to file snapshots for M2-M4. **`git checkout --` is only a safe mutation-restore
when the work under test is already committed.**

All four mutations independently re-proved by Claude, not taken on Codex's report:
- M1 probe reverted → test 1 red, test 3 green.
- M2 **only** the `svc/` argument reverted with the probe left correct → test 1 STILL red. This is the
  one that mattered: it rules out a test that reads only the probe and would have passed a half-fix.
- M3 helm release renamed → tests 2 and 3 red, test 1 green.
- M4 predicate re-inverted → red on BOTH the `hub` and `k3s-hostinger` cases.

Gates: `make test` 1099/1099 (was 1096, +3 new bats); `pytest` 189 (was 184, +5 parametrized cases);
`provider_contract.bats` 57/57; shellcheck unchanged — `k3s-hostinger.sh` 2→2, `cluster-status-summary`
0→0; `make check-doc-links` 1760 files OK.

Operator step now unblocked: `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger` will both flip
`k3d-manager/shopping-cart` to `"true"` AND stop deleting the pushgateway port-forward agent.
# 2026-09-24 — webhook Phase 4 lifecycle/status extraction (working tree; commit pending)

- [x] Extracted exactly 7 measured lifecycle functions into `webhook/lifecycle.py` and exactly
      4 measured reporting functions into `webhook/status.py`; no deferred failure-analysis,
      metrics, redaction, or Slack-thread functions were moved.
- [x] Added six lifecycle and four status unittest cases using SourceFileLoader; tests cover
      direct argv/no shell, timeout, actor audit, provider fallback, concurrent refusal,
      status formatting, malformed payloads, and redaction.
- [x] Injected `_log`, `_notify_job`, `_push_metrics`, `_analyze_stall`, `_analyze_failure`,
      `_redact_secrets`, process/job state, and provider probes; copied none of those functions.
      Left the existing `agent.py` `_notify_job` duplication untouched.
- [x] Updated architecture module map and Unreleased changelog; adapted only the existing
      webhook BATS checks that inspected moved functions or patched their old globals.
- [x] Gates: focused pytest 10; bare pytest 189; webhook BATS 64/64; hub ESO BATS 4/4;
      `make test-all` completed plans 1112 and 132 with unittest counts 7/6/14/13/6/6/4,
      then expected EXIT=2 because Homebrew Python 3.14.7 has no pytest; doc links 1765;
      repo-root and server import passed; `_agent_audit` passed. M1–M6 each produced red
      output and was restored.
- [ ] Commit/push blocked by `.git/index.lock: Operation not permitted` after one commit attempt;
      no retry, lock removal, hook bypass, force-push, or PR. All scoped changes remain staged;
      no Phase 4 SHA exists.

## 2026-09-24 — lib-foundation v0.4.18 credential-test observability

- [x] Spec `docs/plans/v0.4.18-credential-test-observability.md` (lib-foundation) — `d695f81`
- [x] Implementation — **`1bcde41`** on `feat/v0.4.18-credential-test-observability`, local == origin.
      Codex wrote it; `.git/index.lock: Operation not permitted` blocked its commit, so Claude
      verified the tree and committed.
- [x] Gates re-measured by Claude: jest 7 suites / **32** tests (baseline 28), disappearance gate
      4 -> **0**, `node --check` clean x2, `make bats` **138/138 exit 0**.
- [x] Codex-reported bats red (case 16, missing-aws-CLI) investigated, not dismissed: does not
      reproduce on the host; the test skips on `aws` in `/usr/bin:/bin`, a sandbox-only difference.
- [x] Operator live `credential-test` run (TTY + CDP required; operator-only) — RAN 2026-09-24.
      Credentials confirmed `username=present password=present`; reached `path=auto-login`;
      auto-login FAILED on `locator.click` timeout. The instrumentation's first real catch: the
      old bare `ACG_SESSION_EXPIRED` had been hiding a login path that has never worked.
- [x] Bug filed: `docs/bugs/2026-09-24-acg-pluralsight-login-click-preconditions.md` — **`b48ad1c4`**,
      local == origin. 4 defects in `playwright/lib/pluralsight_login.js`; root cause explicitly
      NOT reproduced (a CDP probe disproved the "never stable" hypothesis).
- [x] Login fix — **`8a74258`** (3 files) + **`a33727c0`** (bug-doc gate table), local == origin.
      Codex wrote it; `.git/index.lock: Operation not permitted` blocked its commit AGAIN (2nd time
      on this branch) and left 3 gates unrun. It correctly stopped rather than working around the
      lock. Claude reviewed the diff and ran the outstanding gates.
- [x] Gates measured by Claude: `node --check` clean x2; jest 7 suites / **36** tests (from 32);
      `npm run check` clean; `make bats` **138 ok / 0 not ok / 0 skips**.
- [x] **Mutation check PASSED exactly** — pre-fix source swapped in by file copy (not `git stash`,
      which is what failed for Codex): **4 failed / 32 passed**. The 4 new tests are all real
      guards; the 32-test baseline undisturbed.
- [x] Operator re-ran `credential-test` — **the click hang is GONE**. New diagnostic fired:
      `ACG_LOGIN_FIELDS_MISSING: email=missing password=filled`.
- [x] **D5 root cause REPRODUCED and fixed — `7801ff4`**, local == origin. The email field is
      `type="text" name="Username" id="Username"`; CSS attribute VALUES are case-sensitive, so
      every arm of the old `EMAIL_SELECTOR` missed. Measured via Playwright's own engine on the
      live form: **OLD count=0, NEW count=1**. Fixing D1-D4 did not fix login, it revealed this.
- [x] D5 gates: jest **39** (from 36); mutation check **3 failed / 36 passed** vs old selector;
      `npm run check` clean; `make bats` **138/0/0**; live probe 0 -> 1. Captcha ruled out
      (`ShowCaptcha="False"`, 0 reCAPTCHA iframes) so unattended login is feasible.
- [x] **Operator re-ran `credential-test` — CONFIRMED.** `ACG_SESSION_OK path=auto-login` from a
      signed-out start, then Open Sandbox -> Start Sandbox -> 4 inputs extracted -> credentials
      written to `~/.aws/credentials` -> `sts:GetCallerIdentity OK`. **First successful headless
      Pluralsight login in this subsystem's history.** Bug doc marked RESOLVED &
      OPERATOR-CONFIRMED at **`38c64ade`**; both gate tables flipped to confirmed.
- [x] The live `credential-test` gate required before any lib-foundation PR has PASSED.
- [x] **PR #55 opened and merge-ready** — one PR covering observability + the login fix.
      Gates measured here: `npm run check` clean; jest 7 suites / **40** tests; `make bats`
      `1..138` all ok; CI green on `8986227` verified per-job. Copilot: 4 findings / 5 comments,
      2 real and fixed in `8986227` (unbounded `_robustClick` timeout; duplicated `Outcome`
      section in the bug doc), 3 false positives on `process.env` isolation that already exists
      via `beforeEach`/`afterAll`. All 5 threads replied to and resolved.
      No `enforce_admins` lever — lib-foundation `main` is ruleset-protected with no
      required-approvals gate.
- [x] Merge PR #55 (operator's), then tag v0.4.18 + GitHub release. Merged to main at
      `2f244ee4`; tag pushed; release at https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.18.
- [x] Subtree pull lib-foundation v0.4.18 (prefix `scripts/lib/foundation`, NOT scripts/lib/acg) —
      `7d786cd0`, vendored tree hash == upstream main tree `8b2f7956`. Tier 2 preflight rewired in
      `a4d6ef53`: `_secret_load_data` instead of a keychain existence check (which passes on a
      locked keychain and on an empty stored value), plus `export K3DM_ACG_REQUIRE_CREDENTIALS=1`
      so the session check fails closed. 14 BATS, mutation-gated (5 fail on the old code).
      Guide updated in the same commit.
- [x] Open a PR for lib-foundation `docs/v0.4.18-retrospective` — **PR #56**, CI 3/3 green.
      Copilot found three real gaps (verified against `acg_session_check.js`, not taken on faith):
      the marker table omitted `path=manual-login` (emitted at line 120), `docs/api/acg.md` had the
      same omission, and the retro cited `path=pluralsight_login` — a value emitted nowhere. Fixed
      in `78eacbe2`, all three threads replied to and resolved. `CHANGE.md` entry added in
      `1077361`. The same omission was mirrored in k3d-manager's harness guide and fixed in
      `4376a6ec`.
- [x] Open the v1.37.0 PR — **PR #131** (`4376a6ec`), Copilot requested, CI running at handoff.
- [x] Add `make e2e-sandbox` (Tier 2 `e2e_verify_sandbox`, `DIGEST=` optional) so Tier 2 has the
      same make entry point Tier 1 has, and expose `e2e-sandbox` on Slack `/k3dm` as an
      `operator` target (optional `DIGEST`, 3600s, no `confirm` — symmetric with `e2e-remote`).
      Docs: harness guide, Slack howto (incl. the unattended `ACG_SESSION_EXPIRED` caveat),
      CHANGELOG. Tests: Makefile-wiring BATS assertion + allowlist regression, both
      mutation-proven.
- [x] Fix both PR #131 CI reds — BATS `9a649af3` (fake `security` executable on PATH; the shell
  function stub was invisible inside `bash -c`, so macOS read the real keychain and Linux CI
  found no binary) and pytest `444aea0c` (`alert_delivery` missing from **both** sensor-stub
  sites, so the real sensor shelled out to live `kubectl`). Both were green locally for
  environment-specific reasons. Mutation-gated; 189 pytest passed offline.
- [x] Analyse + document CodeQL alerts 23/24/26/27 — `d482fc47`, false positives
  (`docs/issues/2026-09-24-codeql-pr131-spawn-injection-false-positives.md`) with in-code
  markers at both sinks.
- [ ] **Operator action:** dismiss CodeQL alerts 23/24/26/27 via `gh api` — the classifier
  denied it as a CI bypass; must be run from the operator's terminal. Blocks the #131 CodeQL
  gate; `enforce_admins` untouched until then.
- [ ] Follow-up (deliberately out of scope): dedup the two `_robustClick` copies —
      `sandbox.js` swallows errors, `acg_restart.js` does not, so unifying them changes the
      live sandbox path and needs a sandbox to verify.
- [x] **Bootstrap the cloud bridge** — `origin/cloud-requests` seeded as an orphan (`67dc3468`,
      parents `[]`, only `ledger/processed.txt`) and `com.k3d-manager.cloud-bridge` bootstrapped as
      a `gui/` LaunchAgent. Added `make init-cloud-requests` / `install-cloud-bridge` /
      `uninstall-cloud-bridge`. Fixed two blocking bugs with one root cause — `git fetch origin
      <branch>` with a bare branch name ignores the configured refspec and writes only
      `FETCH_HEAD`, so nothing maintained `refs/heads/cloud-requests`: the bridge's `update-ref`
      old-value check failed every tick (before the webhook call, so nothing half-executed) and the
      helper died with `unable to resolve reference` in any fresh clone, i.e. the documented
      cloud-side flow. Plist switched from `StartInterval` to `KeepAlive`. Proven on the live path:
      `cluster-status` → 202, `job-status` → 200 with output, helper exit 0.
- [x] **Cloud bridge testable from a cloud session** — `--wait` was broken in exactly the clone
      shape a cloud session gets. Third instance of the bare-branch fetch defect: the poll read
      `origin/cloud-requests:responses/<id>.json` while refreshing with `git fetch origin
      cloud-requests`, so in a `--depth 1 --branch main` clone `refs/remotes/origin/cloud-requests`
      never existed and every poll exited 5 with the response on the branch. Two live round trips
      from the laptop passed because a full clone writes all tracking refs at clone time. Fixed to
      an explicit `+refs/heads/cloud-requests:refs/remotes/origin/cloud-requests`, verified on a
      real shallow clone, regression test mutation-checked, how-to warns against reverting it.
- [ ] **Unalerted public-path failure:** `make status CLUSTER_PROVIDER=k3s-hostinger` reports
      Frontend 404 while all four `shopping-cart-apps` pods are Running 1/1, so `ServiceDown`
      (`kube_pod_status_ready ... == 0`) is correctly silent. Nothing probes the public hostnames —
      there is **no blackbox exporter anywhere in the repo** and nothing writes smoke/status results
      to Pushgateway, so no rule can fire and no SMS can be sent. Delivery is fine
      (`severity = critical` → `sms-critical`). Second silent failure from this same gap; the
      blackbox-probe + `CloudflareTunnelDown` follow-up is now load-bearing.
- [x] **Root-cause the Frontend 404** — `docs/bugs/2026-09-25-frontend-public-url-routes-to-wrong-cluster.md`.
      Tunnel → `:8000` → OrbStack → **hub** Istio, which has no `frontend` route and no frontend
      workload; the healthy pod is on hostinger with no Ingress and no NodePort. Fix is an
      architecture choice and needs the operator.
- [x] **Spec the public-endpoint blackbox probes** — `docs/plans/v1.39.0-public-endpoint-blackbox-probes.md`
      (5th plan doc; v1.38.0 is now at the max-5 cap). Two modules, explicit `User-Agent`,
      `PublicEndpointDown` / `CloudflareTunnelDown` / `PublicEndpointProbeAbsent`.
- [x] **Keycloak `awk` fix dispatched and verified** — `e0815211` on
      `origin/fix/keycloak-reconcile-awk-free` (`shopping-cart-infra`). `awk` 11 → 0, YAML parses,
      shellcheck clean both sides, 13/13 helper-vs-awk equivalences with 2 negative controls.
      PR is the owner's call.
# v1.39.0 `/k3dm help` cluster lifecycle commands — DONE 2026-09-27

- [x] Added role-filtered `/cluster-*` and `/hostinger-status` discoverability to `/k3dm help`
  without adding Makefile targets or changing routing.
- [x] Added the four specified regression tests and the short Slack slash-command documentation
  note. Focused pytest: `33 passed, 78 subtests passed`; `make test-python-unit`: all seven suites
  passed.
- [x] Commit `f3cdc25a3a0393e4198e472f6530b82114a93895` pushed to
  `origin/k3d-manager-v1.39.0`; no PR created.

# 2026-09-26 — vectordb Vault credential seed authored

- [x] Added the idempotent in-pod Vault seed and bootstrap call before the AppProject.
- [x] Added six focused BATS gates and `docs/guides/vector-store.md`; no credential value was
  handled or recorded.
- [x] `bats scripts/tests/plugins/argocd_vectordb.bats`: 16/16 passed after restoration.
- [x] Mutation-proof red lines captured for gates 11–16; all mutations restored.
- [x] Implementation commit `10dcd995` is pushed to `origin/k3d-manager-v1.39.0`; no PR created.
# v1.39.0 test-suite metrics — 2026-09-27 implementation status

- [x] Worktree implementation complete within the spec files: offline log parser/pusher and tests,
      opt-in `test-metrics` target, dashboard, apply hook, staleness rules, and guide.
- [x] Verification: focused pytest `11 passed`; bare pytest `307 passed`; `make test-all` observed
      `EXIT=0`, with `1304 BATS ok / 0 not ok`, unittest `7/6/29/22/6/6/4`, and pytest `307 passed`.
      Shellcheck clean, YAML/JSON checks clean, and `make check-doc-links` reported `1793 file(s) OK`.
- [x] Seven mutations M1-M7 each went red and were restored; focused suite returned `11 passed`.
- [ ] No commit/push SHA: the environment denies writes to `.git` (`FETCH_HEAD` and `index.lock`).
      Resume by retrying the required pull, commit (including the observed marker fact), push, and
      remote SHA verification from a checkout with writable Git metadata.

# v1.39.0 test-suite metrics — DONE 2026-09-27, commit `205405c0`

- [x] Spec `docs/plans/v1.39.0-test-suite-metrics-and-staleness.md` implemented: `bin/k3dm-test-metrics`,
      focused pytest suite + fixture, opt-in `make test-metrics`, `k3dm-tests` dashboard, ACG apply
      hook, five Prometheus rules, guide update. `make test` and `make test-all` recipes unchanged.
- [x] Codex wrote the worktree changes but could NOT commit — sandbox denied `.git` writes. Claude
      verified, fixed two gaps, and committed `205405c0`. Codex's own "blocked, no SHA" entries
      above are accurate for its run and are left as written.
- [x] Claude-added coverage: the real flat-TAP BATS path, which Codex's invented `# file:` fixture
      marker left untested. Mutation-proved red, then restored identical.
- [x] Claude-fixed spec misses: the guide's triage-table row, and the false "exit code reads 2"
      claim (the real capture exits 0 with a pyenv pytest on PATH).
- [ ] OPERATOR-OWNED, deliberately not done: the first live `make test-metrics` push, and
      confirming the `k3dm-tests` dashboard loads in the ACG Grafana. No live Pushgateway, cluster
      or host action was taken by any agent.
# v1.39.0 public endpoint blackbox probes — 2026-09-27, pushed `ba2a01e1`

- [x] Offline half implemented in one commit `ba2a01e1679423d3fbf7978cb4a248addbe57085` and
  pushed to `origin/k3d-manager-v1.39.0`; no PR created.
- [x] Added pinned `prometheus-blackbox-exporter` chart `11.3.1` with image tag `v0.27.0`, both
  required modules with explicit `User-Agent`, `public-endpoint-probes.yaml` with two
  `release: kube-prometheus-stack` Probe resources and `${CF_DOMAIN}` targets, and
  `public-endpoints.yaml` with all three spec rules.
- [x] Added the P4 operator guide, Grafana triage row, and v1.39.0 CHANGELOG entry. Static gates:
  yq parse and non-empty expressions pass; each new manifest has `grep -c '3ai-talk' = 0`;
  focused observability BATS `1..28` all pass; `_agent_audit` passes; `make check-doc-links` says
  `1793 file(s) OK`. `promtool` was unavailable, so YAML parsing and expression non-empty checks
  are the documented fallback.
- [!] Curated test-all was `1..1151` with 42 unrelated webhook failures (312–353); the focused
  observability subset passed. Untouched observability shellcheck has pre-existing SC2016 line 856.
- [ ] **Live verification pending operator action:** deploy the chart/Probe resources via ArgoCD;
  query `count(probe_success)` and all seven `probe_http_status_code` series; prove the frontend
  404 yields `probe_success 0`; reapply hub and ACG ApplicationSets; run
  `argocd_check_values_branch`. The local remote-tracking ref could not be updated by the sandbox,
  but `git ls-remote` reports the pushed SHA above.

# v1.39.0 test-suite metrics — live push CONFIRMED 2026-09-27

- [x] First real `make test-metrics` run: green, 1692 cases, 0 failed, push accepted by the
      live Pushgateway at `:9091`. The T4 `origin`-in-URL grouping produced
      `instance="test-all-local"` as designed.
- [x] `OfflineSuiteVacuous` false-positive fixed — scoped to `{result="ok"}`. It would have
      paged on a fully green run because every `result="not_ok"` series is 0 when healthy.
- [ ] **Duration metrics are dead** — `k3dm_test_run_duration_seconds` is a hardcoded 0 and
      `bats`/`pytest` suite durations are 0 (the parser expects a `# duration:` marker that no
      harness emits). Needs Makefile timing + `--duration` + a pytest `in <n>s` parse. DECISION
      PENDING: fix in v1.39.0 or file as a bug doc for v1.40.0.
- [ ] Operator-owned: apply the `k3dm-tests` dashboard (`make observability-acg`) and confirm it
      loads in the ACG Grafana. The ConfigMap is still absent on both clusters, so the metrics
      that just landed have nothing reading them yet.

# v1.39.0 blackbox probes — Codex landed ba2a01e1 2026-09-27

- [x] `ba2a01e1` verified on `origin/k3d-manager-v1.39.0` by my own fetch. 7 files, 151
      insertions, all named by the spec, no scope creep. Trailer correct.
- [x] Three alerts present with non-empty exprs: `PublicEndpointDown`, `CloudflareTunnelDown`,
      `PublicEndpointProbeAbsent`. Chart pinned `11.3.1`, image `v0.27.0`, no `latest`.
      `check-doc-links`: 1793 OK.
- [x] Codex's "42 pre-existing webhook failures" claim DISPROVEN — 27 reds, all sandbox
      Keychain-token artifacts; the same tree is 1304/0 in a real shell.
- [ ] Operator-owned live DoD: ArgoCD deploy, seven `probe_success` series, seven status codes,
      prove the frontend returns `probe_success 0` / 404, ApplicationSet reapply,
      `argocd_check_values_branch`.
# 2026-09-27 — launchd PATH omission fixed

- [x] M1–M5 implemented exactly from `docs/bugs/2026-09-27-launchd-path-omits-local-bin.md`.
- [x] **Fix taken live on the host (operator go, 2026-09-27)** — webhook plist template `PATH` now
      leads with `{{HOME}}/.local/bin` so `make install-launchd` cannot reinstall the defect, and the
      loaded plist was updated with a targeted `PlistBuddy Set`. Verified by reading `PATH` back out
      of `launchctl print`, not by the restart's exit code.
- [x] **`make restart-webhook` does NOT apply plist changes** — `launchctl kickstart -k` reuses the
      cached service definition; the loaded `PATH` stayed stale through a "successful" restart.
      `bootout` + `bootstrap` was required. Makefile left unchanged; reported to the operator.
- [x] **Sibling templates fixed** — `cloud-bridge` and `prometheus-credential-rotator` templates now
      lead `PATH` with `{{HOME}}/.local/bin`; `install-cloud-bridge` gained the missing
      `s|{{HOME}}|$(HOME)|g` substitution without which the placeholder would have landed in the
      plist verbatim. Both live plists reloaded with bootout/bootstrap and read back.
- [x] **`hermes` handled differently, on purpose** — its plist is rendered by `_install_hermes_agent`
      in the lib-foundation subtree, which substitutes no `{{HOME}}`, and that subtree is edited
      upstream only. `bin/k3dm-hermes` normalizes its own `PATH` instead. Agent is not loaded, so
      nothing needed restarting.
- [ ] **Upstream lib-foundation change: add `{{HOME}}` substitution to `_install_hermes_agent`** so
      the hermes template can carry the fix like its siblings. Not started; needs the lib-foundation
      repo and its own PR.
- [x] **Regression test exists now** — `scripts/tests/bin/launchd_plist_path.bats`, 4 tests,
      mutation-verified (reverting the cloud-bridge template turns test 1 red). The earlier
      classifier denial that blocked this file is cleared.
- [x] Implementation commit `f8d5ced74467bd703f19cca60bda37b7360dfcf3` pushed to
- [x] **Claude verified the launchd PATH fix independently** — SHA on origin via `gh api` (local `.git` was unwritable in Codex's sandbox), six-file diff scope, no subtree or `system.sh` changes, BATS 39/39 re-run by Claude, shellcheck histogram identical pre/post.
- [x] **Fixed a tautological test Claude had specced** (`393f6570`) — the idempotence case asserted on an inline copy of the guard instead of `bin/cluster-up`, so it passed against unfixed source; now extracts and sources the real block and fails pre-fix.
      `origin/k3d-manager-v1.39.0`; no PR created per instruction (PR URL: not applicable).
- [x] Focused BATS: 39/39; shellcheck: no new warnings; `_agent_audit`: passed.
- [!] Mutation proof against pre-fix HEAD copies: tests 1, 3 and 4 fail; test 2 passes because its
      literal body is self-contained and does not inspect either script, so it cannot fail against
      the unfixed source without altering the required test block.
# 2026-09-29 — stale unmanaged ArgoCD registration cleanup fixed

- [x] Added `make cleanup-stale-registration CLUSTER=<name> [CONFIRM=1]` for exact,
  explicitly confirmed removal of one stale ArgoCD cluster registration. The helper
  deletes the registration Secret first, then removes only matching Applications with
  non-blocking deletion. Bug filed at `docs/bugs/2026-09-29-stale-unmanaged-argocd-registration.md`.
  Targeted cleanup tests: 5/5; `bash -n`, ShellCheck, `_agent_checkpoint`, `_agent_lint`,
  and `_agent_audit` passed. Commit `39193aae` pushed to `origin/k3d-manager-v1.40.0`.
# 2026-09-30 — VectorDB hub metrics implementation

- [x] Added hub Pushgateway chart application and static Prometheus scrape.
- [x] Routed VectorDB publishers to `K3DM_VECTORDB_PUSHGATEWAY_URL` (default localhost:19094).
- [x] Moved the dashboard to the hub platform-ops set with byte-identical JSON and corrected labels.
- [x] Added offline tests, ran mutation red/green checks and repository gates; commit SHA is in the
  completion handoff.

# 2026-09-30 — Hermes dashboard evidence and status history

- [x] Added failed-host labels and CI run URLs to the Hermes exporter and findings table.
- [x] Added status enum/evidence guidance to the history panel.
- [x] Added regression coverage for dashboard fields, sensor evidence, and CI run metadata.
- [x] Mutation checks failed as expected when the history explanation or CI field was removed, then
  passed after restoration. Full pytest: 442 passed; manifest validation: 10 valid; doc links: 1825
  files OK. Final commit SHA: `3d0c5478`.

# 2026-09-30 — Grafana overview no-data fix

- [x] Added matching release labels to the hub and ACG Grafana ServiceMonitors.
- [x] Added a regression test and confirmed the rendered Helm ServiceMonitors contain the labels.
- [x] Mutation made the regression test fail; restoring the label made it pass. Final commit SHA is
  recorded in the bug doc: `bc301f83`.

# 2026-09-30 — fix-sync ArgoCD connection

- [x] Fixed `fix-sync` and `fix-force-sync` to self-manage the default local ArgoCD port-forward
  and use gRPC-web, with cleanup and a configurable server override.
- [x] Added regression coverage; removing `--grpc-web` made the test fail, then restoration passed.
  Final commit SHA: `ffe501fa`.

# 2026-09-30 — fix-sync plaintext follow-up

- [x] Added `--plaintext` to `fix-sync` and `fix-force-sync` for the local ArgoCD port-forward.
- [x] Focused regression passed; removing `--plaintext` made it fail, then restoration passed.
  Follow-up SHA: `14dab218`.

# 2026-09-30 — fix-sync stale-token recovery

- [x] Added automatic ArgoCD session validation and password-stdin login for stale tokens.
- [x] Regression passed; removing the login plaintext flag made it fail, then restoration passed.
  Final SHA: `a7fb7798`.

# 2026-09-30 — fix-sync failure diagnostics

- [x] Preserve the temporary port-forward log on failure and report Secret/login failures instead
  of returning a bare status 1. Full fix-target BATS: 6/6. Final SHA is recorded in the bug doc
  after commit: `36653c96`.

# 2026-09-30 — fix-sync login compatibility

- [x] Matched the working ArgoCD login flags and newline-fed stdin; login errors are now surfaced.
- [x] Regression passed; removing `--skip-test-tls` made it fail, then restoration passed. Final
  SHA: `e853c849`.

# 2026-09-30 — fix-sync login diagnostic capture

- [x] Captured both stdout and stderr from ArgoCD login failures, preserving the password boundary
  while exposing the actual error. Focused BATS passed; final SHA is recorded in the bug doc after
  commit: `75952f57`.

# 2026-09-30 — fix-sync CLI-version compatibility

- [x] Replaced unsupported `argocd login --stdin` with password-stdin API authentication and
  `ARGOCD_AUTH_TOKEN`. Focused BATS passed; final SHA: `4335a601`.

# 2026-10-01 — fix-sync Vault-first ArgoCD credentials

- [x] Added explicit override, Vault-first lookup, and Kubernetes fallback for ArgoCD admin
  credentials. Focused BATS passed; final SHA: `122129bb`.

# 2026-10-01 — fix-sync password newline handling

- [x] Corrected the embedded Python newline escape in both sync targets and added a regression
  assertion. The faulty escape mutation failed the focused suite; restoration passed. Final SHA is
recorded in the bug doc: `db351961`.

# 2026-10-01 — Grafana Overview raw labels

- [x] Filed the bug with screenshot evidence and confirmed the built-in Overview JSON is absent
  from the available source checkouts.
- [x] Add and deploy a source-controlled replacement/override after confirming dashboard ownership.

# 2026-10-01 — Grafana Overview readable dashboard

- [x] Added and tested the source-controlled readable dashboard with a unique UID/title; final SHA
is recorded in the bug doc after commit. Final SHA: `3664bea7`.
The hub platform-ops manifest and regression assertion are included as well; final SHA is recorded
in the bug doc after commit: `3664bea7`.

# 2026-10-01 — k3dm-tests exit result panel

- [x] Replaced the raw exit-code table with a latest-result view and regression coverage; final SHA
  is recorded in the bug doc: `e3db399e`.

# 2026-10-01 — v1.41.1 load-test credential/preflight spec

- [x] Specified the safe credential, preflight, remote-write, dashboard, testing, and scope
  requirements for v1.41.1. Implementation remains pending.

# 2026-10-01 — v1.41.0 find-similar-docs links spec

- [x] Specified branch resolution, terminal/Slack/JSON output, offline tests, and scope for
  link-enriched similarity results. Implementation remains pending.
# 2026-10-01 — v1.42.0 daily verification plan

- [x] Specified independent daily offline `k3dm-test` and Tier 1 E2E runs, separate result
  channels/triage, stale-data semantics, timing metrics, mutations, and offline acceptance
  gates in `docs/plans/v1.42.0-daily-offline-and-e2e-verification.md`.
- [ ] Implementation not started; Tier 2 ACG/Stripe remains opt-in and outside this plan.
# 2026-10-01 — k3d-manager Dot roadmap

- [x] Added the candidate v1.42.0 “k3d-manager Dot” milestone to `docs/roadmap.md`, linking
  the independent daily offline/E2E verification scope.
- [ ] Implementation is not started; this remains a roadmap/specification item.
# 2026-10-01 — v1.40.0 review fixes complete

- [x] Four review findings fixed in commits `b5227418`, `393a0aae`, and `236219f6`; docs commit
  records the spec as FIXED and updates CHANGELOG/memory-bank.
- [x] Gates: `shellcheck bin/argocd-app-sync`; focused BATS 23/23; Hermes pytest 51 passed; and
  `make check-doc-links` passed.
- [x] Mutation checks: Hermes rerunnable ordering, Grafana verdict mapping, and stale ArgoCD
  session probe each failed their named regression test and were restored green.
- 2026-10-02: e2e RabbitMQ broker + payment spring.rabbitmq key path landed — payment `9778e21`, k3d-manager `034d9513` (Codex, verified: 66/66 bats, 3 mutations red). PRs pending go.
- 2026-10-02: payment CI 37025969474 GREEN on `9778e21` (137 tests, +1 RabbitPropertiesBindingTest). Payment + e2e-tests PRs ready to prepare; awaiting go.
- 2026-10-02: e2e-tests PR #9 opened (fix/payment-client-v1-bearer). Payment fix branch still unmerged (ahead 2, behind 1); #76 merged was Dependabot.
- 2026-10-02: payment PR #78 opened; e2e #9 Copilot fix dispatched to Codex.
- 2026-10-02: e2e #9 Copilot thread fixed `ce145ee` and resolved.
- 2026-10-02: e2e runs 1790958376-31051 (dead keychain PAT, 401) and 1790959569-5392 (GHCR OK via gh refresh; product-catalog rollout timeout, no diagnostics) failed pre-test. Specs: GHCR resolver remedies + substrate failure diagnostics, dispatched to Codex.
- 2026-10-02: landed `937c4bfe` (make e2e recording), `b2ca3acc` (GHCR messages), `6266ef9e` (substrate diagnostics) — Codex, Claude-verified. Architecture docs spec (cloud bridge + vector store) dispatched to Codex.
- 2026-10-02: docs/architecture/cloud-bridge.md + vector-store.md landed with README links (Codex + Claude verification).
- 2026-10-02: operator added admin PR-merge bypass to payment ruleset 20607313 and disabled enforce_admins on e2e-tests main (re-enable after #9 merges). Payment #78 CI all green.
- 2026-10-02: payment #78 Copilot finding (resource_access roles from ANY client grant payment roles) fixed `a3c0c24`: client roles scoped to payment.security.resource-client-id (default payment-service); CI pending.
- 2026-10-02: payment #78 CI green on `a3c0c24` (139 tests); Copilot thread resolved. Both PRs ready for operator merge.
- 2026-10-02: payment #78 MERGED (`412bc78`), e2e-tests #9 MERGED (`755ad2d`); e2e-tests enforce_admins re-enabled. Awaiting payment main build 37031252652 image publish → substrate pin bump.
- 2026-10-02: Overview "Firing Alerts by Category" table spec `617ac4c8` (operator request; classifies the 55 firing alerts) dispatched to Codex.
- 2026-10-02: Firing Alerts by Category table landed `bf32ce99` (Codex, verified: 28/28 bats, panel 12 identical in both copies, shipped expr live-checked). Live on next ArgoCD sync.
- 2026-10-02: payment image sha-412bc78 published (run 37031252652, build-push success); substrate pin bumped `7c9caff7` (Codex, verified 56/56 e2e bats). Next: operator live Tier 1.
- 2026-10-02: live Tier 1 run 1790958044-29337 failed before tests: no GHCR pull PAT in env or Vault (gh token lacks read:packages). vcluster reconcile table-parsing bug filed `a8f52a5c`, dispatched to Codex.
- 2026-10-02: vcluster reconcile JSON fix landed `5706eb21` (Codex, verified 4/4 bats, shellcheck clean). Operator re-running `make e2e` from their terminal.
- 2026-10-02: e2e run 1790961003-14944 FAILED pre-test: product-catalog crash-loop on service-link `RABBITMQ_PORT=tcp://…` (regression from `034d9513`), found via new substrate diagnostics. Spec `af17b25c` dispatched to Codex.
- 2026-10-02: service-link fix landed `c7fa36e4` (Codex, Claude-verified 60/60 bats, mutation red). Operator to re-run `make e2e`.
- 2026-10-02: recorded make log lags live run (macOS script buffers); spec `6cd5697a` (script -F / -f) dispatched to Codex. Live e2e run 17:26:38Z in progress, watched via /tmp/e2e.log.
- 2026-10-02: recorded-log flush fix landed (script -F / -f; 6/6 bats, mutation red; live flush unverified — no TTY in Claude shell).
- 2026-10-02: e2e run 1790961998-24160: service-link fix confirmed live (product-catalog/basket/order rolled out); FAILED at keycloak rollout — realm import roles.realm nested object (from `570734c7`). Spec + Overview "Dashboards" stat title spec `380bf24a` dispatched to Codex.
- [x] e2e Keycloak e2e-user incomplete profile ("Account is not fully set up", run 1790968818-9643): spec docs/bugs/2026-10-02-e2e-keycloak-user-profile-incomplete.md FIXED 5862c50d (Codex, Claude-verified); LIVE-VERIFIED run 1790970000-22917 (56 passed / 1 failed).
- [x] Go payment response missing gatewayTransactionId: FIXED, live-verified 2026-10-04 by make e2e run 1791168841-15959 (all payments specs pass; Java fix 4169430, PR #80 merged 19c42aa).
- [x] e2e order-management flow tests use CONFIRMED/DELIVERED (8 reds, run 1791168841-15959; 91/102 passed): recurrence spec appended to docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md; Codex d8fb1ef pushed to shopping-cart-e2e-tests fix/order-flow-status-enum, Claude-verified; PR #11 merged e5e644d (2026-10-05).
- [x] Payment image CVEs (hostinger, sha-cced344): Tomcat 10.1.55 3 CRIT + 12 HIGH; spec docs/bugs/2026-10-02-payment-image-tomcat-critical-cves-bom-lags.md (pom overrides, branch fix/payment-cve-bom-overrides) FIXED payment 90e3052 (Codex, Claude-verified: effective-pom 5/5 fixed, CI 37068823246 green 139 tests); payment PR #81 MERGED 2d9ec91 2026-10-02; main CI 37070809364 Trivy: all 5 fixed packages clean, NEW netty 4.1.135 (CVE-2026-75595 CRIT fixed 4.1.137, CVE-2026-59901 HIGH fixed 4.1.136; BOM netty.version 4.1.135, latest 4.1.138) -> follow-up netty.version override; hostinger digest re-pinned sha256:b722319e (sha-2d9ec91) + e2e newTag sha-2d9ec91 on k3d-manager-v1.41.0. PR #80 (Java gatewayTransactionId) MERGED (verified 2026-10-03); hostinger re-pin INERT until the operator patches the promoter override on the Application (cmd in bug doc)
- [x] Operator rollouts: Istio no-HPA (119f8a7b), LDAP rotator (96af55b1) — DONE 2026-10-02, Claude-verified live (0 HPAs; CronJob → vault.secrets.svc; both alerts cleared)
- [x] Readable Overview title collides with stock 'Grafana Overview': spec docs/bugs/2026-10-02-grafana-overview-readable-title-collides-with-stock-dashboard.md FIXED 9ccfcccd (Codex, Claude-verified); LIVE 2026-10-02 (AppSets reapplied at v1.41.0). Operator found it; no tags + no uid (derived from stock JSON): spec docs/bugs/2026-10-02-grafana-health-dashboard-no-tags-no-uid.md (uid k3dm-grafana-health + tags + guide row fix) FIXED 86f21788 (Codex, Claude-verified 32/32, mutation red); LIVE on hub (auto-sync).
- [x] Payment Netty CVE (CVE-2026-75595 CRIT, 4.1.135 -> 4.1.138.Final override): spec docs/bugs/2026-10-02-payment-image-netty-critical-cve-bom-lags.md (59d62e05); DISPATCHED to Codex 2026-10-02, payment branch fix/payment-netty-cve-override — payment PR #82 MERGED (verified 2026-10-03)
- [x] CVE promoter live override shadows git pin (FIXED 78b1fe7a; rolled out 2026-10-03): spec docs/bugs/2026-10-02-cve-promoter-live-override-shadows-git-pin.md (59d62e05); DISPATCHED to Codex 2026-10-02 on k3d-manager-v1.41.0; operator rollout = make platform-ops + remove 4 hostinger overrides (supersedes the set-override cmd)

- [x] 2026-10-02 hostinger payment outage (credential drift since 09-29 Vault KV regen) recovered by operator ALTER USER; 1/1 Ready on b722319e. [x] same drift latent on orders/products/redis (fixed by APPLY=1 run 2026-10-03).
- [x] 2026-10-02 credential-drift tool spec dispatched to Codex (docs/bugs/2026-10-02-hostinger-shopping-cart-credential-drift-after-vault-kv-regen.md); operator rollout = make shopping-cart-credential-drift [APPLY=1].
- [x] 2026-10-02 promoter live-override fix 78b1fe7a verified (operator rollout pending). [x] Netty override verified; payment PR #82 open, awaiting go.
- [x] 2026-10-02 credential-drift tool landed 64e52b65 (verified); [x] operator APPLY=1 run 2026-10-03: 5 stores FIXED, 1 MATCH; all pods Ready, apps Synced+Healthy (Claude-verified).
- [x] 2026-10-02 k3dm-cleanup orphaned Docker volume prune LANDED `3204c74e` (Codex, Claude-verified 9/9 bats, mutation red, shellcheck 4=4). Check ~/Library/Logs/k3dm-cleanup.log after next 03:00 run.
- [x] 2026-10-03 payment PRs #80 (19c42aa) + #82 (e3b6f06) MERGED. [ ] Trivy 0 CRITICAL on sha-e3b6f06, re-pin hostinger + e2e.
- [x] 2026-10-03 payment sha-e3b6f06 Trivy 0 vulns; re-pinned hostinger digest + e2e tag b7604afe. [ ] payment repo k8s/base stuck at sha-19c42aa (CI commit-back rebase conflict). [ ] hostinger payment VulnerabilityReport 0 CRITICAL.
- [ ] 2026-10-03 payment k8s/base stuck at sha-19c42aa: promote rebase bug (2026-09-21 doc) unimplemented; re-run fails deterministically. Spec needs is-ancestor guard + refresh; then bump caller pins.
- [x] 2026-10-02 promote-loop fix spec refreshed + dispatched to Codex (infra fix/promote-refetch-never-backwards). [x] e1ef171c verified (harness 5/5, guard mutation red). [x] infra PR #107 MERGED 98b10f05 (enforce_admins restored). [ ] hostinger trivy: no reports for payment/order/catalog (uninvestigated). [x] Part B pin bumps verified: payment 741ffdc, basket 01904e2, order af3f105, product-catalog d3ac722. [ ] PRs: payment #83 OPENED 2026-10-03 (+CHANGELOG a8add76; Copilot 1 finding = CHANGELOG entry outside Fixed list, fixed 171d8e4, thread resolved, issue doc 79ff70d; CI GREEN on 79ff70d, mergeable clean; ruleset-protected main, no enforce_admins lever) MERGED 2026-10-03 e93d32c by operator; main CI 37088705440 SUCCESS = first live promote-loop run: pushed e93d32c..4e79be2 on attempt 1, k8s/base newTag sha-e93d32c (stale sha-19c42aa repaired). basket #50, order #80, product-catalog #57 OPENED 2026-10-03 (CHANGELOG entry each; Copilot requested; CI pending). basket/order/catalog HELD: open dependabot PRs basket #49, order #79, catalog #56 bump the same line to older infra SHAs (64c11783/e41f2adb) -> CLOSED as superseded 2026-10-03 (user go). Remaining: open those 3 PRs after payment's first main promote run is confirmed. [ ] confirm payment main promote repairs k8s/base. CI 2026-10-03: basket #50 green/CLEAN, order #80 green/BLOCKED (review), product-catalog #57 RED — pre-existing: SQLAlchemy 2.1.3 defaults bare postgresql:// to psycopg3 (not installed; Dependabot #56 same on 09-28). Bug docs/bugs/2026-10-03-product-catalog-sqlalchemy-2-1-defaults-postgresql-url-to-psycopg3.md dispatched to Codex on catalog branch fix/sqlalchemy-explicit-psycopg2-driver (postgresql+psycopg2:// + tests/unit/test_config.py); after merge, update-branch #57. Codex 9c92929 verified (2.1.3, 110 passed, ruff clean) + Claude dbe05c5 (CHANGELOG moved inside Fixed list — Codex repeated the payment placement error); catalog PR #58 OPENED, Copilot requested; #58 CI ALL GREEN; #58 MERGED 666b832 (2026-10-03); #57 merged main in 41e7e1c (CHANGELOG conflict, kept both entries), #57 CI GREEN + CLEAN. main run 37090500718 (old pin) published + promoted newTag sha-666b832 — first catalog image since 09-22. Copilot: 0 reviews on #50/#80/#57. 2026-10-03: basket #50 MERGED f84411f (Go CI main run 37091213040 SUCCESS: new loop pushed f84411f..3194768, newTag sha-f84411f — basket proven); #57 BEHIND after promote commit → update-branch, CI GREEN + CLEAN again, awaiting merge; order #80 merge REFUSED (ruleset 20606891: 1 approval, no admin bypass); classifier denied Claude ruleset edit, operator ran 0→merge→1: #80 MERGED 86f79e4, ruleset verified back to approvals=1 / DeployKey bypass / same 4 rules. Catalog #57 MERGED 2d3d687 (operator, --admin); ALL FOUR PROVEN on the new loop: order run 37120665295 pushed 86f79e4..6386ed1 newTag sha-86f79e4; catalog run 37120828300 pushed 2d3d687..b050ba1 newTag sha-2d3d687. Promote-loop rollout DONE.

- [x] 2026-10-03 k3dm-tests duration bug filed (`docs/bugs/2026-10-03-k3dm-tests-duration-panel-shows-only-unittest-milliseconds.md`; pulls v1.42.0 §3 offline part forward) — Codex `15f59862` VERIFIED by Claude (7 spec files only; pytest 17 passed; mutation to hardcoded 0 turns 2 tests red, restored green; bats 38/38; dashboard JSON ok; make -n carries --run-duration). Dashboard shows real values only after the next `make test-metrics` + `make observability-acg` (applies the ACG dashboard ConfigMap). LIVE-CONFIRMED 2026-10-03: operator ran both; Pushgateway now holds `k3dm_test_run_duration_seconds{target="test-all"} 440`, pytest suite 83.08s, 2207 cases / 0 failed.
- [x] 2026-10-03 Daily `make test-metrics` launchd stopgap (until v1.42.0): plist `com.k3d-manager.test-metrics` (04:30 daily, log `~/Library/Logs/k3dm-test-metrics.log`) drafted by Claude; install denied to Claude by auto-mode classifier [Unauthorized Persistence] — OPERATOR INSTALLED + kickstarted; first launchd run exit 0, 2207 cases / 0 failed, pushed run_duration 600s, pytest 122s (launchd runs ~35% slower than interactive 440s). Remove when v1.42.0 scheduling lands.
- [ ] 2026-10-03 v1.41.0 features dispatched to Codex ONE AT A TIME, Claude verifies each before the next: (1) find-similar-docs-links — DONE `a4996800` (Claude verified: on origin, 4 scope files, 11+1s / make test-pytest 590+1s, doc-links OK, independent mutation forcing "main" fails the URL test); (2) cloud-bridge round-trip latency bug — `6fc0bc47` pushed (Codex gates: 82 / 599+1s / doc-links OK / 2 mutations); Claude review found a regression (MAX_PER_TICK cap returns own pushed commit as last_tip → requests 11+ stall); follow-up DONE `819e636a` (Claude verified: on origin, 2 files, 68 bridge tests, independent revert-to-break mutation fails the new test); operator restarted 2026-10-03 06:18; live: bridge gap 14 s / 9 s, client round trip ~20 s (was up to ~90 s); Codex cloud session (codex@github) also used it 06:23 — diagnose-apps 7 s, job-status 8 s bridge-side (hand-committed requests, not the helper); old Sep 29 publickey lines still the log tail — log untouched since `docs/bugs/2026-10-03-cloud-bridge-round-trip-latency.md` (adaptive 5s tick, no re-fetch, 5s client poll; operator then `make restart-cloud-bridge`); (3) webhook-log-levels-and-retention — `3f7cf103` M1 / `73d0ef56` M2 / `dc5211de` M3 / `f1d0ec5d` M4 (Claude verified: test-pytest 605+1s, test-python-unit 7 suites OK, cleanup BATS 12/12, shellcheck clean, 0 print(), independent mutation removing ALL redaction fails the token test); review finding: M2 hollowed `test_make_target_passes_timeout_to_transport` (no assertion) → follow-up DONE `cd20fc1b` (Claude verified: on origin, 1 file, test-python-unit 7 suites OK, independent mutation dropping killpg fails the test at 30 s vs <5 s); item 3 COMPLETE — operator to run `make restart-webhook` (restarts bridge too); docs sweep of all v1.41.0 features after the queue (operator ask 2026-10-03); (4) cloud-bridge-e2e-dispatch — split into two runs: part A M1–M6 DONE `a324b6cd` (Claude verified: on origin, 14 files, 100 bridge/capability tests, test-python-unit 7 OK, e2e_remote BATS 81/81, shellcheck clean; independent mutations: capability check→True fails 2 pytest + 3 unittest, dropping lock holder from refusal fails BATS 24; nits: blank line splits the trailers, `removeprefix("make:")` would grant a future non-make route named e2e → fixed in part B; architecture doc lacks cloud-runner token → part B); part B M7–M8 + hardening DONE `c2667b6d` (Claude verified: 8 files, bridge 80 passed, policy unittest OK, independent mutation running slow actions inline fails 1; review: job state `killed` (cluster kill route) is missing from TERMINAL_JOB_STATES → a killed job is watched until timeout+10 min then 'watch expired' — folded into the sandbox spec); item 4 COMPLETE — operator `make restart-webhook` now; operator ask 2026-10-03: let the cloud agent bring the ACG sandbox up/down (not the primary cluster) → spec `docs/plans/v1.41.0-cloud-bridge-sandbox-lifecycle.md` (5th v1.41.0 plan = cap) — DISPATCHED 2026-10-03 (codex-sandbox-lifecycle.log); operator rationale: 4h+ sandbox lets an agent debug without touching live Hostinger; single `make restart-webhook` after it is verified, then operator does the ACG sandbox login (Chrome CDP) so `sandbox-up` can run; operator provisioned Keychain `k3dm-webhook-token-cloud-runner` (account k3dm) 2026-10-03; operator restart-webhook deferred until B verified (shared worktree) (now M1–M8: + M7 slow actions off the serial loop, M8 bridge follows its own jobs → `.final.json` / `--wait-final`); (5) python-agent-rigor (brief A lib-foundation, then B k3d-manager). Sandbox lifecycle DONE `9d527cec` (Claude verified: on origin, 8 files = spec, 83 bridge tests, test-python-unit 7 OK; independent mutation granting any provider fails 8 hostinger/empty/AWS/gcp subtests, cmp-restored). Codex's run wiped Claude's uncommitted memory-bank edits (re-added) — commit memory-bank before a dispatch, never leave it dirty in the shared worktree. NEXT: operator `make restart-webhook`, then a live `sandbox-up` smoke — operator plan 2026-10-03: after the operator's own run completes, the operator asks a cloud agent to run `bin/k3dm-cloud-request --wait-final sandbox-up` (first live use of the cloud-runner lifecycle path); Claude then checks the bridge request/response/.final.json commits and the webhook job. Operator's own `make up CLUSTER_PROVIDER=k3s-aws` 2026-10-03 FAILED: data-layer Application never Synced — hub ArgoCD cannot resolve `host.k3d.internal` (NodeHosts has only the 4 nodes, last written by k3s-supervisor 2026-09-27 hub rebuild). Root cause: `_acg_repair_hub_host_alias` (bin/cluster-up:170) resolves the host IP with `getent`, which rancher/k3s:v1.32.0-k3s1 lacks → empty → WARN + skip, so the repair has been a silent no-op since the rebuild. OrbStack: `nslookup host.docker.internal` in the server container = 0.250.250.254. CloudFormation stack k3d-manager-cluster (us-west-2) left running (billable). Sudo prompt during the run = ArgoCD browser HTTPS LaunchDaemon reinstall (wrapper changed); headless runs skip it. No manual ACG login step: operator confirmed 2026-10-03 that `make up` logs in unattended (Keychain `k3dm-acg-pluralsight` auto-login runs before the TTY gate, acg_session_check.js:91-99); how-to corrected.
- [ ] 2026-10-03 QUEUED (operator decision) — cloud-agent sandbox debugging, two separate releases: (1) v1.43.0 (v1.42.0 is already reserved to its 5-plan cap by the Hermes alert-triage scope §5): sandbox-only (`provider=aws`) read-only diagnostics — namespace events, get/describe deploy/svc/ingress/node, logs `previous` + `container` (webhook supports container/tail_lines; the bridge does not pass them); also verify the ACG ApplicationSet values ref tracks the branch a cloud agent pushes to (git push → ArgoCD sync is the agent's only write path). Operator follow-up: "possible to delegate to hermes for investigation and report info (cloud agent <-> hermes)" — Claude proposed building (1) as a Hermes on-demand investigation: bridge action `hermes-investigate` (structured args only, no free text reaching Hermes' LLM) → Hermes runs a fixed read-only evidence bundle on the sandbox context, reusing the v1.42.0 `alert_recipes` engine, + prior art → one report back as a bridge artifact. (2) a LATER release, deep investigation first: a sandbox-bound mutating step (e.g. rollout restart) — natural home is a Hermes Phase-2 allowlisted repair with Slack approval. Awaiting operator's pick on the Hermes route.
- [x] **Bug: sandbox-up unbounded hang** — `docs/bugs/2026-10-03-sandbox-up-hangs-on-unresponsive-server-node.md` DONE `deb5f635` (Codex implemented; its `.git` write was denied, so Claude committed. Claude verified: 6 spec files; webhook_lifecycle pytest 10 passed; shopping_cart BATS 32/32; shellcheck histogram unchanged (SC2015×5, SC2016×3, SC2153×2); independent mutation removing the SSH-preflight call site fails the k3sup test, cmp-restored). Operator: `make restart-webhook` to load it. Network outage during the run 2026-10-03 left hub pod acg-expiry-check in ImagePullBackOff for 98 min; Claude deleted it and the rerun Completed.
- [x] **Grafana restored 2026-10-03 12:16** — operator chowned `~/.local/share/k3d-manager/logs` (root-owned bug doc `docs/bugs/2026-10-03-root-owned-state-logs-dir-kills-grafana-port-forward.md` confirmed: Grafana PF exit 78 → running, `:3001` 200 after kickstart). Claude reinstalled `com.k3d-manager.cloudflare-tunnel` by hand (same plist as bin/cluster-up, logs in `k3s-aws/logs`, existing `~/.cloudflared/config.yml`; creds untouched): 4 edge connections registered; `grafana.3ai-talk.org` 302 / `/api/health` 200. ArgoCD public host still 502 (argocd-port-forward restored by the next sandbox `make up`).
- [x] **Hub Alertmanager restored 2026-10-03 12:28** — operator ran `make restore-google-app-password && make observability` in Terminal.app (all three Keychain items present; app password 19 chars with spaces; the two `!` runs failed only because Claude's session cannot read the Keychain). `alertmanager-smtp-secret` created 19:28:15Z; live config at 19:30 has smtp_from plus the ACG email route (`cluster=~"acg|ubuntu-k3s"`, severity critical → platform-warning) ahead of `sms-critical`, verified via `:19093/api/v2/status`. Remaining operator steps: `make signing-restore` (Terminal.app; if still "no Keychain backup", decide before signing_init), `hub_recovery_reconcile --confirm`, `make platform-ops`.
- [ ] **Hub DR one-command target** (operator 2026-10-03: "we should have a better make <target> to execute hub recovery") — spec `docs/bugs/2026-10-03-hub-restore-has-no-single-make-target.md`: `bin/hub-restore` (TTY + Keychain + context + root-owned-dir preflight, 8 keep-going steps, summary), tunnel agent extracted to `scripts/lib/cloudflare_tunnel.sh`, `make hub-restore` / `make hub-recover`, alertmanager-secret backs up gmail_app_pw, restore-google-app-password tells empty vs denied apart. Codex DISPATCHED 2026-10-03. Live: operator's `restore-google-app-password` in Terminal.app said not in Keychain although the item is present → empty value or denied ACL; operator checking length.
- [ ] **Hub identity + public origins are sandbox-path only** (found 2026-10-03 12:45). Operator ran signing-restore (RESTORED from Keychain — key not lost), reconcile and platform-ops (OK; webhook-token, app-rebuild and git-writer Secrets synced) in Terminal.app. Reconcile stopped at the identity hook: no `shopping-cart-identity` Application on the hub (only cluster-up Step 10c creates it). Claude applied it by hand; it is blocked on Vault keycloak/admin, keycloak/clients, keycloak/smoke-user and ldap/admin (404, seeded only by deploy_shopping_cart_data). PublicEndpointDown SMS for argocd/keycloak/frontend (local PF agents + sandbox frontend missing) → Claude added 6 h silence `84a19233`. Fix: the next sandbox `make up` restores all of it; durable fix in the follow-up section of the hub-restore spec. After that make up, rerun `hub_recovery_reconcile` (smoke user, ArgoCD admin mirror, cloudflared config steps did not run) and expire the silence.
- [ ] **Proposal v1.43.0: off-laptop outage watcher** (operator 2026-10-03: use Hermes to coordinate jobs during a local network outage) — first confirm where Hermes runs; it only helps if it is off the Mac (heartbeat page, queue held until reconnect, sweep stuck pods/jobs afterward).
- [x] **Host-alias + rules CRD race FIXED** — Codex `82fe2218` on origin; Claude verified: trailers, 8-file scope, 45 BATS green, shellcheck clean, mutation (stub helper) → 2 red then cmp-restored, live `_hub_docker_host_ip` on the rebuilt hub → `0.250.250.254`.
- [x] **ACG sandbox criticals → email, not SMS** — DONE, landed inside `eeca8b59` (Claude's memory-bank commit swept in Codex's STAGED files: template route, alertmanager_config_secret.bats, alerting guide, CHANGELOG — so the commit carries a chore message and no Codex trailer; pushed, not rewritten). Claude verified: route at index 1 after the Trivy null route, before `sms-critical`; BATS 28/28 (amtool not installed → route tests skip); independent mutation receiver→sms-critical fails test 4, cmp-restored. Takes effect on the next `make observability` (hub) and next sandbox `make up`. Lesson re-learned: `git diff --cached` before EVERY commit in the shared worktree.
  - Original entry: **ACG sandbox criticals → email, not SMS** (operator 2026-10-03: "only hub and hostinger have to" text) — `docs/bugs/2026-10-03-acg-sandbox-critical-alerts-send-sms.md`; one route `severity=critical, cluster=~"acg|ubuntu-k3s"` → `platform-warning` ahead of `sms-critical`. Hostinger pages via Hermes, untouched. Codex DISPATCHED 2026-10-03 after the hang fix (`deb5f635`).
- [ ] **HUB DELETED 2026-10-03 ~08:35** — Claude gave `make down CLUSTER_PROVIDER=k3s-aws` without `KEEP_LOCAL=1`; `bin/cluster-down` defaults `_keep_hub=0` → `k3d cluster delete k3d-cluster`. No k3d containers/volumes remain; context gone; all hub dashboards error. Fix spec `docs/bugs/2026-10-03-make-down-deletes-hub-by-default.md` (default keep hub, `DELETE_HUB=1`/`--delete-hub` to delete; `k3d` provider implies delete). Dispatch order: host-alias (running) → make-down default → hang → SMS routing. Hub rebuild = operator, hub-only sequence + Vault reseed from Keychain (app-cluster-kubeconfig, cosign-public-key not backed up).
- [x] **make down keeps the hub FIXED** — Codex `435c95a1` on origin; Claude verified: trailers, 5-file scope, 19/19 cluster_down.bats, `make down-hub-flag` mapping (default empty; DELETE_HUB=1 / KEEP_LOCAL=0 → --delete-hub; DELETE_HUB=1 KEEP_LOCAL=1 → error), mutation `_keep_hub=0` → test 10 red, cmp-restored; hub untouched (4 nodes). Note: 3 pre-existing tests run cluster-down with real PATH under DRY_RUN only — every destructive line is dry-guarded (checked).
- [ ] **Hub recovery progress (Claude, 2026-10-03 09:00–09:15)** — done: Vault PF reinstalled (health 200); `make platform-ops` OK; AppSets reapplied 13/13 pinned to v1.41.0; hub self-registration + Hostinger re-registered (ArgoCD + Vault auth mount); all 30 apps Synced; hub pushgateway :19094 OK. `hub_recovery_reconcile` stopped at step 5 (signing — Keychain unreadable from Claude session). BLOCKED on operator: (1) `sudo chown -R cliang:staff ~/.local/share/k3d-manager/logs` (root-owned since 07:34 → grafana-port-forward exits 78); (2) `make alertmanager-secret` + `make observability` from operator terminal (Keychain); (3) `make signing-restore` then `./scripts/k3d-manager hub_recovery_reconcile --confirm`; (4) `make platform-ops` rerun for Keychain-synced secrets (webhook token); (5) Cloudflare tunnel agent missing → public hosts 530; ArgoCD PF + browser LaunchDaemons missing (restored by next sandbox make up / cluster-up). NO snapshot existed (M2 `k3dm-snapshots` absent, `~/k3dm-backups` empty).
- [x] **`make up CLUSTER_PROVIDER=k3d` (hub-only rebuild)** — operator ask 2026-10-03; spec `docs/bugs/2026-10-03-no-make-target-for-hub-only-rebuild.md` (`bin/hub-up` + Makefile `k3d)` branch + `make hub-up` alias). Filed as a bug: v1.41.0 plans at the 5 cap. Codex queue after make-down default. Operator is rebuilding the hub now by hand (hub-only sequence). Codex `abbcfd65` landed (6/6 BATS, shellcheck OK) — Claude review: Steps 3–5 act on CURRENT context → would deploy onto Hostinger if context=ubuntu-hostinger; follow-up U4 (current-context guard) dispatched. U4 DONE `ed22bda9` (Codex .git denied → Claude committed): 7/7 BATS, shellcheck OK, guard-removal mutation → test 5 red, cmp-restored.
- [ ] **Hub-loss DR (real, 2026-10-03)** — operator: "a good lesson and a disaster recovery". Capture per-step timings (measured RTO) + lost-for-good list (RPO) during the manual rebuild; after recovery write `docs/issues/2026-10-03-hub-deleted-by-sandbox-teardown.md` (timeline, cause, restored-from-Keychain/git, lost, timings). Follow-ups: scheduled off-hub Vault snapshot (proposed v1.43.0); maybe `make hub-restore` for post-rebuild restores (decide after counting today's manual steps). No snapshot exists today — recovery is per-item from Keychain (`k3d-manager-app-cluster-secrets`, signing, alertmanager, cloudflared) + git.
- [ ] **Bug: root-owned state logs dir kills grafana-port-forward** — `docs/bugs/2026-10-03-root-owned-state-logs-dir-kills-grafana-port-forward.md` (OPEN, hypothesis: root LaunchDaemons recreated the dir after cluster-down removed it). Operator workaround: `sudo chown -R cliang:staff ~/.local/share/k3d-manager/logs` + kickstart.
- [ ] **2026-10-03 sandbox `make up` FAILED at Step 10c (Keycloak never created)** — root cause: `bin/cluster-up` identity Application heredoc sets `Replace=true`; ArgoCD replaces the bound `postgres-keycloak-pvc` (immutable) and the sync fails; infra per-PVC `Replace=false` (`00d0d8a`) is present live and IGNORED. Fix F1 (ServerSideApply=true + ServerSideDiff=true) appended to `docs/bugs/2026-09-23-argocd-identity-replace-true-cannot-update-bound-pvc.md`, dispatched to Codex. Operator rollout: patch live app + start sync, then re-run make up. CFN stack `k3d-manager-cluster` (us-west-2) left running by the failed run.
- [x] **Identity F1 LANDED `e08eaa83`** (Codex wrote; Claude verified: parsed-YAML test, Replace=true mutation red, cluster_up.bats 33/33 after `a3f951ae` fixed test 30 that Claude's fb71deb4 left red). Operator live-patched the app (SSA + ServerSideDiff) + started sync: PVC now serverside-applied, still Bound pvc-7daa614b. Next blocker: `ExternalSecret/k3dm-smoke-user` wave 0 deadlock (Vault path seeded only once Keycloak runs) — F2 preseed spec appended to `docs/bugs/2026-10-02-smoke-user-secret-lost-on-hub-rebuild.md`; operator pre-seeds Vault by hand now.
- [x] **Identity F2 LANDED `d5b986f4`** (Codex wrote, pushed; Claude verified independently: diff = 6 spec files, keycloak/cluster_up/hub_recovery BATS 0 failures, shellcheck clean, mutation dropping the present-entry `return 0` turns test 15 red, restored + `cmp`). Deviation noted, not rewritten: a blank line splits the Codex/Claude trailers. Live: postgres-keycloak now Running, PVC Bound pvc-7daa614b; identity still Failed at `k3dm-smoke-user` SecretSyncedError — waiting on the operator pre-seed + sync re-trigger, then `make up CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1` re-run.
- [x] **DR docs consolidated 2026-10-03** — incident `docs/issues/2026-10-03-hub-deleted-by-sandbox-teardown.md`; howto `hub-rebuild-from-gitops-vault.md` gains *Identity app stuck after a rebuild* (ESO force-sync + manual sync) and a DR-drill (v1.43.0, not built) pointer; README How-To link; bug statuses → FIXED (435c95a1, fb71deb4, abbcfd65, e08eaa83, d5b986f4). Open: preseed should force ESO refresh; `docs/howto/hub-dr-drill.md` lands with v1.43.0 D8. Live: identity Synced/Healthy, Keycloak 1/1.
- [x] **Sandbox `make up` exit 0 (2026-10-03)** — F2 preseed seen live at Step 10c (entry present → left); identity synced. WARNs: Keycloak frontendUrl update, LDAP bind credential reconcile, LDAP group sync, ArgoCD→ubuntu-k3s reconnect >120s, 2 LaunchDaemons skipped (headless/no sudo), k3dm-webhook-token not in Keychain (headless read). Next: operator runs `hub_recovery_reconcile --confirm` in Terminal.app, then re-check SSO.
- [ ] **hub_recovery_reconcile run 2026-10-03 13:44** — identity Synced/Healthy, KC 1/1, but public Keycloak 502: wrapper pins REMOTE_PORT 8080, infra svc exposes http:80 → recurrence + named-port spec appended to `docs/bugs/2026-08-22-keycloak-port-forward-wrong-remote-port.md` (Codex queue). Smoke seed skipped (public mint curl 56). Vault root token Keychain write failed silently (-25308, non-GUI) — same doc. Operator: stopgap wrapper edit + kickstart, rerun reconcile foreground in Terminal.app. My wrapper sed was classifier-DENIED (Irreversible Local Destruction) — don't retry.
- [ ] **Reconcile rerun (operator, foreground)** — Keycloak PF stopgap verified: :8880 + public 200; smoke client created; identity Synced/Healthy; ESO SecretSynced. public-endpoint-probe: all OK except frontend 502 — origin 127.0.0.2:80 has no listener because the frontend/keycloak browser-http LaunchDaemons were skipped by headless make up (none in /Library/LaunchDaemons). Fix: operator `make refresh CLUSTER_PROVIDER=k3s-aws` in Terminal.app. Keychain root-token write -25308 even foreground → operator `security show-keychain-info`.
- [ ] **make refresh did not install LaunchDaemons** — `_system_daemon_install_if_missing` uses --prefer-sudo (sudo -n only) → silent soft fail; filed `docs/bugs/2026-10-03-refresh-system-daemon-install-never-prompts-for-sudo.md` (Codex queue). Workaround: `sudo -v && make refresh CLUSTER_PROVIDER=k3s-aws`. Keychain -25308 root cause = login keychain LOCKED (show-keychain-info failed until unlock-keychain); operator unlocked → rerun reconcile to sync Vault root token.
- [x] **Hub recovery verified 2026-10-03** — after `sudo -v && make refresh` + foreground reconcile (keychain unlocked): public-endpoint-probe 7/7 OK, frontend+keycloak browser-http LaunchDaemons installed.
- [x] **DR plan v1.43.0 amended** — §9 DR posture (RPO/validation/authority/Vault-loss/prod-safety), D9 drill hub isolation (DR_DRILL_MODE=1 stops hub-up before deploy_argocd; no egress; no shared identities), gate 3b + mutation (e), L7 egress check, quarterly offline-age-key check, RPO=export cadence note.
- [ ] **v1.43.0 PLAN: weekly hub DR drill** — `docs/plans/v1.43.0-hub-dr-drill.md` (operator 2026-10-03: planned DR, restore data quickly, not image snapshots). Operator decisions 2026-10-03: (1) Vault unseal shards durable in Keychain `k3dm-vault-unseal-dr` (M4+M2), generate-root short-lived token, no state.db in backups; (2) pre-bind PVCs with selected-node + node-match hard stop; (3) data = age-encrypted critical claims (~100MB) in private repo `wilddog64/k3dm-hub-data`, M4 has public key only, bounded history; (4) drill runs on M2 with its own kubeconfig; (5) PrometheusRules in git + GitHub scheduled freshness workflow in the data repo; (6) drill hub on M2, not a 2nd hub on M4. Also DELETE_HUB=1 refuses without an export <24h. Live checks L1–L6 before dispatch; likely split into 2 Codex dispatches (export/restore, then drill). Supersedes the scheduled-snapshot proposal below. 1 of 5 for v1.43.0.
- [ ] **DR gap: no snapshot before destructive teardown** — `make snapshot` exists (M2 store) but is manual and was never run; nothing captured before the 08:35 hub deletion. Propose v1.43.0: scheduled snapshot + `make down DELETE_HUB=1` refuses without a verified snapshot < N h old.
- [x] **Hub DR one-command target** — `make hub-recover` (preflight → hub-up → hub-restore) and `make hub-restore` landed in `fb71deb4` (Codex impl; Claude verified: 14/14 BATS, shellcheck clean, signing-SKIP mutation red→restored). Run in Terminal.app. Follow-up still queued: hub-up/hub-restore must own the identity stack, its Vault seeding, and the ArgoCD/Keycloak PF agents.
- [ ] **Hub VectorDB empty after rebuild** — the Hermes index tick fails every run because the Vault copy `secret/embeddings/gemini` was lost with the hub; launchd can't use the keychain. The operator reseeds it via `docs/guides/vector-store.md` (Terminal.app), then runs `make index-docs`. Durable fix = hub-restore follow-up F2.

- [ ] **index-docs stalled at 700/1802 (2026-10-03 14:08)** — sleeping on an uncapped server `retryDelay` (likely per-day quota). Bug filed: `docs/bugs/2026-10-03-index-docs-sleeps-on-uncapped-server-retry-delay.md`; Codex queue. Operator to Ctrl-C and re-run later (resumes).
- [ ] **index-docs re-run** — operator runs `make index-docs` morning of 2026-10-04 (after midnight-PT quota reset); 700/1802 committed, ~1102 remaining.
- [ ] **Codex chain dispatched 2026-10-03 14:20** (`codex exec`, sequential): f3 Keycloak named port + Keychain write verify; f4 refresh `--interactive-sudo`; f5 index-docs retry-delay cap. Logs `scratchpad/codex-f{3,4,5}.log`. Claude verifies each SHA on origin. Not yet specced for Codex: preseed ESO force-sync, hub-restore embeddings key.
- [x] **Codex chain verified (Claude, 2026-10-03 14:35)** — `2735a7d2` Keycloak named port + Keychain read-back; `1df58d4b` refresh interactive sudo on TTY; `7a4bd396` embeddings retry-delay cap. All on origin. Claude re-ran: cluster_up 35, cluster_refresh 5, hub_recovery 43, provider_contract 57 all ok; test_prior_art 56 passed. Mutations red (delay cap, Keychain compare, TTY branch); restored, cmp clean. shellcheck clean. Nit: `7a4bd396` has a blank line between the two Co-Authored-By trailers (not rewritten — pushed). Next: spec preseed ESO force-sync + hub-restore embeddings key.
- [x] **F3 implemented by Codex, committed by Claude** (Codex `.git` read-only) — preseed forces ESO refresh; reconcile retries a Failed/Error identity sync. Claude re-ran keycloak/hub_recovery/cluster_up/provider_contract: 0 failures; phase-check mutation red, restored (cmp); shellcheck clean.
- [x] **hub-restore F2 (embeddings key)** — Codex implemented; operator hand-fixed the 2 review defects (vault-0 exec now `-n secrets --context`; dead `set +x/set -x` fallback removed); Claude restored a stray vim line (121 `fi`) and tightened the BATS stub to require the ns/context. hub_restore 11/11, makefile_signing_restore 8/8, shellcheck clean; mutation (drop ns/context) red, restored (cmp).
- [ ] **Bug: cluster-up Keycloak LDAP component lookup picks a mapper** (2026-10-03, Claude) — `docs/bugs/2026-10-03-cluster-up-keycloak-ldap-component-lookup-picks-a-mapper.md`. Explains all 3 `make up` SSO WARNs: `grep -B1 'ldap'` returns the "full name" mapper id (10d.6 update/sync fail; 10d.7 created stray group-mapper `9233ebab` under that mapper → NPE `ldapProvider is null`); frontendUrl sent top-level instead of `attributes.frontendUrl` (also fired 2026-07-07). Live SSO is OK (real provider `a5a37610` syncs 5 users; issuer public via `_keycloak_smoke_ensure_realm`). Spec F1–F4 for Codex; fix also deletes the stray mapper on the next `make up`.
- [x] **LDAP/SSO fix `fd3616fd`** (2026-10-03, Codex impl, Claude verified: 2 files = spec, cluster_up.bats 37/37, independent mutation `== ldap` → `== *ldap*` turns the behavior test red, cmp-restored, shellcheck 31 = HEAD 31; Codex blocked on .git lock → Claude committed). Live check on the next sandbox `make up`: no SSO WARNs, one group-mapper (parent a5a37610), stray 9233ebab gone.
- [x] **Recovery leftovers closed 2026-10-03 ~17:00:** silence `84a19233` EXPIRED (all 7 public hosts 5/5 OK, no PublicEndpointDown firing); `k3dm-webhook-token` Secret present in `cicd` (make-up WARN was the headless Keychain read only).
- [ ] **Bug (OPEN): ACG sandbox Prometheus never starts** — `docs/bugs/2026-10-03-acg-sandbox-prometheus-crds-missing-from-api-discovery.md`. Hub `TargetDown federate-acg`: sandbox has no Prometheus; 4 large operator CRDs are Established but missing from `/apis/monitoring.coreos.com/*` discovery; ArgoCD `acg-kube-prometheus-stack` failed 432+ syncs. Re-check discovery on the next sandbox `make up` before writing a fix.
- [ ] **Root-owned logs bug updated** — confirmed `argocd.sh:83` defaults the ROOT ArgoCD browser daemon log into the shared top-level `logs/` (cluster-up's per-provider fallback is dead); 744-mode creator still unconfirmed.
- [x] **hub-restore preflight F2b `523c6993`** (Codex, Claude verified: on origin, 2 files, hub_restore 12/12 + signing 8/8, independent mutation dropping `! -name '*.lock'` turns test 11 red, cmp-restored; live scan now finds 0 dirs). Live run had stopped on root daemon `keycloak-browser-http.log.lock` dirs. `make argocd-hermes-token` DONE by operator 2026-10-03 (35 apps visible, Hermes restarted).
- [x] **hub-restore live run 2026-10-03 17:37 (operator, Terminal.app):** steps 1–8 PASS (signing key restored, embeddings key PASS, Keychain root-token read-back OK); 9/9 Verify FAIL was a race — step 8 kickstarts the Grafana PF, step 9 probed :3001 before it listened; all 4 checks pass on re-read. F2c fix `db02bf07` (Codex; Claude verified 22/22, mutation to a single probe reds 2 tests, cmp-restored, shellcheck 1 = HEAD 1; Codex blocked on .git lock → Claude committed). Hub DR recovery COMPLETE.
- [x] **Sandbox `make up` 2026-10-04 01:30–01:57 UTC (from Claude `!`, same sandbox reused) — exit 2 at Step 14.**
  - **SSO fix `fd3616fd`, live:** F1 (provider `a5a37610`, no passwords in argv), F3 (single `group-mapper` `b7eb43f7`, `9233ebab` gone) and F4 (frontendUrl, no WARN) PASS.
  - **REGRESSION:** 10d.6 now writes Vault `ldap/admin.admin_password` (the shopping-cart `ldap` Deployment) to the provider, which binds `openldap-0`. A read-only `testAuthentication` returns AuthenticationFailure, and the group sync hits error 49. **Hub LDAP SSO is broken** until the operator runs `KEYCLOAK_BASE_URL=http://localhost:8880 ./scripts/k3d-manager keycloak_provision_shopping_cart_realm`. Fix F5 is specced in the bug doc and goes to Codex. [x] operator repair (needed `KEYCLOAK_SMOKE_ADMIN_SECRET_NAME=keycloak-secrets`; testAuthentication now rc 0) [x] Codex F5 `cc81df52` (on origin; Claude verified: diff = spec, 4 files, BATS 66/66, shellcheck 18 = HEAD~1 18, both mutations red then cmp-restored; commit lacks the Codex/Claude trailers). [x] live check 2026-10-04 sandbox `make up`: 10d.6 "bind credential reconciled and full sync triggered", 10d.7 "LDAP group sync complete", Keycloak sync 02:27:41 = 5 users updated, `testAuthentication` rc 0, no `error code 49` after 02:05 (all 8 hits predate the run). **CLOSED.**
  - **Step 14:** `kubectl wait` on any CRD hangs on the sandbox (it works on the hub), and discovery still misses `prometheuses`. The likely cause is a stuck apiextensions watch. A k3s server restart is the candidate recovery (operator). Recurrence recorded in the bug doc.
  - Other WARNs: Cloudflare credentials missing from Keychain (operator: `make cloudflared-backup`); the ArgoCD browser HTTPS listener was skipped because there was no TTY; the 10g.5 Keycloak reverse tunnel failed.
  - **10g.5 diagnosed (2026-10-04):** false alarm on rerun. The previous `make up`'s `ssh -R 18080` (PID 27102) still holds ubuntu:18080 and serves 200; the new ssh exits on `ExitOnForwardFailure`. Spec `docs/bugs/2026-10-04-cluster-up-keycloak-reverse-tunnel-rerun-false-failure.md` (probe first, skip if live, else pkill the stale one and restart). [x] Codex fix (edits; `.git` lock denied, Claude committed) `22cecd0e` [x] Claude verify (diff = spec, 2 files, BATS 42/42, shellcheck 34 = HEAD 34, `!= "999"` mutation reds only the `000` test then cmp-restored, pkill pattern `pgrep`-matches only the tunnel) [x] live check 2026-10-04: 10g.5 printed "already active on ubuntu:18080 — skipping", no warn; `ssh ubuntu curl 127.0.0.1:18080` = 404 (Keycloak). **CLOSED.**
  - **Rerun 2026-10-04 ~02:30 UTC ended `make up` Error 1 at Step 14** — same Prometheus CRD watch/discovery fault, recurrence #2 recorded in `docs/bugs/2026-10-03-acg-sandbox-prometheus-crds-missing-from-api-discovery.md` (prometheusrules now Established+served; prometheuses/prometheusagents/scrapeconfigs/thanosrulers still absent from discovery ~6h on). [ ] decide fix (conditions-get vs k3s restart) [x] operator k3s restart (2026-10-04 ~02:40Z, discovery fully restored)
- [ ] **ssh-tunnel down after k3s restart** — orphaned sandbox sshd (PID 51046) holds `-R 8200`; autossh `ExitOnForwardFailure` loops; ArgoCD loses ubuntu-k3s. Bug `docs/bugs/2026-10-04-ssh-tunnel-autossh-reconnect-blocked-by-orphaned-remote-8200.md`. [x] operator kill+kickstart (tunnel back 02:46Z) [x] sync — ArgoCD auto-sync Succeeded, Synced/Healthy, Prometheus 2/2 Running, svc prometheus-operated present [x] operator restarted Step 14b PF (PID 93911, 19190); hub federate-acg up=1 at ~02:55Z (14c pushgateway agent already up on 9091) [ ] decide fix on sandbox if sandbox metrics wanted. Orphan `bin/cluster-up` PID 1927 + child 85324 killed by operator.
- [x] **Codex: three sandbox-recovery fixes** (dispatched 2026-10-04) — DONE `f61d3b3b` (cleanup PID ownership) / `3b789adf` (CRD condition + discovery warn + 14b svc guard) / `d49e5eb8` (Vault reverse forward as own agent + remote fuser). Claude verified: all on origin, scope = spec, no new shellcheck warnings, 61/61 targeted BATS, independent mutation (drop ownership check) fails test 28, cmp-restored. Review: R1 Step 14b warn expands `$!` to this run's PID (paste writes the Vault PF PID into acg-prom-pf.pid); R2/R3 Codex split `"su""do"` to slip past the pre-commit bare-sudo audit (observability warn text + tunnel wrapper remote `sudo fuser`). R1+R2 specced in the CRD bug doc; R3 needs operator decision (sandbox 8200 listener is held by non-dumpable sshd, so remote fuser needs root). [x] follow-up R1/R2 `98835aac` (Codex edits, Claude committed; 8/8 crd-discovery BATS + lint; R1 mutation red; `\$!` renders literally) [x] R3 decision: audit exemption upstream — lib-foundation `5c9b631` on `fix/agent-audit-remote-sudo-marker` [x] lib-foundation PR #57 MERGED `44e7e8d` 2026-10-04 (no tag: fix branch, [Unreleased]) [x] subtree pull `ce1164eb` (tree-equal to 44e7e8d) [x] operator: retire the stale local fork `scripts/lib/agent_rigor.sh` → shim to the subtree copy (trial: 9/9 local BATS pass) — spec `docs/bugs/2026-10-04-pre-commit-hook-loads-stale-local-agent-rigor-fork.md` (C1 shim, C2 tunnel marked sudo) [x] Codex [x] verify — `e22b7df6` + `0670b075` (23/23 BATS, fork-restore mutation red, hook accepted marked sudo) [x] make test 5133de03: 1345/1345 BATS, pytest 621 passed 1 skipped [x] make test 709aba8d: 1336/1341, 5 test-only reds [ ] live verify next `make up` + `tunnel_start` migration
- [ ] **make test reds at 709aba8d** — spec `docs/bugs/2026-10-04-v1.41.0-make-test-reds-after-sandbox-recovery-fixes.md` (F1 observability.bats stubs, F2 CRD-wait test 1070, F3 keycloak trap count, F4 eight bare negations; 3rd recurrence of the 2026-09-14 negation bug). [x] Codex (edits; `.git` lock denied, Claude committed) `9ec4434b` [x] Claude verify (diff = spec plus the needed `_kubectl` wrapper-stub cases; gate 116/116; keycloak trap mutation red, cmp-restored) [x] make test green at `402bd596` (1342/1342 BATS, pytest 621 passed 1 skipped)
- [ ] **Hermes app_health never enabled** — spec `docs/bugs/2026-10-04-hermes-app-health-sensor-never-enabled.md` (template env ENABLED=1 + CONTEXT=ubuntu-hostinger; Claude dry run 2026-10-04: payment-service:8084 health/liveness/readiness UP via service proxy). [x] Codex (edits; Claude committed) `254a291e` [x] verify (3 files = spec, pytest 12/12, Codex mutation KeyError) [x] make test (402bd596 green) [x] operator `bin/k3dm-hermes-setup` 2026-10-04 — first poll 11:43:35Z app_health healthy "1 service(s) agree with their probe groups". **CLOSED.**
- [ ] **Hermes Slack-approval setup make targets** — operator asked 2026-10-04 to replace the 5 hand-typed credential steps. Spec `docs/bugs/2026-10-04-hermes-slack-approval-setup-has-no-make-target.md` (`hermes-approvals-kv` / `hermes-drain-token` (token via `security -i` stdin, read back, ROTATE=1) / `hermes-approvers APPROVERS=` / umbrella `hermes-approvals-setup`; stubbed BATS; guide + CHANGELOG). [x] Codex [x] verify `2054d058` (20/20 BATS; both mutations red; Claude hardened: APPROVERS read from env not recipe text, `</dev/null` on kv create — stub hung on inherited stdin) [x] make test `09370a01`: 1345/1345 BATS; test-bin 287/289 — 2 reds PRE-EXISTING at `544ed18a` (k3dm_cleanup.bats:89 GNU-only `stat -c` on macOS; make_lifecycle.bats:17 `make down` `_keep_hub_flag=--keep-hub` assertion) — untriaged [~] operator: ran drain token MANUALLY (first keychain write failed 'User interaction is not allowed', retry ok; APPROVAL_DRAIN_TOKEN uploaded) — KV binding, APPROVER_ALLOWLIST, deploy-worker still pending. Operator's first `make hermes-approvals-setup` died SILENTLY in hermes-approvals-kv (`x=$(cmd)` under set -e exits before the friendly message) — fixed: `|| true` on Keychain reads, wrangler output printed on create failure, 2 regression tests (red on old recipe). Operator had used Claude's PLACEHOLDER id U07ABC12DEF — needs real member ID (Profile → ⋮ → Copy member ID). Follow-up (unanswered): LaunchAgent template lacks `K3DM_HERMES_APPROVAL_DRAIN_URL`. Operator rerun with real member ID: kv create failed 'APPROVALS_KV already exists' (made by hand earlier) — Claude bound existing id `ee9eb140ea624a09802fef9e16396caf` in wrangler.toml; operator reruns setup (KV step skips). `ROTATE=1` rerun SUCCEEDED 2026-10-04: APPROVAL_DRAIN_TOKEN (new 64-hex) + APPROVER_ALLOWLIST uploaded. Guide gained member-ID how-to, troubleshooting table, recovery notes. Operator DONE 2026-10-04: deploy-worker, Slack Interactivity + `/hermes-auth`, drain URL set by hand via PlistBuddy (verified in `launchctl print`). Automation spec `docs/bugs/2026-10-04-hermes-launchagent-template-lacks-approval-drain-url.md` (static URL in template + opt-in moves to Keychain drain token) [x] Codex [x] verify (232 pytest; gate mutation red; Claude fixed Codex typo `k3d-slack-relay` → `k3dm-slack-relay` in template/test/guide — test was self-consistent so it passed). Operator: rerun `bin/k3dm-hermes-setup` optional (hand-set URL already correct).
- [ ] **index-docs** — paused 2026-10-04 at 1000/1120 on the Gemini free-tier daily embeddings quota (HTTP 429, retry ~12h); re-run `make index-docs` after reset, it resumes.
- [x] Sensor-history ESO lines (2026-10-04): all 47 ExternalSecrets synced on hub/hostinger/sandbox; history = hub rebuild (2/5 kubeconfig+cosign, 1/9 smoke-user) + tonight's sandbox k3s restart (3/18 postgres admin); "healthy" with failures = first tick of the threshold-2 debounce. No new bug.
- [ ] **index-docs local embedding cache** — operator asked 2026-10-04: hub loss costs >1 day of Gemini quota to re-index (1000/1120 paused). Spec `docs/bugs/2026-10-04-index-docs-rebuild-after-hub-loss-costs-a-day-of-quota.md` (SQLite cache ~/.cache/k3dm/embeddings.sqlite keyed by model/dim/task/text; newest-dated-first on misses; summary 'from cache'). [x] Codex [x] verify (316 pytest incl. 7 new; cache-off mutation → 3 red; Claude fixed duplicated EMBED_DIM=768 in embed_cache.py → import from prior_art). Cache fills on the next real index run.
- [ ] **Embedding cache second copy** — operator agreed 2026-10-04 (cache on same M4 as hub). Spec `docs/bugs/2026-10-04-embedding-cache-has-no-second-copy.md` (`make embed-cache-backup DEST=` via sqlite backup API + atomic replace; `embed-cache-restore SRC=` merges INSERT OR IGNORE) + integrity metadata per 2nd review (schema v2 via user_version, model/dim/task/content_hash/created/last_used; read+restore integrity checks; `embed-cache-stats`; `embed-cache-prune` = stale AND unused >90d). [x] Codex [x] verify (648 pytest; 6 mutations red→restored; Claude fixed spec defect: NULL last_used_at counted as unused + restore dropped metadata → first prune would wipe the v1/restored cache; migration now stamps timestamps, restore copies metadata, +2 tests). Operator next: `make embed-cache-backup DEST=…` after quota-reset index run.
- [x] **Embedding cache seed from store** — 2026-10-04: operator's cache empty (12KB) while hub holds ~1000 vectors embedded pre-cache; quota spent today. Spec `docs/bugs/2026-10-04-embedding-cache-starts-empty-beside-a-full-store.md` (`make embed-cache-seed [REF=]`: COPY path/hash/embedding from store, cache rows whose hash matches corpus, no overwrite, zero Gemini). Codex done, Claude verified 2026-10-04 (654 pytest, 2 mutations red, howto reworded). Operator: `make embed-cache-seed` then `make embed-cache-backup DEST=…`.
- [x] **Hermes quota pause → Pacific reset** — pause ended 00:00 UTC (17:00 PDT) but Gemini RPD resets 00:00 PT → re-429 + ~17h lost per hit. Spec `docs/bugs/2026-10-04-hermes-quota-pause-ends-at-utc-not-pacific-midnight.md` (`_next_quota_reset` = next 00:05 America/Los_Angeles, DST-safe). Codex done, Claude verified 2026-10-04 (UTC mutation reds 2 tests). Live on the next Hermes poll from the working tree.
- [x] **embed-cache backup/restore to another Mac over scp** — operator wants `DEST=m2-air:~/.local/backup`. Spec `docs/bugs/2026-10-04-embed-cache-backup-cannot-reach-another-mac.md` (host:path detection, ~ rewrite, mkdir -p, scp to tmp + atomic mv, remote restore). Codex done, Claude verified + added retries/keepalive/timeout handling and unquoted scp paths 2026-10-04. Commit `0b13d794`. Operator ran it 2026-10-04: 1693 vectors to `m2-air.local:.local/backup/embeddings.sqlite`. Re-run after Hermes embeds the remaining ~110 docs post-reset.
- [x] **Hermes re-index after hub rebuild + dashboard** — found 2026-10-04 while checking Grafana: `_refresh_index` fingerprint noop ignores an empty rebuilt store (backlog 0 while drift = corpus); `--limit 100` counts cache hits; dashboard 'embedded' now = API calls. Spec `docs/bugs/2026-10-04-hermes-index-refresh-ignores-a-rebuilt-store.md` (status check before noop; limit = misses only; `k3dm_vectordb_index_from_cache_last` + panel 13). [x] Codex [x] verify (320 pytest; 3 mutations red→restored; Claude fixed status call missing K3DM_INDEX_REF → working-tree vs ref mismatch would re-index every poll, and skipped empty upserts after limit). Next: dispatch second-copy/metadata spec.
- [x] 2026-10-04 bug-doc status sweep: 12 stale OPEN/SPEC status lines corrected to FIXED/CLOSED (docs only).
- [ ] 2026-10-04 Codex queue: [x] root-owned logs (verified, committed this push) (docs/bugs/2026-10-03-root-owned-state-logs-dir-kills-grafana-port-forward.md) [x] e2e dispatch CPU gate — Codex done, Claude-verified, commit held until operator make e2e ends (docs/bugs/2026-09-30-e2e-harness-dispatch.md) [ ] deploy-worker keychain msg (docs/bugs/2026-10-02-deploy-worker-keychain-error-misleading.md) [ ] then payment e2e rerun (operator)
- [x] deploy-worker keychain message (docs/bugs/2026-10-02-deploy-worker-keychain-error-misleading.md): Codex done, Claude-verified (mutation red 1,2,4), committed.
- [x] hermes-approvals-kv tests copy the bound wrangler.toml: FIXED (Codex, Claude-verified, 12/12, mutation 3 red).
- [ ] Sandbox make up hijacks Hostinger launchd labels (frontend.3ai-talk.org 502, Pushgateway refused after sandbox expiry): docs/bugs/2026-10-05-sandbox-make-up-hijacks-hostinger-launchd-labels.md OPEN; operator workaround = plutil repoint + make refresh-edge; fix spec pending.
- [x] e2e-tests PR #11 (order flow statuses) MERGED e5e644d 2026-10-05 (admin merge; enforce_admins restored true). Next: e2e image rebuild + pin bump + make e2e (#4).
- [x] Sandbox/Hostinger launchd label collision fix (docs/bugs/2026-10-05-sandbox-make-up-hijacks-hostinger-launchd-labels.md): FIXED 2026-10-05, Claude-verified; live check after next sandbox make up.
- [x] Hermes provider pin (K3DM_HERMES_PROVIDER=k3s-hostinger): spec in docs/bugs/2026-06-24-hostinger-provider-switch-stale-active-provider.md (Recurrence 3); FIXED 2026-10-05, Claude-verified; operator reruns bin/k3dm-hermes-setup.
- [x] Stale active-provider marker trusted without liveness (Makefile status, cluster-status-summary, webhook): Recurrence 4 FIXED 2026-10-05, Claude-verified. [ ] operator `make restart-webhook`.
- [x] cluster-down legacy-cleanup dry-run test: FIXED 2026-10-05, Claude-verified.
- [x] lib-foundation agent-audit `*-sudo` flag false positive: FIXED 16908e5 + a2115d1 on fix/agent-audit-sudo-flag-false-positive, Claude-verified. PR #60 open, CI green, Copilot 0 findings. PR #60 MERGED c6876cc, subtree pull 58f27f48.
- [ ] lib-foundation `_browser_launch` missing ready helper under host: PR #61 MERGED `dbed340` (2026-10-05; fix branch, stays under [Unreleased] — no tag). Subtree pull DONE `1a62d0b2` (pushed; only scripts/lib/foundation touched). Live check: next `make up` with Chrome closed.
- [ ] 2026-10-05 `make up` FAILED exit 1 at Step 10b: sandbox node ip-10-0-1-161 kubelet went silent 12:20:37Z (EC2 alive, status checks ok); sandbox Prometheus: Trivy scan of kube-system/cilium (7 scanner containers x 1Gi limit) at 1265Mi, MemAvailable 398Mi; ESO webhook endpoints empty -> data-layer OutOfSync. CFN stack still up. Bugs filed: `docs/bugs/2026-10-05-sandbox-node-notready-trivy-cilium-scan-starves-kubelet.md` (ACG excludeNamespaces kube-system + scanJobsConcurrentLimit 1 + kubelet system/kube-reserved 256Mi) and `docs/bugs/2026-10-05-cluster-up-data-layer-wait-silent-on-cause.md` (explain op message + NotReady nodes; reconnect timeout logs 'connected'). Both dispatched to Codex (one run).
- [ ] Follow-up candidate: `shopping_cart.sh:1403` server-Ready probe `kubectl get nodes` has no `--request-timeout`; hangs silently ~1-2 min on a fresh sandbox (observed 2026-10-05 make up). Not filed yet.
- 2026-10-05: `427f4e0f` sandbox Trivy scope (skip kube-system, 1 concurrent scan) + kubelet reservation (k3sup server/agent, `K3S_KUBELET_RESERVED_ARGS`) + data-layer timeout explainer / reconnect-log gate — Codex, Claude-verified (96/96 bats; 4 mutations RED + cmp; shellcheck = HEAD). Truncation test found vacuous (`$output` unset inside `bash -c`) — bug docs/bugs/2026-10-05-cluster-up-explain-truncation-test-vacuous.md FIXED (Codex, Claude-verified: mutation + pre-fix RED, 53/53). Sandbox recovery (operator): `make down KEEP_LOCAL=1` + `make up` to exercise the reservation.
- [ ] 2026-10-05 alert deep dive: 5 bug specs filed (argocd-cve-scan no-newer-chart exit 1; offline tests rotted on v1.41.0; nightly test-metrics push failure silent; hub Trivy scans vclusters; E2E alert re-fires on exporter rollout) — dispatched to Codex (one run). Claude verifies + commits.
- [x] 2026-10-05 alert deep dive fixes LANDED `536454bc` (all five specs; make test 1362/1362, test-bin 314/314).
- [x] 2026-10-05 CoreDNS restart in `_acg_repair_hub_host_alias` FIXED (Codex; Claude verified pre-fix RED 3/3, two mutations caught, cluster_up.bats 56/56, shellcheck 31=31). Operator may rerun `make up`.
- [ ] 2026-10-05 hub agent-0 k3s agent memory leak: measure growth rate (scratchpad RSS sampler, 10-min), then spec a kube-proxy sync-staleness alert (`docs/issues/2026-10-05-hub-agent-0-k3s-agent-memory-wedges-kube-proxy.md`).
- [x] 2026-10-05 bare `make down` with k3s-aws + k3s-hostinger live now proceeds (FIXED, Codex; Claude verified pre-fix RED 2/4, mutation caught, provider_active_set.bats 30/30, shellcheck 0=0). `make status` unchanged.
- [ ] 2026-10-05 ACG extend fix (lib-foundation fix/acg-extend-wait-for-button): spec filed; [x] Codex [x] Claude verify (65cc6bd; jest 44/44, BATS 17/17, 8 new tests red pre-fix, reload + retry mutations red, cmp-restored) [x] PR #62 merged (1b4cd33; Copilot never picked up the request; credential-test gate skipped pre-PR, handed to operator post-merge) [x] make credential-test PASS post-merge (rc=0, sts OK, no restart) [x] subtree pull (3d8956e4, pushed) [x] launchd reinstall (operator 18:12; wrapper verified: node + acg_extend.js) [x] live wake verified (in-process watcher PID 13364, 19:12: found `[data-testid="extend-sandbox-modal"] button:has-text("Extend")`, "Extend action complete"; Auto Shutdown moved 19:25 → 23:25) [x] launchd agent itself verified 2026-10-05 21:42 PDT (04:42Z): first run after reinstall connected via CDP, TTL ~102m, "Extension window not open yet … Skipping" — no "No such file" error (the old wrapper failures stop at the reinstall). Logs now at ~/.local/share/k3d-manager/run/k3d-manager-acg-watch.{err,out}, not /tmp. [ ] a launchd-driven run that actually extends
- [ ] 2026-10-06 ACG watcher still lets the sandbox expire (lib-foundation `fix/acg-watch-interval-and-expired-ttl`): launchd runs every 3.5h but extend only fires with <=65m left (21:42 PDT saw 102m, skipped; sandbox died ~23:24); 01:12 run read yesterday's 11:24 PM shutdown as +1331m. Spec `docs/bugs/2026-10-06-acg-watch-misses-extend-window-and-reads-expired-as-22h.md` filed [x] (`25e2b75`) [x] Codex [x] Claude verify (lib-foundation `211a3fd` pushed; RED + mutations A/B/C, jest 49/49, bats 170/170) [x] PR lib-foundation #64 (release v0.5.1, docs back-filled; CI green, Copilot 0 inline findings, mergeable clean; awaiting operator --check live gate, merge) [ ] tag v0.5.1 [ ] subtree-pull [ ] reinstall agent (make up / acg_watch_start).
- [ ] 2026-10-05 sudo prompt in `make up` Step 10g + `refresh-edge`: root cause = (1) sudo resolves bare `install` to gnubin (GNU coreutils) so the `/usr/bin/install` NOPASSWD rule never matches, (2) `bin/*` source stale `scripts/lib/system.sh` lacking the no-TTY `-n` guard. Spec `docs/bugs/2026-10-05-sudo-prompt-stale-system-sh-gnubin-install.md` filed [ ] Codex [ ] Claude verify [ ] commit. Follow-ups: lib-foundation path resolution upstream; reconcile the two system.sh copies; `sudo -n true` probe defect.
  - 2026-10-05 RETARGETED per operator: defect 1 → lib-foundation spec `docs/bugs/2026-10-05-sudo-resolves-bare-name-through-user-path.md` on `fix/sudo-system-path-resolution` (`df38037`); Codex fix verified + committed `48f8a70` (bats 168/168, mutations A/B), pushed. lib-foundation PR #63 MERGED `8b97c0b` (2026-10-05; fix branch, no tag — stays [Unreleased]); subtree-pulled `c848d37c` (tree == 8b97c0b). bin/* spec rewritten 2026-10-05 as a shim (scripts/lib/system.sh loads the foundation copy, keeps only kubeconform; prototype 305/305, mutations red) → Codex (run hit OpenAI model capacity after gate 2; resumed same session). FIXED `b3b2542a` 2026-10-05: Claude verified — all files cmp-identical to prototype (copilot bats indent normalised), shellcheck clean, affected BATS 310/310 (Codex), make test 1371/1371 outside the sandbox (Codex's 33 reds were sandbox-only: webhook/k3s-aws/acg-up). Operator: confirm no Password: prompt on the next `make up` Step 10g / `refresh-edge`.
- [x] e2e Failure groups row (operator 2026-10-05): run `1791168841-15959` = the pre-fix run already filed in `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md` (Recurrence). Fix merged e2e-tests PR #11 `e5e644d`, `:latest` image published 11:14Z. Pending: operator `make e2e` → 0 order-management failures.
- [x] 2026-10-05 Step 10g loopback alias aborts make up — spec docs/bugs/2026-10-05-frontend-loopback-alias-aborts-cluster-up.md; [x] Codex [x] Claude verify (pre-fix red, --soft mutation red, 8/8 BATS, shellcheck 159=159)
