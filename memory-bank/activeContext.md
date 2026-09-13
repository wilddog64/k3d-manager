# Active Context — k3d-manager

> Compressed 2026-08-24 (CVE panel ② saga closed → collapsed to pointers). Settled fixes
> live as pointers; detail in `memory-bank/archive/`, `CHANGELOG.md`, `docs/retro/`,
> `docs/issues/`, `docs/bugs/`, git history, and auto-memory.

## Current focus

- **LIVE GATE RUN 2026-09-12 10:50 — browser automation now WORKS; failure moved to a
  broken host `aws` CLI.** `make credential-test PROVIDER=aws` on `4389e03` ran in **101s**
  (was 10+ min). `ACG_SESSION_OK` was legitimate, `handleSignIn` never fired, extraction
  succeeded, sandbox restart succeeded, second extraction succeeded. The dead-host and
  session-check fixes are confirmed working on live infrastructure.
  **New failure:** `ERROR: sts:GetCallerIdentity failed — credentials invalid after all
  attempts.` **The credentials were NOT invalid** — verified with a stdlib SigV4 POST to
  `sts.amazonaws.com`: `STS RESULT: VALID, arn:aws:iam::<account>:user/cloud_user`.
  **Real cause:** the host `aws` CLI cannot start —
  `ImportError: dlopen(_awscrt.abi3.so): Library not loaded .../libaws-c-s3.1.0.dylib`.
  `awscli` 2.36.44's bottle links `aws-c-s3` **1.0**; installed is **1.1.0**, which ships
  only `libaws-c-s3.1.1.0.dylib`. `brew reinstall awscli` does NOT fix it (same bottle) and
  `brew outdated` lists neither formula. Remaining options, all operator calls:
  `brew reinstall --build-from-source awscli`, the official AWS pkg installer, or wait for a
  rebuilt bottle. Claude did NOT run `--build-from-source` — long toolchain rebuild, out of
  scope for ACG work.
  **DESTRUCTIVE SIDE EFFECT — the sandbox was deleted and restarted for nothing.**
  `acg-credential-test` probes `aws sts get-caller-identity >/dev/null 2>&1` and keys only
  on exit status, so "CLI cannot start" is indistinguishable from "STS rejected creds" —
  and only the latter justifies the restart. Spec filed:
  `docs/bugs/2026-09-12-acg-sts-probe-conflates-broken-cli-with-invalid-credentials.md`
  (`1838f08`): preflight `aws --version`, keep the probe's stderr, restart ONLY on
  recognized rejection codes, same guard for the Azure paths. **FIXED `e12d41a`** (Codex;
  Claude verified + committed). Restart-worthy codes: `InvalidClientTokenId`, `ExpiredToken`,
  `AuthFailure`, `SignatureDoesNotMatch`, `AccessDenied`, `UnrecognizedClientException`.
  All three Azure paths guarded; `_azure_auth_failed` confirmed non-destructive (prints +
  `exit 1`, no restart). **Claude proved the guard is real, not just green:** the PRE-fix
  script run against a stubbed broken CLI restarts once (bug reproduced); post-fix does not
  restart at all. Gates: lint, shellcheck-lib, **137 BATS** (3 new), npm check, jest 28/28.

- **lib-foundation PR #50 MERGED 2026-09-12 as `c87196d0`.** `fix(acg): dead identity host,
  profile split-brain, and a destructive STS probe`,
  https://github.com/wilddog64/lib-foundation/pull/50 — head `685031a`, base `cf62d41`,
  now head `7e9eae5` (11 commits), base `cf62d41`. **CI 3/3 green** (shellcheck, bats, acg
  node), `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`, **all review threads resolved**.
  Claude does NOT merge.
  **Copilot DID review — it was just slow, not a no-op.** `reviewRequests` stayed `[]` and
  ~2 min of polling found nothing, so it was recorded as the known silent no-op; the review
  in fact landed later, unprompted. **Lesson: `reviewRequests: []` plus a short poll is not
  evidence Copilot declined — it is evidence it has not answered YET. Re-check `gh pr view
  --json reviews` before claiming a Copilot gate is unobtainable.**
  **Copilot's single finding was VALID and was REBASE DAMAGE — fixed in `7e9eae5`.**
  `CHANGE.md` carried 12 resurrected lines: the pre-correction wording of the
  signed-out-detection entry (present only in `308bb3c`, rewritten out by `e547147`), minus
  its `- ` bullet marker and the blank line before `### Security`. It contradicted the
  CORRECTION carried by the surviving bullet. One of the four hand-resolutions during the
  rebase onto post-#49 main reinstated it, so `e547147`'s removal had nothing left to remove.
  **Root cause of the MISS: the post-rebase integrity check ran
  `git diff --stat backup/prism-pre-rebase HEAD -- . ':(exclude)CHANGE.md'` — it excluded the
  ONLY hand-resolved file, so it could not have caught this by construction.** Correct form is
  a positive assertion on the conflicted file itself: `git diff <backup> HEAD -- CHANGE.md`
  must equal exactly what the new base contributed (verified: only #49's Security entry).
  Documented in lib-foundation `docs/issues/2026-09-12-copilot-pr50-review-findings.md`.
  **lib-foundation PR #51 MERGED 2026-09-12 21:40Z as `92d885272daeae411dc62e7226ffe84c3986f557` — release v0.4.17 SHIPPED.**
  Tag `v0.4.17` pushed at the merge commit; GitHub release published from the CHANGE.md
  `[v0.4.17]` section body verbatim (81 lines):
  https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.17
  **Subtree pulled into k3d-manager `k3d-manager-v1.33.0` — `d1aeea19` (merge) + `45d91ce5`
  (squash `10de7f4c..92d88527`), pushed.** Brought in #49 + #50 + #51. Verified by positive
  assertion, not by the diffstat: `psPrismMonogram` selector present at
  `playwright/lib/pluralsight_login.js:13`; `SIGNED_OUT_SELECTORS`/`pageLooksSignedOut`
  present (6 hits); **zero** `id.pluralsight.com` occurrences left in `playwright/lib/`;
  `gcp.js` logs `[set]`/`[empty]` only. Diff was fully contained inside
  `scripts/lib/foundation/` (0 files outside the prefix). Gates: `bash -n` OK on all 4
  changed shell files, shellcheck clean, acg jest **28/28 across 7 suites**.
  **k3d-manager full BATS `test all`: was 820 pass / 4 fail — none caused by the pull;
  now 824 pass / 0 fail as of `64bc7af4` (2026-09-12).**
  All 4 were **stale test assertions, not product bugs** — fixed by Codex against spec
  `docs/bugs/v1.33.0-bugfix-stale-bats-grep-assertions.md` (`f6be494b`), commit
  `64bc7af4` (test files only, 3 files / +16 / -2). Verified independently by Claude:
  diff contained to the 3 permitted test files, all 3 suites green, full suite re-run
  `1..824` with **0 `not ok`**.
  Root causes: (1+2) `argocd_deploy_keys.bats` ran under `env -i` **without
  `CLUSTER_PROVIDER`**, so `_acg_resolve_provider` (`scripts/lib/provider.sh:246`)
  auto-detected a context by probing `kubectl get --raw=/readyz`; `stub_kubectl_command`
  routes bare `kubectl` into `_kubectl`, so the probe both polluted `KUBECTL_LOG` (breaking
  `[ ! -s ... ]`) **and consumed one `KUBECTL_EXIT_CODES` entry** — meaning the two
  exit-code-scripted tests were passing for the wrong reason. Fixed by pinning
  `CLUSTER_PROVIDER=k3s-hostinger` in `BASE_ENV`. (3) `slack_slash_commands.bats` grepped
  the whole frozen `ALLOWED_COMMANDS` line, which broke when `/cleanup-stale-sandbox` was
  added to the worker; the worker and `docs/howto/slack-slash-commands.md` were already
  correct. Now asserts membership per command (still requires all 12 — a narrowing, not a
  weakening). (4) `slack_relay_ack.bats` grepped `const { ok } = await relay(...)`, but the
  worker now destructures `conflict` and passes `meta`; now asserts the relay target only.
  **CORRECTION to the earlier entry: `slack relay cluster-status acks before webhook
  completes` was NOT a load-only flake.** It is a `grep` against a static file and fails
  3/3 deterministically in isolation — the earlier "passes in isolation" claim was wrong.
  Neither failing suite referenced `foundation`, so the not-caused-by-the-pull conclusion
  stands on the containment diff independently.
  **Retro written: lib-foundation `docs/retro/2026-09-12-v0.4.17-retrospective.md` on branch
  `docs/v0.4.17-retrospective` (`e6fff6a`, pushed, NO PR).** Put on its own branch so the
  package-rename PR's diff stays at exactly 3 identity lines. Note v0.4.13–v0.4.16 have no
  retro; this resumes the practice rather than back-filling.
  Superseded detail (kept for the record): #51 was branch `release/v0.4.17`, commit
  `058b209`, and promoted `CHANGE.md` `[Unreleased]` to `## [v0.4.17] — 2026-09-12` and nothing
  else (diff is 2 added lines, 0 removed; verified). Empty `[Unreleased]` kept per the
  `31be1f7` (v0.4.15) precedent. **Decision 2026-09-12 (user): lib-foundation `main` advances
  ONLY through PRs — a direct promotion commit to main was offered and declined.** After #51
  merges: tag `v0.4.17` at the merge commit, cut the release from that section body (notes ==
  section body verbatim, per v0.4.16), then `git subtree pull` the ACG tree into k3d-manager.
  **All gates GREEN on #51: CI 3/3, Copilot 🟢 Approval recommended (0 findings), 0 unresolved
  threads, `mergeStateStatus: CLEAN`.** Copilot again answered only after `reviewRequests` had
  read `[]` — consistent with the #50 lesson: poll `reviews`, not `reviewRequests`.
  Claude does NOT merge.
  Branch-protection restore is **N/A for lib-foundation** — ruleset-guarded
  (`deletion`, `non_fast_forward`, `copilot_code_review`), no `enforce_admins` or
  required-approval lever; `/branches/main/protection` 404s by design.
  **`shopping-cart-infra` #97 MERGED 2026-09-12 20:25Z as `1b35d962` — `enforce_admins`
  RESTORED to `true` (verified `.enabled: true` via bodyless POST). Main pulled
  fast-forward `4263d36..1b35d96`. No tag: CHANGELOG has only `[Unreleased]`.**

  #49 MERGED as `cf62d41`; the prism branch was rebased onto it and force-pushed by the USER
  (`e12d41a...685031a`, forced) after the classifier denied Claude the force-push.

  **Rebase detail:** User merged #49 (`fix(acg): mask GCP username in provider debug log`)
  2026-09-12. Claude rebased the 10-commit prism branch onto the new `origin/main`;
  new tip `685031a` (was `e12d41a`), backup ref `backup/prism-pre-rebase` kept at `e12d41a`.
  The only conflicting file was `CHANGE.md` `[Unreleased]` and it conflicted **4 times**,
  not once — 6 of the 10 commits touch it, so each replayed CHANGE.md commit re-conflicted
  against #49's `### Security` block. Every resolution was the same: keep BOTH sides, my
  bullet appended under `### Fixed`, #49's `### Security` after it (Keep-a-Changelog order).
  Verified: `[Unreleased]` has exactly `### Fixed` + `### Security`, 6 bullets, #49's entry
  present exactly once, zero conflict markers, and `git diff backup/prism-pre-rebase HEAD`
  over all non-CHANGE.md paths shows **only** #49's `gcp.js` line — i.e. none of my code
  moved. Gates re-run green on the rewritten SHAs: `make check`, `make lint`,
  `make shellcheck-lib`, **137 BATS**, Playwright e2e 7/7, **jest 28/28**
  (`npm test` in `scripts/lib/acg` — `make test` runs only the Playwright set, they are
  DIFFERENT suites), and the **live `make credential-test PROVIDER=aws` again green with no
  restart**.
  Claude's `git push --force-with-lease` was denied by the auto-mode classifier
  (`[Git Destructive]`); the user ran it instead. Lesson: a post-rebase force-push of a
  FEATURE branch is Claude-blocked — plan on handing it to the user, or integrate with a
  merge commit instead of a rebase.
  **Do NOT force-push the k3d-manager or lib-foundation `main`** — feature branch only.

- **LIVE GATE PASSED 2026-09-12 — `make credential-test PROVIDER=aws` is GREEN.** It was
  never blocked on Homebrew. The host already has a **working aws CLI v1 at
  `~/.pyenv/shims/aws` (aws-cli/1.45.3, botocore/1.43.3)** — pure-Python, no `awscrt`
  native lib, so the `libaws-c-s3` ABI break cannot touch it. Homebrew's broken v2 at
  `/opt/homebrew/bin/aws` merely shadows it in PATH. Running the gate as
  `PATH="$HOME/.pyenv/shims:$PATH" make credential-test PROVIDER=aws` passes end to end:
  session OK, sandbox tab reused, 4 copyable inputs extracted, creds written, and
  `INFO: AWS credentials validated (sts:GetCallerIdentity OK)` — **no restart**, which is
  the `e12d41a` guard working on live infrastructure. `sts get-caller-identity` returns
  `arn:aws:iam::<account>:user/cloud_user`, rc=0.
  **Lesson: check for a second, working copy of a broken tool before declaring a blocker.**
  `which -a <tool>` costs nothing; "blocked on the user" was wrong for a full session.
  Homebrew's v2 is **also fixed now** — the user ran `brew upgrade awscli` (2026-09-12),
  which pulled `aws-c-s3` 1.1.0 → 1.1.1 and the `awscli` 2.36.44 → 2.36.44_1 revision
  bottle that links against it. `/opt/homebrew/bin/aws` reports `aws-cli/2.36.44` and
  `sts get-caller-identity` returns rc=0. The gate was re-run on the **default PATH** with
  no shim and passed identically, so no PATH workaround is needed going forward.
  **The PR gate for `fix/acg-prism-monogram-selector` is now MET.**

- **ACG credential-test failure — ROOT CAUSE CORRECTED 2026-09-12. `id.pluralsight.com`
  IS DEAD.** The earlier false-green diagnosis was WRONG and is retracted. Measured, not
  inferred: a throwaway signed-out Chrome profile navigating to `SANDBOX_URL` **redirects
  to `https://app.pluralsight.com/id`**, where `text=/Cloud Sandboxes/i` has **count 0** —
  absent from the DOM, so it cannot false-green. Pre-fix commit `a8342e1` run against that
  profile printed `ACG_SESSION_EXPIRED` in **8 seconds**. The specified bug does not exist.
  **Real cause:** `scripts/lib/acg/playwright/lib/sandbox.js:112` — `handleSignIn` does
  `waitForURL('**id.pluralsight.com**', {timeout: 300000})`, and `id.pluralsight.com`
  **does not resolve** (`dig` empty, `curl` → "Could not resolve host"). Pluralsight moved
  identity to a PATH on the main host. The glob can never match → deterministic 300s hang,
  twice per run (extraction + restart path). Spec:
  `docs/bugs/2026-09-12-acg-signin-wait-targets-dead-id-pluralsight-host.md` (`e547147`).
  Also stale: the `a[href*="id.pluralsight.com"]` alternative at `sandbox.js:104`, and the
  post-login wait at `:143` which matches `app.pluralsight.com/id` itself so it can return
  while still unauthenticated. NOT yet dispatched to Codex.
  `308bb3c` (negative gate) is KEPT — the same measurement validates it (all 3
  `SIGNED_OUT_SELECTORS` match the real signed-out page) — but it is no longer described
  as a bug fix; CHANGE.md corrected.

- **ACG session survives only as long as the browser process — NOT an idle timeout.**
  Read from `pw-profile/Default/Cookies`: the auth cookie `.pluralsight.com
  Identity.Session` is **non-persistent** (`is_persistent=0`, `has_expires=0`, no expiry).
  Killing Chrome discards it. The 2026-09-12 cleanup ("ensure Chrome is not active after
  test") is therefore what logged the user out. `~/Library/LaunchAgents/
  com.k3d-manager.chrome-cdp.plist` exists to hold a long-lived CDP Chrome but is **NOT
  loaded**, and is **stale — do NOT load as-is**: it points at
  `/Applications/Google Chrome.app` (the user's personal Chrome, superseded by the
  Playwright-managed Chromium) and `--user-data-dir=.../k3d-manager/profile` (current is
  `pw-profile`), and its `KeepAlive` would fight `cdp.sh` port reclaim. **Measured drift:**
  `vars.sh:21` exports `PLAYWRIGHT_AUTH_DIR=.../k3d-manager/profile` (0 pluralsight
  cookies, mtime Aug 20) while `cdp.sh` falls back to `.../pw-profile` (34 cookies incl.
  the live `Identity.Session`, mtime today) — the `credential-test` path never sources
  `vars.sh`. Spec filed:
  `docs/bugs/2026-09-12-chrome-cdp-launchd-agent-wrong-browser-and-dead-profile.md`
  (`7b7a403`). **FIXED `4389e03`** (Codex; Claude verified + committed). `vars.sh` now names
  `pw-profile`; browser resolution extracted to ONE shared `_acg_resolve_cdp_browser_bin`
  called by both `_browser_launch` and `_acg_chrome_cdp_write_plist` (so they cannot drift
  again); writer fails without emitting a plist when the browser is unresolvable, replacing
  the old `/Applications` existence check in `acg_chrome_cdp_install`.
  Claude verified beyond the gates: rendered plist passes `plutil -lint` (the added XML
  comment is valid) and macOS parses `ProgramArguments` to the Chrome for Testing binary
  with `--user-data-dir=.../pw-profile`; the REAL `~/Library/LaunchAgents` plist is
  byte-identical after the suite (BATS redirects `HOME` in `setup()`); agent still unloaded;
  `:9222` and its `Identity.Session` intact. Gates: lint, shellcheck-lib, **134 BATS**
  (2 new), npm check, jest 28/28, both dead-reference greps clean.
  **STILL AN OPERATOR STEP — not automated, deliberately:** `launchctl load` the agent, and
  only while :9222 is free (installing it against a running Chrome collides on the profile's
  `SingletonLock`).

- **Method note: a throwaway `--user-data-dir` is a guaranteed signed-out profile.** It
  reproduces the signed-out path in ~1 minute on a spare port without touching `:9222` or
  the operator's session. Use it BEFORE writing a spec from log-reading.

- **ACG session-check false-green — BUG FILED, CODEX WORKING (2026-09-12).** The live
  `make credential-test PROVIDER=aws` gate on lib-foundation
  `fix/acg-prism-monogram-selector` RAN and FAILED. Root cause is not the selector fix:
  `pageLooksLoggedIn` lists `text=/Cloud Sandboxes/i` as a logged-in marker, and that
  string renders on the signed-OUT view of `SANDBOX_URL`, so `acg_session_check.js`
  printed `ACG_SESSION_OK` for an expired session. Both escape hatches were therefore
  skipped — the `K3DM_NONINTERACTIVE=1` hard fail AND the interactive manual-login
  prompt — and the run burned two 300s `waitForURL` timeouts before dying in the restart
  path. That is why "the script still needs a human login after a while" shows up as a
  mystery timeout instead of a prompt.
  Spec: `docs/bugs/2026-09-12-acg-session-check-false-green-on-signed-out-page.md` in
  lib-foundation (`ecfc15f`, pushed). Fix = drop the two content selectors, add
  `SIGNED_OUT_SELECTORS` + `pageLooksSignedOut`/`urlLooksSignedOut` negative gate,
  warn when the `k3dm-acg-pluralsight` Keychain item is absent. Dispatched to Codex via
  `codex exec` from the lib-foundation repo. **DONE + VERIFIED 2026-09-12** — commit
  `308bb3c` on `fix/acg-prism-monogram-selector` (pushed, `origin` confirmed). Diff touched
  exactly the 3 spec'd files plus a CHANGE.md entry Claude added. Gates re-run by Claude,
  not taken on trust: `npm run check` clean, jest 25/25 in 7 suites, `make lint`,
  `make shellcheck-lib`, 132 BATS all green.
  **Blocked on the user either way:** the live gate cannot pass until the
  `k3dm-acg-pluralsight` Keychain item exists (username+password) or someone signs in
  once manually in `~/.local/share/k3d-manager/pw-profile`. MFA accounts = manual only.
  Still NO PR for `fix/acg-prism-monogram-selector`.

- **Keycloak/LDAP landing sequence — STEP 1 OF 3 DONE 2026-09-12.** User chose the
  B.3-correct order: land the openldap repoint first, then the hook fix, then one
  operator sync. **PR #96 `fix/sso-federate-openldap0` MERGED** to
  `shopping-cart-infra` main as `4263d36b` (11:49Z); `45def89..4263d36`.
  Post-merge done: `enforce_admins` re-enabled (verified `enabled=true`),
  `required_approving_review_count=1` intact, local main synced. CHANGELOG is
  `[Unreleased]` only → no tag, no release.
  Copilot caught a real defect Claude missed on that PR: the reconcile hook's LDAP
  group mapper still hardcoded `groups.dn: ou=groups,dc=shopping-cart,dc=local`
  (would have broken group sync and ArgoCD RBAC), and `membership.user.ldap.attribute`
  had to go `uid`→`cn` because the seed stores `member: cn=<user>,ou=users,dc=home,dc=org`.
  Both fixed in `7be63e3`.
  **STEP 2 DONE 2026-09-12: PR #97 the hook fix MERGED as `1b35d962`** — branch
  `fix/keycloak-reconcile-pipefail-ldap-federation` @ `a5838c19`; CI was 4/4 green
  (YAML Lint, Kubeconform, Kustomize Build, GitGuardian). CHANGELOG entry landed.
  Post-merge: `enforce_admins` re-enabled on `shopping-cart-infra` main (verified
  `enabled=true`), local main fast-forwarded `4263d36..1b35d96`. No tag/release —
  CHANGELOG carries only `[Unreleased]`, so the skip-tagging rule applies.
  **Both B.3 code fixes are now on main; the remaining gap is purely cluster-side.**
  **STEP 3: operator sync with hook replay**, then verify the realm has a
  `UserStorageProvider` and users resolve from `ou=users,dc=home,dc=org`.
  **Live impact confirmed 2026-09-12:** neither fix synced to the cluster yet — the
  `shopping-cart` realm has **0 users** and no `UserStorageProvider` (osixia `ldap`
  pod still live, not `openldap-0`), so ALL logins fail — this is the true cause of
  the `make status` "Keycloak login" red, NOT a keycloak crash. The 67-restart
  `keycloak-0` StatefulSet is gone; keycloak is now a healthy Deployment
  (`keycloak-55d5d4c998-*`, 0 restarts).

- **k3d-manager PR #124 (dependabot browserslist 4.28.2→4.28.9) — REVIEWED 2026-09-12,
  DO NOT MERGE AS-IS.** It patches
  `scripts/lib/foundation/scripts/lib/acg/package-lock.json`, i.e. **inside the
  lib-foundation subtree** (and the nested lib-acg copy) — merging it writes straight
  into a subtree, which the edit-upstream-first rule exists to prevent; the next
  `git subtree pull` would conflict or silently revert it. `browserslist` is a
  **transitive** dep (not in lib-acg's `package.json`; pulled in via jest/babel at
  `^4.24.0`). Both upstreams are still at 4.28.2 and NEITHER has a
  `.github/dependabot.yml`, so upstream will never file this bump itself — that is
  the structural gap. Backing alert is real but effectively unreachable here:
  GHSA-73wf-gq98-2v4g (high, open, alert #9) needs an untrusted
  `browserslist-stats.json`, which this repo has none of; GHSA-c83g-rgw3-j3cx
  (alert #8) is already auto-dismissed.
  **Fix landed upstream: lib-foundation PR #47** (`fix/browserslist-4.28.9-ghsa-73wf`
  @ `7b2adbd`). Routing settled by [[project_lib_acg_absorption]]: standalone `lib-acg`
  is LEGACY/diverged, so acg fixes belong in lib-foundation's native `scripts/lib/acg/`
  (precedent: brace-expansion bump `efaf31b`) — NOT lib-acg. Lockfile regenerated with
  `npm update --package-lock-only browserslist` (not hand-patched); resulting diff is
  23+/23- over the same six packages as Dependabot's = identical scope. Gates: CI **3/3
  green** incl. the `acg (node)` job that runs `npm ci` from the committed lockfile;
  Copilot **approval recommended, 0 comments, 0 unresolved**; `npm audit` no longer
  reports either browserslist advisory; `mergeable_state: clean`. **MERGED 2026-09-12 as
  `12aa9a06`.** Correction: lib-foundation `main` is NOT unprotected — the classic
  `/branches/main/protection` endpoint 404s because it is guarded by **ruleset `13934293`**
  ("Copilot review for default branch", `enforcement: active`, `bypass_actors: []`, rules
  `deletion`/`non_fast_forward`/`copilot_code_review`); see
  [[reference_classic_protection_404_on_ruleset_repos]]. #47 still needed no override —
  Copilot had reviewed it, so the rule was satisfied.
  **Release follow-up: lib-foundation PR #48** (`release/v0.4.16`, `2ef907c`) — promotes
  `CHANGE.md` `[Unreleased]` → `## [v0.4.16] — 2026-09-12` and records the unported
  lib-acg selector (below). Docs-only, 2 files. CI green, Copilot review completed with
  0 comments, `mergeStateStatus: CLEAN`. **MERGED 2026-09-12 as `10de7f4c`.** NOTE: release stamps used to
  go straight to `main` (`31be1f7`, `c1df1be`); this session's auto-mode classifier denies
  both `git commit` on `main` ([CI Bypass]) and `git push origin main` ([Merge Without
  Review]), so the stamp went through a PR instead.
  **Chain COMPLETE 2026-09-12:** tag `v0.4.16` pushed on `10de7f4c` → GitHub release
  https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.16 → `git subtree pull
  --prefix=scripts/lib/foundation lib-foundation main --squash` on `k3d-manager-v1.33.0`
  (`1de3b1e0`; vendored `browserslist` now 4.28.9, verified in the lockfile) → **k3d-manager
  #124 CLOSED** unmerged with a comment explaining the subtree routing. k3d-manager itself
  has no `.github/dependabot.yml` — this PR came from default security-updates-only, and
  adding one to lib-foundation remains the open structural fix.

- **lib-acg absorption Phase 3 (archive) — DONE 2026-09-12.** `wilddog64/lib-acg` is now
  `archived: true` (flipped after #48 merged; API confirmed). Last pushed 2026-07-30. Its one
  stale open PR (#47, `fix/acg-session-profile-selector`) was triaged and **closed**
  unmerged with a pointer comment. Triage result: the `bin/acg-credential-test`
  undefined-`_sts_valid` half was already fixed in lib-foundation earlier
  (`docs/bugs/2026-06-23-acg-credential-test-undefined-sts-valid.md`), but the
  `.psPrismAvatar .psPrismMonogram[aria-label]` selector was **genuinely never ported** —
  lib-foundation's `LOGGED_IN_SELECTORS` in
  `scripts/lib/acg/playwright/lib/pluralsight_login.js` still lacks it. Carried forward as
  `docs/bugs/2026-09-12-acg-logged-in-selectors-missing-prism-monogram.md` (in PR #48).
  It needs a live `make credential-test PROVIDER=aws` gate, so it is tracked not
  blind-ported. Archive flip was held until #48 merged so the carry-forward record reached
  lib-foundation's default branch first — verified present on `origin/main` before the flip.
  Archiving does not delete lib-acg's PR branches or diffs; they stay readable read-only. See
  [[project_lib_acg_absorption]].

- **v1.32.1 SECURITY HOTFIX RELEASED (2026-09-13) — PR #125 MERGED `062dd9ab`; tag + release v1.32.1; enforce_admins re-enabled (verified true); Dependabot #9/#10 fixed (0 open); main merged into v1.33.0 `3a37ca1a`. Retro `docs/retro/2026-09-13-v1.32.1-retrospective.md`.** History: Subtree pull of
  lib-foundation `9c0af5b` onto a branch from `main` to close Dependabot #9/#10. Blocked on 2 valid
  Copilot findings in vendored acg code, being fixed upstream on lib-foundation
  `fix/acg-cdp-plist-silent-fail-and-missing-cli-msg` → lib-foundation #54 MERGED `023f76e`, re-pulled into v1.32.1 + v1.33.0, #125 thread resolved, CI green. **#125 merge-ready.** Post-merge done (see header). Full detail in
  progress.md. Worktree: `~/src/gitrepo/personal/k3d-manager-v1.32.1`.

- **2 high npm advisories in the acg module — FIXED 2026-09-12 (Codex), NOT YET A PR.**
  `npm audit` in lib-foundation `scripts/lib/acg/` reported `brace-expansion` 1.1.16
  (GHSA-mh99-v99m-4gvg, GHSA-rgw5-rvv9-x895) and `js-yaml` 3.15.1 (GHSA-2883-xcg3-v3hh),
  both high. **Exposure is dev-only:** both are transitive deps of `jest@29.7.0`, marked
  `"dev": true`, unreachable from any runtime path (the runtime dep is `playwright`) —
  measured paths are in the spec. Patched releases already satisfied the semver ranges jest
  requests (`^1.1.7` → 1.1.18, `^3.13.1` → 3.15.2), so **no `overrides`, no `package.json`
  change, no jest bump** were needed — just a stale lockfile. Fix proven in a throwaway copy
  BEFORE writing the spec: `npm update brace-expansion js-yaml --package-lock-only
  --ignore-scripts` changes exactly 6 lines across 2 entries and yields `found 0
  vulnerabilities`.
  Branch `fix/acg-npm-audit-brace-expansion-js-yaml` off `origin/main` `92d8852`. Spec
  `docs/bugs/2026-09-12-acg-npm-audit-brace-expansion-js-yaml.md` (`1fa457c`), Codex fix
  `7d26515`, Claude follow-up `1d48a68`. Tip = `1d48a68` = `origin/...` (verified).
  **Codex DID commit and push this time** — the `.git/index.lock` denial from the BATS task
  did not recur in lib-foundation, so that limit is not universal; still verify, never assume.
  **New sandbox boundary found:** `codex exec --sandbox workspace-write` cannot write
  `~/.npm`, so npm dies with `EPERM ... /Users/cliang/.npm/_cacache` (whose message
  misleadingly blames root-owned cache files and suggests `sudo chown`). Codex resolved it
  cleanly on its own with `NPM_CONFIG_CACHE=/private/tmp/...` — no sudo, no chown. **Pre-set
  `NPM_CONFIG_CACHE` inside the sandbox roots in any future npm handoff prompt.**
  **Real defect in Codex's output, caught by verification:** the spec said to add the entry
  under `[Unreleased]` "in a `### Security` subsection (create it if absent)" — Codex found an
  existing `### Security` and appended to it, but that one belongs to the **already-shipped
  `[v0.4.17]`** section. Moved to `[Unreleased]` under its own heading in `1d48a68`, asserted
  positively (entry's nearest `## ` heading is `[Unreleased]`; 0 occurrences inside v0.4.17;
  v0.4.17's `### Security` gcp.js entry still intact). Second instance of
  [[feedback_clean_rebase_is_not_correct_rebase]] — this time from an agent, not a rebase.
  **My spec wording invited it: "create it if absent" does not say which section's subsection.**
  Gates re-run by Claude independently: `npm ci` → `found 0 vulnerabilities`, `npm audit` → 0,
  `npm test` → 7 suites / 28 tests, installed versions 1.1.18 / 3.15.2, diff contained to
  exactly 3 files, `package.json` untouched.
  **PR #53 MERGED 2026-09-13 as `9c0af5b`; subtree pulled into k3d-manager (`3fa3df41`), vendored
  tree == lib-foundation main, BATS 824/0.** (History: opened once #52 merged.) `main` merged
  in (CHANGE.md `[Unreleased]` conflict resolved keeping both entries, placement asserted), gates
  re-run, CI 3/3 green, Copilot approval recommended with 0 comments. The user merges.
  **Then ONE subtree pull into k3d-manager for #52 + #53 together.**

- **lib-acg residue cleanup — 2026-09-12.** Three leftovers from the absorption, handled:
  (1) **Package identity re-homed.** `scripts/lib/acg/package.json` + `package-lock.json` in
  lib-foundation still declared `"name": "lib-acg"` — inherited by the v0.4.0 verbatim
  tree-copy. Renamed `lib-acg` → `lib-foundation-acg` on branch
  `fix/acg-package-name-identity` (`a63884c`, pushed), spec
  `docs/bugs/2026-09-12-acg-package-name-still-lib-acg.md`. Diff is exactly 3 identity lines;
  `private: true`, never published, nothing resolves it by name; jest 28/28 green after.
  **Brought forward onto v0.4.17 main 2026-09-12 — branch tip is now `31a648f`
  (`2556023` = merge of `92d8852`, then `31a648f`).** Deliberately done as a MERGE, not a
  rebase: the rebase (tried first in a throwaway worktree) rewrote the branch and would have
  needed `--force-with-lease`, which the classifier denies on feature branches. The merge
  path was proven equivalent by **tree equality** — both produce tree
  `254e952f179e6ace5e0605d1365318924725e89f` — and pushed as a plain fast-forward.
  **Real defect the rebase exposed:** #51 promoted `[Unreleased]` to `## [v0.4.17]` while this
  branch was open, so the rename entry — placed at the END of `[Unreleased]` precisely to
  dodge a conflict — silently ended up INSIDE the shipped v0.4.17 section. It applied without
  conflict, so nothing flagged it. Moved to `[Unreleased]` in `31a648f`; verified the v0.4.17
  section is byte-untouched (CHANGE.md diff vs main is additions only, 0 deletions).
  **Lesson: a clean rebase is not a correct rebase — conflict-avoiding placement can be
  semantically wrong once the anchor it dodged gets promoted.**
  Post-merge state re-verified: `npm ls` → `lib-foundation-acg@0.4.0`, jest 28/28.
  **PR OPENED 2026-09-12 on the user's go-ahead: lib-foundation #52, head `a2a61c3`.**
  Pre-PR gates run locally first: `npm ci` resolves under the new name with no lockfile churn,
  `npm test` 7 suites / 28 jest green, both JSON files parse and agree on `name`. CI after the
  PR: `acg (node)`, `bats`, `shellcheck` all **pass**. Copilot reviewed (COMMENTED, 1 inline
  finding) and it was **right**: the spec's verification bullet claimed "the two files are the
  only ones changed" while the branch also touches `CHANGE.md` and adds the spec doc itself.
  Reworded in `a2a61c3` to scope the claim to the two metadata files and name the doc-only
  files explicitly; thread replied + resolved via GraphQL, 0 unresolved.
  **No admin-override step exists or is needed here** — `main` carries a ruleset with only
  `deletion` / `non_fast_forward` / `copilot_code_review` (classic protection 404s, as
  [[reference_classic_protection_404_on_ruleset_repos]] predicts), so there is no required-review
  or `enforce_admins` lever to drop. **#52 MERGED 2026-09-13 as `a1331a6` by the user.**
  The live `make credential-test PROVIDER=aws` gate was deliberately NOT run for #52 and that
  is recorded in the PR body: it covers ACG login/credential behaviour, and this change touches
  no runtime path — two JSON metadata fields in a private, never-published package. The gate
  stays outstanding independently.
  **RESOLVED 2026-09-13:** the k3d-manager subtree now reads `"name": "lib-foundation-acg"` after
  the `3fa3df41` subtree pull (carried #52 + #53 together).
  The ~89 other `lib-acg` references (CHANGE.md, docs/plans, docs/bugs, docs/issues,
  README.md, docs/api/acg.md) are **provenance and deliberately unchanged** — rewriting them
  would falsify where the code came from.
  (2) **Orphaned `scripts/lib/acg/` in k3d-manager DELETED** — 51M / 4,482 files, 0 tracked,
  contents were `node_modules` only. The real subtree lives at
  `scripts/lib/foundation/scripts/lib/acg/`; the standalone path was retired in v1.8.0.
  (3) **Local `~/src/gitrepo/personal/lib-acg` clone — DELETION CANCELLED 2026-09-12 by the
  user's explicit decision: "we don't need to remove lib-acg, archive github lib-acg is good
  enough."** It stays on disk. This is no longer a pending user action — do not re-propose it.
  The safety work below was already done and still holds, so the clone remains disposable at
  any time if that ever changes.
  (Original note: deletion was classifier-denied for Claude anyway.) First made it safe: 175 commits across 48 local branches were unreachable
  from remote `main` `7708ae31b` (35 branch tips + 2 stashes). Mostly pre-squash history of
  merged PRs, but not provably all. Bundled every ref to
  `~/src/gitrepo/personal/lib-acg-final-archive-2026-09-12.bundle` (860K, 76 refs,
  `git bundle verify` = "complete history"), with the two stashes preserved as tags
  `archive/stash-0` / `archive/stash-1`. **Test-restored from the bundle (50 branches,
  15 tags, stash commits intact) before declaring it safe** — so deleting the clone is
  reversible via `git clone <bundle>`. All remote tags (v0.4.0/v0.3.0/v0.1.9…) survive on
  the archived repo independently.

- **Product catalog empty DB — ROOT-CAUSED AND REPAIRED 2026-09-11.** The
  `product-catalog` API served `HTTP 200` over a zero-row database for ~12h.
  `argocd-repo-server` was crash-looping (28 restarts) during the
  `11:11:44Z → 11:18:51Z` sync, which died on `ComparisonError: ... dial tcp
  10.43.86.193:8081: connection refused (retried 5 times)` **before the PostSync
  phase**, so the `product-catalog-seed` and `product-catalog-fts-index` hooks
  never ran. Because every tracked resource still compared `Synced`, there was no
  drift and auto-sync could never replay them — the app sat green indefinitely.
  Repaired by an operator-initiated sync (`kubectl patch application
  ubuntu-k3s-shopping-cart-product-catalog --type merge -p
  '{"operation":{...,"sync":{"syncStrategy":{"hook":{}}}}}'`); both hooks ran and
  self-deleted per `HookSucceeded`. Verified: 1000 rows (Accessories 350,
  Electronics 250, Monitors 200, Peripherals 200) and
  `https://frontend.3ai-talk.org/api/products` returns HTTP 200 with real items.
  Note `shopping_cart_reconcile_product_catalog()` could not have helped — every
  kubectl call in it hardcodes `--context ubuntu-k3s`, which does not exist
  locally, and all failures are swallowed by `|| _info WARN`.

- **Hermes ArgoCD operation-phase blind spot — IMPLEMENTED + VERIFIED 2026-09-11,
  commit `6014235f` on `origin/k3d-manager-v1.33.0`.** `argocd()` in
  `scripts/lib/hermes/sensors.py` classified apps by `health`/`sync` only and never
  read `status.operationState.phase`, so the failure class above was undetectable.
  Spec: `docs/bugs/v1.33.0-bugfix-hermes-argocd-operation-phase-blindspot.md`. Added
  module constant `TERMINAL_OPERATION_FAILURES = ("Error", "Failed")` and an `elif`
  branch (deliberately not a third `or`, so existing alert text stays byte-identical
  and the signal is purely additive); resolves app name/project from the real CR
  shape (`metadata.name`/`spec.project` — the old `app.get('name','unnamed')`
  rendered every alert as `default/unnamed`); appends `(+N more)` on truncation.
  Debounce channel stays `"argocd"` — no new sensor name, record type, or Slack
  route. Detection only; no auto-remediation. Gate: `pytest scripts/tests/hermes/ -q`
  → **57 passed**. Codex implemented `sensors.py` exactly per spec, then correctly
  REFUSED to commit because one of my spec's test lines was defective (a fresh `{}`
  constructed per comprehension iteration reset `_debounced`'s counter, so it could
  never cross `threshold=3`); Claude fixed it with a shared `error_state` and
  committed. My spec's predicted `58 passed` was wrong arithmetic (2 new tests on a
  55 baseline) — corrected to 57 in the same commit. Non-vacuity proven by stashing
  only `sensors.py`: `2 failed, 55 passed`.

- **`ubuntu-k3s-data-layer` RECOVERED 2026-09-12** by operator-initiated sync
  (same lever as product-catalog). The drift was NOT caused by the outage: three
  `shopping-cart-payment` ExternalSecrets (`payment-encryption-secret`,
  `payment-gateway-secrets`, `postgres-payment-app`) stored `refreshInterval: 15m0s`
  where git has `15m`. `kubectl diff` confirmed that was the only real difference,
  and `git log -S'15m0s'` in `shopping-cart-infra` returns zero matches — so the
  normalized value came from an out-of-band `kubectl apply` during the 2026-09-11
  hub ESO recovery, not from the repo. **Key mechanism learned:** the app had
  `syncPolicy.automated.selfHeal: true` and real drift, yet self-heal never fired
  for 14h — ArgoCD suppresses automated retry of a revision whose last operation
  terminally failed. So `operationState.phase=Error` blocks self-heal *even when
  drift exists*; my earlier note that "it has drift so auto-sync could recover it"
  was wrong. This widens the blast radius of the blind spot the Hermes fix above
  now detects.

- **`shopping-cart-identity` root-caused 2026-09-12 — SPEC WRITTEN, NOT IMPLEMENTED.**
  `docs/bugs/2026-09-12-bugfix-keycloak-reconcile-pipefail-and-missing-ldap-federation.md`.
  Its `keycloak-realm-reconcile` PostSync hook has been `Failed` since
  `2026-09-11T01:54:41Z`, exiting 1 with **no error output** and a success line as its
  last log entry. Cause: the script runs `/bin/bash -euo pipefail`, and
  `ldap_id="$( kcadm get components ... | grep '"id"' | ... )"` returns nothing, so
  `grep` exits 1, `pipefail` propagates it, and `set -e` kills the script on a plain
  assignment — making the `else` "No LDAP component found; skipping mapper setup"
  branch **unreachable**. Four more unguarded `grep`-in-`$()` sites have the same
  latent silent-death (their explicit `ERROR: could not resolve ...` diagnostics can
  never print). **Second, worse defect:** the `shopping-cart` realm has **zero users
  and no `UserStorageProvider` component** even though `realm-shopping-cart.json:359`
  declares an LDAP one, the `ldap` pod is Running, and `partialImport` exited 0 — so
  nothing can authenticate against that realm. This is the likely real origin of the
  Keycloak smoke-user / frontend-login warnings (Findings 4/5), which have been
  triaged as seed/credential problems. It also **contradicts**
  `shopping-cart-infra/docs/bugs/2026-05-15-keycloak-ldap-mappers-missing-from-reconcile.md`,
  which claims partialImport *does* create the top-level component. `|| true` alone
  would convert a crashing job into a green job that configures nothing, so the fix
  must also create the component or fail loudly. Work repo is `shopping-cart-infra`
  (spec-first, Codex-only, feature branch).
  **DISPATCHED to Codex 2026-09-12** — spec made dispatchable in `cd424371` +
  `fe041b83`; branch `fix/keycloak-reconcile-pipefail-ldap-federation` created by
  Claude from `origin/main` @ `45def89` because the codex sandbox denies `.git`
  writes (it also cannot `checkout`/`fetch`, not just `commit`). Changes that
  unblocked it: **B.1 demoted from blocker to open question** (needs a scratch realm
  on live Keycloak = operator action; B.2 is correct under either answer);
  **`keycloak:24.0` ships no `jq`/`python`/`awk`, only `sed`** (probed the image), so
  the component body is `sed`-range-extracted from the *rendered* realm JSON —
  verified locally as valid JSON with all 24 `config` entries, `providerType`
  injected and `parentId` omitted so Keycloak defaults it to the realm; all five
  `grep` sites given literally (120/138/160/**182**/**257** — the last two differ
  only by two spaces); the silent `else` skip replaced by a hard failure instead of
  dedenting ~100 lines. **B.3 landing-order constraint:** create-if-absent is not
  reconcile-to-desired, and unmerged `fix/sso-federate-openldap0` (`d02e6622`, not in
  `origin/main`) repoints this same component from osixia to `openldap-0` — the fix
  is config-agnostic and the branches touch disjoint files, but landing the fix first
  creates a federation aimed at the retired directory that will never be updated.
  Land `fix/sso-federate-openldap0` first, else delete the stale component once.
  **2026-09-12 — user chose the B.3 order ("Land openldap repoint first, then fix,
  then sync"). `fix/sso-federate-openldap0` is now PR #96, merge-ready:** CI 4/4,
  Copilot 2/2 fixed (`7be63e3`) + resolved, `enforce_admins` disabled (RE-ENABLE
  AFTER MERGE). Copilot found a defect I missed — the hook's group mapper still used
  `ou=groups,dc=shopping-cart,dc=local`, which would have broken group sync and
  ArgoCD RBAC; also corrected `membership.user.ldap.attribute` uid→`cn` to match the
  seeded `member: cn=...` DNs. Verified the fix's `sed` extraction against this
  branch's realm JSON in the real image — composes correctly, yields openldap values.
  Nothing merged, nothing synced.
  **IMPLEMENTED + VERIFIED 2026-09-12 — `a5838c19`, pushed, local == origin.** Codex
  wrote it, Claude verified and committed. 1 file, +38/-6. `YAML OK`; shellcheck 0
  warnings both before and after; `bash -n` clean; five spec sites guarded
  (120/138/160/182/288) + the new re-resolve at 207; realm JSON untouched; `pipefail`
  intact. Went past the spec's gates and **executed the `sed` extraction inside
  `quay.io/keycloak/keycloak:24.0`** — necessary because the host runs BSD `sed` while
  the recipe depends on GNU `sed` honouring `\n` in the replacement: 1781 bytes of
  valid JSON, `providerType` present, 24 `config` entries, credential substituted, no
  placeholder left. **Negative test:** reindenting the realm file to 8 spaces empties
  the extraction and trips the `[ ! -s ]` guard, so a future reformat fails loudly
  rather than silently skipping the user store. `shopping-cart-identity` is still
  `Failed` — the manifest is landed but nothing has synced it, and no PR exists
  (gated).

- **Hardcoded `ubuntu-k3s` context — folded into the existing portability spec, NOT a
  new bug doc.** `docs/bugs/2026-07-07-app-cluster-vault-portability.md` already owns
  this as Phase 3, so per the dedup rule the measured inventory was appended there:
  24 literal `--context ubuntu-k3s` occurrences in `scripts/plugins/shopping_cart.sh`
  across exactly three functions (`shopping_cart_reconcile_product_catalog` 13,
  `shopping_cart_reconcile_order_service` 6, `deploy_shopping_cart_data` 5), with the
  default-preserving resolver `_shopping_cart_resolve_app_context()` already present
  in the same file at `:553-563` and already consumed at `:161/:221/:407/:498`.
  **Correction to my earlier note:** this is not "dead code" — `ubuntu-k3s` is the ACG
  sandbox context and these functions belong to the `acg-up`/`bin/cluster-up:1831`
  flow where it is correct; the defect is the coupling plus the fact that every call
  swallows failure via `|| _info WARN`, so the function reports success while doing
  nothing. Phase 3 still needs its decision-#1 re-scope before an implementation spec.

- **Hub recovery execution:** M2 copy is checksum-verified. The new recovery
  helper has read-only validated seven source claims, resolved all seven live PV
  targets, and rendered a container-aware dry run. Next guarded rung is the
  control-plane replacement; no cluster volume has been deleted.

- **Hub incident 2026-09-09 — mitigated, durable retention work OPEN.** Hub K3s
  Kine SQLite state was 8.3G plus a 537M WAL, with 1,013,597 retained rows and
  zero freelist pages; integrity check and offline `VACUUM INTO` proved it was
  real history, not safely reclaimable free space. Stale ACG ArgoCD registration
  (`cluster-ubuntu-k3s` → `host.k3d.internal`) drove `Unknown` application
  retries. Hub `/readyz` has recovered, stale registration is unlabelled, and
  `argocd-application-controller` remains deliberately scaled to zero until
  stale applications are cleaned up. Hostinger status now returns structured
  `WARN` with 20/20 ESO synced; monitoring is intentionally paused. Separate
  signing bug fixed locally: Hostinger's Vault auth mount was hard-coded to hub
  `kubernetes`; `SIGNING_ESO_AUTH_MOUNT` makes it provider-specific. Details:
  `docs/issues/2026-09-09-hub-kine-history-and-hostinger-cosign-role.md`.
  **Hermes Kine circuit-breaker IMPLEMENTED (2026-09-09, `0e86974d`):** live
  read-only evidence is now 8,831,115,264 bytes and repeated Slow SQL with no
  COMPACT event in a 30-minute window. New v1.33 plan/bug introduce a bounded,
  opt-in stale-ACG circuit breaker; never raw SQLite retention deletion. It is
  is enabled in the live LaunchAgent (`K3DM_HERMES_AUTO_KINE_GUARD=1`) and
  launchd-verified running. It cannot act on the current state because stale
  registration is false. Live
  read-only probe verified after push: 8,831,115,264 bytes / 3 Slow SQL events /
  recent compaction seen / stale registration false; therefore it will monitor
  but cannot trigger the circuit breaker on the current signature.
  **Controlled rebuild execution authorized:** plan
  `docs/plans/v1.33.0-hub-kine-controlled-rebuild.md`; backup/inventory rung
  started. Hard gate: second verified archive copy before any datastore-volume
  removal. First capture safely BLOCKED on an invalid/truncated archive; raw
  offline inputs exist but are unverified. Hub restarted and `/readyz=ok`; no
  data/volume deletion occurred. Details:
  `docs/issues/2026-09-09-hub-rebuild-online-kine-backup-truncated.md`.
  M2 external-copy is in progress using the verified MeshHome address after
  intermittent mDNS; macOS rsync requires `-aHE --partial --progress` (not
  Linux `-A`/`--info=progress2`). Rung 4 remains blocked pending a complete,
  checksum-verified second copy.
  **Additional rebuild blocker (2026-09-10):** k3d normal recreate replaces
  all agents, but durable local-path data is agent-local and has no tested
  old-PVC→new-PVC restore mapping. See
  `docs/issues/2026-09-10-hub-rebuild-agent-volume-restore-gap.md`; do not
  run a cluster recreation until a restore rehearsal exists.
  Restore-mapped plan #4/5 now records the seven logical claims and restore
  dependency order: `docs/plans/v1.33.0-hub-local-path-restore.md`.
  **M2 recovery copy checksum-verified 2026-09-10:** `COPY_CHECKSUM_VERIFIED`;
  an M2 SSH timeout interrupted the first transfer but `rsync --partial`
  resumed safely. Incident: `docs/issues/2026-09-10-hub-backup-monitor-ssh-retry-gap.md`.
  New `hub_recovery_{plan,validate,restore}` preflight helper is offline-gated;
  it has not recreated or deleted any hub resource.
  Read-only `hub_recovery_targets k3d-k3d-cluster` rehearsal passed for all
  seven PVs; restore implementation must stream into k3d node containers,
  because target local-path values are not host filesystem paths.

- **Hub red items ALL CLOSED 2026-09-13 (Claude, user said "close those open items"):**
  `make status CLUSTER_PROVIDER=k3s-hostinger` → **Overall: HEALTHY** (Keycloak token
  minted, Frontend /api/cart 200, ArgoCD 200, Grafana 200). All Argo apps Healthy.
  (1) Identity hook: first hook sync FAILED at LDAP sync — `identity/sts/openldap`
  was left at `replicas: 0` by the restore (helm declares 1); scaled to 1, replayed
  hook sync → Succeeded (realm now has LDAP UserStorageProvider + mappers). (2)
  Smoke user `identity/k3dm-smoke-user` was absent → `KEYCLOAK_BASE_URL=https://keycloak.3ai-talk.org
  keycloak_seed_smoke_user` (default `keycloak.shopping-cart.local` unresolvable on hub).
  (3) User chose RE-SEED: Vault `secret/platform-ops/app-cluster-hostinger` seeded
  via stdin from hostinger read-only SA `platform/hub-cve-inventory-reader-token`
  → ES SecretSynced, exporter serves 62 shopping-cart CVE series; hub-platform-ops
  Healthy (residual OutOfSync on the ES is a defaulted-field diff, auto-sync
  Succeeded). (4) Vault root token stored in Keychain service `k3dm-vault-root-token`
  account `k3d-k3d-cluster` (user request; via `security -i` stdin). (5) Specs READY
  FOR CODEX (decisions answered: extend register_app_cluster; eso-apps as 2nd policy
  on eso-ldap-directory; provider-keyed `origins.tsv`; separate
  `hub_recovery_reconcile --confirm`; user wants all of it automated):
  `docs/bugs/2026-09-13-hub-recovery-manual-fixes-not-declarative.md` (6 defects,
  C1-C6; found latent bug: `_vault_configure_secret_reader_role` overwrites role
  policies → LDAP re-run detaches eso-apps),
  `docs/bugs/2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md` "Spec 2026-09-13"
  (provider-aware AMBIENT_CNI_* defaults), and
  `docs/bugs/2026-09-13-grafana-port-forward-plist-overwritten-by-acg-writers.md`.
  DISPATCHED to Codex 2026-09-13 (user go) — sequential codex exec A=reconcile, B=CNI, C=grafana plist; Claude verifies. M2 rollback window ends 2026-09-18.

- **Hub red-items pass 2026-09-13 (Claude):** `make status CLUSTER_PROVIDER=k3s-hostinger`
  → no control-plane errors; only ✗ Grafana login 401 (+2 known Keycloak/frontend
  login warnings). Root cause: installed grafana PF plist was a stale
  `bin/cluster-refresh`/`bin/cluster-up` variant pointing :3001 at hostinger
  `acg-kube-prometheus-stack-grafana`, while the smoke check uses hub creds →
  09-11 Finding 3 "diverged grafana.db password" is likely a MISDIAGNOSIS (do NOT
  reset-admin-password). Plist regenerated on disk from repo function (hub
  wrapper; backup in session scratchpad) — **operator reload owed**
  (bootout+bootstrap denied to agent). `hub-loki` never rendered (chart 18.2.0
  needs `test.enabled=false` when canary off) → fixed `e047a718` (pushed; Argo
  will deploy Loki on hub). `app-cluster-kubeconfig`: Vault path never seeded
  (Finding 9, seed-or-drop decision). Reconcile hook: fix merged (#97
  `1b35d962`), app tracks it, but last hook run predates merge → **operator sync
  with hook replay owed** (agent sync denied). istio-cni 4/4 pods 0/1, informers
  0/1 → operator restarted 2026-09-13, STILL 0/4: real cause = hub `istio-ambient`
  appset rendered with Cilium paths; k3d needs conf `/var/lib/rancher/k3s/agent/etc/cni/net.d`
  + bin `/bin` → operator reapplied `deploy_istio_ambient --confirm` → istio-cni 4/4 Ready, 4 app pods HBONE (no restarts), FIXED
  (recurrence in `docs/bugs/2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md`).
  Grafana PF reloaded by user → `make status` Grafana login 200, Overall WARN (0 errors).
  Declarative-recovery spec: `docs/bugs/2026-09-13-hub-recovery-manual-fixes-not-declarative.md`
  (4 design decisions open; repo static cloudflared config still has stale
  frontend `127.0.0.2:80`).

- **Hub Kine rebuild CLOSE-OUT 2026-09-13 (read-only verify, Claude):** rebuild
  executed 2026-09-11; both v1.33.0 plan docs now say EXECUTED. Verified: 4 nodes
  Ready, `/readyz` ok, `k3d cluster list` SERVERS 1/1, Kine 624 MiB (WAL 12.6 MiB),
  0 Slow SQL/1h, COMPACT every 5m ~1000 revs behind (stall cleared), 7 mapped +
  7 shopping-cart PVCs Bound, Vault unsealed. Grafana public 502 = zombie
  hostinger PF → `launchctl kickstart -k com.k3d-manager.grafana-port-forward`
  (user-approved) → local + public `/api/health` 200. Still open: `make status`
  not run; keycloak-realm-reconcile PostSync Failed (logs end silently);
  hub istio-cni-node 0/1 readiness 503; `platform-ops/app-cluster-kubeconfig` ES
  fails → hub-platform-ops Degraded; hub-loki Unknown; declarative
  registration/eso-apps/Cloudflare origins (needs `docs/bugs/` spec). M2
  rollback window ends 2026-09-18.

- **Hub recovery public-origin repair 2026-09-11:** control-plane rebuild is
  serving all four nodes again. Lost Argo `app-cluster` registration was
  restored as `ubuntu-k3s`; Vault ESO received a scoped `eso-apps` policy and
  application secrets/GHCR pulls recovered. Recovered serverlb now routes
  HTTP through Istio NodePort `192.168.97.5:31284`; Cloudflare origins were
  corrected (frontend→8000, ArgoCD→8080, Keycloak→8880). Public probes passed
  frontend API 200, Keycloak 200/302, ArgoCD UI 200, Grafana health 200, and
  Prometheus ready 200. Details:
  `docs/issues/2026-09-11-hub-recovery-public-origin-and-eso.md`. Remaining
  durability work: declare the registration/policy/origin mapping in recovery,
  and resolve intermittent Kine/API saturation plus slow payment startup.

- **v1.32.0 RELEASED 2026-09-07** — PR #123 MERGED (`f65549f0`). Shipped webhook security remediation (F1 fix-mode role gating, F3 response_url host allowlist, F2 sandbox egress hardening) + Hermes monthly security-audit (read-only CodeQL/Dependabot/branch-protection/credential-expiry digest, optional BATS security-regression subset). Gates: pytest 47 hermes / webhook.bats 64/64 on macOS, sandbox 11/11 on Linux, shellcheck clean. 1 lint failure + 2 Copilot findings in CI, all fixed before merge. Hermes↔Slack Option A split to v1.33.0 (PULL model with Slack approver MFA + 24h re-auth). Post-merge housekeeping COMPLETE 2026-09-07: enforce_admins restored true (verified), tag/release v1.32.0 published at `f65549f0` (latest, non-draft), release-ledger backfill (CHANGELOG `[1.32.0]` + releases.md/README rows + retrospective doc `docs/retro/2026-09-07-v1.32.0-retrospective.md`) + memory-bank update committed on `k3d-manager-v1.33.0`.

- **Next milestone: v1.33.0 branch** (`k3d-manager-v1.33.0` created 2026-09-07 from `f65549f0`, origin tracking). Scope: Hermes↔Slack integration **Option A** (interactive Approve/Deny buttons via PULL model: Slack approver allowlist + `24h /hermes-auth` re-auth MFA → Cloudflare KV → Hermes drains on poll → `repairs.approve()`). Spec: `docs/plans/v1.33.0-hermes-slack-approval.md`. Also pending: TwinkleAI real-estate gen-AI × MCP research platform prototype (plan-patch queued for Codex).

- **Webhook-server security audit DONE 2026-09-07** → `docs/issues/2026-09-07-webhook-server-security-audit.md`. Strong baseline; findings ranked: **F1 (HIGH)** `/ask` fix-mode escalation (`_run_cluster_ask` gets no role → a `reader` unlocks `K3DM_FIX_MODE=1` writes by phrasing "restart/resync/fix"); **F2 (HIGH)** `bin/k3dm-ask-bash` bypassable denylist + reads `~/.kube`/`~/.cloudflared`/`/etc` + `curl` GET egress → credential exfil with no bypass; **F3 (MEDIUM)** `_slack_post`/`response_url` no host allowlist → blind SSRF + exfil; **F4 (LOW)** `X-K3DM-Role` header-asserted (safe only under single-admin-token invariant). Remediation order: F1, F3 (self-contained bugfixes suitable for `docs/bugs/` now), then F2 (own plan doc, land BEFORE widening the Slack audience). Queued after: TwinkleAI plan patch.

- **Webhook remediation IN PROGRESS 2026-09-07 (branch `k3d-manager-v1.32.0`):** **F1 + F3 IMPLEMENTED + tested** — F1: threaded caller role into `_run_cluster_ask`, gated fix-mode via new `_fix_mode_enabled(question, role)` (requires operator+); reader's fix-phrased question downgraded read-only with a notice. F3: `_slack_post` now rejects non-`https`/non-Slack-host `response_url` via new `_is_allowed_slack_url` (`hooks.slack.com`/`slack.com` only). Both call sites pass role (`slack_role`/`request_role`). Bug doc `docs/bugs/2026-09-07-webhook-ask-fix-mode-role-gating.md`; 2 new BATS tests in `scripts/tests/lib/webhook.bats` (57 tests, 0 failures); CHANGELOG `[Unreleased] ### Fixed`. **F2 IMPLEMENTED** (`97d96366`) — `docs/plans/v1.32.0-ask-bash-sandbox-hardening.md` Phase 1: dropped `/etc`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `~/.kube`, `~/.cloudflared` from `_DIAG_PATHS`; blocked outbound egress outright (curl/wget/nc/ssh/scp/…); added editor/find-exec/tar-exec/awk-system blocks; blocked `make` in read-only mode; updated `claude_system` prompt to drop the "curl GET" advice. Codex (session `01a07cf6`) applied the edits but was **killed by OOM before committing** — Claude verified the on-disk diff against the spec (all 5 changes exact, scope clean), ran the gates (shellcheck clean, `bats scripts/tests/lib/webhook.bats` 62 tests 0 failures), and committed. Phase 2 (allowlist / OS-enforced boundary) = durable follow-up, documented not built; must precede widening the Slack audience. F4 = documented invariant.

- **Hermes↔Slack Option A SPEC WRITTEN 2026-09-07** → `docs/plans/v1.33.0-hermes-slack-approval.md` (split to v1.33.0 on 2026-09-07 — keeps v1.32.0 = webhook hardening + monthly audit; not yet implemented — spec-first, awaiting review). PULL model preserving off-hub/no-inbound: Hermes posts Block Kit Approve/Deny buttons via the existing incoming webhook → approver taps → `k3dm-slack-relay` worker `POST /slack/interactivity` verifies Slack sig + **approver allowlist (by user ID, separate from slash-command role map)** + **24h re-auth stamp** (`/hermes-auth` slash cmd writes `reauth:<user>` to KV with 86400s TTL; MFA enforced channel-side) → writes `approval:<action_id>` to Cloudflare KV (`APPROVALS_KV`, 1h TTL) → Hermes **drains** KV on next poll via bearer-guarded worker `GET/DELETE /hermes/approvals` → calls **unchanged** `repairs.approve()` (still re-validates precondition + one-attempt-per-incident). Nonce guards stale/superseded buttons. Opt-in via `K3DM_HERMES_APPROVAL_DRAIN_URL` (unset = today's behavior). 5 reviewable slices; new secrets `APPROVER_ALLOWLIST`/`APPROVAL_DRAIN_TOKEN` (worker) + `k3dm-hermes-approval-drain-token` (Keychain). NOTE: does NOT widen the `/ask` audience (approvers = admin set); F2-Phase-2 gate is unrelated. Watch max-5-plan cap → may split to v1.33.0.

- **Hermes monthly security-audit SPEC WRITTEN 2026-09-07** → `docs/plans/v1.32.0-hermes-monthly-security-audit.md` (not yet implemented). Read-only report (not an actuator, no repair path). Cadence = once-per-month state-dedup in the existing poll (`state["last_security_audit_month"]`, mirrors the daily token-expiry advisory — no new launchd job); plus manual `bin/k3dm-hermes audit`. Group A (API-only, core): open CodeQL alerts, Dependabot alerts, branch-protection posture (enforce_admins/reviews/ruleset), credential-expiry sweep. Group B (optional, phase 2): run the F1/F3/F2 security BATS subset behind `K3DM_HERMES_AUDIT_RUN_BATS=1`. KEY PREREQ RESOLVED 2026-09-07: all three Group-A endpoints verified to respond on this public/user-owned repo (code-scanning `[]` / Dependabot 1 (#9) / branch-protection enforce_admins=on reviews=1). Decision = dedicated read-only **fine-grained** `k3dm-hermes-audit-token` (Read on Code scanning alerts + Dependabot alerts + Administration + Metadata, scoped to this repo). R4 App rejection does NOT apply (that was App-install, not a user PAT). Only remaining: USER creates the PAT + stores in Keychain. Checks must still degrade gracefully on a missing scope (never a false clean bill). New module `scripts/lib/hermes/audit.py` (DI, mirrors preflight.py). 5 slices — no blocker for slice 1.
  - **SLICE 1 IMPLEMENTED 2026-09-07** (not yet poll-wired): `scripts/lib/hermes/audit.py` `run_audit(github_get, header_fetch, keychain, repo, now) -> (report, digest)` (Group-A: code-scanning + Dependabot severity counts, branch-protection drift, credential-expiry sweep; graceful "unavailable" on 403/404, never a false clean bill); `bin/k3dm-hermes audit` subcommand (prints digest + JSON, no dedup write); `scripts/tests/hermes/test_audit.py` (7 tests incl. no-write/no-repairs invariant). Full hermes suite 40 passed. Poll dedup = slice 2, live token check = slice 3, Group-B bats = slice 4. **KEYCHAIN FIXED + LIVE CHECK PASSED 2026-09-07:** token re-stored under `-a k3dm`; `bin/k3dm-hermes audit` ran live and produced the correct real digest (code-scanning 0, Dependabot 1 high #9, branch-protection enforce_admins=on reviews=1, audit token 90d / gh token 87d). This clears slice 3's live token check early. Remaining: slice 4 (Group-B bats), slice 5 (docs + setup).
  - **SLICE 2 IMPLEMENTED 2026-09-07:** `audit.monthly_audit_advisory(github_get, header_fetch, keychain, state, this_month, ...)` = once-per-calendar-month gate (mirrors `token_expiry_advisory`) — returns the digest + stamps `state["last_security_audit_month"]` the first time a `YYYY-MM` is seen, returns None with NO network call on later polls that month. Wired into `bin/k3dm-hermes` poll branch (posts via `post_summary`). +3 dedup tests (fire-once, month-rollover, no-network-when-already-run); hermes suite **43 passed**. Not live-poll-tested to avoid an out-of-cadence Slack post; gate is unit-covered + `run_audit` already live-verified + `post_summary` is pre-existing.
  - **SLICES 4 + 5 IMPLEMENTED 2026-09-07 — ALL 5 SLICES DONE (feature complete):** Slice 4 (Group-B bats) = `audit._security_regressions(bats_runner, run_bats)` runs `bats --tap --filter "role|fix mode|Slack host" scripts/tests/lib/webhook.bats` (the 8 F1 role/fix-mode + F3 Slack-host regression tests), TAP-parsed to passed/failed; gated behind `K3DM_HERMES_AUDIT_RUN_BATS=1` (unset → "skipped", never runs bats); a fail surfaces in `attention` + digest ⚠️. Wired into both `bin/k3dm-hermes audit` and the poll (new `_bats_run(argv)` runner, cwd=ROOT, 300s timeout). +4 tests (skipped-default, pass, fail→attention, not-run-when-disabled) → **47 passed**. LIVE-VERIFIED end-to-end: `K3DM_HERMES_AUDIT_RUN_BATS=1 bin/k3dm-hermes audit` → "Security regressions (bats): 8 passed, 0 failed ✅"; filter selects exactly the 8 intended tests. Slice 5 (docs+setup) = `docs/guides/hermes.md` new "## Monthly security audit" section (cadence, Group A/B checks, `bin/k3dm-hermes audit`, digest example, the 4-permission fine-grained-PAT table, Keychain store under `-a k3dm`, optional/degrades-gracefully), credentials table + config table rows added; `bin/k3dm-hermes-setup` prints a **non-fatal** advisory when `k3dm-hermes-audit-token` is absent (lib-foundation preflight can't be edited — subtree — so the check lives in the local bin script). shellcheck clean. `repairs`/subtree untouched; `audit.py` stays pure (bats subprocess lives in `bin/k3dm-hermes`). Ready for CHANGELOG + PR.

- **TwinkleAI plan PATCH APPLIED 2026-09-07** — edited the external plan file in `~/Downloads/` (separate project, NOT this repo): wired the LLM (`.env.example` LLM keys default `claude-sonnet-5`, `services/llm/client.ts` in Task 7, `generate-answer.ts` in Task 9), added the mock→real `/api/query` cutover in Task 8 (+ `mode != "mock"` test), removed orphan files + added `prisma generate`/`migrate` (Task 10), and token-hygiene (sub-skill → `executing-plans`, build gated to milestone Tasks, Task 14 runner headless/summary-only). Ready for Codex. NEXT: prototype from ACG AWS + Grafana.

- **v1.30.0 tag + GitHub release: PUBLISHED 2026-09-06** — tag `v1.30.0` created at `8e71692b`, pushed, GitHub release published (latest, non-draft). Post-merge fully closed.

- **2026-09-06 — HERMES PHASE 2 STARTED (user go: "go ahead with phase 2 and work with codex").** Per the Phase-1
  gate, Phase 2 begins as a SCOPE DOC (no code until user sign-off). Scope doc `docs/architecture/hermes-phase2-repair-scope.md`
  committed `77873f7d` on `origin/k3d-manager-v1.30.0`. Defines: closed **repair allowlist** (R1 `make restart-webhook`,
  R2 zombie-PF `launchctl kickstart -k`, R3 `_hostinger_refresh_access_layer` edge refresh, R4 `gh run rerun --failed`
  transient CI), multi-signal preconditions, governing principle "health-degraded ≠ safe-to-repair" (the Replace=true
  Keycloak trap), least-privilege access delta (**R1–R3 need NO new cluster/cloud write** — off-hub local levers; only
  R4 adds `actions:write` to the GH PAT), 3 approval mechanisms (A propose-only / **B CLI `k3dm-hermes approve` = recommended**
  / C Slack-interactive). NON-goals: no ArgoCD sync, no kubectl mutation, no auto-execution, closed allowlist.
  **SIGN-OFF (2026-09-06):** approval mechanism = **B CLI `k3dm-hermes approve <action-id>`**; allowlist = **all
  four incl. R4** (so GH PAT gains `actions:write` — user-provisioned prereq; code degrades R4→propose-only if absent).
  Implementation spec `docs/plans/v1.30.0-hermes-phase2-repairs.md` committed `0840fc86` on origin (plan doc #1/5).
  **DISPATCHED TO CODEX 2026-09-06** (codex exec, session `01a077af`, gpt-5.6-terra, background) — pure code+pytest,
  no live cluster. Codex to implement records.py `data` field, sensor `data` attach, `repairs.py` allowlist+propose/
  approve, bin/k3dm-hermes `_run_cycle`+approve subcommand, test_repairs.py; commit+push to k3d-manager-v1.30.0.
  **IMPLEMENTED + VERIFIED 2026-09-06 — commit `ddda256b` on origin/k3d-manager-v1.30.0.** Codex was sandbox-blocked
  on `.git` (index.lock EPERM) so it wrote the working tree only; Claude verified independently then committed.
  Files: records.py (`data` field), sensors.py (reachability verdict+failed_hosts, ci repo/run_id/conclusion —
  transient=timed_out|cancelled|stuck ONLY), NEW repairs.py (REPAIRS R1-R4 + propose/approve + one-incident guard),
  bin/k3dm-hermes (`_run_cycle`, propose→Slack, `approve`/`list` subcommands, post-repair re-sample), test_repairs.py,
  docs/guides/hermes.md. **Gates (Claude-run, not trusted from Codex):** pytest 18/18 (scratch venv pytest 9.1.1),
  py_compile clean, invariant-1 grep-proven (runner() only in approve(), approve only from CLI subcommand).
  **DEFECT CAUGHT + FIXED by Claude:** Codex FABRICATED R2 port-forward labels (argocd/keycloak/grafana PF labels
  that don't exist; omitted real vault). Grounded against `scripts/etc/cloudflared/config.yml` ingress ports vs the
  3 real `com.k3d-manager.*-port-forward.plist` listen ports → only `prometheus.3ai-talk.org`→`com.k3d-manager.prometheus-port-forward`
  matches exactly (alertmanager ingress :9093 ≠ PF :19093; argocd/keycloak/grafana served by other mechanisms). R2 map
  reduced to that one grounded entry + comment; test fixture updated.
  **2026-09-06 — R4 actions:write PROVISIONED + LIVE-VERIFIED (user go, PR boundary = provision PAT first).** User set
  the `k3dm-hermes-gh-token` fine-grained PAT to **Actions: Read and write** (screenshot-confirmed; fine-grained →
  token value unchanged, no Keychain re-save). Claude verified the token R4 actually reads (`GITHUB_SERVICE =
  k3dm-hermes-gh-token`, sensors.py:11/18): authenticates as wilddog64, Actions **read** confirmed; **write** confirmed
  via the real code path (`repairs._r4_command` → `_keychain_secret(GITHUB_SERVICE)` → POST rerun-failed-jobs on a
  **succeeded** run) returning `403 "This workflow run cannot be retried"` (business-logic reject reached only AFTER
  authorization) rather than `"Resource not accessible by personal access token"` → token HOLDS actions:write. R4 fully
  live (not propose-only). (Note: a smoke-script VERDICT heuristic misfired on GitHub's wording — raw API response is
  authoritative; token has write.)
  **2026-09-06 — v1.30.0 PR OPENED: PR #121** https://github.com/wilddog64/k3d-manager/pull/121 (base main ← k3d-manager-v1.30.0,
  head `a7e457d6`). PR boundary decision (user "Ship + file App follow-up"): ship Phase 2 alone. Copilot review requested
  (GraphQL-confirmed Bot `copilot-pull-request-reviewer`); CI in_progress. **PR gate in progress → STOP at merge (NEVER
  auto-merge; enforce_admins stays true).** enforce_admins verified true before PR.
  **Token-management follow-up filed:** user flagged PAT scoping as poor token mgmt (GitHub has no API to mint/re-scope
  PATs → manual by design). Filed `docs/plans/v1.31.0-hermes-r4-github-app-auth.md` — replace R4 PAT auth with a
  **GitHub App installation token** (short-lived ~1h, auto-scoped, no Keychain PAT) + a DI-testable **scope preflight**
  (`k3dm-hermes preflight`, deferred from v1.30.0 into this follow-up since it couples with the App work and belongs as a
  tested hermes-package fn, not a bin bolt-on). Auth-swap only; Phase 2 repair logic unchanged. Phase 3 (cooldowns/
  budgets/durable audit/auto-verify) still deferred, separate scope doc.
  **2026-09-06 — PR #121 GATE RUN (all green so far).** CI green on every head. **Copilot: 11 findings across 5 rounds,
  ALL fixed** (fix→push→reply→resolve; 0 unresolved threads): round 1 (`0065e1fe`) — (1) approve() one-attempt guard
  vs stale pending action_id, (2) R4 403 misclassification (any "403" → now only "resource not accessible" = missing
  scope; business-logic 403s fall through to "failed"), (3) reachability evidence "hosts healthy"→"hosts failing"
  (inverted); round 2 suppressed (`b6c9f02a`, no threads → addressed via PR comment) — (4) _r4_precondition now
  requires data["repo"] (avoids KeyError in _r4_command on repo-less ci record), (5) approve() pops pending_repairs
  once acted on (no stale ids in `list`, no unbounded state growth); round 3 (`<pending>`, summary-level, no threads)
  — (6) approve CLI exit code now 0 ONLY for outcome "executed" (failed/skipped/refused all non-zero; was masking),
  (7) Slack approval string uses `bin/k3dm-hermes approve` (matches the real entrypoint + guide; bare `k3dm-hermes`
  is not on PATH — plist runs it by absolute path); round 4 (`2a459419`, summary-level, no threads) — (8) propose()
  now uses a STABLE action_id (sha1 of key+command, dropped proposed_at) so pending_repairs is idempotent per
  condition (was minting a new id every cycle → unbounded growth), (9) copilot-instructions.md dropped the
  non-existent `--config <path>` flag (CLI is no-arg poll + list/approve), (10) scope-doc rule 1 reworded from
  "multi-signal / single degraded sensor never triggers" to "structured-signal precondition" (R3/R4 legitimately
  key on one sensor's structured verdict); round 5 (`f37c8321`, 1 thread, replied+resolved) — (11) SECURITY: R4 no
  longer falls back to ambient gh auth — approve() skips R4 ("skipped: hermes GitHub token unavailable") when the
  hermes PAT read is empty, before runner and before recording attempted (empty GH_TOKEN would let gh use the
  laptop's ambient OAuth, violating no-ambient-auth/least-privilege). Gates: pytest **24/24** (was 18; +6 regression),
  py_compile clean, scope check clean (NO subtree edits, v1.30.0 plan docs=1, no token literals in argv). Live smoke:
  `k3dm-hermes list` verified on the real binary (state-driven, side-effect-free); approve unknown-id refusal is
  unit-proven (a live approve triggers a full live sensor re-sample by design → not run standalone as smoke; live
  poll cycle is a post-merge activation step like Phase 1).
  **MERGED 2026-09-06 (`8e71692b`).** User self-merged PR #121 after the gate. Post-merge housekeeping done:
  enforce_admins re-enabled (verified true), main pulled (fast-forward `cd38a7e5..8e71692b`), next branch
  `k3d-manager-v1.31.0` created + checked out, retro `docs/retro/2026-09-06-v1.30.0-retrospective.md`, memory-bank
  updated. **Process rule learned:** disable `enforce_admins` PROACTIVELY at every PR merge-ready (user self-merges,
  needs admin override on) — not "if needed"; `/post-merge` re-enables it. (Recorded in auto-memory
  `feedback_notify_pr_review_before_merge`.) v1.30.0 tag/release PUBLISHED 2026-09-06 (`8e71692b`); ledger backfill on v1.31.0 (`06164a04`); branch cleanup done — 11 shipped tag-backed branches pruned local+remote, v1.19.0/v1.21.1 escalated (no tag, not main-ancestors). See Current focus.

## Merged releases

- **v1.29.0 RELEASED 2026-09-06** (PR #120 merged `cd38a7e5`). All v1.29.0 release steps completed:
  (1) **ApplicationSet reapply done** — `deploy_argocd_applicationsets --confirm` applied 12/12 sets, all Applications re-pinned to k3d-manager-v1.29.0. (2) **enforce_admins restored to true** on main branch (verified via gh api). (3) **v1.29.0 tag + GitHub release published** (tag created, HTTPS-pushed, release created from CHANGELOG excerpt). (4) **Release-ledger backfill** — README + docs/releases.md rows added for v1.29.0, v1.28.0, v1.27.0 (v1.25.0 folded into v1.26.0 as documented). (5) **Retrospective written** — docs/retro/2026-09-06-v1.29.0-retrospective.md covers Hermes Phase-1 shipping, seeder fixes, ApplicationSet reapply entrypoint, Copilot xtrace findings + process rules added. (6) **Standing-doc audits deferred** to v1.30.0 branch (non-stale entries confirmed: projectbrief.md, copilot-instructions.md, api/functions.md all current). (7) **Memory-bank updates** — progress.md + activeContext.md updated with v1.29.0 merged state, v1.30.0 branch noted as next active. Shipped: Hermes Phase-1 read-only monitoring (5 stdlib-only sensors, off-hub launchd, read-only 3-cred access), self-healing Vault seeders (grafana fresh-gen, cosign restore-first), durable ApplicationSet reapply entrypoint.

- **2026-09-05 — VAULT SEEDER SELF-HEAL: spec'd + dispatched to Codex (user go "dispatch to codex to fix the issue").**
  Fixes the recurring post-incident exposure (grafana KV + cosign KV/policy wiped on every cluster rebuild). Spec
  `docs/plans/v1.29.0-vault-seeder-self-heal-grafana-cosign.md` committed `c7fa6cbd` on `origin/k3d-manager-v1.29.0`.
  Decisions locked: grafana = **fresh-generate-if-absent** (user-chosen; no backup exists to restore), cosign =
  **non-destructive restore from Keychain** (`signing_restore` + `signing_init` prefers restore over regenerate).
  Codex dispatched via `codex exec` for code + BATS only; live seeder run vs hub is a SEPARATE deferred Claude step
  (classifier gates live Vault writes).
  **IMPLEMENTED + VERIFIED 2026-09-05, commit `43ce7732`** — Codex authored code+BATS, hit sandbox `.git`-lock →
  Claude committed after independent verify. Claude added two necessary fixes the literal impl surfaced:
  (1) observability.sh sources vault.sh via `VAULT_PLUGIN` idiom (dispatcher lazy-loads only the invoked plugin →
  `_vault_exec`/`_vault_exec_stream` were undefined during `deploy_observability`, seed would silently no-op on real
  bring-up; also makes the pre-existing `declare -f`-guarded writer-role config finally fire); (2) stubbed the seed in
  `lib/observability.bats`. Gates: targeted 27/27 green, all 6 observability suites green, shellcheck only 2
  pre-existing SC2016 infos. Remaining `make test` failures (argocd_deploy_keys #6/#8, slack #5/#10) proven
  pre-existing & unrelated (those suites don't reference observability/signing).
  **2026-09-06 — LIVE RUN surfaced two bugs in `43ce7732` (BATS stubbed Vault → slipped verify), FIXED `7eaaf897`:**
  (1) `signing_restore` never called `_vault_login` (siblings init/rotate/status all do) → standalone run 403'd on the
  key probe; (2) grafana seed was private-only → dispatcher refused `_observability_seed_grafana_if_absent`. Fix: added
  `_vault_login` to `signing_restore` + new public `observability_seed_grafana` wrapper (both ns=secrets release=vault).
  Bug doc `docs/bugs/v1.29.0-bugfix-signing-restore-no-login-grafana-seed-no-public-entry.md`. BATS 30/30 (was 27; +3),
  shellcheck 2 pre-existing infos only. Pushed, local===origin===`7eaaf897`. Live state observed pre-fix:
  `signing_status secrets vault` → `vault_key=present keychain_backup=present eso_public_secret=absent` (cosign material
  safe; the ESO public secret is what needs healing). **NEXT: user re-runs the now-working commands** —
  `./scripts/k3d-manager signing_restore secrets vault` (heals eso_public_secret) and
  `./scripts/k3d-manager observability_seed_grafana secrets vault` (seeds grafana KV if absent); then read-only verify.
  **2026-09-06 — LIVE RE-RUN (chained 4 cmds): ALL FOUR original remediation targets HEALTHY** — grafana KV present
  (seed skipped), cosign KV present (restore skipped), `cosign-verify` policy re-applied ("Success! Uploaded policy"),
  ESO role grant present (role `eso-ldap-directory` already grants cosign-verify). Login fix works: no more 403 on the
  probe; `observability_seed_grafana` dispatchable. Two non-regressions noted: (a) `eso_public_secret=absent` +
  `namespaces "kyverno" not found` — this cluster has no Kyverno admission stack, so the public-key ExternalSecret
  (targets `SIGNING_ADMISSION_NAMESPACE`=kyverno) has nowhere to land; NOT one of the 4 targets; (b) the raw
  standalone `_vault_exec` verify 403'd because each dispatcher call is a fresh process w/o `_vault_login` — my
  command flaw, not a bug. **HARDENING commit `ae9d8cb4`:** `_signing_apply_pub_externalsecret` now `_warn`+`return 0`
  (skip) when the admission namespace is absent, instead of hard-erroring — keeps `signing_restore` idempotent/safe
  anytime. BATS 32/32 (+2), shellcheck 2 pre-existing infos. Bug doc DoD all checked. **Seeder self-heal fully DONE;
  nothing pending here.**

- **2026-09-04 v1.29.0 MILESTONE = Hermes Phase-1 (the "hermes-agent") — IMPLEMENTATION PLAN DRAFTED.**
  User set the v1.29.0 theme to Hermes Phase-1 (read-only ops monitoring). Gate satisfied: runs OFF-HUB
  (laptop, like bin/k3dm-webhook) per scope §9 → NOT hardware-gated (no M5 wait). Master plan:
  `docs/plans/v1.29.0-hermes-phase1-implementation.md` (executes scope doc
  `docs/architecture/hermes-phase1-monitoring-scope.md`). Workstreams: WS0 access model (§6, read-only,
  FIRST), WS1 sensor set (§3 — ESO/ArgoCD/reachability[shipped bin/public-endpoint-probe]/node-pressure-via-webhook/CI),
  WS2 correlator+Slack (§8, fires only on sustained multi-signal), WS3 `_install_hermes_agent` (lib-foundation
  subtree, off-hub launchd), WS4 guide. HARD constraints: read-only reports-and-stops (NO mutation path in
  codebase), webhook authoritative (bin/cluster-status-summary → /api/v1/health), least-privilege, LLM
  least-resort (non-Claude default + per-day budget). Phase-1 first deliverable (public-endpoint probe) already
  shipped v1.28.0. SSO fix branch d02e6622 recommended to merge as a STANDALONE fix (independent of this milestone).
  **WS0 STARTED (2026-09-04):** spec `docs/plans/v1.29.0-hermes-ws0-ws3-access-and-installer.md` (WS0 now; WS3 stub).
  KEY DISCOVERY: the authoritative webhook payload (`_smoke_test_services`, bin/k3dm-webhook) ALREADY reports
  `ESO ClusterSecretStore`, `ESO ExternalSecrets {n}/{n} synced`, per-service, Data layer, and ArgoCD-server liveness
  — so routing ESO (sensor a) + node pressure (d) through the webhook means Hermes needs ZERO direct kube-apiserver
  credential (a direct K8s Role would be a forbidden "second health model"). Access model = 3 read-only creds:
  (1) existing webhook bearer token (reused, GET-only); (2) NEW ArgoCD read-only local account `hermes` — added
  `accounts.hermes: apiKey` + policy `p, role:hermes-readonly, applications, get, */*` to
  `scripts/etc/argocd/values.yaml.tmpl` (get only, no sync/write) for sensor b (per-Application Degraded/OutOfSync,
  which the webhook JSON omits); (3) NEW GitHub fine-grained read-only PAT (USER mints) for sensor e (CI). Manifest
  committed to branch, NOT applied (prepare-and-stop): live activation = reapply ArgoCD helm values on hub +
  `argocd account generate-token --account hermes` (→ laptop Keychain) + user mints GH PAT, then run DoD checks.

  **WS0 LIVE ACTIVATION (2026-09-05):**
  - GH PAT (cred #3) VERIFIED read-only: Actions read 200, metadata 200, write attempt 403. Keychain `k3dm-hermes-gh-token -a k3dm`.
  - **CRITICAL DRIFT DISCOVERY:** the live `argocd-cm`/`argocd-rbac-cm` are NOT sourced from `values.yaml.tmpl`.
    Both carry a `kubectl.kubernetes.io/last-applied-configuration` (a separate `kubectl apply` overwrote what Helm
    created). Live argocd-rbac-cm holds a RICH policy (platform-admins, argocd-developers/viewers, platform-dev/ops,
    order-admin, catalog-admin — Keycloak/LDAP groups) that has NEVER been in values.yaml.tmpl history (`git -S` = 0).
    Live argocd-cm has `resource.customizations.health.*` Lua + `admin.enabled:true` but LACKS the tmpl's
    `timeout.reconciliation:180s` + `ignoreResourceUpdates.ConfigMap`. `deploy_argocd_bootstrap` does NOT apply these
    CMs. ⇒ a `helm upgrade` with the tmpl would DESTROY the live RBAC (real SSO group access). So helm-reapply is the
    WRONG activation path here; used an ADDITIVE patch instead.
  - **DONE (additive, non-destructive live patches, context=hub k3d-k3d-cluster):**
    `kubectl -n cicd patch cm argocd-cm` → added `accounts.hermes: apiKey`;
    `kubectl -n cicd patch cm argocd-rbac-cm` → appended `p, role:hermes-readonly, applications, get, */*, allow` +
    `g, hermes, role:hermes-readonly` (rich policy preserved, verified 67 lines, platform-admins/order-admin intact).
  - **hermes ArgoCD token (cred #2) — DONE + DoD VERIFIED 2026-09-05 (user minted, Claude verified):** user ran
    `argocd login` (admin) + `argocd account generate-token --account hermes` → stored Keychain
    `k3dm-hermes-argocd-token -a k3dm` (created 12:17:02Z, 237-char JWT, `sub: hermes`). WS0 DoD all green:
    `can-i get applications */*` = **yes**; `can-i sync */*` = **no**; `can-i delete */*` = **no**; functional
    `app list` = 38 apps; live `app sync --dry-run` refused server-side (`PermissionDenied … sync … sub: hermes`);
    NO hermes K8s ServiceAccount (all namespaces), NO hermes kubeconfig context — off-hub model intact. All 3
    creds now present: `k3dm-webhook-token` (#1, GET-only), `k3dm-hermes-argocd-token` (#2, get-only), 
    `k3dm-hermes-gh-token` (#3, read-only PAT).
  - **DRIFT REMEDIATION — DONE 2026-09-05 (user go "yes, please"):** captured the live argocd-cm/rbac-cm at-risk
    content into `scripts/etc/argocd/values.yaml.tmpl` so a `deploy_argocd`/helm reapply reproduces the live hub
    instead of destroying it. Root cause pinpointed via each CM's `last-applied-configuration`: the rich RBAC,
    `scopes: '[groups, email]'`, and the two `resource.customizations.health.*` Lua blocks (App-of-Apps + ESO
    ExternalSecret) were MANUAL applies (not chart defaults) → helm would drop them; the stale template also
    rendered `${ARGOCD_RBAC_ADMIN_GROUP}` = an LDAP DN (`cn=admins,ou=groups,dc=home,dc=org`) that does NOT match
    the live Keycloak group model. Fix: embedded the live rich policy.csv VERBATIM (8 groups + hermes, hardcoded
    Keycloak group names), added `scopes`, `admin.enabled: "true"`, and both health Lua blocks. The many
    `ignoreResourceUpdates.*`/`resource.exclusions`/`timeout.*`/`impersonation`/`statusbadge` keys were confirmed
    chart defaults (absent from last-applied) → helm regenerates them, deliberately NOT captured (minimal patch).
    VERIFIED by rendering the tmpl through the plugin's exact envsubst allowlist + diffing vs live: policy.csv
    IDENTICAL, scopes/policy.default match, both health blocks IDENTICAL, admin.enabled match, YAML parses.
    NOTE: template values file feeds helm ONLY on the LDAP/Keycloak deploy path (`_argocd_helm_deploy_release`
    else-branch skips it) — that IS the production hub path, so the risk was real.
  **WS0 COMPLETE 2026-09-05.** 3-credential read-only access model live + verified.
  **WS1+WS2 IMPLEMENTED + VERIFIED 2026-09-05 — commit `4e9d3e6e` on `origin/k3d-manager-v1.29.0`.**
  Spec `docs/plans/v1.29.0-hermes-ws1-ws2-sensors-correlator.md` (plan doc #3/5). Codex-dispatched via `codex exec`
  (session `01a0718e`); Codex hit sandbox `.git` lock so Claude committed + pushed after independent verification.
  Agent = Python 3 stdlib-only: `bin/k3dm-hermes` + `scripts/lib/hermes/` (sensors/correlator/slack/records),
  pytest `scripts/tests/hermes/test_hermes.py` (8 tests, all green). 5 sensors grounded in REAL interfaces: (a) ESO
  via `/api/v1/health` `services[]` entries `ESO ClusterSecretStore`/`ESO ExternalSecrets`; (b) ArgoCD `app list -o
  json --grpc-web` (hermes token, get-only); (c) `bin/public-endpoint-probe --json` verdict; (d) node/data-layer =
  `Data layer` entry + aggregate `ok:false` (webhook-authoritative proxy, NO direct node probe); (e) GitHub Actions
  read API (gh PAT). Normalized record `{sensor,status,evidence,sampled_at}`, status enum healthy/degraded/UNKNOWN
  (unknown when source unavailable — constraint 2). Debounce >N cycles. WS2 fires ONE Slack summary only on
  sustained multi-signal (≥2 degraded in-window), LLM only on trip (default `gemini`, Claude never authors, per-day
  budget cap default 10 w/ deterministic fallback — constraint 4). VERIFIED by Claude: py_compile clean, 8/8 pytest
  green (via temp venv — repo py3.14 has no pytest), both DoD greps 0 matches (no mutation verb, no kubeconfig),
  stdlib-only, secrets via `security -w` never in argv, only spec-listed files touched.

  **WS3 SPEC WRITTEN 2026-09-05** — filled the stub in `docs/plans/v1.29.0-hermes-ws0-ws3-access-and-installer.md`
  (no new plan doc — stays within the ≤5 cap). Design: `_install_hermes_agent`/`_uninstall_hermes_agent` in
  **lib-foundation `scripts/lib/system.sh`** (mac-only guard, read-only Keychain preflight of the 3 WS0 creds +
  slack relay — NEVER mints/deletes a cred, all via `_run_command`/`_security`), rendering a NEW consumer template
  `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl` (Label `com.k3d-manager.hermes`, `StartInterval=300`, NO
  `KeepAlive`, no secrets in plist) via a thin `bin/k3dm-hermes-setup` entrypoint (mirrors `bin/k3dm-webhook-setup`
  `[--uninstall]`); plus a minimal `K3DM_HERMES_JITTER`-gated jitter add to `bin/k3dm-hermes` main() (constraint 5).
  Execution path is HEAVYWEIGHT + Claude-owned (NOT codex-exec-able): edit lib-foundation upstream → shellcheck +
  BATS + `make credential-test` live gate → PR (user go) → tag (~v0.4.15) → `git subtree pull` into
  `scripts/lib/foundation/` → add consumer files in k3d-manager → verify (no-mutation grep, no kubeconfig,
  off-hub).

  **WS3 lib-foundation UPSTREAM DONE 2026-09-05 — commit `dce8d2a` on `origin/feat/v0.4.15` (lib-foundation repo).**
  `_install_hermes_agent`/`_uninstall_hermes_agent` in `scripts/lib/system.sh` + `scripts/tests/lib/hermes_install.bats`
  (5 tests) + CHANGE.md Unreleased entry. GATES GREEN LOCALLY: shellcheck `system.sh` + full `shellcheck-lib` clean;
  full BATS 129/129 green (CI-scrubbed `env -i`), incl. the 5 new. **PREPARE-AND-STOP at the lib-foundation PR gate:**
  before PR, lib-foundation requires `make credential-test` LIVE ACG gate (serialize-live-sandbox; needs a live ACG
  sandbox) + Copilot + Claude scope; never auto-merge (await user go). After merge → tag `v0.4.15` → `git subtree
  pull --prefix=scripts/lib/foundation` into `k3d-manager-v1.29.0` → THEN add k3d-manager consumer files
  (`scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`, `bin/k3dm-hermes-setup`, `K3DM_HERMES_JITTER` add to
  `bin/k3dm-hermes`) + verify (no-mutation grep, no kubeconfig, off-hub). Consumer files NOT yet written. Then WS4
  `docs/guides/hermes.md`.**

  **WS3 lib-foundation PR #46 OPEN — ALL GATES GREEN, AWAITING MERGE GO (2026-09-05).**
  https://github.com/wilddog64/lib-foundation/pull/46 (base main ← feat/v0.4.15, head `6dbdbb1`). Gates: CI
  `completed/success` on `6dbdbb1`; `make credential-test PROVIDER=aws` live ACG gate passed (ACG_SESSION_OK, STS OK);
  Copilot reviewed — 4 findings, ALL FIXED in `6dbdbb1` + all 4 threads resolved (0 unresolved); scope 3 files
  additive. Copilot findings were legit: (1) plist render used sed — `&`/delimiter in a path could corrupt it →
  switched to literal bash `${//}` AND disable bash 5.2+ `patsub_replacement` around it (the `&`-as-match hazard bit
  in bats' bash 5.3; my new special-char BATS test caught it); (2) bootstrap wasn't `--soft` (could `_err`-exit the
  caller's shell) + always echoed success → checked plist write, `--soft` bootstrap returns nonzero on failure;
  (3) `_uninstall_hermes_agent` lacked `_is_mac` guard → added; (4) "WS0" wording leaked into foundation doc →
  genericized. BATS now 8 hermes cases, full suite 132/132 green, shellcheck-lib clean. **NEVER AUTO-MERGE —
  prepare-and-stop. On user go: merge #46 → tag `v0.4.15` → `git subtree pull --prefix=scripts/lib/foundation` into
  k3d-manager-v1.29.0 → add consumer files (plist tmpl + `bin/k3dm-hermes-setup` + `K3DM_HERMES_JITTER` in
  `bin/k3dm-hermes`) → verify → WS4 guide. Consumer files NOT yet written.**

  **WS3 DONE (code) 2026-09-05.** lib-foundation PR #46 MERGED (squash `e558888` on main) → released **v0.4.15**
  (`31be1f79`, CHANGE.md promoted) → `git subtree pull` into k3d-manager (`67de00cb` squash + `5c9e9577` pull commit)
  → consumer files committed `6aad603d` on `origin/k3d-manager-v1.29.0`: `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`
  (StartInterval=300, RunAtLoad, NO KeepAlive, no secrets), `bin/k3dm-hermes-setup [--uninstall]` (sources foundation
  subtree, calls `_install_hermes_agent`/`_uninstall_hermes_agent`), `bin/k3dm-hermes` `K3DM_HERMES_JITTER` initial
  sleep 0-30s. VERIFIED: py_compile clean, pytest 8/8, setup shellcheck+`bash -n` clean, both install/uninstall fns
  reachable via the setup source path, real-template dry render resolves all placeholders (StartInterval present, no
  KeepAlive), DoD greps clean (no mutation path, no kubeconfig across the added bin/plist files). Dispatcher already
  prefers the foundation copy (`scripts/k3d-manager:70`) so the fn is live at runtime.
  **LIVE INSTALL = prepare-and-stop (NOT done):** needs WS0 creds minted first (ArgoCD `hermes` token +
  GH read-only PAT into laptop Keychain — user actions per WS0 Live steps), then `bin/k3dm-hermes-setup` +
  `launchctl print` check + re-run WS0 read-only DoD post-install. **NEXT: WS4 `docs/guides/hermes.md` (last
  workstream; release DoD). Also still pending for v1.29.0: reapply hub+ACG ApplicationSets pinned to
  k3d-manager-v1.29.0 + `argocd_check_values_branch`; hub CPU overcommit Step 2 load-shed.**

  **WS4 DONE 2026-09-05 — `docs/guides/hermes.md` commit `c7fa27a8`. ALL HERMES PHASE-1 CODE WORKSTREAMS
  (WS0-WS4) COMPLETE.** Guide grounded in real code, passes `_doc_hygiene_check` (the memory's
  `scripts/check-doc-links.sh` does NOT exist in this repo — the real .md gate is `_doc_hygiene_check` in
  lib-foundation `doc_hygiene.sh`: no placeholder tokens + https-only; no relative-link-existence check), all
  relative links verified to resolve. **REMAINING FOR v1.29.0 RELEASE:** (1) LIVE activation prepare-and-stop —
  user mints WS0 creds (ArgoCD `hermes` token + GH read-only PAT → laptop Keychain), then `bin/k3dm-hermes-setup`
  + re-run WS0 read-only DoD; (2) reapply hub+ACG ApplicationSets pinned to `k3d-manager-v1.29.0` +
  `argocd_check_values_branch`; (3) hub CPU overcommit Step 2 load-shed; (4) then v1.29.0 PR (gated: CI + Copilot +
  Gemini smoke + Claude scope; never auto-merge).**

  **WS0 LIVE-ACTIVATION RE-VERIFY 2026-09-05 (this session) — all 3 creds still present + read-only posture confirmed.**
  Re-ran the WS0 DoD before installing the LaunchAgent: ArgoCD `hermes` token (Keychain `k3dm-hermes-argocd-token`,
  pulled via `security -w` into `ARGOCD_AUTH_TOKEN` env, never argv) → `Username: hermes`, `can-i get`=yes,
  `can-i sync`=no, `can-i delete`=no (the bare `argocd account can-i` on the CLI reports **admin**'s privilege — must
  test AS the hermes token). GH PAT read path 200. Webhook running (PID on `127.0.0.1:7443`, launchd `com.k3d-manager.webhook`).

  **BUG FOUND + FIXED during activation 2026-09-05 — commit `9ad90782` (see progress.md).** The webhook is **plain HTTP**
  (`ThreadingHTTPServer`, TLS terminated at Cloudflare edge — `bin/k3dm-webhook:3750`, no `wrap_socket`; `_k3d_ssl_ctx`
  is a *client* ctx for the kube-apiserver, not the listener), but Hermes built `https://` → both webhook sensors always
  `unknown`. Also `_http_json` `timeout=10` << the ~46s authenticated `/api/v1/health` (runs the full smoke test). Fixed
  scheme (webhook `http`, github stays `https`) + env-overridable `K3DM_HERMES_HTTP_TIMEOUT` (default 90). Live-verified:
  eso + node_pressure now return real payload data. **LaunchAgent NOT yet installed** — this fix precedes `bin/k3dm-hermes-setup`.
  Remaining activation: run `bin/k3dm-hermes-setup`, `launchctl print` check, watch `~/Library/Logs/k3dm-hermes.log` for a clean cycle.

  **HERMES LAUNCHAGENT INSTALLED + FIRST CYCLE VERIFIED 2026-09-05 (user go "then go ahead to install hermes").**
  Ran `bin/k3dm-hermes-setup` (→ `_install_hermes_agent` in lib-foundation v0.4.15) → `~/Library/LaunchAgents/com.k3d-manager.hermes.plist`
  written, `launchctl bootstrap gui/$(id -u)` OK, `launchctl print` → `state = running`, `RunAtLoad` fired pid 43258
  immediately on the bounded 300s `StartInterval` (no `KeepAlive`, logs `~/Library/Logs/k3dm-hermes.log`). The benign
  `Boot-out failed: 3: No such process` is the installer's idempotent pre-clean (no prior instance). First cycle finished
  in ~75s: **all 5 sensors returned real data, zero `unknown`** — the scheme+timeout fix holds live under launchd
  (eso "1/20 not synced: cosign-public-key"; argocd per-app Degraded/OutOfSync; reachability 4/7; node_pressure "webhook
  failures: Keycloak, Grafana, ESO ExternalSecrets"; ci ok). State `debounce {eso:1, argocd:1, node_pressure:1, reachability:1}`
  — raw signals degraded but not yet flipped (eso threshold 2, argocd 3 = anti-flap working). `correlation_history [[]]`,
  `event: null` → **no incident, no Slack post** (correct; needs ≥2 distinct flipped-degraded sensors in the window). If the
  hub stays degraded, expect eso/node_pressure to flip within a cycle or two, then one Slack incident ~10–15 min out.
  Uninstall: `bin/k3dm-hermes-setup --uninstall` (leaves Keychain creds intact). Note: git status snapshot shows branch
  `k3d-manager-v1.28.0` but working branch is `k3d-manager-v1.29.0` (confirmed via `git branch --show-current`).

  **INCIDENT REMEDIATION — GRAFANA VAULT-SEED (user go "please address that incident") 2026-09-05.**
  Hermes surfaced eso "1/20 not synced" + Grafana in the node_pressure webhook failures. Root cause: Vault healthy but
  KV path `secret/observability/grafana` was **entirely missing** → ExternalSecret `monitoring/grafana-admin-credentials`
  `SecretSyncedError` "could not get secret data from provider" → grafana pod `CreateContainerConfigError` stuck **27h**.
  The `grafana-credential-rotator` CronJob can rotate but CANNOT bootstrap an empty path (its `restore()` reads OLD pw
  under `set -eu` → 404 aborts). Fix executed by the **user via `!`** (classifier blocks Claude live privileged Vault
  writes): seeded `secret/observability/grafana` `{username:admin, password:<fresh 24-byte hex>}` — schema matching the
  rotator's `restore()`. Correct stdin pattern: `{ printf RT; printf PW; } | kubectl exec -i vault-0 -- sh -c '<script>'`
  (script in `-c` argv = no secrets; secrets on stdin via `read`; NOT a heredoc — heredoc+pipe collide on fd 0 and the
  token gets executed as a command → 403). Result: `SEEDED`, ES flipped to **SecretSynced True**, secret created with
  `admin-user`+`admin-password`, old grafana pod recovered `0/3 CreateContainerConfigError → 2/3 Running`, rollout
  restarted to fully clear.

  **COSIGN RESTORE — DONE 2026-09-05.** Two-part fix (both user-run via `!`; scripts in session scratchpad
  `cosign-restore.sh` + `cosign-eso-policy.sh`). **Part 1 — data:** `secret/cosign/signing` was also missing.
  RESTORED the ORIGINAL key from Keychain backup `k3d-manager-signing` (NOT regenerated — never ran `signing_init`):
  read `k3dm-cosign-key`/`k3dm-cosign-password`, decoded the `security -w` hex-encoded multi-line PEM (`xxd -r -p`,
  [[reference_security_w_hex_encodes_multiline]]), derived `cosign.pub` on host via `cosign public-key`, wrote the
  cosign.key/cosign.password/cosign.pub triple to Vault (base64 over stdin, `key=@file` in pod). **Part 2 — the real
  blocker (403, not data):** seeding the data was NOT enough — the ESO read still 403'd on `secret/data/cosign/signing`.
  Root cause: the ESO Vault **policy** grant was also lost. The shared ClusterSecretStore `vault-backend` authenticates
  via k8s-auth role `eso-ldap-directory` (SA `eso-ldap-sa`/`identity`, ttl 3600); it held only policy `eso-ldap-directory`
  (grants observability/* — why Grafana worked) but NOT cosign. Fix mirrors `signing.sh` `_signing_apply_vault_policy` +
  `_signing_grant_eso_read`: wrote policy `cosign-verify` (`read` on `secret/data/cosign/signing`, from
  `scripts/etc/signing/cosign-verify-policy.hcl`) and appended it to the role, **preserving every existing field**
  (all others were already Vault defaults, so Grafana + the other vault-backend ES are unaffected). ESO re-authed on
  force-sync → `cosign-public-key` ES now **SecretSynced**, secret created (`cosign.pub`). (Benign `audience` warning =
  Vault v1.21+ forward-compat; hub is v1.20.1.) **NEVER run `signing_init`/`deploy_image_signing`** — `_signing_seed_vault_key`
  regenerates the keypair AND clobbers the Keychain backup, destroying the original signing key.

  **INCIDENT CLOSED.** Cluster-wide ESO sweep: all synced except `platform-ops/app-cluster-kubeconfig` (SEPARATE, EXPECTED
  — [[project_app_cluster_vault_auth_portability]] open seam; no app-cluster registered → its KV path is intentionally
  empty; not Hermes-flagged, untouched by this remediation). Keycloak 502 / argocd-repo-server restart-loop = separate
  CPU-pressure thread (ties to hub CPU overcommit Step 2 load-shed), NOT addressed here.
  Post-incident note filed: docs/issues/2026-09-05-vault-kv-and-eso-policy-loss-grafana-cosign.md

- **2026-09-04 LDAP↔SSO decoupling — DECISION RESOLVED (Option B) + REMEDIATION SPEC WRITTEN (not executed).**
  Investigation on the live hub refuted the earlier "osixia is orphaned drift" read: the `shopping-cart-identity`
  ArgoCD Application owns the ENTIRE live identity stack (keycloak + postgres + osixia `ldap` + ExternalSecrets),
  and its manifests live in a SEPARATE repo — `wilddog64/shopping-cart-infra` (`identity/keycloak`, `identity/ldap`).
  Keycloak federating its bundled osixia `ldap` (`dc=shopping-cart,dc=local`) is intentional upstream design; the
  k3d-manager cluster-up seed + `get-keycloak-password` target openldap-0 (`dc=home,dc=org`) and mislead by implying
  they feed SSO. User chose **Option B: unify on openldap-0** (repoint keycloak → openldap-0, retire osixia). Spec:
  `docs/bugs/2026-09-04-sso-federate-openldap0-retire-osixia.md` (exact old/new blocks for 3 files + Phase-2 osixia
  retirement; CROSS-REPO shopping-cart-infra → Codex on `fix/sso-federate-openldap0`, never direct/imperative — ESO+ArgoCD
  revert). NO live changes made. App-source verified HEALTHY: shopping-cart-identity is a multi-source ArgoCD app pointing
  DIRECTLY at shopping-cart-infra HEAD with automated{prune,selfHeal}; OutOfSync is benign (3 ESO secrets only); a push
  auto-applies (keycloak-config hash rolls keycloak; keycloak-realm-reconcile PostSync hook re-imports realm). No app-source fix needed.
  **Phase 1 IMPLEMENTED by Codex + Claude-verified (2026-09-04):** shopping-cart-infra branch `fix/sso-federate-openldap0`,
  commit `d02e6622` (on origin). 3 files, exact spec diff (kustomization keycloak-config literals, realm-shopping-cart.json
  LDAP component, keycloak-secrets ES remoteRef → secret/ldap/openldap-admin·LDAP_ADMIN_PASSWORD; rdnLDAPAttribute uid→cn;
  usernameLDAPAttribute/bindCredential untouched). Independently verified: SHA on origin, only 3 files, JSON valid,
  `kustomize build` renders openldap-0 env. NO PR/merge (gated), identity/ldap untouched (Phase 2 pending). **NEXT:** user
  decides PR+merge of the shopping-cart-infra branch (auto-applies to live SSO on merge to main) → then live-verify SSO
  (get-keycloak-password developer binds; real login) → then Phase 2 (retire osixia).
  Issue doc corrected across CORRECTION 1 + 2: `docs/issues/2026-09-04-keycloak-federates-osixia-ldap-not-seeded-openldap.md`.
  Commits on k3d-manager-v1.29.0: `4cd7918d`, `bfacf896` (doc), spec commit next. **NEXT:** await user go to hand the
  spec to Codex + resolve the OutOfSync app-source wiring.

- **2026-09-04 v1.28.0 RELEASED — PR #119 merged, tag pushed, branch protection restored.**
  Post-merge housekeeping COMPLETE: retrospective doc `7d321adf`, tag v1.28.0 pushed, GitHub release published, `enforce_admins` restored to `true` (verified), next branch k3d-manager-v1.29.0 created. Two open follow-ups carried forward to v1.29.0+: (1) LDAP↔SSO decoupling decision A/B/C (docs/issues/2026-09-04-keycloak-federates-osixia-ldap-not-seeded-openldap.md), (2) hub CPU overcommit durable fix (queued until Mac Mini M5 upgrade, Oct 2026). Zero-downtime-rollouts spec remains in git, marked hardware-gated.

- **2026-09-04 v1.28.0 PLANNING — Claude weekly-quota lever + Hermes install decision.**
  Context: user on $20/mo flat rate hits Claude's weekly quota fast; under flat-rate the goal
  is routing work OFF Claude's constrained quota onto Codex/Gemini (other flat plans) + Haiku
  (cheaper Claude), NOT reducing total tokens. Two-part plan agreed: **(1)** workflow-defaults
  audit + tighten [started]; **(2)** Hermes as a Claude-last-resort ops router [deferred, scope
  doc gated].
  - **DECISION #1 (2026-09-04): keep Opus 4.8 as the global default** (`settings.json`
    `"model": "opus"` UNCHANGED). User wants Opus interactively for orchestration/judgment/verify;
    quota relief comes from subagent routing of mechanical lanes, not from flipping the default.
  - **DONE — `~/.claude/commands/create-pr.md` Phase 2 Opus→Sonnet.** Was labeled "Sonnet" but ran
    in the Opus main conversation → Copilot-fix read+edit burned Opus. Now a real **Sonnet
    subagent**; Opus only trust-but-verifies the returned fix rationales. (Config repo, not k3d-manager.)
  - **DONE — DECISION #2 (2026-09-04): `/bugfix` + `/handoff` spec-authoring → Sonnet subagent.**
    Both commands now draft the spec (read source + write exact old/new blocks) on a Sonnet
    subagent; Opus reviews the draft for exact-code-block precision before handoff. Edits in
    `~/.claude/commands/bugfix.md` (step 3) + `handoff.md` (steps 1–2). (Config repo, not k3d-manager.)
  - **Hermes install decision recorded** in `docs/architecture/hermes-phase1-monitoring-scope.md`
    §10: `_install_hermes_agent` in **lib-foundation** (subtree-first), installs Hermes **off-hub**
    (laptop tier, like `bin/k3dm-webhook`) — which also resolves the §9 hub-stability gate without
    waiting for the M5. Deferred to Hermes impl phase; no code yet. (Hermes theme = roadmap
    candidate v1.28.x, `docs/roadmap.md:156`.)
  - **DONE — Hermes Phase-1 first deliverable (§5) shipped: `bin/public-endpoint-probe`.**
    New self-contained, read-only script + `make status-public` target. Samples each public
    hostname (enumerated from `scripts/etc/cloudflared/config.yml` ingress) K×, host healthy only
    if ≥M/K return 2xx/3xx; discriminates **edge-down** (all fail → cloudflared split-brain) vs
    **single-service** (one fails → zombie port-forward) with exit codes 0/1/2/3; `--json` for
    Hermes to consume later. Spec `docs/plans/v1.28.0-hermes-status-probe.md` (drafted by Sonnet
    subagent, Opus-reviewed). shellcheck-clean; all 3 verdict paths + JSON validity verified via
    stubbed curl. Webhook untouched (§4 stays authoritative). This is the ONLY Hermes work this
    session — sensor set / correlator / Slack / guide stay deferred as a separate release story.
    Uses **1 of the 3 remaining v1.28.0 plan-doc slots** (now 3 v1.28.0 docs).
  - **DECISION 2026-09-04 (amended) — v1.28.0 = TWO themes: Hermes probe (done) + parallel-multi-cloud.
    Zero-downtime-rollouts QUEUED until hardware upgrade.** Original "all 3 in one release" call was
    reversed the same day: there is **no CPU headroom** on the current M4 Air 24GB hub for 2+ replicas
    of the stateless tier — the hub already CPU-starves at single replicas (`reference_one_second_
    probes_cpu_starvation_kill_loop`, `reference_hostinger_maxsurge_rollout_deadlock`: maxSurge=1 needs
    2× CPU on a 2-CPU node → FailedScheduling). Zero-downtime is a hardware story, gated on the Mac Mini
    M5 (Oct 2026 target, [[user_hardware]]). Operational-resilience through-line still holds for the two
    that ship: (#1, done) detect edge reachability honestly; (#2) provision providers concurrently
    without local-state corruption. `v1.28.0-platform-zero-downtime-rollouts` spec stays on disk, marked
    queued/hardware-gated.
  - **DONE (offline slice) 2026-09-04 — parallel-multi-cloud Phase 1+2.** Provider-scoped
    `_ACG_STATE_DIR` + `_acg_migrate_flat_state` one-time migration (decision "all scoped, migrate on
    first run"); `active-providers/` marker-dir set (`_acg_record_provider`/`_acg_unrecord_provider`/
    `_acg_list_active_providers`) fixing `k3s-hostinger.sh:1007` whole-file delete; set-aware
    best-effort resolver fallback. 14/14 new BATS (`provider_active_set.bats`) + 54/54 contract
    regression + shellcheck clean. Implementation-ready detail appended to the spec. DEFERRED:
    Phase 3 (ports/labels + make down/status refuse-when-ambiguous), Phase 4 (hub+kubeconfig flock),
    live two-cloud DoD. Recon corrections: webhook `_ACTIVE_PROVIDER_FILE` is a dead constant; the
    resolver already picks by context reachability (the file is only an offline fallback).
  - **DONE (offline core) 2026-09-04 — parallel-multi-cloud Phase 3+4.** mkdir-based hub lock
    (`_acg_lock_acquire`/`_acg_lock_release` — macOS lacks `flock(1)`; pid stale-reclaim; bounded wait
    then proceed) wrapping `cluster-up` Step 3.5+3.6 hub verify+bootstrap; `_acg_provider_port_offset`
    (k3s-aws=0 so single-cloud is byte-identical) applied to the ACG Prometheus forward (`19090+offset`).
    Key recon correction: hub-shared forwards (Vault 18200 → `k3d-k3d-cluster`, hub ArgoCD) are NOT
    offset — created once + reused, serialized by the lock; only per-app-cluster forwards (19090 →
    app context) offset. BATS 20/20 + contract 54/54, shellcheck + parse clean. DEFERRED (Phase 3b):
    kubeconfig-merge lock, full per-app-cluster launchd-label suffix audit, make down/status
    refuse-when-ambiguous (touches Makefile global CLUSTER_PROVIDER default), live two-cloud DoD.
  - **DONE (offline) 2026-09-04 — parallel-multi-cloud Phase 3b partial.** kubeconfig-merge lock around
    `cluster-up`'s k3s app-context fetch; new `bin/require-unambiguous-provider` (purely additive) wired
    into `make down`/`status`/`status-json` — refuses bare invocation when ≥2 providers live + no explicit
    CLUSTER_PROVIDER, verified end-to-end through make. BATS 23/23, contract 54/54, shellcheck clean.
    STILL DEFERRED to the live two-cloud session: the per-app-cluster launchd-LABEL suffix audit across
    observability.sh/argocd.sh/k3s-hostinger.sh (topology classification, no offline test — mis-classifying
    a hub-shared label breaks single-cloud teardown), the k3s-hostinger kubeconfig lock path, and the live
    two-cloud DoD. **v1.28.0 parallel-multi-cloud is now feature-complete for everything offline-verifiable;
    the remainder is genuinely live-gated.**
  - **FIX 2026-09-04 — Phase 1 scoping consistency (caught by live smoke).** Phase 1 scoped the
    producer (`cluster-up`) but not consumers → after migration, teardown/refresh would look in the
    flat path and break. Corrected: new single-source `_acg_provider_state_dir` helper used by
    `cluster-up`/`cluster-down`/`cluster-refresh` (the k3s-aws/gcp trio; `cluster-down` now sources
    provider.sh). **Architecture fact:** k3s-hostinger/oci use the dispatcher `deploy_cluster`
    (NOT `bin/cluster-up`); `k3s-hostinger.sh` is its own producer+consumer at the flat path →
    internally consistent, deliberately left flat (collides with nothing; aws/gcp live under
    `<base>/<provider>/`). Migration now reachability-guarded: with no legacy scalar it claims flat
    state for the run provider ONLY if that provider's context is reachable — so a `make up k3s-aws`
    (sandbox down) never steals a live hostinger's flat state. BATS 25/25, full lib 323/0.
  - **LIVE OPS 2026-09-04 — hostinger edge FIXED, hub still DOWN.** Public endpoints were all-530
    (EDGE-DOWN, validated live by the new `status-public` probe — 7/7 530). Root cause: no cloudflared
    connector running (stray `com.cloudflare.cloudflared` already `.disabled`, not split-brain). Fixed
    via `refresh_access_layer` (k3s-hostinger) — tunnel restarted, frontend now 200. **Remaining 502s
    (argocd/keycloak/prometheus/grafana) = the laptop hub (k3d) is DOWN** — only `ubuntu-hostinger`
    context exists; those services live on the hub. User decision: bring the hub up (pending — verify
    whether the hostinger dispatcher path does hub setup, or if hub needs `make up`). PR: HOLD until
    milestone complete.

- **2026-09-03 v1.27.0 PR #118 MERGED & RELEASED** — https://github.com/wilddog64/k3d-manager/pull/118
  (base `main`, head `k3d-manager-v1.27.0`, merged SHA `62c9ff27`, tag/release v1.27.0 published
  2026-09-03). CI green (lint✓ detect✓ stage2 skipped-by-design). CodeQL FP fixed in code
  (`26e1a1ff`: precompiled `re.sub` regex barrier + dropped `kc_realm` interpolation; no token
  needed). Copilot review 4 inline comments all valid + fixed in `0b028b5f` + all 4 threads
  replied+resolved via GraphQL. **Post-merge steps COMPLETE:** retrospective doc `2e9b5ade`,
  tag v1.27.0 pushed, GitHub release published, `enforce_admins` restored to `true` (verified),
  next branch k3d-manager-v1.28.0 created. **ApplicationSets REAPPLIED 2026-09-03** pinned to
  `K3D_MANAGER_BRANCH=k3d-manager-v1.27.0` (NOT the checked-out v1.28.0 dev branch): `hub-platform-ops`
  (signing config) was already on v1.27.0; the only drift was `grafana-dashboards-hub` +
  `grafana-dashboards-acg` still on v1.26.0 — reapplied both appsets, apps flipped to v1.27.0.
  `argocd_check_values_branch k3d-manager-v1.27.0` GREEN (6/6 values refs). Only `rollout-demo-*`
  remain off-version (intentional HEAD-pin). Full post-merge close-out DONE.

- **2026-09-03 PRE-PR BATS GATE — branch was RED; 9 test-only fixes applied, branch now green-minus-env.**
  A single-threaded local `bats scripts/tests/ --recursive` on `k3d-manager-v1.27.0` found **13 failures**.
  Bucketed by running affected files on `main` (CI-green) vs branch, in isolation: **9 branch-related
  (all test-only — code is correct/intentional)** + **4 pre-existing local-macOS-env** (fail on `main` too,
  pass in CI → NOT PR-blocking; tracked in `docs/issues/2026-09-03-bats-preexisting-local-macos-env-failures.md`).
  Spec: `docs/bugs/2026-09-03-bats-red-branch-stale-guards-and-vcluster-harness.md`. The 9:
  stale guards from intentional milestone changes — LDAP chart migration to `openldap-stack-ha`
  (`:389→:1389`, `dc=shopping-cart,dc=local→dc=home,dc=org`) [53/54]; ghcr pull secret moved to a
  `frontend` ServiceAccount [720]; node-health threshold `3→5` [81]; argocd port-forward self-healing
  rework (`sleep 30→RESTART_DELAY=2`, `HEALTH_FAILURE_THRESHOLD 3→6`) [288/518]; plus vcluster harness
  bugs from `142fd06b` (`_vcluster_wait_ready` 60s stub timeout, `run`-subshell drops `_VCLUSTER_BIN`,
  bare-`vcluster` vs `$VCLUSTER_STUB` string) [850/851/854]. 6 affected files re-run → 104 ok / 0 not ok.
  Full-suite confirmation (expect 4 env-only failures) in progress. NOT committed yet. **PR still gated.**

- **2026-09-03 v1.27.0 CVE-loop CODE-COMPLETE — ADMIT latch SHIPPED (`5e5bd33b`, pushed).**
  Kyverno `verifyImages` now carries an `attestations:` block (`type:
  https://cosign.sigstore.dev/attestation/vuln/v1`) beside the signature `attestors:`, so a first-party
  image must carry a vuln attestation signed by our key. Renderer blocker fixed: `_signing_render_policy`
  got a `# __PUBLIC_KEY_ATTEST__` awk branch injecting at 26 spaces (fixed-22 signature branch untouched).
  signing.bats 20/20 (+3, yq-parsed), shellcheck clean. **Three-latch loop code-complete: BUILD ✅ /
  PROMOTE ✅ (`588aab3e`) / ADMIT ✅ (`5e5bd33b`).** All ship inert: PROMOTE default-off (`COSIGN_VERIFY=1`
  **and** `COSIGN_VERIFY_ATTESTATION=1`); ADMIT default `Audit`, Enforce gated behind
  `SIGNING_ALLOW_ENFORCE=1` + clean Audit dashboard (D2). **Remaining = live enablement only**, in order:
  exercise PROMOTE gate → ADMIT Audit dashboard clean → ADMIT `--enforce`. No PR yet (still on the
  milestone branch, per gate).

- **2026-09-02 hub outage:** Cloudflare Grafana 502 and ArgoCD OAuth redirect failures traced to
  k3s API/etcd readiness failure and severe server CPU saturation (~650–880%). Agents/server were
  restarted; API remained unstable. Evidence and recovery attempts: `docs/issues/2026-09-02-hub-control-plane-saturation-causing-public-502.md`.

- **2026-09-02 follow-up:** `shopping-cart-identity` remains degraded from Argo strategic-merge
  duplicate Keycloak ports; Grafana/Frontend public origins flap during recurring API saturation,
  and Grafana has a stale dashboard route. Evidence: `docs/issues/2026-09-02-argocd-identity-drift-and-dashboard-502.md`.

- **E2E Tier-1 gate → GREEN on everything it covers (2026-08-29).** Both Codex fixes verified,
  images built (e2e via CI `sha-9202b194`; basket local `k3d image import` `sha-8614773e`), Tier-1
  rerun = **48 pass / 9 fail / 45 skip** (was 45/12/45) — all 9 fails are `payments.spec` (Tier-2/ACG).
  Order-status + cart qty-0 now green. **PRs OPEN (2026-08-29, user go-ahead):**
  e2e-tests **#8** (`fix/e2e-order-status-enum`, base main), basket **#44**
  (`fix/basket-update-quantity-zero`, base main). CI: e2e GitGuardian pass; basket all green.
  **Copilot review requested+addressed (2026-08-29):** requested via GraphQL `requestReviews`
  (REST bot-login no-ops; bot node `BOT_kgDOCnlnWA`). Fixes via Codex (spec
  `docs/issues/2026-08-29-copilot-pr-findings-e2e-basket.md`): e2e `6cb808d` (add PROCESSING to
  Order union + Number() normalize create/update product); basket `65fdb96` (`Quantity *int`
  `required,min=0` + handler deref + gin binding test `{}`→400/`{qty:0}`→200). e2e #8 also merged
  main in (`bcc63da`) to drop already-merged multiarch workflow from the diff + fixed PR desc.
  Deferred: order-management.spec flow-status rewrite → `docs/issues/2026-08-29-e2e-order-management-flow-status-alignment.md`.
  **Copilot threads ALL RESOLVED (2026-08-29):** e2e #8 3/3, basket #44 1/1 — replied w/ fix
  rationale + `resolveReviewThread` on each (api-client normalize thread auto-resolved; the other
  three replied+resolved). **Basket pointer-fix (`65fdb96`) re-validated live on Tier-1** (rebuilt
  `sha-65fdb96` + `k3d image import`, temp substrate tag, e2e img `sha-9202b194`): run
  `1788057617-1177` = **48 pass / 9 fail / 45 skip** (all 9 = payment/Tier-2) — no regression;
  vCluster self-cleaned; substrate `kustomization.yaml` basket newTag **reverted** to CI
  `sha-f70d5801` (65fdb96 is local-import only, not in GHCR).
  **basket #44 MERGED (2026-08-30, user go — admin override, squash `4b42ecc7` on main).** Merge
  method: `gh pr merge --admin --squash` (mergeStateStatus was CLEAN; ruleset left intact — the
  bypass-actor PUT was classifier-blocked so admin-override merge used instead). Main Go CI building
  → GHCR image `sha-4b42ecc755d599e2d673ec0a22341c62e8363493`. **e2e #8 ALSO MERGED (2026-08-30,
  admin override, squash `7601aa14` on main).** **/post-merge done (Haiku subagent + Claude
  verify):** e2e-tests `enforce_admins` **RE-ENABLED** (verified `true`, reviews=1); basket ruleset
  untouched (no restore needed); both mains synced (e2e `7601aa14`, basket `4b42ecc7`);
  `docs/next-improvements` already exists in both. **SUBSTRATE BUMP DONE + VALIDATED (`e06abead`):**
  main publish CI green for both → GHCR images confirmed (basket `sha-4b42ecc7`, e2e `sha-7601aa14`
  which `latest` now also points to — same digest, so `E2E_IMAGE_TAG:-latest` default already tracks
  the merged e2e code, no `e2e.sh` change). `kustomization.yaml` basket newTag → `sha-4b42ecc7`;
  Tier-1 re-run against REAL GHCR images (basket pulled from GHCR, not local-import) = **48/9/45**
  (9 payment/Tier-2). **E2E Tier-1 order-status + cart-qty-0 loop FULLY CLOSED.**
  **Docker-space follow-up (2026-08-30):** Tier A+B cleanup done (14GB orphan vol + 18 dangling +
  10 superseded tags freed ~19GB inside Docker; OrbStack backend reclaims to host over time). New
  helper `e2e_prune_images` (`2e8799c2`, dry-run-default) prunes >N-day images NOT in the E2E
  working set — dispatch `./scripts/k3d-manager e2e_prune_images [--days N] [--apply]`; protects all
  substrate images + running containers + `E2E_IMAGE_PRUNE_KEEP`. See progress.md. No release
  tag/retro (service-repo fix PRs, no version bump). (History below.) Substrate fix DONE+verified (`aa2f2190`
  postgres initdb `orders`/`order_items` schema matched to deployed Go order `5603388`), gate
  26/31/45 → **45/12/45**. Residual 12 = 9 payment (structural → Tier-2/ACG) + 2 order-status
  e2e-test bugs + 1 basket-service bug. User decision: fix e2e tests AND basket, payment→Tier-2.
  **Handed off to Codex (both repos):** (a) `shopping-cart-e2e-tests` orders.spec `CONFIRMED`→
  `PAID`/legal chain (branch `fix/e2e-order-status-enum` off `feat/e2e-image-multiarch` — the
  deployed image `0c2505b` is NOT in main, must preserve envelope fix); (b) `shopping-cart-basket`
  `internal/model/cart.go:151` `binding:"required,min=0"`→`"min=0"` (branch off `origin/main`).
  Specs: `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`,
  `docs/issues/2026-08-29-basket-update-quantity-zero-required.md`. Next after Codex: rebuild both
  images, Claude re-runs Tier-1 (residual should drop to the 9 payment specs only). PR/merge GATED.

- **v1.27.0 active branch** (`k3d-manager-v1.27.0`, branched from v1.26.0 merge). **Scope = 4 plan
  docs (4/5, under cap)**, dependency-ordered load-split leads (decision 2026-08-21 "keep all four"):
  1. `v1.27.0-foundation-managed-vcluster-cli.md` — **COMPLETE.** Part A = lib-foundation `v0.4.13`
     (PR #44 `0a3e4043`, subtree-pulled). Part B = HEAD `142fd06b` rewires `vcluster.sh` to
     `foundation_ensure_vcluster_cli` (module-scoped `_VCLUSTER_BIN`, guards non-zero+empty). Claude
     re-ran gates (BATS 36/36, shellcheck/`bash -n` clean, disappearance greps empty, subtree
     untouched) + **live `make e2e` CLI-contract gate PASSED** (real download+SHA+atomic install of
     vcluster `0.32.1` managed path; substrate rolled out; artifact/ConfigMap/exporter carry
     `9b3a5754`). Playwright app Job failed pre-existing (not the CLI change). No PR yet (release-time).
  2. `v1.27.0-m2-remote-e2e-runner.md` — **Increments 1–6 DONE** (inc 6 `b5fff9c4`, BATS 68/68).
     Producer runner-provenance, consumer/exporter+Grafana `runner` dim, `e2e_remote.sh`
     preflight/bootstrap/dispatch/restricted-publisher/lock+ops, `make e2e-remote|e2e-runner-health|
     e2e-replay|e2e-runner-unlock`. **Remaining: 2-run live acceptance gate** (1 fail + 1 pass via
     `make e2e-remote RUNNER=m2`) + deferred live redeploy of the inc-2 runner-labelled
     exporter/dashboard/rule via `argocd.sh`. **Blocker (a) CLEARED 2026-08-24:** e2e-tests image
     multiarch — PR **#7 MERGED** (`90c13994`, shopping-cart-e2e-tests; protection lowered→merge→
     restored, enforce_admins back on); Publish E2E Image reran on main push → `:latest` rebuilt
     **multiarch, VERIFIED** `docker manifest inspect` = `linux/amd64` + `linux/arm64`
     (QEMU+`platforms`+`provenance:false`, run `32725667211` success).
     **Publish-back CONFIGURED 2026-08-24:** dedicated restricted key `~/.ssh/e2e-m4-publisher`
     generated on M2 (private stays on M2); M4 `authorized_keys` restricted forced-command entry
     (`command="…/k3d-manager e2e_result_publish",restrict,no-pty,no-forwarding`) installed via
     `e2e_result_publisher_install`; `E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local` set in gitignored
     `k3d-manager/.envrc` (`source_up` preserves parent thinking-cap). Smoke-tested M2→M4: publisher
     key auths, forced command fires (no-pty confirmed), invalid payload rejected by schema (no
     ConfigMap written). Hub write target (`platform-ops`, ctx `k3d-k3d-cluster`) reachable.
     **Key ROTATED 2026-08-24:** old ed25519 `SwC+H3C7…` retired (M4 authorized_keys line removed →
     old key now `Permission denied`; old private overwritten on M2); new ed25519
     `SHA256:WwhGtx7C5KUt…` (comment `e2e-m2-publisher@m2-air-20260824`) installed at same canonical
     path `~/.ssh/e2e-m4-publisher` behind the identical forced-command restriction — no code/config
     change (path+host unchanged). Verified: neg-test old rejected, prod-path smoke passes. Still
     passphraseless BY DESIGN (unattended publish-back); real control is the `command="…
     e2e_result_publish",restrict,no-pty,no-*-forwarding` lock. M4
     `~/.ssh/authorized_keys.bak-rotate-20260824T225550Z` = rollback.
     **Policy DECIDED 2026-08-24: source-pin only, NO scheduled rotation** (per-deploy + time-based
     auto both declined — blast radius = one schema-validated ConfigMap write behind a forced command;
     frequent rotation adds silent-lockout risk for ~no gain). **`from="192.168.39.0/24"` pin APPLIED**
     to the live M4 line (M2=192.168.39.164, M4=192.168.39.169). Gotcha: mDNS resolves `m4-air.local`
     to IPv6 link-local too → default ssh went v6 → outside the v4 /24 → legit M2 rejected; fixed with
     M2 `~/.ssh/config` `Host m4-air.local\n AddressFamily inet`. Default publish path re-verified
     passing. **Both mitigations are OUT-OF-REPO** → durability spec
     `docs/issues/2026-08-24-e2e-publish-back-source-pin-durability.md` (bake `from=` into
     `e2e_result_publisher_install` via `E2E_PUBLISH_FROM` + `-o AddressFamily=inet` into
     `_e2e_publish_back_push`; a future reinstall/rotation currently DROPS the pin).
     **Durability implemented 2026-08-24:** commit `0cf69e28` makes the source pin optional
     (`E2E_PUBLISH_FROM`, empty preserves the legacy line) and forces IPv4 on publish-back;
     focused BATS `68/68`, `bash -n`, ShellCheck, and an explicit unpinned install proof passed.
     No live SSH or authorized_keys access was performed. PR = none per task instruction.
     **Still BLOCKED** on the 2-run live acceptance gate. M2 bootstrap/preflight passed and the
     intentional invalid-digest run published a failure. The required passing retry
     `1787708603-5833` completed but failed 45/102 tests: current E2E image/client expects flat
     responses and numeric prices while deployed APIs return `{data: ...}` envelopes and string
     prices. Result was published once to `platform-ops`; no M2 transport/publisher failure.
     Evidence: `docs/issues/2026-08-25-m2-e2e-acceptance-contract-mismatch.md`. **RERUN 2026-08-29 with the
     aligned image `sha-0c2505bbdc09b4ad12e5ea251ce9a8eeb7975e00` (Tier-1 vcluster, `E2E_IMAGE_TAG=…
     e2e_verify_vcluster`) STILL FAILS: 26 passed / 31 failed / 45 skipped (exit 1).** TWO issues: (1)
     CONFIRMED — payment-service is NOT in the Tier-1 substrate (`scripts/etc/e2e/` has no payment manifest)
     → 27 payments.spec + payment-dependent cross-service can't pass in vcluster; that's Tier-2/ACG's job.
     (2) orders.spec fails — root cause NOT confirmed; `orders is not iterable` (136×) is a cleanup SYMPTOM,
     and the client's `getOrdersByCustomer` DOES unwrap `{data}` (so the list-envelope hypothesis is
     unlikely); per-test errors lost on teardown (saved .log empty). **NEXT: rerun capturing Playwright
     reporter output to root-cause orders.spec, fix the real cause + rebuild image; decide payment coverage
     (add payment to Tier-1 substrate OR move payment acceptance to Tier-2).** Do NOT claim a list-unwrap fix
     without evidence. Stale vCluster cleanup was required before
     retry and should be treated as a follow-up idempotency bug. The Grafana E2E dashboard table
     also exposes duplicate raw service labels and blank legacy totals; this is documented in
     `docs/issues/2026-08-25-e2e-grafana-table-raw-labels.md`.
     **Dashboard fix committed `cfe925fc` and pushed:** service variables/queries now use
     `exported_service`, the exporter identity `service` is hidden, and table labels are renamed
     to concise names. **E2E client fix committed `0c2505b` and pushed** on
     `shopping-cart-e2e-tests:feat/e2e-image-multiarch`: response envelopes are unwrapped and
     product price/quantity values normalized to numbers. Full repo `tsc` still reports unrelated
     pre-existing strictness/type errors in test files; no new api-client errors remain.
     M2 runner fully provisioned + proven end-to-end (dispatch→SSH→
     OrbStack→k3d→vCluster→substrate→Playwright launch). See M2 bug docs under `docs/bugs/2026-08-22-*`.
  3. `v1.27.0-image-signing-cve-loop-closure.md` — cosign sign+attest, Kyverno Audit→Enforce, promoter
     verify gate. Multi-repo, heavy. **STARTED 2026-08-24 (sliced).** Full milestone decomposed into
     isolated shell/logic units (Codex, no cluster) vs live-rollout stages (Claude, live hub):
     A=`signing.sh` plugin (Part 0) → **✅ DONE + Claude-verified `e1ef0037`** (spec `0fb8c70e`; Codex
     session `01a0363c` generated, `.git` was read-only in its sandbox so Claude committed). Gates:
     bash -n / shellcheck clean / BATS 6/6. **Review trim before commit:** dropped Codex's
     `_signing_configure_writer` — it bound a create/read/update Vault role to the kyverno namespace
     (no consumer; seed goes via direct pod-exec, CI gets the key as GH secrets) and violated parent
     plan line 270 ("read-only … do NOT grant Kyverno broad Vault access", OWASP A01).
     B=live Stage-0 seed → **✅ DONE + live-verified 2026-08-24** (`7d335b1a`). cosign 3.1.3 (brew)
     seeded `secret/cosign/signing` (key/password/pub), Keychain backup, `kyverno` ns created,
     read-only `cosign-verify` policy, ESO `cosign-public-key` in kyverno = **SecretSynced True,
     cosign.pub ONLY** (private key withheld). **3 live-found signing.sh bugs fixed:** (i) no
     `_vault_login` before Vault ops → 403 (`6f3c6dd3`); (ii) signing_init returned early when key
     existed → never re-applied ESO/policy — now guards only key-gen, applies always run; (iii) ESO
     403 because no identity could read the path — added `_signing_grant_eso_read` (auto-discovers
     the ClusterSecretStore role `SIGNING_ESO_STORE`/`SIGNING_ESO_ROLE`, merges `cosign-verify` into
     it; store here uses role `eso-ldap-directory`, NOT eso-reader) (ii+iii `7d335b1a`). Note: ESO
     needs a controller restart after a role policy change (cached token freezes policies at issue).
     C=CI sign+attest across 5 shopping-cart repos [specs→Codex, branch now free]; D=Kyverno
     install+ClusterPolicy Audit→Enforce + promoter `cosign verify` gate [Claude live; kyverno ns +
     pub secret already staged]. Verify Codex SHA on origin per
     [[feedback_codex_verification_protocol]] before trusting.
  - **Stage D Kyverno 401 → RESOLVED 2026-08-30 (`8d8b2251`, pushed).** Live decision tree on hostinger:
    NOT a credential problem (kyverno-ns == app-ns `ghcr-pull-secret` byte-identical; same token passes the
    Deployment/autogen verify). Kyverno's cosign verifier resolves creds against the admitted object's
    `metadata.namespace`; a ReplicaSet Pod (`generateName`) has empty object ns at CREATE → 401, and the
    cosign path ignores `--imagePullSecrets` AND a mounted `DOCKER_CONFIG` (both tested, both failed).
    Fix = match workload controllers (Deployment/StatefulSet/DaemonSet/Job/CronJob) not `Pod` in the policy
    template; basket+order verify clean, 0 UNAUTHORIZED, BATS 17/17. `docs/bugs/2026-08-30-kyverno-verify-401-private-ghcr.md`.
  - **Stage D AUDIT NOW CLEAN — all 5 first-party PASS, 0 FAIL 2026-08-30 (`ce4374ff`+`d7375188`, pushed).** Closed
    all Enforce blockers: (a) re-pinned two unsigned deployed digests (product-catalog `53e668…`→`3db7b8da…`,
    payment `95f2680…`→`3b5f478c…`, both signed 2026-08-28 builds) — ArgoCD synced, both PASS; (b) re-applied the
    policy durably from the committed template via `deploy_image_signing --app-cluster --audit` (helm rev 5, values
    preserved via `SIGNING_KYVERNO_HELM_SET`; stray `ghcr-docker` volume removed); (c) **refined root cause** — frontend
    still 401'd at controller level b/c it ran as `default` SA (cred only on pod-template, which cosign ignores); the
    other 4 use a dedicated SA. Fix = dedicated `frontend` SA (`services/shopping-cart-frontend/`). So verify needs BOTH
    controller-match AND a dedicated non-default SA carrying the ghcr cred.
  - **Stage D ENFORCE FLIPPED — LIVE + verified 2026-08-30 (user go).** `SIGNING_ALLOW_ENFORCE=1 deploy_image_signing
    --enforce --app-cluster` (helm rev 6; live values preserved via `SIGNING_KYVERNO_HELM_SET`; all 4 controllers still
    1 replica). Rule `verifyImages[].failureAction=Enforce` (Kyverno 1.19 per-rule action; deprecated top-level
    `validationFailureAction` stays `Audit`, ignored). Blocking nothing: 5 app pods Running 1/1 0-restart, 5
    PolicyReports PASS=1 FAIL=0, zero PolicyViolation events. **Ran via `!` in-session** — the Claude Code classifier
    gates the enforce mutation, so the flip executes under the user's shell, not Claude's Bash. **Stage D DONE.**
  - **CVE-loop closure #1 — promoter cosign-verify gate ✅ CODE DONE 2026-08-31 (`98b0dc4a`).** Spec
    `docs/bugs/2026-08-31-promoter-cosign-verify-gate.md`. `app-cve-scan.sh` now runs `cosign verify --key <pub>
    --insecure-ignore-tlog=true` on a clean candidate digest **before** pinning it — unverifiable = **refused**
    (fail-closed, `App CVE Promotion Blocked (unsigned)` notify). Mirrors the Kyverno policy stance exactly. Pub key via
    new ESO `cosign-pub-externalsecret.yaml` (Hub Vault `cosign/signing` → `platform-ops/cosign-public-key`) mounted at
    `/cosign`; `COSIGN_VERSION=v2.4.1` (matches CI signer). BATS 12/12, shellcheck clean, howto updated.
    **LIVE-DEPLOY RUNBOOK ready 2026-08-31** — in `docs/howto/image-signing.md` (§Deploying the gate live): targeted
    apply of the ES + CronJob + script ConfigMap on the Hub (`k3d-k3d-cluster`), verify ESO `SecretSynced`, smoke via a
    manual `--from=cronjob/app-cve-scan` job grepping `SIGGATE`. Preflight confirmed: hub Vault `vault_key=present`,
    `vault-backend` CSS Ready, `platform-ops/cosign-public-key` not-yet-present (clean first deploy). **User runs it via `!`
    (deploy-path mutation, classifier-gated for Claude Bash).**
  - **HUB STABILITY / PUBLIC 502 — LIVE DIAGNOSIS 2026-09-02 (Claude-verified live).** Root cause = single-node
    hub CPU oversubscription driving a self-reinforcing control-plane storm. Live snapshot: `k3d-cluster-server-0`
    646% CPU, agent-1 578%, agent-0 322% (M4 Air ~8-10 cores → oversubscribed). Storm drivers (live):
    `svclb-istio-ingressgateway` **600 restarts** (klipper ServiceLB host-port fight), `coredns` 93 restarts +
    `node-exporter` 322 restarts (CPU-starvation SIGTERM kills — cf [[reference_one_second_probes_cpu_starvation_kill_loop]]),
    `argocd-application-controller-0` **901m CPU** (top) continuously reconciling the stuck `shopping-cart-identity`
    app + kube-prom CRD comparison timeouts, `prometheus-0` 698m, `postgres-keycloak` **CreateContainerConfigError**
    (Keycloak DB won't start → identity never Healthy → Argo retries forever = feedback loop). Chain:
    CPU-oversubscribe → pod restarts (coredns/svclb) → DNS+API churn → Argo reconcile storm → kine/sqlite slow →
    API timeouts → port-forward health-checks fail (grafana launchd last-exit -15 SIGTERM, keycloak -9 SIGKILL) →
    Cloudflare **502**. NOT a cloudflared split-brain — stray `com.cloudflare.cloudflared` connector is `.disabled`,
    only `com.k3d-manager.cloudflare-tunnel` live. Codex fixes VERIFIED: `e64111d7` CVE-exporter background-refresh
    thread (line 370 `Thread(...,daemon=True).start()` ✅ correct), `94682a78` status hub-agent surfacing + Makefile
    keycloak secret `keycloak-admin-secret`/`password` (live secret-name confirm pending), `0bca3e21` `Replace=true`
    on shopping-cart-identity app — CORRECT lever for the duplicate-`http`-port strategic-merge drift but blanket
    blast radius (also force-replaces Keycloak STS/PVC → cf `docs/issues/2026-09-02-secure-argocd-sync-and-pvc-blocker.md`);
    commit msg "secure credential piping" NOT reflected in the 1-line diff. Roadmap Hermes theme `41f2f68c` VERIFIED
    (well-scoped, 3-phase, no unrestricted creds, scope-doc-gated) — roadmap-ONLY, no code/repo; keep parked until hub
    stable + scope doc; this incident is its Phase-1 justification.
  - **HUB STABILITY — STAGE A EXECUTED 2026-09-02, 502s RESOLVED (Claude live).** Actions (ALL REVERSIBLE, must resume):
    (1) `make monitoring-pause` → suspended auto-sync on kube-prometheus-stack/hub-loki/trivy-operator (grafana kept);
    prometheus-0 scaled down (shed ~698m). My 240s timeout killed the make wrapper (Terminated:15) but the suspend
    landed. (2) `kubectl -n cicd patch application shopping-cart-identity {syncPolicy.automated:null}` — suspended the
    identity app's tight retry storm (the 901m app-controller driver). **RESULT: grafana.3ai-talk.org 302, argocd 200
    (were 502); agents near-idle.** ⚠️ RESIDUAL: `server-0` control-plane still ~713% CPU — single-node hub structurally
    over capacity (Stage C). **RESUME LEVERS when stable:** `make monitoring-resume` + re-add identity
    `syncPolicy.automated:{prune,selfHeal}`. **keycloak-secrets ROOT CAUSE PINNED:** NOT manifest/seal/auth —
    SecretStore `vault-kv-store` is Ready=True (auth OK), Vault unsealed+active; the ExternalSecret fails because the
    **Vault KV DATA is missing** at `secret/keycloak/admin` (props `admin_password`,`db_password`) + `secret/ldap/admin`
    (`admin_password`) — a Vault-seeding gap (cf [[reference_show_service_passwords_na_root_causes]]). keycloak-0 still
    Running on the legacy Bitnami `keycloak-postgresql` STS so SSO likely unaffected; the git-rendered `postgres-keycloak`
    Deployment is a half-done DB migration blocked on that seed. NEXT: seed Vault keycloak/ldap KV → force ES reconcile →
    resume identity auto-sync → verify Synced/Healthy; then Stage B (resource requests/priorityClasses, calm
    svclb-istio-ingressgateway 600-restart churn, sustained public probes in make status) + Stage C structural offload.
  - **CVE-loop closure #2b — RE-PIN 4 callers to attest SHA ✅ DONE + VERIFIED, 4 PRs OPEN (user-gated) 2026-08-31.** Codex
    (session `01a057f5`, task `bi5vx45pp`) bumped each caller's infra reusable-workflow pin
    `@1fa7ab0`→`@45def89e` on branch `feat/repin-infra-attest` (from each `origin/main`). **Claude-verified
    on origin** (branch SHA + `contents?ref=` bytes, not Codex's word): basket `a5fb8809`
    (`.github/workflows/go-ci.yml`), order `38d70585` (`ci.yml`), payment `28abe731` (`ci.yaml`),
    product-catalog `9dc3b59f` (`ci.yml`) — all: 1 file changed, new SHA=1/old SHA=0, exact msg
    `ci: re-pin infra reusable workflow to attest SHA 45def89e`. Spec
    `docs/plans/v1.27.0-image-signing-attest-repin-callers-codex-task.md` (`2dbfa354`).
    **4 PRs ✅ MERGED + VERIFIED (gh) 2026-09-01:** basket #45 `b84a534d`, order #74 `33e269b7`,
    payment #69 `a672ee42`, product-catalog #52 `0540db3d` (all base main ← `feat/repin-infra-attest`).
    Branch protection intact: all 4 use `main-protection` rulesets (still `active`) — nothing was lowered,
    nothing to restore. BUILD latch now emits vuln+SBOM attestations for all 4 reusable-workflow callers.
    **Frontend inline-attest spec WRITTEN 2026-08-31** —
    `docs/plans/v1.27.0-image-signing-frontend-inline-attest-codex-task.md`: adds 3 steps (trivy `cosign-vuln`
    + `spdx-json` predicates by digest → `cosign attest --type vuln`/`--type spdxjson`) inline into
    `shopping-cart-frontend/.github/workflows/ci.yml` `publish` job after `Sign image by digest`, trivy pin
    reused at `v0.36.0`, branch `feat/frontend-inline-attest`. NOT yet dispatched to Codex. Remaining
    follow-ups: verify side (promoter `app-cve-scan.sh` + Kyverno `verify-attestation --type vuln`); codify
    app-cluster Vault seed/grant + kyverno-ns ghcr ES into `signing.sh`.
  - **CVE-loop closure #2 — CI `cosign attest` (vuln+SBOM) ✅ CODE DONE + VERIFIED + MERGED 2026-08-31.** **PR #95**
    https://github.com/wilddog64/shopping-cart-infra/pull/95, merge SHA `45def89e151bc9d3506f7d641f46d045bc84029d` (base main). **CI all green** (GitGuardian, Kubeconform,
    Kustomize Build, YAML Lint). Codex session `01a05793`; Claude-verified on origin (SHA match, 1 file/33-ins, exact msg, descended
    from origin/main, yaml ok, order Sign→Generate-vuln→Generate-SBOM→Attest→promote, all guarded `if: env.COSIGN_KEY != ''`).
    **Copilot review N/A on infra repo** — REST `requested_reviewers` POST (both `Copilot` + `copilot-pull-request-reviewer[bot]`)
    returns 200 but silently drops the reviewer; only `copilot-swe-agent` is assignable, and PR #94 had zero Copilot reviews →
    Copilot code-review is not enabled on shopping-cart-infra (user's Copilot-required rule is payment-repo-specific). **USER-MERGED 2026-08-31** (user ran `gh pr merge 95`; self-merge via enforce_admins override). **ADMIN OVERRIDE RESTORED 2026-08-31:** `enforce_admins` restored to `true` (verified `gh api ... --jq '.enabled'`) on shopping-cart-infra main post-merge.
    Spec `docs/plans/v1.27.0-image-signing-attest-codex-task.md`. Adds 3 steps to shopping-cart-infra reusable
    `build-push-deploy.yml` (trivy `cosign-vuln` + `spdx-json` predicates → `cosign attest --type vuln` / `--type spdxjson`),
    guarded `if: env.COSIGN_KEY != ''`, reusing already-pinned trivy-action@v0.35.0 + cosign-installer@v3.7.0 (no new versions).
    Branch `feat/cosign-attest` **from origin/main** (the local `feat/cosign-sign-attest` is spent — sign step squash-merged as
    PR #94/`1fa7ab0`, callers pin that SHA). Codex must NOT touch callers or the verify side. Follow-ups: re-pin the 5 callers
    post-merge; then extend the promoter gate + Kyverno policy with `verify-attestation --type vuln`. Then codify app-cluster
    Vault seed/grant + kyverno-ns ghcr ES into `signing.sh`.
  - **Payment Java CVE remediation — spec written + ASSIGNED CODEX 2026-08-30.** Spec
    `docs/issues/2026-08-30-payment-cve-remediation.md`. Root cause: 7 fixable CRIT + 42 HIGH are ALL transitive from
    `spring-boot-starter-parent 3.2.0` (nothing pinned in pom). Fix = single BOM bump to latest 3.5.x + targeted
    `<tomcat.version>`/`<postgresql.version>` overrides (spring-security-web CRIT floor is 6.5.9 → forces the 3.5.x
    line). Codex branch `fix/payment-cve-spring-boot-bump`; gate `./mvnw clean verify` green + dependency:tree proof.
    Codex does NOT build/sign image or re-pin digest — CI signs on merge; trivy re-verify + digest re-pin are Claude's
    downstream steps. Verify Codex's SHA on origin before trusting.
    **RE-DISPATCH 2026-08-30 (v2):** first `codex exec` was launched from k3d-manager → its workspace-write sandbox
    was confined to k3d-manager, so the sibling payment repo was unwritable (`.git/index.lock: Operation not permitted`);
    Codex worked around it by cloning into `k3d-manager/scratch/` — killed + cleaned. Re-launched from INSIDE the payment
    repo (self-contained inlined-spec prompt, no k3d-manager touch) so the sandbox root IS the payment repo. Task
    `b8r8nmk0l`, session `01a05415`. Codex-v1 found: SecurityConfig already uses modern `SecurityFilterChain`
    (minimal/no code change expected); it proposed parent 3.5.16.
    **PAYMENT PAUSED — cross-repo blocker + user decision 2026-08-30.** Claude ran the mvn gate in a
    `maven:3.9-eclipse-temurin-21` container (no host JDK; DooD socket mounted for Testcontainers). ALL unit + web-slice tests
    PASS on 3.5.16; SecurityConfig needed ZERO code change. Two latent breakages the bump surfaced: (1) FIXED (uncommitted) —
    Flyway skew, pom hardcoded `flyway-database-postgresql 13.3.0` vs SB-managed `flyway-core 11.7.2` → `NoSuchMethodError
    getExact`; fix = pin to `${flyway.version}`. (2) BLOCKER — Spring Cloud `CompatibilityNotMetException` (Boot 3.5.16 needs
    the 3.2.x train); Spring Cloud is transitive via `com.shoppingcart:rabbitmq-client` (Vault), NOT in the payment pom; verifier
    fires even though `rabbitmq.vault.enabled` defaults false. **User chose Option C: fix rabbitmq-client-java first.** Payment
    branch left with 2 good uncommitted pom edits; resumes after the library republishes.
  - **rabbitmq-client-java Boot 3.5 upgrade — spec written 2026-08-30 (unblocks payment CVE).** Spec
    `docs/issues/2026-08-30-rabbitmq-client-spring-boot-3.5-upgrade.md`. Bump `<spring-boot.version>` 3.2.0→3.5.16 +
    `<spring-cloud.version>` 2023.0.0→2025.0.x in `~/src/gitrepo/personal/shopping-carts/rabbitmq-client-java` (multi-module,
    v1.0.1, uses `VaultTemplate`/`spring-cloud-starter-vault-config`). Version bump 1.0.1→1.0.2, republish to GH Packages (CI
    on merge), then payment repins `<rabbitmq-client.version>`. Branch `feat/spring-boot-3.5-upgrade`. Execute same as payment:
    edits via Codex (its sandbox has no JDK), Claude container-verifies. Testcontainers (RabbitMQ+Vault) → needs Docker.
    **✅ DONE + VERIFIED + PUSHED 2026-08-30 — `51fa46fa` on `origin/feat/spring-boot-3.5-upgrade`.** Codex made the pom-only
    edits (spring-boot 3.5.16, spring-cloud **2025.0.3**, version 1.0.1→1.0.2 across parent+3 modules) but its sandbox blocked
    `.git` writes (`.git/index.lock: Operation not permitted` even as workdir) → Claude created the branch + committed+pushed.
    Claude container-verified (maven:3.9-eclipse-temurin-21): clean compile of ALL Vault code + **73 unit tests pass, 0 fail,
    NO code changes**. NOTE: the library's live-Vault integration suite runs via a dedicated CI job (`-P integration-tests`
    with Vault+RabbitMQ *services*, not Testcontainers) — that runs on the PR, NOT on feature-branch push (CI push trigger is
    main/develop/fix-ci-stabilization only). NEXT (gated): PR on the library → CI incl. integration job → merge → CI republishes
    1.0.2 to GH Packages → payment repins `<rabbitmq-client.version>` 1.0.0-SNAPSHOT→1.0.2 + finishes (commit the 2 held pom edits).
    **✅ LIBRARY MERGED + PUBLISHED 2026-08-30 (user go = "do all 4"): PR #8 admin-squash-merged `a4a4640f` on main.**
    Post-merge CI ALL GREEN — Build+Test ✅, **Integration Tests ✅ (live Vault+RabbitMQ services — real regression bar, no behavior change)**,
    Publish ✅. **`1.0.2` confirmed in GH Packages** (`gh api .../packages/maven/com.shoppingcart.rabbitmq-client/versions` → 1.0.2/1.0.1/1.0.0-SNAPSHOT).
    enforce_admins toggled off→merge→**restored true**. Copilot reviewer N/A on this repo (`Could not resolve login 'copilot'`); required check `CI`
    is a phantom context (actual check = `Build and Test`). **PAYMENT RESUMED**: repinned `<rabbitmq-client.version>`→1.0.2 (uncommitted, joins the 2 held
    pom edits), full container verify re-running (should clear the Spring Cloud CompatibilityNotMetException now that 1.0.2 carries the 2025.0.3 train).
    **✅ PAYMENT VERIFIED + PR OPEN 2026-08-30.** Container `mvn clean verify` = **BUILD SUCCESS, 130 tests 0 fail/err/skip** (incl. Testcontainers
    Postgres integration; Spring context loads clean on Boot 3.5.16 — compat blocker gone). 3 pom edits committed `2bc05325` on
    `origin/fix/payment-cve-spring-boot-bump` (parent 3.5.16 + rabbitmq 1.0.2 + flyway `${flyway.version}`), zero code changes. **PR #68 OPEN**
    (`fix(deps): bump spring-boot-starter-parent 3.2.0 -> 3.5.16 …`). **#68 MERGED** `ecdb421f` 08-31T00:45Z (squash). Copilot addressed both nits:
    flyway `${flyway.version}` override DECLINED w/ justification on-thread (binding = BOM flyway-core 11.7.2, keeps modules aligned); missing lib
    `v1.0.2` tag/release — CREATED on `rabbitmq-client-java` @ `a4a4640f` (package was published but git tag absent). Merge treadmill note: each merge
    fires a `ci: update ... [skip ci]` image-pin auto-commit on main → next PR goes BEHIND under the up-to-date ruleset; needs re-update-branch +
    Copilot re-request (review is per-head). Copilot #68 threads: replied + **RESOLVED** both (missed on first pass — user caught it;
    lesson [[feedback_copilot_resolve_threads_not_just_reply]]: "addressed" = REPLY + RESOLVE, sweep `isResolved:false` as a pre-merge gate).
    **✅ STEP 4 DONE — CVE→SIGN→VERIFY LOOP CLOSED 2026-08-31.** Payment main sign run `33345512446` (sha `ecdb421f`) all 6 jobs green;
    `Build, Scan & Push` pushed+**cosign-signed** new digest `sha256:8f195e336cb702c347e1b78193e9ad96143a82716d3cecaec7713307c21daab1`
    (tlog index 2656526539). **cosign verify PASSES** against the kyverno-synced pub key (logIndex matches CI). **trivy re-verify (fixed-only
    CRIT/HIGH): 0 CRITICAL (was 7 fixable), HIGH 42→9.** Residual 9 HIGH are NOT pom-fixable here: 3 base-image OpenSSL (alpine `libcrypto3`/
    `libssl3`/`openssl` 3.5.7→3.5.8, needs base rebuild), 3 `com.rabbitmq:amqp-client` 5.25.0→5.33.x (library-transitive → next rabbitmq-client-java
    bump), 2 `httpcore5` 5.3.6→5.4.3, 1 `postgresql` 42.7.11→42.7.12 → follow-ups, not blockers. Substrate re-pinned
    `services/shopping-cart-payment/kustomization.yaml` digest `3b5f478c…`→`8f195e33…`. "Do all 4" chain COMPLETE.
    **Dependabot cleanup (payment repo, user go):** #67 (parent→4.1.1) CLOSED as superseded (4.x breaks the 2025.0.3 train + oversized).
    #66 (fetch-metadata 2.3.0→3.1.0) **MERGED**; #65 (setup-java 5→6) **MERGED** 08-31T00:25Z (each merge invalidates the next under the up-to-date
    ruleset). Copilot review on payment repo IS enabled (`copilot-pull-request-reviewer`); user REQUIRES it — request via raw-JSON `--input -`.
  - **Stage C merges ✅ ALL 6 MERGED (2026-08-25/26, user go given; merge SHAs gh-verified 2026-08-28):**
    infra #94 `1fa7ab005b57148468d0d23c6aa33fcc193baff5`, frontend #99 `000bdcc0945fcc62f38c366c843193da72b9e88a`,
    basket #39 `6f5a57c90e66d6a0be5eb0c1fd4ab43a86a5dfc7`, order #72 `cb4403db0a16eace10e0ff06c900849f8d483c03`,
    product-catalog #51 `c42a5ccdc860a01c2cdd328136bce1e2364ec486`, payment #63 `fa396eef56f18445d4b52e0da07e59fe44e08a76`.
    All 5 backend callers now pin the signing-enabled infra reusable workflow `build-push-deploy.yml@1fa7ab0`.
    Pin bumps (on `feat/cosign-sign-attest`): order `da8fcc2e` (was 47769da), product-catalog `00665840`
    (was 6163fdf), payment `be796c6d` (was 47769da) — clean +1/-1 diffs; basket already pinned via its own
    `14f5b1257` (two harmless net-zero newline commits `b55c11eb`+`e67290ab` on its post-merge branch → prune
    in /post-merge). **BLOCKER RESOLVED:** workflow-file writes needed the `workflow` OAuth scope; user ran
    `gh auth refresh -s workflow`. Gotcha memory'd: [[reference_gh_contents_put_trailing_newline]]. **Ruleset
    handling:** order+payment enforce via `main-protection` rulesets (not classic protection) — order merged
    via enforcement disabled→merge→**restored to `active`**; payment merged via branch-update (ruleset left
    intact); both **gh-verified `active` 2026-08-28**. **⚠ POST-MERGE SIGNING BLOCKER (found 2026-08-28,
    spec `docs/bugs/2026-08-28-stage-c-cosign-signing-fails-post-merge.md`):** the cosign SIGN step FAILS on
    every image-building caller's post-merge main build — images are pushed to GHCR **unsigned**. TWO root
    causes: **(RC1)** basket/order/product-catalog/payment fail `getting signer: reading key: invalid pem
    block` — the `COSIGN_KEY` GH secret is the **hex encoding** of the PEM, because seeding piped
    `security find-generic-password -w` (which hex-encodes any value containing newlines) straight into `gh
    secret set`. The key itself is VALID (Keychain hex → `xxd -r -p` = clean 11-line `ENCRYPTED SIGSTORE
    PRIVATE KEY` PEM). Fix = re-seed `COSIGN_KEY` from true PEM via a **file** (`gh secret set COSIGN_KEY
    --repo R < cosign.key`), never `--body "$(security -w)"`. **(RC2, frontend only)** frontend's direct
    `ci.yml` `publish` job has NO job-level `env.COSIGN_KEY` (it's on the `docker` job) → `Install cosign`
    (`if: env.COSIGN_KEY != ''`) skips while `Sign image` (own step-env) runs → `cosign: command not found`
    (exit 127). Fix = add job-level `env.COSIGN_KEY` to `publish`. infra #94 builds no app image (n/a).
    **FIX IN PROGRESS (user go given 2026-08-28):** ✅ **RC1 re-seeded** — recovered true PEM via Keychain
    `xxd -r -p`, verified key+password load in cosign locally (derived pub saved `/tmp/cosign-verify.pub`),
    `gh secret set COSIGN_KEY --repo R < file` across all 5 image callers (frontend/basket/order/
    product-catalog/payment); private key never in argv, temp files 0600 + removed. `COSIGN_PASSWORD` left
    as-is (45-byte single-line, no newline → `security -w` returned it verbatim, uncorrupted). ✅ **RC2 PR
    open** — frontend `fix/cosign-publish-job-env` commit `d47e675c` adds job-level `env.COSIGN_KEY` to
    `publish` (diff verified clean +2, no newline strip); **PR #101** (https://github.com/wilddog64/
    shopping-cart-frontend/pull/101), **MERGED 2026-08-28 (user go), squash `85265e7b`**. ✅ **BLOCKER
    RESOLVED 2026-08-28:** all 5 main builds re-triggered → `Sign image by digest` = success; **`cosign
    verify --key <derived pub>` PASSES on all 5** (GHCR `sha256-<digest>.sig` present): basket `4a96cf41…`,
    order `ca2d398b…`, product-catalog `3db7b8da…`, payment `3b5f478c…`, frontend `ca25a636…`. ⚠
    product-catalog run still red on a SEPARATE pre-existing step "Fail when image promotion did not
    complete" (GitOps promotion, NOT signing; its main was red pre-Stage-C) — tracked apart. ✅ **Stage D
    AUDIT SLICE IMPLEMENTED 2026-08-28 (user go):** `signing.sh` +`_signing_install_kyverno`/
    `_signing_render_policy`/`_signing_apply_cluster_policy`/`deploy_image_signing [--audit|--enforce]`; new
    `cluster-policy-verify-images.yaml.tmpl` (verifyImages, **sig-only**, `ghcr.io/wilddog64/*` in
    `shopping-cart-apps`/`shopping-cart-payment` ONLY, Audit, webhook failurePolicy Ignore); Kyverno chart
    pinned 3.9.0; 12 BATS green; howto+functions.md. ✅ **Stage D AUDIT LIVE on hostinger 2026-08-29** (user go): added
     `deploy_image_signing --app-cluster` (skips hub Vault; ESO CSS `vault-backend` on the app cluster) +
     Kyverno-install-first reorder + `_signing_wait_pub_secret` + `SIGNING_KYVERNO_HELM_SET` (`ec746ade`,
     spec `docs/bugs/2026-08-29-signing-app-cluster-mode.md`, 16 BATS). Kyverno 1.19 field-name fix
     `ignoreTlog`/`ignoreSCT` (`bbbacfe0`; template used pre-1.19 `ignore:true` → strict-decode reject).
     hostinger runs its OWN Vault (bridged, not a KV replica) — had to seed cosign.pub (public ONLY) + grant
     `eso-app-cluster` role read on the app-cluster Vault (extended `app-cluster-reader`). Kyverno 4/4 Running
     (1 replica, tiny requests, node fine), `cosign-public-key` SecretSynced, ClusterPolicy Ready (Audit).
     **⚠ AUDIT FINDING:** Kyverno can't verify private `ghcr.io/wilddog64/*` — **401 UNAUTHORIZED** (registry
     auth, NOT signature; sigs known-good per Stage C). `docs/issues/2026-08-29-kyverno-verifyimages-ghcr-registry-auth.md`.
     **REGISTRY CREDS WIRED but STILL 401 (2026-08-29):** created ghcr `ExternalSecret` in kyverno ns
     (Vault `github/pat`→dockerconfigjson), helm-set `existingImagePullSecrets[0]=ghcr-pull-secret` →
     admission ctrl runs `--imagePullSecrets=ghcr-pull-secret`. Credential is VALID (curl Basic→ghcr token
     endpoint = 200) but Kyverno's cosign verifier sends NO auth (401 at token endpoint, fresh/uncached) —
     Kyverno 1.19 cosign path ignores `--imagePullSecrets`. **DefaultKeychain mount ALSO FAILED** (patched
     admission ctrl: `DOCKER_CONFIG=/kyverno-docker` + dockerconfig mount → fresh order-service dry-run still
     401). BOTH documented mechanisms ignored → Kyverno 1.19.0 cosign verifier builds its own cred-less
     registry client (upstream/version issue, not config-fixable). **NEXT (before Enforce):** Kyverno chart
     version bump (or upstream issue) — SEPARATE task → re-audit clean → `SIGNING_ALLOW_ENFORCE=1 --enforce`;
     then promoter `cosign verify` gate + `cosign attest` in CI. Codify: app-Vault seed/grant + kyverno-ns
     ghcr ES into signing.sh. Full diag: `docs/issues/2026-08-29-kyverno-verifyimages-ghcr-registry-auth.md`.
     **[SUPERSEDED next-line:]** run `deploy_image_signing
    --audit` against the APP cluster (ACG/hostinger — NOT the hub; no app ns there), watch PolicyReports →
    zero would-be-blocks → `SIGNING_ALLOW_ENFORCE=1 --enforce`; then promoter `cosign verify` gate in
    `app-cve-scan.sh` (needs cosign+pub in platform-ops CronJob image) + `cosign attest` in CI. Also
    /post-merge housekeeping (sync mains, prune `feat/cosign-sign-attest` branches incl. basket net-zero).
  4. `v1.27.0-adaptive-checkout-load-testing.md` — API-level checkout load + telemetry. **STARTED
     2026-08-24 (sliced).** E=adaptive controller + stop-condition hysteresis + unit tests →
     **DONE** Codex commit `17be2e69`, pushed to `origin/k3d-manager-v1.27.0`; pure decision logic +
     BATS 9/9, no cluster/Prometheus/k6/Stripe. PR URL: none (task prohibits PR creation);
     F=k6/Go generator + Grafana dashboard + live capacity run [Claude live, Stripe test-mode].
     **Slice F BLUEPRINT (2026-08-29, `docs/bugs/2026-08-29-loadtest-slice-f-generator.md`):** discovered +
     verified the full build: checkout = `POST /api/orders` on order-service (ns shopping-cart-apps, ClusterIP
     :8081, NodePort 30081) with `{customerId,items[{productId,productName,quantity,unitPrice}],shippingAddress,
     currency}` — synthetic items OK (no real product IDs needed); payment downstream (queue→payment-svc,
     Stripe test). Generator runs on laptop via `kubectl port-forward` (off the measured node). Metrics:
     `prometheus-pushgateway` (monitoring :9091) deployed, or enable Prometheus `enableRemoteWriteReceiver` +
     k6 `experimental-prometheus-rw`. **AUTH:** 401 without Bearer; issuer `https://keycloak.3ai-talk.org/
     realms/shopping-cart` is PUBLIC (no in-cluster trick). Token recipe: password grant, `client_id=
     order-service` (confidential, directAccessGrants=true, secret=Vault-resolved `${ORDER_SERVICE_CLIENT_
     SECRET}`), users federated from OpenLDAP (realm has no local users; `alice/password` dev). **NEXT:** fetch
     order-service client secret + confirm LDAP user → prove one authed `POST /api/orders` 201 → build k6 +
     wire Slice E stubs (`_loadtest_fetch_metrics`, `loadtest_run`) + Grafana dashboard + staged live run.
     **✅ SLICE F DONE 2026-08-31 — live run executed, gate correctness fixed + verified.** Live run used
     the `k3dm-smoke` Keycloak public client (password grant; secret off argv). **Two gate bugs found + fixed:**
     (1) every `LOADTEST_PROMQL_*` default with a `{...}` label selector was corrupted by `${VAR:-default}`
     brace-termination — the first `}` closed the parameter expansion → invalid PromQL → Prometheus 400 →
     `_loadtest_prom_query`'s `curl -sf` fails → `0` fallback → `breaches=[]` even at 88% real HTTP-429 errors.
     BATS never caught it (stubbed `_loadtest_curl`, never hit a real parser). Fix = `_loadtest_promql_default`
     helper (single-quoted default via `printf -v`; every `}` stays literal), all 8 defaults converted, new
     pinned-string BATS regression test → 17/17. (2) operational, not code: a stale hub port-forward
     `svc/prometheus-operated 19090:9090 --context k3d-k3d-cluster` squatted :19090, so k6 remote-wrote to /
     gates queried the **hub** Prometheus (no receiver → POST /write 404, no k6 series) instead of hostinger —
     confirm run still `breaches=[]` until found; fix = kill squatter, bind hostinger pod to :19090, verify via
     `runtimeinfo.startTime` + POST /write→415. Also: checkout.js status-0 mistag fixed (`>=200 && <400`);
     `loadtest_run` now records real `actual_throughput` (`LOADTEST_PROMQL_THROUGHPUT`). **Gate verified E2E:**
     25→200 VU confirm = stage25 `hold[error_rate]` → stage200 `stop[error_rate]`; 15-VU green = `hold[]`
     `actual_throughput 10.64`. **Capacity finding:** checkout ceiling ~20–21 req/s (app rate limiter in
     order-service `httpx/middleware.go`, 429-sheds excess); hostinger node (2CPU/8Gi) never the constraint.
     Full detail in `docs/bugs/2026-08-29-loadtest-slice-f-generator.md` (Status 2026-08-31 session 2).
     Substantial v1.27.0 work now down to remaining signing deferrals + remote-e2e acceptance gate + release.
     Verify Codex output on origin per [[feedback_codex_verification_protocol]] before trusting;
     note the `codex exec` sandbox has `.git` read-only, so expect Codex to leave files uncommitted
     and Claude commits after review (as with Slice A).
  - Finding 1a — ✅ FIXED + live-verified `5cd67228` (`num()` coerces empty/None→0 so one malformed
    value can't zero the scrape; `up{exporter}=1`, both E2E + CVE dashboards receiving data).
    `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
  - Finding 2b — dispatcher `--confirm` strip on `deploy_app_cluster` — ✅ RESOLVED 2026-08-29
    (`3a6dddb0`). Guard publishes `K3DM_DEPLOY_CONFIRMED`; `deploy_app_cluster` honors it
    (additive, no blast radius; 5 other `--confirm`-as-`$1` sites are subtree
    `_provider_*_destroy_cluster`, not guard-gated). BATS `deploy_app_cluster_confirm.bats`
    (5/5) proves `--confirm` reaches the confirmed path. Spec
    `docs/bugs/2026-08-29-dispatcher-confirm-flag-deploy-app-cluster.md`; issue closed.

- **Dependabot automation — IMPLEMENTATION-READY (2026-08-29, `aa3bcc50`):**
  `docs/plans/v1.27.0-dependabot-automation.md` now carries the concrete reusable
  `workflow_call` workflow for `shopping-cart-infra` (author-gated on `dependabot[bot]`,
  `permissions:{}` default, pinned `fetch-metadata`, labels, rebase-on-dirty, allowlisted
  `--auto` merge, Slack-on-failure) + the thin per-repo caller + rollout order + pre-merge
  actionlint validation. Grounded in the existing baseline
  `shopping-cart-product-catalog/.github/workflows/dependabot-automerge.yml` (7 sc repos;
  product-catalog + basket/order/frontend/payment/e2e). Copilot-request + transient-retry
  = best-effort follow-ons. **Routes via branch+PR per sc spec-not-direct + PR-gate — NOT a
  direct push;** land in infra first, pin callers to the merged SHA, validate on one repo's
  real Dependabot PR, then roll to the rest. Product-catalog PR #51's skipped job is correct
  (author `wilddog64`, not `dependabot[bot]`).

- **Slack-secret redaction + branch prune — DONE (2026-08-29):** plaintext signing secret
  redacted from `docs/issues/2026-06-04-slack-slash-commands-wrong-url.md` and landed on `main`
  via `84e2917d`. Stale branch `security/redact-leaked-signing-secret` (was `b81c3da0`) pruned
  local + origin 2026-08-29 (content already on main; secret was already rotated/dead). No open
  branch or leak remaining.

- **v1.26.0 RELEASED** — PR #117 `1bbe5439` merged, tag/release published, protection restored
  (`enforce_admins=true`, 1 approval). Shipped 3/5 scopes (fleet count-agnostic lifecycle, E2E
  promotion gate + observability, managed registration cleanup). Retro
  `docs/retro/2026-08-21-v1.26.0-retrospective.md`. v1.25.0 = PR #116 `d48e465f`.
- v1.28.0 planned: parallel multi-cloud provisioning + zero-downtime rollouts.

## Open follow-ups

- **2026-09-01 frontend Keycloak login:** Hostinger frontend bundle uses the `frontend` client in
  realm `shopping-cart`, but the Keycloak realm has no such client (`clientId=frontend` returned
  `[]`), producing the browser's “Client not found” page. Bug recorded in
  `docs/issues/2026-09-01-frontend-keycloak-client-not-found.md`; create/reconcile the public
  client with the production callback before retesting.

- **2026-08-27 hub CPU overcommit — Step 1 IMPLEMENTED + live-applied (`85518a88`→`2a38670c`):**
  `docs/bugs/2026-08-27-hub-cpu-overcommit-resource-governance.md`. Diagnosed the CPU stress the
  federation-scrape tweak (`977d9e11`) could not fix: single 10-CPU/12.6GB hub VM oversubscribed
  (`docker stats` ~1414% vs 1000%; agent-2 426%, load avg 70; `/livez` 1.4–5.3s). Root = zero
  resource governance → unbounded `argocd-application-controller`/`repo-server` (`resources: {}`)
  starve apiserver → 24s status patches → ~4s hot reconcile loop on 25 apps → probe-kill restart
  storm (repo-server 221, svclb 465, coredns 143, keycloak 57). Plus istiod + istio-ingressgateway
  HPAs pinned 5/5 @80%-of-tiny-request (scale-out death spiral). **Both istio HPAs are IstioOperator-
  owned (`scripts/etc/istio-operator.yaml.tmpl` via `_istioctl install` in `k3d.sh`), NOT the ambient
  appset** (that targets remote clusters). **Committed:** requests+limits on all 6 ArgoCD components
  (`values.yaml.tmpl`; controller mem limit 2Gi to avoid OOM — CPU is the constraint) + pilot/ingress
  `hpaSpec:{min=max=1}`+limits (`istio-operator.yaml.tmpl`). **Live-applied** (ArgoCD is Helm-managed,
  no self-Application; no live istio operator reconciler → patches durable): `kubectl patch hpa
  istiod|istio-ingressgateway maxReplicas=1` (5→1 each) + `kubectl patch` controller/repo-server
  resources. **Result:** total CPU ~1414%→~1144% (~2.7 CPU freed); `/livez` 5.3s→~0.4s; agent-2 load
  70→39↓; new repo-server pod 0 restarts; restart storm FROZEN. `kubectl top nodes` UNDERCOUNTS
  (showed agent-2 ~15%); trust `docker stats`. **Istio durable rollout DONE via real tool:**
  `istioctl install -f <rendered istio-operator.yaml.tmpl>` (v1.30.0) reconciled live from committed
  config — HPAs now durably `MINPODS=1 MAXPODS=1` (operator-owned, not just the hand HPA patch),
  istiod limits 500m/1Gi + gateway 500m/512Mi applied, both pods fresh/healthy at ~44% CPU.
  (`istioctl install` foreground-times-out at 2m on the loaded hub — benign, k8s finishes the roll;
  verify with `kubectl get deploy/hpa -n istio-system`.) **ArgoCD formal redeploy DEFERRED** — see
  chart-drift follow-up; fix stays live (patched) + committed. **Step 2 load-shed IMPLEMENTED
  (config committed 2026-08-27; awaiting observability appset reapply for live rollout)**
  (`docs/bugs/2026-08-27-hub-load-shed-observability-footprint.md`): `lokiCanary.enabled: false`
  in `loki-values.yaml` (chart `loki-18.2.0`, canary is a top-level key — no selfMonitoring
  sub-block); `kube-prometheus-stack-values.yaml` `scrapeInterval`+`evaluationInterval` 30s→60s
  (the big CPU lever), `retention` 7d→3d, `retentionSize` 20GB→8GB. Prometheus CPU limit was
  already 1500m and etcd/scheduler/CM/coredns/kube-proxy scrapes already disabled — so those
  parts of the spec were pre-existing. **ROLLOUT PENDING:** reapply the `observability` appset
  with `K3D_MANAGER_BRANCH=k3d-manager-v1.27.0` so `$values` tracks the release branch, then
  ArgoCD selfHeal picks up the new values (loki-canary DaemonSet should disappear; prom CPU drops).
  Monitoring loop still running — hub was oscillating hot (load ~35–50, livez bursting to 20s)
  after Step 1, exactly the demand Step 2 removes.

- **2026-08-27 keycloak-0 restart loop FIXED live + committed + CoreDNS collateral fixed live**
  (`docs/bugs/2026-08-27-keycloak-restart-loop-tight-probes.md`): root cause was the SAME hub
  CPU starvation making Bitnami's **1-second probes** fail. keycloak-0 (67 restarts) was killed
  by liveness `tcpSocket period=1s failureThreshold=3` (SIGTERM 143) — NOT OOM. Fix in
  `scripts/etc/keycloak/values.yaml.tmpl` (previously set no probes/resources): liveness
  `period 1→10s failureThreshold 3→5`, readiness `timeout 1→5s`, **NEW startupProbe** (30s +
  40×10s = 430s grace), resources `750m/768Mi → 1000m/1Gi`. The startupProbe is the critical
  piece — Bitnami `start-dev` re-runs Quarkus augmentation every boot: live logs measured
  `augmentation 172742ms` + `started in 154.023s` = **~326s cold start**, so the old ~170s
  liveness window killed it mid-boot forever. Applied LIVE via `kubectl patch statefulset/keycloak`
  (KEYCLOAK_HELM_CHART_VERSION is empty=latest, so a `helm upgrade`/`deploy_keycloak` would risk a
  chart bump off `keycloak-25.2.0` + Bitnami-deprecation pull failure — patch was the low-risk
  path; template edit makes it durable at next deploy). keycloak-0 now **1/1, 0 restarts**.
  ⚠ **Rolling the pod exposed CoreDNS in CrashLoopBackOff (155 restarts, deploy 0/1)** — same
  1s-probe-under-CPU-starvation disease (`plugin/health … took more than 1s: 1.93s` → liveness
  SIGTERM). DNS was cluster-wide down; only cached-connection pods survived. Live-patched
  `deploy/coredns` liveness `timeout 1→5s failureThreshold 3→5`, readiness `timeout 1→3s` →
  CoreDNS `1/1` stable, DNS restored. **⚠ CoreDNS patch NOT in git — k3s-managed**
  (`k3s.cattle.io` owner, on-node `coredns.yaml`); k3s addon controller may revert. FOLLOW-UP:
  persist via k3s manifest override/HelmChartConfig, or land Step 2 load-shed so 1s probes stop
  failing at the source. This is fresh evidence Step 2 is no longer optional.

- **2026-08-27 hub-wide CPU-starvation cascade INCIDENT (mitigated live).** The keycloak dig
  uncovered that 1s liveness/readiness probes were failing platform-wide under CPU starvation,
  crashlooping EVERY core component into a deadlock: coredns (DNS down), loki-canary (4 pods,
  200+ restarts each), argocd-repo-server (probe-killed 40× → ArgoCD couldn't render manifests →
  couldn't sync the Step 2 relief → deadlock), and **agent-0 node went NotReady** (kubelet
  starved). User ran the Step 2 appset reapply (`applicationset observability configured`, now
  `$values`=k3d-manager-v1.27.0), but ArgoCD sync stayed `Unknown` because repo-server was down
  and then because rendering the big kube-prometheus-stack chart timed out (`DeadlineExceeded`).
  Live mitigations (NOT all in git): (1) `kubectl patch deploy argocd-repo-server` → light
  `/healthz` probes + startupProbe + 10s timeout (broke the deadlock; repo-server 1/1 stable);
  (2) `kubectl delete ds loki-canary` + force-deleted its pods (biggest immediate CPU win);
  (3) `kubectl patch prometheus kube-prometheus-stack-prometheus` → scrape/eval 30s→60s,
  retention 7d→3d, retentionSize 8GB **directly on the CR** (bypasses the timed-out chart
  render; operator regenerates config; ArgoCD sync is stuck so won't revert; and v1.27.0 values
  ALSO say 60s so they AGREE when sync eventually lands). Result: all 4 nodes Ready again
  (agent-0 self-recovered), keycloak/coredns/repo-server/argocd-server stable (restart counters
  frozen), Prometheus cut to 60s + counter frozen, replaying TSDB toward 2/2. ⚠ Live-only debts
  to reconcile: repo-server probe patch (ArgoCD-self-managed → reverts to 1s on next argocd
  self-sync — OK once CPU is free), coredns patch (k3s-managed), metrics-server was briefly
  unavailable. Durable resolution = the committed v1.27.0 Step 2 config syncing once repo-server
  can render the chart under freed CPU. Prometheus prometheusSpec should also carry a startupProbe
  headroom review, but its probes are already sane (not a 1s victim).

- **2026-08-28 node-health-watch was bouncing agent-0 in a restart loop (mitigated live +
  durable fix committed).** Morning regression: agent-0 `NotReady`, coredns `0/1` (DNS
  endpoints empty), prometheus-0 `Pending`/`Unknown`. Root cause was NOT a new probe bug and
  NOT OOM (`RestartCount=0 OOMKilled=false ExitCode=0` = external restarter). The launchd
  watchdog `com.k3d-manager.node-health-watch` (`bin/k3dm-node-health-watch`,
  `K3DM_NODE_RECOVERY_ENABLED=1`) polls `/healthz` with a 5s timeout; under CPU pressure that
  times out on a **slow-but-`Ready`** node, 3 fails (~90s) → `docker restart agent-0`, 300s
  cooldown, repeat ~every 6 min (log: restart 04:11→recover 04:13→fail→restart 04:17 PDT). Each
  bounce takes DNS down (coredns is a single replica pinned to agent-0) and strands Prometheus
  (its local-path PVC is on agent-0) → net-harmful. This is the **node-level instance of the
  1s-probe disease** ([[reference_one_second_probes_cpu_starvation_kill_loop]]). Live mitigation:
  `launchctl bootout gui/$(id -u)/com.k3d-manager.node-health-watch` → restarts stopped, agent-0
  holds Ready on its own (self-recovers), coredns 1/1, DNS restored, Prometheus rescheduled and
  replaying TSDB. Durable fix committed: `bin/k3dm-node-health-watch` now triggers recovery only
  on the authoritative `_ready`=False verdict (a Ready-but-slow `/healthz` is advisory, no
  restart), healthz timeout 5s→15s (`K3DM_NODE_RECOVERY_HEALTHZ_TIMEOUT`), threshold 3→5. Spec
  `docs/bugs/2026-08-28-node-health-watch-restart-loop-slow-node.md`. ⚠ Watchdog is currently
  **unloaded** — reload it (`launchctl bootstrap`) only after the fixed script is the one on
  disk AND the hub CPU has calmed; follow-up fragility: coredns SPOF + prometheus PVC both
  hostage to agent-0.

- **2026-08-28 chronic hub CPU overcommit persists after the watchdog fix — `make status` blocked
  on a pegged control plane.** With the self-inflicted node bounces stopped, all 4 nodes hold Ready,
  but the hub is still CPU-overcommitted at the source. `docker stats --no-stream`: server-0
  **492%**, agent-1 344%, agent-2 270%, agent-0 226% (~1333% total). Inside server-0: `/bin/k3s
  server` (embedded apiserver+etcd+controller-manager+scheduler) at **71%** of the node with **load
  average 60**; co-located discretionary load = `trivy server` (29% VSZ), an istio ingress-gateway
  envoy, kube-state-metrics, access-log-exporter, node_exporter. Consequence: every `kubectl` LIST
  times out (single-namespace `get pods` fails at 30s; `top nodes` times out), and the webhook
  `/api/v1/health` aggregator times out at 90s → `make status` reports `Overall: UNKNOWN / status
  source: webhook unavailable`. The webhook process itself is healthy (listening :7443, 401 without
  a token) — restarting it will NOT help; the blocker is the pegged apiserver, not the webhook.
  Durable fix = the committed Step 1+Step 2 load-shed governance (recent commits on
  `k3d-manager-v1.27.0`), but it is **inert** until ArgoCD reapplies it, and ArgoCD can't
  render/sync while the control plane is drowning (chicken-and-egg). Prior live sheds (prom 60s
  scrape, loki-canary off) are live but insufficient. Decision pending: reduce discretionary
  control-plane churn live (candidate: `trivy-operator` scale-to-0 — reversible, non-user-facing)
  vs. force the committed governance to sync. Same disease family as
  [[reference_one_second_probes_cpu_starvation_kill_loop]].
  - **RESOLVED 2026-08-28 via cluster restart (user-authorized).** Live shed alone did NOT help:
    scaled `trivy-operator` (trivy-system) → 0 and `loki`/`loki-gateway` (monitoring) → 0, but
    server-0 kept *climbing* (492→707→867%, oscillating 540-845% over 90s) because the bottleneck
    is the apiserver's own list/watch/reconcile churn, and pod terminations add to it — shedding
    agent workloads doesn't relieve the control plane. `k3d cluster stop/start k3d-cluster` cleared
    the accumulated churn: server-0 settled 607→**50%**, all 4 nodes Ready throughout, **coredns
    stayed 1/1 on the way up** (looser probes + startupProbe held — no DNS outage). Post-restart:
    apiserver responsive, `make status` completes. Recovery lesson: for a churn-storm on the k3d
    control plane, a cluster restart is the effective lever, NOT workload shedding.
  - **Post-restart Vault was sealed** (expected — raft/shamir, threshold 1). Unsealed via cached
    shards: `./scripts/k3d-manager deploy_vault --re-unseal` (keys in Keychain `k3d-manager-vault-unseal`
    + in-cluster `vault-unseal` Secret, both present). vault-0 → 1/1. ⚠ The `vault_install_unseal_watchdog`
    is NOT deployed, so Vault will need a manual `deploy_vault --re-unseal` after every restart until
    the watchdog is installed.
  - **RESTORED 2026-08-28 (user-authorized):** `trivy-operator`, `loki`, `loki-gateway` back to 1
    (all Running/Ready). ⚠ **CPU tradeoff quantified:** with them shed server-0 sat at **50%**; with
    them restored server-0 settled at **~360%** (a 617% loki cold-start spike that decayed) — 7× the
    shed headroom and much closer to the pressure edge that caused the incident. Still functional
    (apiserver responsive, nodes Ready), but loki is the heavy one; re-shed loki if steady-state
    headroom feels tight on this M4 Air. Also re-enabled the `node-health-watch` watchdog
    (`launchctl bootstrap`, PID confirmed) now running the FIXED script (`2b2d5705`) — validated live:
    logged `agent-0 Ready but /healthz slow/unreachable (advisory, no restart)` and `NotReady (1/5)`
    then stopped (self-recovered before threshold 5) — did NOT bounce the node.
  - **`make status` final: all hub infra GREEN** (ArgoCD/Keycloak/Prometheus/Grafana 200, ESO 18/18,
    data 4/4, Keycloak+ArgoCD+Grafana login OK). Sole remaining red = **`Frontend login: HTTP 401 on
    /api/cart` — a smoke-harness artifact, NOT a hub fault**: `k3dm-smoke-user` Secret absent →
    Keycloak login falls back to the Helm admin Secret (master-realm `admin-cli` token) → that admin
    token correctly can't authenticate to the app frontend, and the graceful 401/403 skip guard
    (`bin/k3dm-webhook` ~1831) only fires for `kc_via_smoke_client`, not the admin-cli fallback, so a
    correct 401 is reported as a hard FAIL. Fix candidate: extend the skip guard to the admin-cli
    fallback, or seed a real `k3dm-smoke-user`. Matches the known status-login false-green limitation.
  - **2026-08-28 Frontend login → TRUE GREEN** (`✓ Frontend login: HTTP 200 on /api/cart`). Root cause
    was 3 factors, all live-fixed on the hub Keycloak: (1) no `shopping-cart` realm existed — created it
    mirroring `home` (LDAP federation) + a public direct-grant client `k3dm-smoke`; (2) issuer mismatch —
    tokens minted locally carried a `localhost`/`.local` `iss`, never basket-service's trusted
    `https://keycloak.3ai-talk.org/realms/shopping-cart`; fixed by pinning the realm
    `attributes.frontendUrl=https://keycloak.3ai-talk.org` so **every** locally-minted token carries the
    public `iss` (no Cloudflare round-trip, verified via `.well-known`); (3) cloned LDAP component bound
    with a **masked** `bindCredential` (`**********` from the admin API) → `LDAP error 49 Invalid
    Credentials` on every federated mint; fixed by PUTting the real `LDAP_ADMIN_PASSWORD` (Secret
    `openldap-admin`, bindDn `cn=ldap-admin,dc=home,dc=org`). Smoke **user** is an LDAP entry
    (`cn=k3dm-smoke,ou=users,dc=home,dc=org`) — READ_ONLY LDAP refuses local Keycloak user creation.
    Seeded Secret `identity/k3dm-smoke-user` (username/password/realm/client; pw via stdin, not argv).
    **Webhook code change:** removed `kc_token_is_stub=True` from the smoke-client branch (a real seeded
    smoke user must green on 200 / red on genuine 401; only admin-cli/master fallback stays a skip) +
    reads optional `realm` key from the Secret. Spec: `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`
    (durable-follow-up section). ⚠ Live realm/LDAP/client/user/Secret WERE ephemeral — **now codified**:
    **`keycloak_provision_shopping_cart_realm`** (`keycloak.sh`) idempotently creates the realm + pins
    `frontendUrl` (`KEYCLOAK_SMOKE_ISSUER_BASE_URL`, overridable), clones the LDAP provider from `home`
    and repairs the masked `bindCredential` from Secret `openldap-admin`, creates the `k3dm-smoke` client,
    adds the LDAP smoke user (bind pw via stdin→0600 pod file, generated user pw), and writes
    `identity/k3dm-smoke-user`. Live-verified idempotent: re-run → `iss=…/realms/shopping-cart` →
    `/api/cart` **200**. Reach admin API with `KEYCLOAK_BASE_URL=http://localhost:8880` (keycloak PF up).
    Older `keycloak_seed_smoke_user` retained but wrong for this deployment (see spec) — prefer the new fn.
  - **⚠ 2026-08-28 hub CPU crisis recurred mid-session** — while completing the above, `docker stats`
    showed server-0 **454–568%**, agents ~200–330% each (~1170–1550% total on the M4 Air), and
    `/readyz` flapped `etcd failed`/`etcd-readiness failed`. Symptoms: `:8880` keycloak PF dropping to
    `000`, coredns 4× restarts → keycloak `UnknownHostException: keycloak-postgresql`, keycloak DB pool
    500s. Steady hogs (`kubectl top`): argocd-application-controller 733m, prometheus 681m; plus a
    trivy scan burst (10+ scan pods). Same disease family as the chronic overcommit above — the Step 1/2
    governance is committed but **inert until ArgoCD syncs it**.
    - **CPU-reduction pass applied 2026-08-28** (durable in-repo + live): (1) `vault-unseal-watchdog`
      CronJob cadence **`* * * * *` → `*/5 * * * *`** (`scripts/etc/vault/unseal-watchdog.yaml.tmpl`) —
      cuts 1,440 pod-spawns/day of node churn 5×; (2) ArgoCD `timeout.reconciliation` **120s (chart
      default) → 180s** (`scripts/etc/argocd/values.yaml.tmpl` `configs.cm` + live `argocd-cm` patch) —
      relaxes the 727m application-controller's full-resync cadence; takes effect on next controller
      restart (NOT force-restarted — a restart triggers a full re-sync burst). Prometheus already
      conservative (60s scrape / 3d retention) — left as-is. Snapshot at time of pass: prometheus 754m,
      argocd-application-controller 727m, argocd-repo-server 386m, vault-0 368m, keycloak 162m.
    - **Monitoring pause/resume toggle — DONE + live-verified 2026-08-28** (the "biggest optional lever",
      now built): `observability_pause` / `observability_resume` (`scripts/plugins/observability.sh`) +
      `make monitoring-pause` / `make monitoring-resume`. Scales the whole hub observability stack
      (prometheus+grafana+loki+alertmanager+kube-state-metrics+trivy) to zero on demand — reclaims
      **~1.1 cores** (measured: prometheus 730m + grafana 273m + alertmanager 37m + ksm 18m); node-exporter
      DaemonSet (~15m) left running. **Keeps production-grade config fully intact** — pause only scales
      replicas + suspends auto-sync; resume reconciles the identical committed chart values (scrape 60s /
      retention 3d / all rules unchanged). Nothing deleted, PVCs untouched → history survives within 3d.
      **Two-controller mechanism** (both required, learned live): (1) selfHeal defeated by patching each
      app `spec.syncPolicy.automated=null`; (2) that patch made durable by committing
      `ignoreApplicationDifferences: [/spec/syncPolicy/automated]` to the `observability` ApplicationSet
      (the app-level `skip-reconcile` annotation is STRIPPED by appset re-templating within seconds — does
      NOT work); (3) prometheus/alertmanager are operator-reconciled CRs — scale via the CR, not the STS.
      Resume scales workloads back **explicitly** (operator→CRs→deploy/sts to 1), NOT via ArgoCD sync —
      sync goes `Unknown`/slow exactly under the CPU starvation this feature targets. Spec:
      `docs/bugs/2026-08-28-monitoring-pause-resume-toggle.md`. Config-tune levers (#1 scrape, #2 retention)
      confirmed already spent; trivy is event-driven not cron — so the toggle is the remaining real lever.
    - **`make status` made pause-aware (2026-08-28, `bin/k3dm-webhook`)** — with monitoring paused, status
      previously hard-FAILed on Prometheus/Grafana/Grafana-login 502s. Added `_monitoring_paused()` +
      downgrade pass: when the hub `kube-prometheus-stack` ArgoCD app exists AND `spec.syncPolicy.automated`
      is empty (the deliberate-pause signal, distinguishes pause from crash), those three become `⚪` warnings
      (`monitoring paused (make monitoring-resume)`) → `Overall: WARN`, exit 0. **Two gotchas fixed live:**
      (a) query the **hub/INFRA context** `k3d-k3d-cluster`, NOT `_provider_context()` (returns app cluster
      `ubuntu-k3s`, no such app); (b) **NO provider gate** — `make status` resolves to `k3s-hostinger`
      (Makefile `CLUSTER_PROVIDER=k3s-aws` origin=file → recipe forces hostinger), and the `*.3ai-talk.org`
      Prometheus/Grafana URLs front the hub via cloudflared, so paused-hub explains the 502 in every mode.
      Safety verified: apps with `automated` set → not-paused → real outages stay hard errors. `make
      restart-webhook` required after edits. Spec: `docs/bugs/2026-08-28-status-monitoring-paused-false-fail.md`.
    - **Live CPU proof (2026-08-28):** monitoring running → Keycloak `/realms/master` 1.6–6.3s (erratic) →
      login smoke read-timeout FAILs; after `monitoring-pause` → **9–26ms**, server-node CPU recovers from
      `<unknown>`. Concrete evidence the stack starves Keycloak + API server.
    - **RESUMED to Layer 1 2026-08-28** (decision: user wants Layer 1 = reduced-rate stack always on,
      loginable Grafana, `monitoring-pause`/`resume` as the on-demand escape hatch — pause is NOT the
      default). `make monitoring-resume` restored all workloads to 1; `make status` → **HEALTHY** (all
      green incl. Grafana HTTP 200 + Grafana login 200 + Keycloak token minted). Note: pause scales
      **Grafana too** → no login while paused (Grafana without Prometheus shows empty panels anyway);
      "always loginable" = live in Layer 1, don't pause.
    - **⚠️ Resume gotcha — laptop-sleep clock jump (2026-08-28):** during resume the M4 slept; the k3d
      Docker VM clock froze (~20:54Z) then jumped forward ~3h on wake. Forward jump made
      CrashLoopBackOff burst-fire all pending restarts (ksm/operator counters shot to 43/33) + Prometheus
      "out-of-order samples" + operator "context deadline exceeded". NOT a resume bug. Recovery: clocks
      re-sync on their own; **delete the stateless scarred pods** (ksm, operator — no PVC) so they restart
      with `restarts=0`. Verified clean (both came up 0 restarts, stable). See auto-memory
      `reference_laptop_sleep_clock_jump_crashloop`.

- **2026-08-27 ArgoCD chart-version drift (BLOCKS formal deploy_argocd redeploy):** live helm release
  `argocd` is chart **`argo-cd-10.4.0`** (app v3.5.1, revision 1, deployed 2026-08-20) but the repo
  pins `ARGOCD_CHART_VERSION=7.8.1` (`argocd.sh:53`). Running full `deploy_argocd` could unintentionally
  change the chart version → regression risk, so the Step-1 argocd resource limits were NOT applied via
  helm (only live `kubectl patch` on controller+repo-server + committed to `values.yaml.tmpl`). Helm
  release state has no resource values → a non-tmpl `helm upgrade --reuse-values` would strip them
  (normal `deploy_argocd` re-renders the tmpl → keeps them). **Reconcile the pin (7.8.1→10.4.0, or
  downgrade live) BEFORE any formal argocd redeploy.** Surgical durable option if needed sooner:
  `helm upgrade argocd argo/argo-cd --version 10.4.0 -n cicd --reuse-values -f <resources-only overlay>`.

- **2026-08-27 federation scrape tuning:** source commit `977d9e11` changes the hub `federate-acg`
  Prometheus scrape interval from 30s to 60s; the vulnerability exporter remains at 60s. YAML
  parsing passed. Requires the observability values to be reapplied before live effect; monitor
  M4 CPU/API latency afterward.

- **2026-08-27 status credential discovery:** commit `f07adea8` adds fallback to the deployed
  password-only `identity/keycloak-admin-secret` (master realm/admin-cli) for smoke login checks;
  webhook tests pass. Prometheus/public endpoints recovered after OrbStack + edge restart, but the
  aggregate health sweep remains slow under control-plane load.

- **2026-08-27 hub control-plane outage:** restarting agent-0 and the k3s server did not restore
  the API. Kine reported slow SQL/handler timeouts and hub containers saturated CPU; Prometheus
  remained unavailable. Incident recorded in `docs/issues/2026-08-27-hub-control-plane-still-unavailable.md`.

- **E2E transient cleanup (2026-08-27):** commit `6b20cced` pushed on `k3d-manager-v1.27.0`.
  `_e2e_teardown` now best-effort removes orphaned vCluster kubeconfigs/proxies and transient
  per-run logs while retaining JSON audit summaries; regression coverage added. Host remains
  CPU-saturated by OrbStack/browser workloads, so m2 remains the preferred E2E runner.

- **Hostinger access-layer recovery (2026-08-26):** k3d agent-0 exited (143), causing hub workload
  evictions and local ArgoCD/Keycloak/Prometheus 502s; restarting the single stopped container
  restored all hub nodes to Ready and Prometheus replayed its WAL. Commit `44de06f7` fixes the
  Keycloak forward from service port 80 to 8080, pins tunnel/health probes to IPv4, and uses the
  valid `/realms/master` status path. Focused BATS 68/68, shellcheck, and `_agent_audit` passed.
  Repeated direct public probes reached ArgoCD/Keycloak 200; wrapper flapping remains a live
  follow-up when transient port-forward client resets occur. The shared wrapper now tolerates
  three consecutive health failures, retries after 2 seconds, and binds kubectl to IPv4; local
  ArgoCD and Keycloak checks returned 200 after regeneration. Fix commit `a5dc3967` is pushed.
  Incident:
  `docs/issues/2026-08-26-hostinger-keycloak-port-forward-service-port.md`.

- **Hostinger capacity check (2026-08-26):** live node `srv1754834` has 2 vCPU / 7.75 GiB RAM;
  current requests are 1610m CPU (80%) and 4880Mi memory (61%), while observed usage is 404m CPU
  (20%) and 5496Mi node memory (69%). It currently runs 44 pods, including ArgoCD, Vault, ESO,
  Prometheus, Loki, Trivy, and all shopping-cart services. Moving Keycloak+PostgreSQL there would
  fit steady-state usage but leaves inadequate CPU/request and rollout-failure headroom; defer until
  the node is upgraded to at least 4 vCPU/16 GiB or a second worker is added.

- **M2 E2E acceptance blocked (2026-08-25):** bootstrap/preflight passed and the intentional
  invalid-digest run produced a failed artifact, but publisher variables were absent. Replay
  and the passing run are blocked because `m2jump` cannot resolve `m2-air.local`. Evidence:
  `docs/issues/2026-08-25-m2-e2e-acceptance-blocked.md`.

- **CVE remediation panels empty — FINAL root cause (Claude 2026-08-25).** Two prior RCs were
  incomplete: Codex's "in-memory/no durable source" was WRONG (the CM-based durable source
  exists); my own "missing app-rebuild secret" was NECESSARY-BUT-NOT-SUFFICIENT. **Fixed the
  secret half (live):** stored classic PAT (`repo`+`read:packages`) as Keychain
  `platform-ops-app-rebuild/k3dm` → `argocd_sync_app_rebuild_secret` created the Secret →
  deleted 32h-wedged job `cve-auto-1787541034` → manual run `cve-verify-1787657822` completed
  clean, GHCR auth works, `product-catalog`+`payment` PROMOTED for real HIGH/CRIT CVEs.
  **Panels STILL empty → true RC (Bug A):** *nothing in the repo CREATES* the
  `k3dm.k3d.io/cve-remediation-event=true` ConfigMaps — `cve-remediation-verify.sh` only
  reads/transitions them, the exporter only reads them, and `app-cve-scan.sh` `_promote_image()`
  does live-patch+git-persist+notify but emits NO event CM. Consumer+exporter read events the
  producer never writes. **Bug B surfaced:** `_git_persist_promotion()` writes its askpass helper
  into the same dir it `git clone`s into → clone fails 100% ("destination not empty"), promotions
  are live-patch-only (revert on next ArgoCD sync). Token/netpol/git+CA all ruled out.
  **Fixes APPLIED + live-deployed (commit `915d1459`):** (A) `_promote_image()` now emits a
  durable `cve-remediation-event` CM via new `_emit_remediation_event()` — **verified end-to-end**
  (applied one such CM live → exporter emitted `cve_remediation_event_info{current="true"}`, the
  panels' query, cve_ids parsed; test CM deleted). (B) `_git_persist_promotion()` clones into
  `${_p_work}/repo` so the askpass helper no longer poisons the dest — **VERIFIED LIVE
  (deterministic, `7a830dda`+repro):** the failure is CVE-independent, so confirmed with a repro pod
  on real `aquasec/trivy:0.63.0` + live `platform-ops-git-writer/git-token` — OLD path reproduced
  `fatal: destination path '…' already exists and is not an empty directory`, NEW path cloned OK
  with `services/shopping-cart-payment/kustomization.yaml` at HEAD 7a830dd on k3d-manager-v1.27.0
  (no push). A pre-fix `cve-auto` pod on 08-25 had again logged `GITWRITE … clone … failed`,
  confirming the bug was 100% live before the fix. Deployed live by re-creating the
  `argocd-cve-scan-script` CM. **Hardening/UX DONE (`65bf4e31`):** (1) `argocd_sync_app_rebuild_secret`
  `_warn`s loudly when PAT absent + CronJob exists + no Secret (the wedge condition), stays optional
  otherwise; (2) `activeDeadlineSeconds: 1200` on the app-cve-scan CronJob (live) so a
  CreateContainerConfigError pod self-terminates in 20m vs the 32h backoffLimit-never-trips wedge;
  (3) no-data `description` on both remediation panels (live in monitoring CM). Full trail in
  `docs/issues/2026-08-24-cve-remediation-panels-empty.md` +
  `docs/bugs/2026-08-25-git-persist-clone-into-nonempty-dir.md`.

- **✅ CVE panel ② ("Shopping-cart Unique CVEs") — RESOLVED + DURABLE (2026-08-24).** 75 actionable
  `trivy_vulnerability_inventory{image_repository=~"wilddog64/shopping-cart-.*"}` series, native
  operator-generated (self-refreshing 24h TTL), Prometheus-verified. Three durable commits in
  `trivy-operator-acg-values.yaml`: `49477017` (`trivy.slow`+`timeout 15m0s`) + `8bfcbcc9` (scan-job
  CPU request `50m→10m`) + **`aac9cb27` (`operator.privateRegistryScanSecretsNames` +
  `accessGlobalSecretsAndServiceAccount: true`)**. Real root cause: workloads carry NO imagePullSecret
  anywhere (pod spec AND `default` SA empty) → private images pull via node-level containerd cred,
  invisible to the operator → silent skip; operator-upgrade is a dead end. Manual-CR stopgap (352
  all-sev) deleted in favor of native (75 actionable). Hub-side wiring (RBAC/ESO/appset `84817d88`,
  live Vault SA + policy fixes `9c9c8bb8`/`0f7ea0ad`) complete + verified end-to-end.
  Bug: `docs/bugs/2026-08-24-trivy-operator-skips-private-images-sa-imagepullsecret.md`.
  Auto-memory: `reference_trivy_operator_node_cred_private_image_skip`.
  - **Close-out (2026-08-24, both done):** (a) `acg-trivy-operator` **ArgoCD-synced** — the 3
    OutOfSync resources converged via a manual sync (ref `k3d-manager-v1.27.0` contains `aac9cb27`,
    so the private-registry env survived); app Synced/Healthy, panel ② held at 75 (payment 52 / order
    11 / basket 8 / product-catalog 4). (b) `allow-cve-scan-egress` netpol given a durable home —
    **spec'd + pushed** to shopping-cart-payment `docs/plans/durable-trivy-scan-coverage.md` (branch
    `feat/trivy-scan-egress-netpol`, `3ca0dca`, PR gated); flags the kustomize `commonLabels`→selector
    gotcha + optional SA imagePullSecrets hardening. Live netpol stays drift until that merges. The
    originally-planned pod-spec imagePullSecrets / scan-CR CronJob / operator upgrade are
    UNNECESSARY / redundant+harmful / dead — see bug doc "reassessed".
  - ⚠️ The 2026-08-23 "ArgoCD stale-render bug" was a **mis-diagnosis** (I read the hub's own trivy
    configmap, not hostinger's `acg-trivy-operator`, which has no `automated` syncPolicy so manual
    patches stick). Durable git fixes are correct + live.

- **Keycloak hub deploy DONE + dev SSO RESOLVED (2026-08-22).** `keycloak-0` 1/1, VirtualService
  live (`keycloak.3ai-talk.org/realms/master` 200); port-forward remote-port bug fixed (`04cc1e14`,
  →8080). Realm `home` (`dc=home,dc=org`) is the DESIGNED truth; admin/developer/operator synced,
  the only gap was missing LDAP passwords — fixed `bin/cluster-up` step 10d.5 seed loop (`9efb23f7`)
  + live `seed-dev-sso-passwords.sh` (all 3 verified via ldapwhoami, mirrored to
  `secret/keycloak/users/*`). Steps 10d.6/10d.7 realm-federation reconcile are broken+redundant →
  follow-up: delete or retarget `-r home`. **SSO login round-trip to realm `home` still to be
  confirmed by user.** Docs `docs/bugs/2026-08-22-keycloak-*`, `-hub-openldap-wrong-realm-*`.

- **hostinger istiod-scheduling cascade RESOLVED — 3/3 (2026-08-22).** Single 2-CPU node
  `srv1754834` chronically 95–98% CPU requests; istiod Pending 2d → ambient mesh down →
  product-catalog CrashLoop + frontend stuck. Break-glass restored istiod+frontend; product-catalog
  durable via PR #49 `505f758a` (cpu 100m→50m). **ArgoCD source gotcha (keep):** the hub app reads
  `repo=k3d-manager rev=k3d-manager-v1.26.0` whose kustomization pulls REMOTE
  `shopping-cart-product-catalog//k8s/base?ref=main`; a `refresh=hard` annotation re-fetched `ref=main`
  → OutOfSync, user-run `kubectl patch cpu=50m` landed it (durable, selfHeal won't revert).

- **hostinger CPU right-sizing — durable fix committed, ACTIVATION PENDING (2026-08-24).**
  Investigated: node `srv1754834` is **request-bound, not load-bound** — CPU *requests* 98%
  booked (1960m/2000m, 40m free) while *actual* usage ~20% (419m). 0 pending / no FailedScheduling
  at rest; the risk is a future rollout deadlock (surge pod > 40m free → the
  `hostinger_maxsurge_rollout_deadlock` / istiod-cascade class). Durable overlay patches committed
  `6851b5b0` on `k3d-manager-v1.27.0` (`services/shopping-cart-*/kustomization.yaml`): payment
  requests.cpu 200m→50m (+150m); basket/order/frontend maxSurge=1/unavail=0 → maxSurge=0/unavail=1.
  Each `kubectl kustomize` build verified. **INERT until activated:** the `services-git` appset renders
  app `targetRevision` from `${K3D_MANAGER_BRANCH}`, frozen at `k3d-manager-v1.26.0`; `services/` is
  byte-identical v1.26.0↔v1.27.0 so reapplying at `k3d-manager-v1.27.0` pulls ONLY this fix. Live
  patches will NOT stick (all 5 apps `selfHeal=true`). **All three prepped 2026-08-24:**
  (a) `services-git` appset re-rendered at v1.27.0 (server-diff = ONLY the branch ref moves) — apply
  BLOCKED by classifier, handed to user as a `!` command (`kubectl apply -f
  .../services-git-v127.yaml`). (b) rabbitmq 200m→50m committed `1a85dc7a` on branch
  `feat/rabbitmq-cpu-request-trim` in `shopping-cart-infra` → **PR #93 MERGED** `59ed6342` on
  2026-08-24. `enforce_admins` RESTORED (confirmed `true`); `required_reviews` remains 1. Rabbitmq trim
  now live on ref=main (ArgoCD will roll to hostinger via data-layer app read).
  (c) istiod pilot cpu 100m→50m committed `1dbe68dc` on v1.27.0 in
  `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — istiod `maxSurge=100%` is a hardcoded istio
  chart default (NOT helm-overridable in a pure-helm ArgoCD source), so the request trim shrinks the
  surge-pod footprint instead; re-rendered + server-diff = ONLY pilot cpu; apply BLOCKED by classifier,
  handed to user (`kubectl apply -f .../istio-ambient-v127.yaml`).
  **✅ ALL THREE LIVE + VERIFIED 2026-08-24:** both appsets reapplied at v1.27.0 (services-git
  `targetRevision` v1.26.0→v1.27.0; istiod appset pilot cpu 50m). basket/frontend/order Synced+Healthy,
  payment rolled (50m), istiod Synced/Healthy (surge pod scheduled), rabbitmq rolled via data-layer.
  Hostinger node `srv1754834` CPU requests **1960m (98%) → 1610m (80%)** = ~350m reclaimed (~40m→~390m
  free); zero Pending pods. Rollout-deadlock class eliminated. hostinger CPU right-sizing CLOSED.

- **Other live/tracked follow-ups:**
  - Replace the interim in-cluster CVE promoter git-writer token with a fine-grained
    contents-write-only PAT.
  - Reconcile stale port-forward/LaunchAgent state on public Grafana/status probe failures
    (`reference_single_service_502_zombie_port_forward` in auto-memory).
  - Re-seed display-only Vault paths wiped in rebuild (Prometheus basic-auth, ArgoCD/Grafana
    mirrors) — display-only, not ESO-managed; `make show-service-passwords` triage in
    `reference_show_service_passwords_na_root_causes`. Hub Prometheus is UNAUTHENTICATED (rotate fn
    targets ACG, not hub).
  - Keep ArgoCD smoke credential-drift + k3s-aws SSM registration issues visible in `docs/issues/`
    until their live follow-ups close. Account-level SSM Default Host Management Role optional.
  - Dependabot alert #6 (js-yaml) remediated as lib-foundation `v0.4.11` (subtree `1bf1d2ce`,
    lockfile `3.15.1`); reads `open` only because Dependabot scans main → auto-closes when
    v1.26.0 → main. Dev-only transitive, low risk.

- **k3d agent watchdog hardening (2026-08-26):** existing bounded `node-health-watch` previously
  skipped exited containers; commit `15c7d072` now uses `docker start` for `created`/`exited`/`paused`
  states and `docker restart` only for running containers. Focused BATS 2/2, ShellCheck, and
  `_agent_audit` passed. Watchdog reinstalled live with the existing 3-failure/300-second cooldown.

## Operating decisions

- **2026-08-26 hub outage:** an exited k3d agent caused node-affine Prometheus/Loki pods to hang and
  Kine/SQLite readiness to fail, producing edge 502s. Agent/server restart plus stale pod cleanup
  restored the workloads; public forwards still require live verification. See
  `docs/issues/2026-08-26-hub-control-plane-and-edge-forward-outage.md`.

- **Edge forward hardening:** `ea91431d` increases wrapper probe timeout/hysteresis (5s/6 failures)
  to avoid restarting ArgoCD/Keycloak on transient control-plane latency. Public ArgoCD/Keycloak
  checks still need re-verification once the k3s API settles.

- `make status` follows the active provider (concise/full/JSON); Slack reuses the same summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events; history
  keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials,
  and an EXIT-trap result artifact written before teardown.
- **2026-08-27 M2 E2E migration:** corrected the remote dispatcher to forward an explicit immutable
  `E2E_IMAGE_TAG` to the M2 runner (`0f16f0de` on `k3d-manager-v1.27.0`). The corrected image build
  (`shopping-cart-e2e-tests` run `33073207387`, source `0c2505bb`) passed; live M2 acceptance remains
  the next verification step. M4 storage is healthy (58% root, 196 GB free; OrbStack 26%, 184 GB free).
  The 2026-08-27 M2 run used the immutable tag but failed 31/102 (26 passed, 45 skipped), with
  basket/order response-shape failures and payment-suite failures; see
  `docs/issues/2026-08-27-m2-e2e-acceptance-after-immutable-image.md`.
- **2026-08-27 Keycloak smoke fallback:** committed `931839ab` on `k3d-manager-v1.27.0` to support
  deployed password-only Keycloak admin Secrets while preserving the existing username/password path.
  Focused Keycloak BATS passed 12/12 and ShellCheck was clean.
- Do not deploy source-only changes until their release-branch/PR gates + live verification are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default), k3s-aws selects
  SSH and overrides explicit SSM with a warning; SSM stays available for non-bridge Vault profiles.

- **2026-08-28 hub last-mile close-out** (`k3d-manager-v1.27.0`): four follow-ups from the CPU-crisis
  resolution actioned.
  - **Governance already durable (verified, no-op):** `argocd_check_values_branch` → all 6 Applications
    track `k3d-manager-v1.27.0` (no drift); live `monitoring` ns confirms Step 2 governance is applied —
    loki-canary=0, prom scrapeInterval/eval=60s, retention=3d, retentionSize=8GB. ApplicationSets were
    already reapplied; nothing inert.
  - **Vault auto-unseal watchdog deployed + fixed:** installed `vault_install_unseal_watchdog` (CronJob
    `vault-unseal-watchdog`, ns `secrets`, `* * * * *`, Forbid). Found + fixed two bugs — (1) stale
    pinned image `1.18.3` vs live `1.20.1`, and vars.sh unconditionally exporting the stale default,
    defeating derivation; now `vault.sh` derives the image from the running Vault StatefulSet and vars.sh
    leaves `VAULT_UNSEAL_IMAGE` empty; (2) per-node k3d image cache + `activeDeadlineSeconds:50` killed a
    cold pull → raised to 150. Validated: manual job SUCCEEDED ~12s, logs `vault already unsealed`. Note:
    a real restart preserves node image caches, so the cold-pull only bites first-deploy. Spec:
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Frontend-login false-red fixed:** `bin/k3dm-webhook` skip guard extended from `kc_via_smoke_client`
    to a new `kc_token_is_stub` flag (True on both smoke-client AND admin-cli fallback paths), so an
    expected 401 on `/api/cart` from a stand-in admin token is a SKIP not a hard FAIL. `make status` now
    `WARN (1 warning)` — the lone warning is the honest "no real smoke user seeded" skip; everything else
    green. Real outages still FAIL (guard is 401/403-only). Spec:
    `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`. Durable follow-up (out of scope):
    seed a real `k3dm-smoke-user` in the shopping-cart realm to make this a true PASS.
  - **loki re-shed declined (data-driven):** offered when server-0 was ~360% cold-start; it has since
    settled to **95–130%** with canary already gone. A manual `loki=0` would be reverted by ArgoCD
    selfHeal (git declares 1) and would remove log aggregation for CPU that is no longer pressured — left
    loki at 1/1. One-command shed remains available if headroom is ever needed.
- **2026-08-28 optional durable follow-ups:**
  - **deploy_vault now auto-installs the unseal watchdog** (`vault.sh`, after `_vault_setup_pki`, guarded
    `|| _warn`) so auto-unseal survives a hub rebuild without a second command — same pattern as
    platform-ops in the ArgoCD bootstrap. Decision folded into
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Real smoke-user seed NOT applicable on the hub — architecture finding.** `keycloak_seed_smoke_user`
    targets a `shopping-cart` realm, but the hub Keycloak (identity ns, reached at
    `keycloak.shopping-cart.local`) has only `home` + `master` realms — no `shopping-cart` realm and no
    frontend/app client (`home` has only default clients). The shopping-cart frontend + its realm live on
    the **app-cluster (ACG)**, not the hub. So seeding a hub user cannot produce a true Frontend-login PASS
    without first provisioning the shopping-cart realm + frontend client on the hub Keycloak (a real setup
    task, not a last-mile seed). The honest SKIP from the `kc_token_is_stub` fix is the correct state. Seed
    aborted at the realm-existence check — created nothing (verified: no `k3dm-smoke-user` secret, no
    `k3dm-smoke` client). Also noted: codebase default realm `shopping-cart` is stale vs live hub `home`.

- **2026-08-29 monitoring-pause Grafana keep-list — LIVE-VERIFIED (8506f5fe, pushed):** pure
  whole-word `_observability_workload_in_keep_list` + default
  `OBSERVABILITY_PAUSE_KEEP=kube-prometheus-stack-grafana` pause-sweep exemption; resume unchanged.
  Five pure BATS cases + Makefile help. Spec `docs/bugs/2026-08-29-pause-keep-grafana-up.md`. Coded by
  Codex, Claude-verified (BATS 5/5, `bash -n` clean, SC2016 pre-existing only). Live hub:
  `make monitoring-pause` keeps grafana 1/1 (loginable, `database:ok`) while everything else → 0/0;
  resume → HEALTHY. By design panels show "No data" while paused (UI reachable, not live data). To
  restore the old all-or-nothing sweep set `OBSERVABILITY_PAUSE_KEEP=""`.

- **2026-08-29 layered `monitoring-resume` — LIVE-VERIFIED (1bdbe3c6, pushed):** `make
  monitoring-resume LAYER=1` brings up **Grafana + Prometheus only** (live dashboards), all else 0;
  `LAYER=2` or no arg = full stack (existing body, verbatim). Added `_observability_normalize_layer`
  (1→1, 2/empty/unknown→2 — forgiving) + `_observability_resume_layer1` (keeps ArgoCD `automated:null`
  so selfHeal can't resurrect the 0-set; explicit replica drive; idempotent from pause/L1/L2), reusing
  the keep-list predicate with `OBSERVABILITY_LAYER1_UP=kube-prometheus-stack-grafana
  prometheus-kube-prometheus-stack-prometheus`. Makefile `$(LAYER)` passthrough + help. 5 pure BATS
  normalize cases. Spec `docs/bugs/2026-08-29-layered-monitoring-resume.md`. Coded by Codex,
  Claude-verified (BATS 10/10, `bash -n` clean, SC2016 pre-existing only, diff==spec, scope==3 files).
  **Live hub:** L2→`LAYER=1` dropped to grafana 1/1 + prometheus 1/1 (rest 0/0), Prometheus `up` query
  returned series + Grafana `database:ok`; `LAYER=2` restored all 7 workloads 1/1, `make status`
  HEALTHY. One manual touch during the L2 ramp: deleted a stale `Unknown` prometheus pod from the known
  CPU-starvation cascade (full stack starting at once) — not a feature defect.

- **2026-08-29 Tier-1 E2E orders.spec ROOT-CAUSED + FIXED (aa2f2190, pushed) — gate rerun
  confirming:** the orders.spec wholesale failure (42 ✘) was NOT a client-contract bug. Ground
  truth (captured Playwright `results.json` from the live pod before teardown + direct
  port-forward replay): the deployed order image `sha-56033880` is the **Go** rewrite (commit
  `5603388`), not Java (earlier Dockerfile read was wrong), and it ships **no runtime migration** —
  the substrate created the `orders` DATABASE but never the `orders`/`order_items` TABLES →
  every order DB op HTTP 500 (`relation "orders" does not exist`, 42P01). Fix: added
  `20-orders-schema.sql` to `scripts/etc/e2e/postgres.yaml` initdb (`\connect orders` + DDL).
  Critical nuance: DDL must match the **deployed** commit `5603388` — its `order_items` has **no
  `total_price`** column; copying repo-HEAD/testdata DDL (which added `total_price NOT NULL`) 500s on
  insert (23502) since that binary never writes it. **Live-validated** against the running substrate:
  `POST /api/orders → 201` with full contract (id, status PENDING, items[].subtotal, totalAmount,
  shippingAddress, currency USD), `GET …?customerId=X` (X-User-ID header) → 200 with the order. List
  filters by `X-User-ID` (MockAuthMiddleware), not the query param — e2e client sends it consistently,
  no change needed. Payments.spec (27) + payment cross-service stay Tier-1-out-of-scope (no payment
  manifest = Tier-2/ACG's job). Spec `docs/bugs/2026-08-29-e2e-order-schema-missing.md`; durable
  service-side self-migrate follow-up `docs/issues/2026-08-29-order-service-no-startup-migration.md`.
  Confirming rerun DONE (`~/.k3dm/e2e/1788051374-25838.json`, commit 86298144): **passed 26→45,
  failed 31→12, skipped 45**. Cross-service fully greened (21→0), orders 42→2. **Residual 12 =
  ZERO substrate bugs**: (a) 9 payments `ECONNREFUSED :8084` — no payment svc in Tier-1
  (Tier-2/ACG's job); (b) 2 order status-update — e2e test sends status `CONFIRMED` which is NOT
  in the deployed `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal
  transitions (PENDING→only PAID/CANCELLED) → PATCH 400 → status undefined = **e2e-test contract bug**
  (shopping-cart-e2e-tests, spec-not-direct); (c) 1 cart remove-qty-0 — `cart.items` undefined,
  pre-existing basket/e2e mismatch. Substrate fix is COMPLETE for its scope. To green the gate:
  cross-repo — fix the 3 test-contract bugs in the e2e repo (+ rebuild image) and decide payment
  (Tier-1 manifest vs scope-to-non-payment + Tier-2). User chose (2026-08-29): **fix e2e tests,
  payment→Tier-2.**

- **2026-08-29 e2e residual triage — CART RECLASSIFIED as a basket-service bug (specs written,
  Codex handoff pending):** on grounding the 3 residuals, only 2 are e2e-test bugs; the cart one is
  a service bug:
  - **Order status (2, e2e-test bug):** tests send status `CONFIRMED`, absent from the deployed
    `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal transitions
    (PENDING→only PAID/CANCELLED). Fix = use real enum + legal chain (PENDING→PAID; history
    PENDING→PAID→PROCESSING→SHIPPED). Spec `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`
    (repo `shopping-cart-e2e-tests`).
  - **Cart qty-0 (1, BASKET-service bug, NOT a test bug):** basket `UpdateItemRequest.Quantity`
    is `binding:"required,min=0"`; gin treats int 0 as "missing" so `{quantity:0}` → 400 before the
    handler's `quantity<=0` remove path runs. Test is CORRECT. Fix = drop `required` (use `min=0`).
    Issue `docs/issues/2026-08-29-basket-update-quantity-zero-required.md` (repo `shopping-cart-basket`).
  Both are shopping-cart repos → spec+Codex, branch+PR, rebuild image (spec-not-direct). Codex handoff
  + image rebuild + Tier-1 re-verify still to do; PR/merge gated.

## Canonical pointers

### 2026-09-01 — live frontend Keycloak client hotfix
- Created missing public OIDC client `frontend` in hub `shopping-cart` realm (Keycloak admin API returned HTTP 201); verified by an in-pod admin query.
- Configured callback `https://frontend.3ai-talk.org/callback` and web origin `https://frontend.3ai-talk.org`, matching the deployed frontend bundle.
- Public `keycloak.3ai-talk.org` DNS currently fails to resolve from the workstation, so browser verification remains blocked by the edge/tunnel path, not Keycloak client configuration.

- Roadmap: `docs/roadmap.md`
- v1.27.0 plans: `docs/plans/v1.27.0-*`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`

### 2026-09-02 — ArgoCD identity sync recovery and secure credential handling
- ArgoCD password was handled only in process memory via a Kubernetes-secret-to-API
  pipeline; no password file, shell argument, log, or output was created.
- Recreated the stuck `argocd-application-controller-0` pod and cleared its stale
  operation. Identity sync now reaches the immutable `postgres-keycloak-pvc` blocker.
- Added `Replace=true` to the identity Application template in `bin/cluster-up`.
- Follow-up issue: `docs/issues/2026-09-02-secure-argocd-sync-and-pvc-blocker.md`.

### 2026-09-03 — Grafana CVE panels empty
- Prometheus retained 6,066 vulnerability series and 6 remediation events, but the
  vulnerability exporter target was down on scrape timeout because `/metrics`
  synchronously refreshed both clusters.
- Exporter now refreshes in a 60-second daemon loop and serves the cached snapshot
  immediately. Manifest applied; post-rollout scrape confirmation is pending.
- Issue: `docs/issues/2026-09-03-grafana-cve-tables-empty-exporter-timeout.md`.
### 2026-09-01 — status blind spot documented
- Filed `docs/issues/2026-09-01-status-blind-spot-on-exited-hub-agent.md`: when a hub agent exits, webhook-backed `make status` reports only `UNKNOWN` and omits node evidence. Recommended bounded local Docker/node fallback; no automatic restart.
### 2026-09-01 — status fallback and Keycloak credential lookup fixed
- `make show-service-passwords` now reads `identity/keycloak-admin-secret` key `password`; verified it reports admin present without exposing the value.
- `bin/cluster-status-summary` now adds local `k3d-k3d-cluster-agent-0` Docker state to webhook-unavailable output. Syntax and all 8 BATS tests pass.
### 2026-09-01 — Hermes automation roadmap
- Added an unversioned forward theme for optional Hermes event-driven operations automation: read-only monitoring first, then approval-gated repairs, cooldowns/budgets, audit, and verification. k3d-manager webhook remains authoritative.

### 2026-09-03 — keycloak-secrets ES root cause = Vault FIELD SCHISM (not missing data)
- Live `keycloak-0` is DECOUPLED from `keycloak-secrets`/`postgres-keycloak`: it connects to
  `jdbc:postgresql://keycloak-postgresql:5432/bitnami_keycloak` (legacy Bitnami PG, user `bn_keycloak`)
  with a FILE-based password (`KC_DB_PASSWORD_FILE`) from configmap `keycloak-env-vars`. SSO is safe to
  touch these secrets — nothing live reads them.
- The failing ExternalSecrets (`keycloak-secrets`, `keycloak-client-secrets`, `ldap-secrets`) all use
  store `vault-kv-store`; the WORKING ones (`keycloak-admin-secret`, `keycloak-ldap-secret`, `openldap-admin`)
  use `keycloak-vault-store`. Error is `cannot find secret data for key: "admin_password"` at
  `secret/data/keycloak/admin` — the secret is READABLE but the FIELD is misnamed.
- `secret/keycloak/admin` holds only `password` (keycloak.sh convention); the infra ES wants `admin_password`
  + `db_password` (shopping_cart.sh convention). `secret/ldap/admin` does not exist; canonical ldap admin pw
  is `secret/ldap/openldap-admin#LDAP_ADMIN_PASSWORD`.
- FIX (operational seed, NOT a manifest change): patch `secret/keycloak/admin` to ADD
  `admin_password`(=existing `password`) + fresh `db_password`; create `secret/ldap/admin#admin_password`
  (=openldap-admin LDAP_ADMIN_PASSWORD). Auto-mode classifier blocked the read-into-var+write script twice;
  handed the exact command to the user to run via `!`.
- Live identity app syncOptions = ["CreateNamespace=true","Replace=true"] (Codex 0bca3e21 IS live) with
  automated=null (Stage A suspension holds). DO NOT resume auto-sync until Replace=true is scoped to the
  Keycloak Service only (Stage B) — resuming with blanket Replace=true would force-replace Keycloak STS/PVC.
- Sequence once seeded: ES reconciles (15m or forced) → keycloak-secrets syncs → postgres-keycloak leaves
  CreateContainerConfigError → identity app heals to Healthy while auto-sync STAYS suspended (safe hold).

### 2026-09-04 — v1.28.0 two-cloud bring-up: fresh-hub `make up` aborted on unguarded PrometheusRule apply
- Live two-cloud validation (AWS EC2 k3s + hostinger): both clouds' nodes + hub came up
  (`ubuntu-k3s` 3 nodes Ready, `ubuntu-hostinger` 1 node Ready, hub k3d Up), but ArgoCD stayed BARE
  (0 registered clusters, 0 ApplicationSets, 0 Applications). `make up` had errored, not completed.
- Root cause: `scripts/plugins/argocd.sh` applied `PrometheusRule` (1540), `AlertmanagerConfig` (1546),
  and `vulnerability-inventory-exporter` (1549, bundles a ServiceMonitor) WITHOUT a CRD guard — on a
  fresh hub the Prometheus-Operator CRDs aren't installed yet, so `PrometheusRule` hard-failed
  (`no matches for kind "PrometheusRule" in version "monitoring.coreos.com/v1"`) and aborted the deploy
  BEFORE `register_app_cluster` (bin/cluster-up:758) ever ran. The ServiceMonitor ensure (argocd.sh:512)
  already had the correct guard; these three missed it.
- FIX (this branch): added a single `prometheusrules.monitoring.coreos.com` CRD-presence guard
  (`_prom_operator_present`) mirroring line 512; gated all three applies, left the Grafana ConfigMap
  unconditional. shellcheck clean. Spec: `docs/bugs/argocd-prometheus-operator-unguarded-crd-apply.md`.
- Next: re-run idempotent `make up CLUSTER_PROVIDER=k3s-aws` → confirm it clears platform-ops and reaches
  `register_app_cluster`, then reapply ApplicationSets (hub + ACG) + `argocd_check_values_branch`, then
  inspect the v1.28.0 multi-cloud internals (scoped state dirs, active-providers, port offsets, hub-lock).

### 2026-09-04 (cont.) — argocd guard SHIPPED + verified; next blocker LDAP verify newline FIXED
- argocd guard FINAL scope = ALL SIX monitoring-stack-dependent applies behind one
  `prometheusrules.monitoring.coreos.com` CRD guard: PrometheusRule, AlertmanagerConfig,
  vulnerability-inventory-exporter(+rollout restart), and the argocd/cve-autopatch/e2e Grafana dashboard
  ConfigMaps (all target `namespace: monitoring`, also absent on fresh hub). The earlier "leave the
  ConfigMap unconditional" note was WRONG — corrected before commit. Committed `5f4526fd` (pushed).
- LIVE-VERIFIED: guard fired ("Prometheus-Operator CRDs / monitoring namespace absent; skipping..."),
  platform-ops cleared, `ubuntu-k3s` registered into hub ArgoCD, app stack built through the identity phase.
- NEXT blocker hit at Step 10d.5/14 (LDAP password seed): ldappasswd -S set OK but ldapwhoami verify failed
  Invalid credentials(49) for admin/developer/operator → checkpoint not written → `make up` Error 1.
- Root cause: verify pipe `printf '%s\n'` wrote `<password>\n` to the `-y` file; ldapwhoami -y uses the whole
  file incl. newline as bind password. PROVEN live on openldap-0: -y w/newline → invalid creds(49);
  w/o newline → bind OK. FIX: `printf '%s\n'` → `printf '%s'` at bin/cluster-up:1045 (verify only; the
  ldappasswd -S set step's newlines are prompt delimiters, left as-is). shellcheck clean, bats 8/8.
  Committed `41389804` (pushed). Spec: docs/bugs/2026-09-04-ldap-verify-ldapwhoami-trailing-newline.md.
- Observation (separate, NOT fixed): two LDAP instances in `identity` on hub — openldap-0 (Helm
  openldap-stack-ha StatefulSet, the seed target, holds all real users) + a stray `ldap` Deployment
  (name=ldap, component=directory). Immaterial to the newline bug; matters for Keycloak federation (10d.6).
- IN FLIGHT: `make up CLUSTER_PROVIDER=k3s-aws` re-run (task bsqm1ma34) to confirm 10d.5 clears.
- STILL PENDING after make up completes: reapply ApplicationSets pinned to release branch (hub + ACG) →
  argocd_check_values_branch → inspect v1.28.0 multi-cloud internals across both clouds. No PR yet (gated).

### 2026-09-04 (cont.) — TWO-CLOUD validation COMPLETE (AWS + hostinger, both fixes verified)
- Brought up hostinger as 2nd cloud (`make up CLUSTER_PROVIDER=k3s-hostinger`, task bzqq4i5i6, exit 0).
  Path = deploy_cluster (NOT bin/cluster-up): k3sup install ran idempotently ("Skipping...already exists",
  workloads persist — never touches the VM), merged ubuntu-hostinger kubeconfig, registered into hub
  (ubuntu-hostinger -> https://2.25.146.252:6443), recorded active-providers/k3s-hostinger marker.
- VERIFIED two-cloud state: BOTH cluster secrets in hub cicd (cluster-ubuntu-k3s + cluster-ubuntu-hostinger);
  BOTH active-providers markers coexist; ArgoCD generating ubuntu-hostinger-* apps (data-layer/eso/
  shopping-cart-* Synced+Healthy); both node contexts reachable (k3s=3, hostinger=1); argocd_check_values_branch
  green on k3d-manager-v1.28.0 after BOTH runs; k3s-aws scoped state intact (not clobbered).
- OBSERVATION 1 (consistency, not a bug): k3s-hostinger/ has NO scoped state subtree — deploy_cluster path
  isn't checkpoint-scoped like bin/cluster-up. hostinger uses Cloudflare edge + in-cluster Vault (HUB_VAULT_PROFILE
  =hostinger), so no local port-forward footprint to scope/offset. Port-offset table (aws=0/hostinger=10/...) applies
  to the cluster-up local-PF path only. Candidate v1.28.0 follow-up: scope deploy_cluster state too, or document why not.
- OBSERVATION 2: ubuntu-hostinger-platform app HEALTH=Unknown (others Synced+Healthy) — likely reconciling; recheck.
- MILESTONE STATUS: v1.28.0 two-cloud multi-provider is LIVE-VALIDATED. Remaining before PR (gated): resolve/close
  the two observations, lib-foundation acg-robust-click PR (credential-test first), two-LDAP-instance federation check.

### 2026-09-04 (cont.) — Two v1.28.0 follow-ups CLOSED
- FOLLOW-UP 1 (deploy_cluster scoped-state asymmetry): NO CODE CHANGE — rationale already in
  docs/plans/v1.28.0-parallel-multi-cloud-provisioning.md (~L420: hostinger deliberately flat, "collides
  with nothing", full scoping = tracked future work). Added a dated Live-validation note confirming it:
  hostinger's deploy_cluster path created NO scoped subtree AND no local PF footprint (edge + in-cluster
  Vault), did not disturb k3s-aws state. Sequential two-cloud coexistence PROVEN; literal simultaneity
  (Phase 3/4 ports+flock) still untested.
- FOLLOW-UP 2 (two-LDAP federation check): RESOLVED the question, found a REAL high-sev bug (needs a
  decision, NOT blind-fixed). Keycloak shopping-cart realm federates the osixia `ldap` Deployment
  (ArgoCD-managed by shopping-cart-identity, dc=shopping-cart,dc=local, connectionUrl
  ldap.identity.svc:389), NOT openldap-0. The cluster-up Step 10d.5 seed writes openldap-0
  (dc=home,dc=org) + Vault → DECOUPLED from SSO. PROVEN: Vault dev password fails to bind osixia ldap
  (Invalid credentials 49). So get-keycloak-password returns a non-working-for-SSO password.
  Filed docs/issues/2026-09-04-keycloak-federates-osixia-ldap-not-seeded-openldap.md with 3 decision
  options (A osixia canonical / B openldap canonical / C two-dirs-by-design) + verification steps.
  Supersedes the pre-osixia 2026-08-22 doc. ESCALATED to user — awaiting canonical-directory decision.

### 2026-09-04 (cont.) — Tidy-up: pruned unconditional Jenkins fixtures from LDAP bootstrap seed
- User asked why jenkins-admin appears in openldap-0 though Jenkins was never deployed. Answer: static
  seed fixture in bootstrap-basic-schema.ldif (Jenkins is deprecated/never deployed; 0 jenkins pods on
  hub/aws/hostinger). The ldap.sh generator already GATES jenkins entries behind enable_jenkins; only the
  static bootstrap seeded them unconditionally.
- Pruned (dc=home,dc=org tidy surface, self-consistent): deleted dead jenkins-users-groups.ldif (unloaded);
  removed jenkins-admin user + jenkins-admins group + it-devops dangling jenkins-admin member from
  bootstrap-basic-schema.ldif (kept it-devops w/ chengkai.liang); dropped jenkins-admin from
  test-directory-auto-load user+group loops; dropped jenkins-admin from rotation defaults (vars.sh
  LDAP_USERS_TO_ROTATE + ldap-password-rotator.sh + .yaml.tmpl). shellcheck clean; group blocks keep >=1 member.
- Deliberately KEPT (deprecated-but-gated / separate scope): ldap.sh gated generator, vars.sh LDAP_JENKINS_*
  config block, bootstrap-ad-schema.ldif (separate AD dc=corp,... testing dir), dirservices RBAC,
  jenkins values tmpls, smoke-test-jenkins, ad/vars.sh jenkins-admin path. Source-only cleanup — live
  openldap-0 keeps jenkins-admin until a fresh bootstrap; SSO (osixia ldap) unaffected.
- Spec: docs/bugs/2026-09-04-prune-unconditional-jenkins-ldap-fixtures.md.

### 2026-09-04 (cont.) — DECISION: leave bootstrap-ad-schema.ldif Jenkins fixtures as-is
- After pruning the default-directory Jenkins clutter (d9ee756b), checked the AD-testing schema
  scripts/etc/ldap/bootstrap-ad-schema.ldif (dc=corp,dc=example,dc=com; "Jenkins Service"/"Jenkins Admins").
- FINDING (non-obvious): its Jenkins entries are LOAD-BEARING for a live CI suite —
  scripts/tests/lib/dirservices_activedirectory.bats:227 asserts "CN=Jenkins Admins,OU=Groups,DC=corp,...".
  The whole `activedirectory` directory-service provider is a Jenkins-AD integration feature
  (_dirservice_activedirectory_generate_jcasc/authz, deploy_ad → _ldap_run_ad_smoke_test, AD_BIND_DN=svc-jenkins).
  It loads ONLY under explicit AD testing (ldap.sh:1207 deploy_ad), NOT in the default openldap-0 directory.
- USER DECISION 2026-09-04: LEAVE IT. Removing Jenkins here isn't a fixture tidy — it's "remove the whole
  Jenkins-AD provider + its BATS suite", a separate larger task that conflicts with keep-deprecated-Jenkins.
  Do NOT re-open as "tidy" work. See [[project_jenkins_deprecation]].

### 2026-09-04 (cont.) — lib-foundation PR #45 created (acg robust-click), gates green, AWAITING MERGE GO
- Sequence (user-directed 2026-09-04): (1) lib-foundation PR → (2) subtree-pull into k3d-manager → (3) v1.28.0 PR.
- STEP 1 DONE (prepared, gated): PR https://github.com/wilddog64/lib-foundation/pull/45
  (fix/acg-sandbox-robust-click, commit 91f0f12: _robustClick dispatched MouseEvent for sandbox reveal/provision).
  Gates: make credential-test PASS (extracted + sts-validated AWS creds); CI acg/bats/shellcheck all green;
  scope clean. Copilot NOT attached (appears disabled on lib-foundation; not a payment PR). k3dm overlay
  (scripts/lib/foundation/.../acg/playwright/{sandbox.js,acg_restart.js}) is IDENTICAL to 91f0f12 — no un-upstreamed drift.
- HOLD: never-auto-merge. Awaiting user go to merge #45.
- STEP 2 (after merge): tag lib-foundation v0.4.14 → git subtree pull into k3d-manager (replaces the uncommitted
  overlay). STEP 3: create v1.28.0 k3d-manager PR (branch k3d-manager-v1.28.0, all this session's commits).

### 2026-09-04 (cont.) — STEP 1+2 DONE: lib-foundation v0.4.14 merged + subtree-synced into k3d-manager
- #45 merged (squash dddc18cb); tagged+released lib-foundation v0.4.14; git subtree pull --prefix=scripts/lib/foundation
  lib-foundation v0.4.14 --squash → commits 05c5e952 (squash) + 09dab403 (merge). Overlay now formalized; tree clean.
  Verified: pulled subtree JS identical to v0.4.14, _robustClick present. Pushed origin/k3d-manager-v1.28.0.
- STEP 3 NEXT: create v1.28.0 k3d-manager PR (base main). Pre-PR gates to run: CI green on branch, scope check,
  live smoke. Never-auto-merge holds for the v1.28.0 merge.

### 2026-09-04 (cont.) — STEP 3 DONE: v1.28.0 PR #119 created, CI GREEN, AWAITING MERGE GO
- PR https://github.com/wilddog64/k3d-manager/pull/119 (base main ← k3d-manager-v1.28.0, 24 commits, merge-base 62c9ff27).
- Gates: CI all green (CodeQL actions/js-ts/python, lint, detect, GitGuardian; stage2 skipped-conditional);
  local lib bats 323 exit 0; shellcheck clean; live two-cloud smoke done; scope clean.
- Copilot: NOT attached (requested_reviewers empty on both #45 and #119 via raw-JSON POST — appears Copilot code
  review not enabled on these repos right now). Flagged to user; not a payment PR.
- HOLD: never-auto-merge. Awaiting user go to merge #119. On merge: /post-merge (restore protection, tag v1.28.0,
  release, next branch, retro, standing-docs audit, memory-bank).
- Sequence COMPLETE up to the gate: lib-foundation #45 merged+v0.4.14+subtree-synced → v1.28.0 PR #119 up & green.

## 2026-09-11 — Hub rebuild verification (Claude)

Independently verified Codex's hub rebuild + sqlite compaction (`c62a0f63`).
Headline claims hold: Kine 8.3 GiB -> 554 MiB, 4 nodes Ready, all 14 PVCs Bound,
all 9 public probes reproduced exactly, `hub_recovery.bats` 10/10, shellcheck clean.

The closing "final verification" commit overstated completion. Six gaps filed in
`docs/issues/2026-09-11-hub-post-rebuild-verification-gaps.md`:

1. Kine compaction stalled again — `compactRev` pinned at 12000 vs `currentRev`
   92579; last compaction line 11:35:52, no retry for 2h17m. The rebuild reset the
   symptom, not the cause. PRIMARY.
2. Rebuilt server is outside k3d management (`k3d cluster list` -> SERVERS 0/0;
   no `k3d.cluster`/`k3d.role` labels; hostname `457182e619fc`).
3. Missing mount propagation -> `istio-cni-node` and `node-exporter` stuck in
   CreateContainerError on the control-plane node (526/538 events).
4. Four `svclb-istio-ingressgateway` pods Pending; 2 keycloak-realm-reconcile Error.
5. `hub_recovery.bats` was absent from the CI BATS list — now added.
6. Argo app-cluster registration recorded as `ubuntu-k3s` (dead AWS context name).

In progress: compaction recovery — `make monitoring-pause` applied to relieve
control-plane CPU (was 314% on server-0, host load 15.84) before restarting the
K3s server to revive the stopped compaction loop.

### Kine sensor blind spot fixed (2026-09-11)

Root cause of why Hermes never fired during the stall: `compaction_recent` was
computed as `"compact" in text.lower()`. Every Kine `Slow SQL` line contains
`compact_rev_key`, so the signal was true exactly when compaction was stalled.
Live 20m window measured 132 slow-SQL lines, 107 bare-substring matches, and
**zero** real compaction events. Fixed via `kine_log_signals()` (event-marker
matching + new `compaction_failed`); 52/52 hermes tests pass.

R5's precondition left unchanged on purpose — it still requires
`stale_acg_registration` AND >=8 GiB, so it cannot fire on a compaction stall at
0.7 GiB. Widening an auto-actuator that scales the hub ArgoCD controller to zero
needs owner sign-off.

Open live action: compaction loop is dead (0 attempts in 40m+, `compactRev`
pinned at 12000, db 554->566 MiB and growing). Remedy is a K3s server restart to
revive the loop — NOT yet performed; awaiting owner go because the server was
rebuilt outside k3d. `make monitoring-pause` is currently applied (reverse with
`make monitoring-resume`); it cut slow-SQL but not load, since the churn source
is ArgoCD reconciliation of 9 degraded apps, not monitoring.

### Compaction recovered (2026-09-11 14:52 UTC)

Two levers, in order. Pausing the hub ArgoCD application controller cut churn
1000->557 rev/5min, slow SQL to ~0 and load 17->9.7, but produced zero
compaction events in 12 min — proving a dead goroutine, not a slow one. ArgoCD
was only ~45% of churn; the rest is ordinary baseline.

`docker restart k3d-k3d-cluster-server-0` (14:46:33) revived it. compactRev
12000 (pinned 3h20m) -> 120613 vs currentRev 121763, **zero** Compact failed.
ArgoCD controller restored to replicas=1; compaction stayed healthy with it back.
state.db 618->595 MiB, WAL 150->59 MiB. Load 17->11.2. Keycloak recovered to 200.

Monitoring remains PAUSED by owner request — the two prometheus 502s are that,
not a fault. `make monitoring-resume` reverses it.

Still open: Findings 2/3/4/6 (server outside k3d management -> mount propagation
breaks istio-cni-node + node-exporter, svclb Pending, ubuntu-k3s registration
name) and Finding 8 (R5 precondition still cannot fire on a compaction stall).

### Findings work (2026-09-11, later)

- **Finding 8 DONE** — added Hermes R6 (`docs/bugs`-free, code): proposes
  `docker restart k3d-k3d-cluster-server-0` on a compaction stall. Deliberately
  did NOT widen R5: today proved R5's lever (pause ArgoCD) relieves pressure but
  does not revive a dead compaction goroutine. R6 is proposal-only and excluded
  from the auto guard. 55/55 hermes tests pass.
- **Findings 2/3/4 = one defect**, spec'd in
  `docs/bugs/2026-09-11-hub-control-plane-readoption.md`. The hand-rebuilt server
  lacks k3d labels, shared mount propagation, and `--disable=traefik`. Traefik's
  svclb squats ports 80/443 so Istio's svclb can never schedule.
  **Blocking constraint found: 3 PVs are pinned to node name `457182e619fc`**
  (rabbitmq, postgres-keycloak, trivy-server) and will be stranded by the
  rename — must be repinned/drained inside the window.
  Live `docker exec` fixes (`mount --make-rshared /`, writing
  `/etc/rancher/k3s/config.yaml`) were rejected: they vanish on container
  recreation and leave the node invisible to k3d. Also blocked by the sandbox.
- **Finding 6 deferred with reason**: 12 Applications + 16 appset references use
  `destination.name: ubuntu-k3s`; renaming churns 28 Applications right after a
  compaction recovery. Sequence into the same window.

### M2 backup verified — DO NOT DELETE (2026-09-11)

Owner asked if Codex's M2 backup can be deleted. **No — the M4 source is GONE**
(`~/k3dm-backups`, `~/k3dm-hub-rebuild-20260909`, `.local/share/k3d-manager/backups`
all absent; only `~/Library/Logs/k3dm-hub-rebuild-{copy,monitor}.log` remain).
The plan's two-copy retention is already violated; **M2 is the only copy**.

Verified read-only at `m2-air.local:~/k3dm-backups/k3dm-hub-rebuild-20260909`:
`state.db` page_size 4096 x page_count 2156034 = 8831115264 == file size exactly
(proves NOT truncated — the failure that killed the earlier .tgz); quick_check ok;
769843 kine rows; WAL 0 bytes; all 7 logical claims present matching
`_hub_recovery_records()`; 4 YAML exports valid; no rsync partials.

Two caveats that can never be closed: `COPY_CHECKSUM_VERIFIED` records no value
or method (Codex marker, not evidence), and a 2.57 GiB gap vs the monitor-logged
16347868 KB (likely `--partial` cleanup, unprovable without the source).

Earliest reconsideration **2026-09-17**; make a second copy first.
Details: `docs/issues/2026-09-11-m2-backup-verification-and-lost-source.md`.

Hub fully recovered after my stop/blocked-restart incident: frontend+argocd 200,
56 pods Running, 4 nodes Ready. Residual 2 CreateContainerError / 4 Pending are
the pre-existing Findings 3 and 4, unchanged.

### Findings 2/3/4 RESOLVED + M2 backup deleted (2026-09-11)

Re-adopted the control-plane node under k3d. **Key improvement on the spec: kept
the container hostname `457182e619fc`.** k3d identifies nodes by label and agents
reach the server by container name — both already correct — so only the hostname
was wrong. Keeping it meant the k8s node name never changed and the 3 pinned PVs
were never stranded. The spec's blocking constraint evaporated; no repin/drain.

Acceptance all green: k3d SERVERS 1/1 (was 0/0), mount `shared:272` (was private),
4/4 nodes, 14/14 PVCs Bound, 57 Running / 0 CreateContainerError / 0 Pending,
compaction 2 ok 0 fails, 7/9 probes (2 prometheus 502 = monitoring-pause).
istio-ingressgateway now has a real EXTERNAL-IP on all 4 node IPs.

**GOTCHA — `/bin/k3d-entrypoint.sh` is NOT in `rancher/k3s` stock image**; k3d
writes it in at creation. First recreate died exit 127. Fix: `docker cp` the four
`k3d-entrypoint-*.sh` from a live agent into the Created container, then start.
This is almost certainly the original defect — the hand-rebuild used
`Entrypoint=/bin/k3s`, skipping `k3d-entrypoint-mounts.sh` (= `mount --make-rshared /`),
which caused Finding 3. Also: never `>/dev/null 2>&1` a destructive docker run —
the failure was silent and the cluster sat serverless during diagnosis.

**M2 backup DELETED** per owner direction, after acceptance was green. 13 GiB
reclaimed. Rollback value had inverted — restoring it would reintroduce the
8.3 GiB stalled datastore. **No copy of pre-rebuild hub state exists anywhere now.**

REMAINING: Finding 6 only (ArgoCD registration named `ubuntu-k3s` for the local
hub; 12 Applications + 16 appset refs — needs coordinated git change + appset
reapply, not a live edit).

### Load was swap thrash, not CPU (2026-09-11) — corrects standing notes

Hub load 16-17 on a 10-core M4 Air was NOT CPU saturation. macOS load counts
I/O-blocked processes; the box was thrashing a 93.5%-full swap file. Freeing
~3.7 GB of browser memory (stale 69-day Safari holding 2.2 GB in one
`WebKit.WebContent`, then Playwright `Chrome for Testing`) dropped load
**16.79/15.35/15.03 -> 3.72/4.11/7.98** and shrank swap 19,456M -> 12,288M,
memory free 36% -> 68%.

**Check `sysctl vm.swapusage` + `vm_stat` BEFORE reaching for
`make monitoring-pause`** — if swap is near full, reclaiming host memory is the
faster and far larger lever. `reference_one_second_probes_cpu_starvation_kill_loop`
should be read as a memory pattern presenting as CPU load. Mac Mini M5 upgrade is
a MEMORY argument, not core count.

Likely also the real mechanism behind today's Kine compaction stall: swap-induced
I/O latency pushing the compaction transaction past its window, consistent with
`Compact failed: ... transaction has already been committed or rolled back`.

Safe to kill the ACG browser: profile `~/.local/share/k3d-manager/pw-profile` is
persistent (login survives) and `scripts/lib/acg/cdp.sh` auto-reclaims/relaunches
`:9222`. This SUPERSEDES `reference_acg_login_reuses_cdp_session`'s manual-login
warning. Unloaded `com.k3d-manager.acg-watch` (fired every 3.5h to extend a
non-existent sandbox and would relaunch Chrome); plist retained, re-bootstrap for
long sandbox sessions.

Observability resumed at **Layer 1** (Grafana + Prometheus): measured 313m CPU,
~1.5 GiB. All 9 public probes green. Trivy/Loki/alertmanager stay at 0.
Details: `docs/issues/2026-09-11-hub-load-was-swap-thrash-not-cpu.md`.

### Monitoring fully resumed; Finding 6 closed as misdiagnosed (2026-09-11)

`make monitoring-resume` completed: auto-sync restored on kube-prometheus-stack,
hub-loki and trivy-operator; monitoring and trivy-system workloads scaled back up.
Layer 1 (Grafana + Prometheus) had already been verified green before the full
resume, and host memory headroom from the browser reclaim held.

**Finding 6 was wrong and is now closed as misdiagnosed.** It claimed the Argo CD
app-cluster registration `ubuntu-k3s` was dead AWS naming that should be renamed.
`ubuntu-k3s` is in fact the project's documented default `APP_CLUSTER_NAME`
(`argocd.sh:1200`, `istio_ambient.sh:23`) for whatever cluster fills the
app-cluster role — the hub fills it today, and the registration correctly reads
`server=https://kubernetes.default.svc`. A rename would have broken 28+
references (`shopping_cart.sh`, 12 Applications, 16 AppSet refs) to fix nothing.
**No spec written and nothing handed to Codex** — the scoping pass killed the task.

The real defect was a name collision: a stale *kube context* of the same name
still pointed at the dead EC2 endpoint `https://18.236.123.91:6443`, and was what
the Grafana port-forward dialed during this incident. Deleted (context + cluster +
user; kubeconfig backed up first). Verified after: contexts are now
`k3d-k3d-cluster` (current) + `ubuntu-hostinger`, hub answers `get nodes` 4/4
Ready, registration secret untouched.

**New Finding 10 (not fixed, filed only):** `shopping_cart.sh:59-60`
unconditionally runs `kubectl config delete-cluster default` / `delete-user
default`, and the hub context `k3d-k3d-cluster` maps to exactly those entries —
so the next `shopping_cart` run orphans the hub context. Pre-existing (confirmed
in the pre-deletion kubeconfig backup), recovery is `k3d kubeconfig merge
k3d-cluster`. Pick it up on the next `shopping_cart` change.

Details: `docs/issues/2026-09-11-hub-post-rebuild-verification-gaps.md`
(Findings 6 and 10).

### Finding 10 spec written, assigned to Codex (2026-09-11)

`docs/bugs/2026-09-11-shopping-cart-deletes-default-kubeconfig-entries.md`.
`add_ubuntu_k3s_cluster` unconditionally deletes the `default` cluster and user;
the hub context `k3d-k3d-cluster` maps to exactly those, so the next run orphans
it silently (both deletes are `&>/dev/null || true`). Fix replaces the two lines
with `_shopping_cart_prune_orphan_default_entries`, which deletes a `default`
entry only when no remaining context references it — preserving the original
cleanup (an entry left by a prior merge is unreferenced once the `ubuntu-k3s`
context is removed, so it still gets pruned).

Helper prototyped against three kubeconfig fixtures before filing: hub-style
(both kept), orphan (both deleted), and an empty config with no `contexts:` key
(no delete attempted, exit 0 under `set -euo pipefail`).

**Status: DONE — SHA `0cfbb15e` on `origin/k3d-manager-v1.33.0`.** Bug spec — exempt from the 5-plan-doc
cap, so the v1.33.0 plan-doc budget is untouched at 4/5.


### Finding 10 fixed; codex exec cannot commit (2026-09-11)

`0cfbb15e` — `_shopping_cart_prune_orphan_default_entries` replaces the two
unconditional deletes; 3 new BATS tests. Verified independently: shellcheck
`-S error` rc=0, `bats scripts/tests/plugins/shopping_cart.bats` 20/20 ok,
diff touches only `scripts/plugins/shopping_cart.sh` and
`scripts/tests/plugins/shopping_cart.bats`.

**`codex exec --sandbox workspace-write` cannot commit.** It implemented and ran
the gates correctly, then blocked on
`fatal: Unable to create '.git/index.lock': Operation not permitted` — the
sandbox denies writes to `.git` even with `network_access=true` (that override
only lifts the network block, not the `.git` write block). Codex reported the
failure honestly rather than claiming success. **Claude must commit and push
Codex's working-tree changes itself after verifying them**; do not expect a SHA
back from a `codex exec` dispatch.

**The spec's grep guard was wrong and Codex was right to deviate.** The spec
specified `^\s*kubectl config delete-(cluster|user) default`; Codex used a
literal two-space anchor. `^\s*`/`^[[:space:]]*` also matches the new helper's
own legitimate 4-space-indented delete calls, so the guard fires on the fix
itself — confirmed by running it (test 7 failed). The two-space anchor pins the
`add_ubuntu_k3s_cluster` body indent level and excludes the helper. Lesson: an
anchored-indent guard must be run against the post-fix file, not just reasoned
about when writing the spec.

### make status triage: hub Vault k8s auth broken, 24/25 hub ESOs down (2026-09-11)

`make status CLUSTER_PROVIDER=k3s-hostinger` reported 2 errors + 2 warnings.
Triage: `docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md`.

**Biggest problem was not in the output.** Hub Vault `auth/kubernetes/login`
returns 403; `ClusterSecretStore vault-backend` is `Ready=False`
(InvalidProviderConfig) and **24 of 25 hub ExternalSecrets are failing**. Ruled
out by direct check: Vault sealed (no — unsealed, running), CA rotation (no —
Vault-stored and live CA fingerprints identical), auth-delegator RBAC (present),
roles deleted (all four present). Cause is the stale `token_reviewer_jwt` —
already documented at `scripts/lib/test.sh:710-726` ("projected SA tokens rotate
every ~24h"); `vault-0` restarted 3x. Repair command is in the issue doc.
**BLOCKED: the auto-mode classifier denied the `vault write` (Secret-Store
Writes); the user must run it.**

**`make status` has a hub-ESO blind spot.** It printed `ESO ExternalSecrets:
20/20 synced ✓` — true for the *app* cluster, which really is 20/20 — while the
hub was 24/25 broken. Hub ESO is never sampled, yet hub-hosted credentials
(Grafana/Keycloak/ArgoCD) are what the smoke logins use. Needs a spec.

Downstream/other: Grafana 401 = stale ESO-frozen Secret **and** a persistent
`grafana.db` whose admin password diverged (env only applies at first DB init) —
verified the Secret's current password also 401s. Keycloak "no credentials" is
correct, not a bug — `identity/k3dm-smoke-user` did not survive the hub rebuild;
reseed with `keycloak_seed_smoke_user`. Frontend login is a pure cascade of that.
Product images = catalog genuinely empty (`HTTP 200`, `{"items":[],"total":0}`)
on an app cluster whose ESO is healthy — a data seed gap, not a credential one.

**Fixed (`5f356e90`):** both smoke-triage maps in `bin/k3dm-webhook` selected
product-catalog pods by `app=product-catalog`; the pod only carries
`app.kubernetes.io/name=product-catalog`, so failure triage printed no pod state
precisely when it was needed. `Frontend`'s `app=frontend` was checked and is
correct — that pod carries both label styles.

**Checked before "fixing":** the webhook's `keycloak-admin-secret`/`password`
fallback looked wrong but is the documented default (`keycloak.sh:37-38`) — the
Secret is just absent. Verifying that avoided a wrong patch.

### Hub Vault auth repaired; ESO 1/25 -> 24/25 (2026-09-11)

User ran the `vault write auth/kubernetes/config` reviewer-JWT refresh. Both
stores now `Ready=True`, hub ExternalSecrets 24/25.

**Post-repair status lags ~60s+.** Immediately after the write both stores still
read `Ready=False/InvalidProviderConfig` and every ES stayed failed — the
controller had not revalidated. `force-sync` annotations flipped the stores, then
the ExternalSecrets individually (refreshInterval 1h, so they would have trailed
by up to an hour). Do not judge this repair on a status read taken right after it.

**Grafana 401 is NOT the ESO problem** — proven, not inferred. With the resynced
Secret, Grafana answers `{"messageId":"password-auth.failed"}`. Persistent
`grafana.db` predates the Secret and `GF_SECURITY_ADMIN_PASSWORD` only applies at
first DB init. Needs `grafana cli admin reset-admin-password` (blocked: exec).

**Cloudflare 1010 gotcha (cost real triage time).** A UA-less probe of
`grafana.3ai-talk.org/login` returns HTTP 403 + `error code: 1010` — a Cloudflare
bot block, not an app response. Same request with `User-Agent: k3dm-smoketest/1`
returns the real 401. Always send a UA when probing `*.3ai-talk.org` by hand;
read `1010` as "edge blocked me", never as an app verdict.

**`keycloak_seed_smoke_user` needs `CLUSTER_PROVIDER=k3s-hostinger`** — otherwise
`_keycloak_smoke_base_url` (keycloak.sh:376-382) dials
`http://keycloak.shopping-cart.local` and fails with curl exit 7.

**New: `platform-ops/app-cluster-kubeconfig`** is the last failed hub ES, and it
is not auth — `secret/platform-ops` does not exist in Vault and no seeder for it
exists in the repo. Consumer mounts it `optional: true`, so it degrades
gracefully. Decide: seed or drop.
