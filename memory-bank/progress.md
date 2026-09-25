# Progress — k3d-manager

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
- [ ] Commit, push, and SHA verification remain.

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

- [x] **v1.39.0 Slack corpus Q&A specced** — `docs/plans/v1.39.0-slack-corpus-qa.md`, filed on
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
