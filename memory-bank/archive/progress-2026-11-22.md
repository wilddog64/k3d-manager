# Progress — v1.45.0 (older entries: `memory-bank/archive/progress-2026-11-21.md`, then `progress-2026-11-20.md`; open work lives in `docs/bugs/` Waiting-on lines and the dispatch ledger)

## v1.45.0 status (compressed 2026-11-21; detail in the archive)

- **LIVE-VERIFIED:** remote-promote Part 1 (E9); 2e CVE-pin branch writer (cutover live, E9 PASS); web-console part A
  (E11-E14 on m5-air); priv_open fix (E4 on m4-air); plan-quotas-beside-fable (E2); codex-row float-up (E2, `83344176`);
  dispatch-stall A and D; m5 PATH bug (zshdotfiles#4/#5).
- **LANDED / VERIFIED, live owed:** travel bundle `ddd9329e` (E3) and rev 2 `39a24a59` (E5, needs hub-deploy);
  test-all metrics `64a8de5c` (E3); dispatch-stall C `e05a08ed` (E8) and B (E9/E10); remote-promote 2a VERIFIED, 2d (E11);
  hub-deploy self-update `3b541f3b`; remote-promote 2c `c17eae59` (VERIFIED offline, hub-deploy owed); password-bundle
  Keychain P3 `3971fa3f` (m4-air retry owed); multi-project M2 bug metrics; Astra metrics; lib-foundation v0.5.7 subtree.
- **Open dispatches:** web-console C r2 (168-mutant rerun: 158 red, G8 hang, 5 survivors; guarded B27 reached real sudo prompt again 2026-11-22, killed, no harm; Luna resume 8 running: suite-local sudo/launchctl stubs + B27/B34/B39/G9b/D40/G8 tests); agy-repo-mode P3 LANDED `1e237612` (244/244; mutants all red after resume 2 added WAL/size/cache-allowlist tests); live E6-E8 owed after hub-deploy.
- **Not started:** 2b promote wiring, web-console B (both unblocked by 2c), red-team gate (intents approved).
- **2026-11-22:** C r2 LANDED `1026dbe2`/`c79c8ec0` (P2 instruction-check LIVE-VERIFIED by it); app-cve-scan PAT fixed (classic, exp 2027-02-20); captured order
  workflow_dispatch P2, auth hint P3, test 187 P3; make-up-app-none carried out to grooming (`93fe6b62`). 2b dispatched to Luna (`f12bcc16` approval). Hermes correlator and reauth P3s dispatched to Luna (3 of 3 open).
- **Rechecked 2026-11-21:** offline test-all P2, C1-C4 none reproduce (`af2cc5d9`), to grooming.
- **Captured P3:** hub_deploy.bats catch-up test index.lock race (`0c999bbe`).
- **v1.46.0:** plan 6 travel-bundle iPad SSH spec v1.1, intent approved; plan 7 Tailscale break-glass (moved from v1.48.0 2026-11-22, scope revision owed). Both cap exceptions.

## Log

- 2026-11-22: C r2 resume 10 verified (test 238 red/green). Full land set: machine_setup 187 pre-existing sandbox hang (`ps` denied in `tty_limited`); excluding it, bats 238/238, pytest 2 red (libexec-wide scans hit promote-daemon) → resume 11 dispatched. Token: hub app-cve-scan `reason=auth` since 11-12 (classic regen revoked Keychain copy); operator's new fine-grained PAT 403s at GHCR manifest → classic `repo`+`read:packages` PAT pending.
- 2026-11-22: P2 instruction-check fix LANDED `ffc6f3ed` (land suite 92 s green); E2 owed. C r2 land (scope override only) failed: hub_deploy.bats test 238 (launchd template list) lacks `web-console-totp`. The test predates dispatch (`643747e5`); Luna's runs and Claude's verify both skipped hub_deploy.bats and machine_setup.bats (verification gap: run the land's full --test set before landing). Luna resume 10 (correction) running. zshdotfiles #8 (restore launchd ssh-agent reuse lost in `40eaa67`, pre-commit guard), #9, #10 (sync skips files >95 MB after a 925 MB codex archive blocked pushes) merged; ~/.codex unpushed `eb0f829` undone, archives gitignored.
- 2026-11-22: P2 land instruction-check fix: Luna exited 0; Claude verify PASS under sandbox-exec (codex_dispatch.bats 6/6, scope 13/13, shellcheck clean; pre-fix red on tests 2,3,5; guard mutants N1/N3/N4/untracked-N2 red). Committed in worktree `fcf96e0d`. Land blocked: GitHub SSH publickey refused (no SSH agent socket on m4; keychain?), waiting on operator. P3 captured: unstaged tracked instruction edit untested. tech-articles draft mutants-across-vendors on branch `docs/mutants-across-vendors` (`14381bf`).
- 2026-11-22: ideas row: automated mutation testing tool (mutmut for Python, in-repo bash mutator; sandbox-exec + watcher + restore check built in; mutation score to Prometheus beside CRAP).
- 2026-11-22: P2 dispatcher fix (land instruction check after rebase) spec + Acceptance written, intents approved (`755895c9`), dispatched to gpt-6-luna as `dispatch-land-instruction-check-rebase` (WIP 2/3). C r2 lands after it, no override (its E2).
- 2026-11-22: ideas row: CRAP score per function with Grafana dashboard (Python slice first, bash via kcov after proof).
- 2026-11-22: C r2 land attempts: scope exception recorded in spec (`2d9db6ab`, operator "go ahead"); rebase conflict in not-installed.list (2c promote-authority lines vs totp lines) resolved keeping both, task now `d85926d4`; land then refused for instruction files from the release branch's own `1ab308ef` (dispatcher diffs from dispatch base, not merge-base). P2 captured. Land waiting on operator decision for --allow-instruction-files.
- 2026-11-22: C r2 Claude verification PASS under sandbox-exec + watcher: totp bats 34/34, sshd bats 58/58, pytest 142; mutants G8 (22 s, no stuck proc), G9b, B27, B34, B39 RED; D40 equivalent. Worktree committed `a2de8299`. Land refused: scripts/tests/bin/web_console_sshd.bats not in spec file list (test-only: sudo/launchctl guard stubs, scratch ZDOTDIR, git stub split). `--allow-out-of-scope` rerun blocked by auto-mode classifier; waiting on operator decision.
- 2026-11-22: C r2 resume 9 exited 0 (no root sudo seen). Luna: pytest 142, totp bats 34, sshd bats 58; G8 mutant red in 20 s under sandbox-exec, no new stuck process. D40: no test added; Claude confirmed equivalent mutant (both handlers load state only after a full line, then close; one load per connection). Claude verification running under sandbox-exec + watcher.
- 2026-11-22: Tailscale break-glass spec moved v1.48.0 plan 5 -> v1.46.0 plan 7 (cap exception, operator: "put tailscale in v1.46.0 side by side with iPad SSH plan"); spec only, scope revision owed (m5 hub, iPad client, Screen Sharing). v1.48.0 now 4/5.
- 2026-11-22: ideas rows: iPad-only travel GUI path (Screen Sharing over Tailscale, pulls forward v1.48.0 break-glass) and agent host disk (reclaim m4 before any m2 move). Operator: all Macs clamshelled, always on; goal is travel with iPad only.
- 2026-11-22: password-bundle timeout LANDED `e3f2bcaf` (22/22; pre-fix RED x7; N2/N3/pgrp/no-KILL mutants RED); E6 live after hub-deploy. C r2 mutant rerun: B34/B39/G9b RED; D40 GREEN (test uses two connections, spec asked one connection twice); G8 RED then pytest stuck in U state; B27 reached real root sudo a 3rd time (watcher killed in ~2 s, no ticket, no root effect): tests exec real main, which resets PATH by design, so PATH stubs cannot contain it; harness must use sandbox-exec deny /usr/bin/sudo,/bin/launchctl (proved). Resume 9 dispatched (D40 one-connection replay test; G8 non-blocking pty teardown, file must finish red in 120 s).
- 2026-11-22: Luna resume 8 (C r2) exited 0, uncommitted in worktree. Claude verify started: suites now stub sudo/launchctl in setup with PATH guard asserts and a teardown hit check; fixture mode routes `_wc_priv` to shims with `PATH=''`. Bats+pytest running under a root-sudo watcher; mutant reruns next.
- 2026-11-22: PasswordBundleStale root cause: hub launchd publish run hung since 02:01 (PID alive, later runs skipped); P2 filed `10333ca5` (plugin-only whole-run timeout; Makefile per-call timeouts after C r2). Live hang point: `git -C <iCloud dir> rev-parse` blocked in getcwd/open under launchd (kickstarted run hung again; Terminal instant). Spec rev 2 (Fable folded in, `33157666`), intents approved, dispatched to gpt-6-luna as `password-bundle-publish-timeout`. Cause confirmed: macOS "bash wants to access iCloud Drive" prompt waiting on m5's locked screen; operator chose Allow 04:56, run finished (last-publish 04:56:26). Follow-up for triage: re-grant after brew bash upgrades vs move delivery out of iCloud.
- 2026-11-22: P3 captured: test-all failures cannot be traced to the Mac that ran them (`2aa488fc`); both failing cases and whole files pass on m4-air, run came from m5 or m2 (no host label). PasswordBundleStale alert on hub: investigation waiting on operator's m5 pane output (SSH key refused, no tmux server on m4).
- 2026-11-22: C r2 mutant rerun done; B27 bypassed outer guard via bats PATH resets (real sudo prompt, no ticket, killed); Luna resume 8 dispatched. Ideas row: stall watch for Claude background jobs (`270dfae4`).

- 2026-11-21: autoCompactWindow 400000 trial for the 1M window (`1ab308ef`, operator approved); void if Observed compaction point stays near 167K. CLAUDE.md/rules.md 200K wording corrected.

- 2026-11-21: agy repo/mode P3 landed `1e237612` (Flash 3 runs; Claude mutation check 16/16 red; audit marker for 17 unknown->print assert rewrites).

- 2026-11-21: five bug statuses corrected + Fix commit headers (`b8f1b19b`); Fix-commit recurrence on 2026-10-25 doc (`a985b682`, operator decision); Linux CI red fixed: password-bundle M6/N6/N7 assumed a Mac host (`4b8561af`, P3 doc, CI pending).

- 2026-11-21: P3 agy transcript sessions always unknown repo/mode — filed, dispatched to Flash (`gemini-3.8-flash-medium`).

- 2026-11-21: progress compressed; full log archived to `memory-bank/archive/progress-2026-11-21.md`.
