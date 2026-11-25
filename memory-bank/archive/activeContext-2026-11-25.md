# activeContext archive — 2026-11-25 (sections moved verbatim by /handoff)

## MORNING REMINDER (operator asked 2026-11-24 evening) — deliver at the first chat on 2026-11-25

**Remind the operator: dirused overnight probe on the jump box** (normal, NOT elevated window). Download
`tools/m10b3-probes.ps1` from dirused branch `m10b-scheduled-purge` (raw URL) into `%USERPROFILE%`; then
`cd /d %USERPROFILE%` and `powershell -ExecutionPolicy Bypass -File m10b3-probes.ps1 setup`, then `... run12`; disconnect;
next morning `... collect`, then `... cleanup`; send Claude the output. Confirms P10 (task descriptor for a standard user)
and gates live checks E-B3L1/E-B3L2. Note: operator said "tomorrow morning", so setup/run12 may happen in the morning and
collect the following morning — ask which.

## (old) MORNING REMINDER 2026-11-23 — DELIVERED 2026-11-24; HoverFocus/istioctl m2 checks still pending

**Remind the operator: HoverFocus live checks on m2 this morning** (L1 gates the v0.0.2 merge). Steps:
- **L1-EL second half (config reload):** menu bar "Open Config" (edits `~/.config/hoverfocus/config.json`,
  docs/config.md:3), break it with invalid JSON → "Reload Config" → status reads `Error: config <reason>` and
  hover-focus stops; fix the file → Reload Config → `Running`, hover-focus works again.
- **F1-EL second half:** run `make install` twice in a row on m2 from an iTerm window (no error 37, menu bar icon
  back); then from m4 over SSH run `make install` on m2 and check it prints the `sudo launchctl asuser` commands
  instead of failing.
- **Decisions also waiting at m2:** Electron no-focus (P2 proposed) and no visual focus indicator (P2 proposed) —
  priority and v0.0.2 vs later; signing identity vs keep printing the `tccutil reset` step.
- **Also on m2 (k3d-manager istioctl-b, landed `7d8a40e4`, needs hub/m2 checkout at v1.45.1 head):** E6 — with brew
  istioctl 1.32 still linked, `make dr-drill` stops with one line naming 1.32 before any Istio precheck; E7 — after
  `brew unlink istioctl`, the drill installs pinned 1.31.4 and passes precheck.
- **Tell the operator (no action unless they object):** R2 stage check narrowed overnight — the root bootstrap now
  refuses ANY symlink in a verified stage (was "a symlink pointing out of the stage"; the round-2 verifier escaped the
  lexical check with a two-link pair, Claude reproduced). Repo commits 0 symlinks, so no behaviour loss. Parent bug doc
  F1 + child spec `## Clarification`, commit `cecc52e1`.
- **R2 child A — DECIDED (operator, 2026-11-24):** "go ahead to do correction 3" + "go for it" (Fable design review
  as the gate before landing). Correction 3 resumed 2026-11-24 ~04:01 (resume 4, Luna): D1 wrapper calls root forms
  (`<self> <c> [--ref b]`, `<self> --install-self <c>`), main `stage)` case deleted; D2 `_vs_git` never reads caller
  GIT_CONFIG_*; E1-E5 end-to-end layer executing a constants-patched copy (diff-guarded) with stand-in sudo, exit-code
  table, 163 round-3 survivors re-run (run dir `round3-survivors.txt`). Prompt: scratchpad r2a-correction-3.md.
  Fable reviewed the spec (rev 1 and rev 2) only; never rev 3, the Clarification, or the code. After corr 3 exits:
  Claude checks, then Fable design+code review of the bootstrap, then verifier, then land.
- Record results in `docs/plans/hoverfocus-v0.0.2-l1-app-lifecycle.md` / `-f1-install.md` live-check logs.

**State at end of 2026-11-23 evening session:** WIP 3/3 — r2-a correction 1 (test gaps), totp-a1-fix (Luna, spec
rev 2), istioctl-b (Luna, after v0.5.9 subtree `7dc95697`). On each exit: independent verifier → Claude reproduces top
gap → commit in worktree → land → record verify → push. Landed today: totp-c `c507cfd7`, r2-c `5d9e6410`, lf v0.5.9
(PR #93 `083c249`, tag + release). Next queued: istioctl-c (after B), V4 defect 1 (m2 drill probe), R2-B (after r2-a).
Groom folded into Sunday 2026-11-29. Leftover: 6 root-owned `k3s-*/logs/*-browser-*.log` (~880M, need sudo); two
state-U pytest procs clear on reboot.

- **2026-11-24 dirused M10b1–4:** M10b1 rev 4 and M10b2a rev 2 (TaskXml, split from M10b2) reviewed blind by Fable + Argon (null-control held-skip blocker, UTF-16 declaration case, readback defaults, DTD) and fixed (`e303be3e`). Integration branch `m10b-scheduled-purge` from 966b32b pushed. Dispatched: `dirused-m10b1-engine` (Luna), `dirused-m10b2a-taskxml` (Flash, agy). M10b2 rev 3 written (D14 trust check), reviews after M10b1/M10b2a land. Next: M10b3 jump-box probe script (P2, P3, P8, P10, P12).

- **2026-11-24 dirused:** M10b2a LANDED `cf07ace` on `m10b-scheduled-purge` (verifier round 1 FAIL: DTD mutant green + `$` anchors → correction 1 → PASS); windows CI run 45455761460 pending. M10b1: correction 1 added scheduled tests; mutants d, e red; mutant a HANGS a test → correction 2 (fast-fail fakes) running. Stale v1.45.1 headers fixed `ad8b862f`.

- **2026-11-24 dirused:** M10b1 LANDED `e19783f` (Sonnet verifier PASS, 10 mutants red); M10b2a windows CI green (attempt 2; P3 flake captured `docs/bugs/2026-11-24-dirused-root-shared-open-cleanup-race.md`). Integration branch tip e19783f; CI 45456774994 running. Next: M10b2 rev 3 Fable + Argon reviews → dispatch Luna.

- **2026-11-24 dirused M10b2:** rev 3 NEEDS REWORK from Fable + Argon (D14 refused every stock install: Append on C:\ + inherit-only; no seam signatures; sub-second created). Rev 4 `d7f8a4d4`: shared contract + children b2b (parser, now), b2c (seams+trust, needs P-ACL icacls from jump box), b2d (confirm flow), b2e (list/cancel). Round-2 Fable + Argon reviews running. Operator ask pending: P-ACL icacls (C:\, Program Files, C:\Users, %LOCALAPPDATA%, its parent).

- **2026-11-24 dirused M10b2 round 2:** Fable + Argon round-2 applied `0a44b05a` (contract rev 5, children rev 2: run offset to Pacific, findings shallowest-first, always Secure plans, shared ScheduleFakes.cs, broad-SID list, Get-Acl P-ACL). b2b dispatched to Luna (`dirused-m10b2b-parser`). b2c blocked on operator P-ACL Get-Acl output (owner+SDDL for C:\, Program Files, C:\Users, %USERPROFILE%, AppData, Local). b2d after b2b+b2c; b2e after b2c. M10b3 must be revised to the contract before dispatch.

- **2026-11-24 dirused:** b2b LANDED `6542862` (verifier PASS; correction 1 test-only; Windows mutant proof 45461565040; CI 45462979677 pending). Next: b2c on operator Get-Acl output; then b2d ‖ b2e.

- **2026-11-24 dirused:** P-ACL recorded from jump box (icacls + dir /q; C:\ has stock Users (CI)(AD) — ancestor rule needed; profile has 2nd domain admin + unresolved -8249 SID, placeholders PROD\admin2 / S-1-5-21-9-9-9-8249 in fixtures). b2c dispatched to Luna (`dirused-m10b2c-trust`, `374fee87`). Next: verify b2c, then b2d ‖ b2e.

- **2026-11-24 dirused b2c:** round 1 verifier FAIL — worker could not read the parent contract (k3d-manager file, absent from dirused worktree), guessed ScheduleSeams + empty fixtures. Correction 1 sent with contract sections inlined. **b2d/b2e dispatch must inline the parent contract** (append sections 38-182 to the spec prompt).

- **2026-11-24 dirused:** b2c LANDED `e7970ff` (verifier round 2 PASS; CI 45469466819 pending). b2d (`dirused-m10b2d-confirm`) and b2e (`dirused-m10b2e-list`) dispatched to Luna in parallel, specs carry the contract inline (`cb01683d`). Then M10b3 spec revision, M10b4 docs, one PR to main.

- **2026-11-24 dirused:** b2e LANDED `e825ed8` (round 1 FAIL report.txt header bug → correction 1; CI 45472288659 pending). b2d round 1 FAIL (extras before Held; id from created not run) → correction 1 running with verifier tests as reference.

- **2026-11-24 dirused:** b2d LANDED `ab98677` — **M10b2 complete** (b2a cf07ace, b2b 6542862, b2c e7970ff, b2e e825ed8, b2d ab98677; CI 45473345605 pending). Lesson: Luna's first pass shipped 2-3 test methods per child every time; verifier tests ported as correction each time. Next: revise M10b3 spec to the contract (inline it), operator probe run on jump box, M10b4 docs, one PR to dirused main.
- **2026-11-24 dirused M10b3:** spec rev 3 written `6dc610cd` (to the M10b2 shared contract rev 5 and landed code ab98677; contract inlined; PlanRunner.RunPlan, SchtasksTaskScheduler without rootFolder, ScheduleWindows real classes, AclRights.FromMask, IPlanStore.MoveNew default member, D14 trust re-check at /runplan, Program wiring replacing the interim refusal). Fable + Argon blind reviews running. Dispatch gates: P6 second half, P9 (Claude CI probe), P10 readback; probe script run by operator.
- **2026-11-24 dirused M10b3 reviews:** Fable + Argon both READY WITH FIXES, both: split. Rev 4 `defea2c7` split into b3a (PlanRunner engine, portable), b3b (SchtasksTaskScheduler + AclRights, gate P10), b3c (ScheduleWindows real classes, gates P9 + P6 default-owner check), b3d (Program wiring, ProgramTestSeams); adjudication table in M10b3. P6 second half PASS (jump box 14:07 PT, `b7cb65a9`). b3a dispatched to Luna (`dirused-m10b3a-engine`).
- **2026-11-24 dirused:** b3a LANDED `f4c117e` (verifier PASS 17/17 mutants; correction 1 = verifier tests; land used --allow-out-of-scope for the correction-added test file, spec Files updated); windows CI 45502759684 green. Probe script moved to dirused `tools/m10b3-probes.ps1` (`3fab789`). Owner check: the Administrators-owned files came from an elevated window (High Mandatory Level), not a spec change; normal-window re-check pending. Cleanup-race flake recurred (run 45503227379, rerun green).
- **2026-11-24 dirused P9 PASS** (Actions run 45510934313, scratch branch deleted): create/query-xml/delete OK, second create without /f exit 1, /run exit 1 (AllowStartOnDemand false), descriptor reads back verbatim; readback omits default settings and is single-byte text, TaskXml.Parse accepts it (Claude local). Default-owner check PASS from a normal window (Administrators owner came from an elevated window). b3b dispatched to Luna (`dirused-m10b3b-schtasks`); b3c waits on b3a+b3b only.
- **2026-11-24 dirused:** b3b LANDED `d539912` (verifier PASS, 10/10 mutants, correction 1 = verifier tests; --allow-out-of-scope for the correction file). b3c dispatched to Luna (`dirused-m10b3c-windows`): gates met (b3a, b3b, P6, P9).
- **2026-11-24 (night):** lib-foundation v0.5.10 tagged (PR #94 merged 01a5723), subtree pulled a9862332; istioctl hang E6 PASS (instant refusal) + E7 PASS (pinned 1.31.4 installed, precheck clean) on m2 — hang bug E4 done. TOTP enrol QR/pause LANDED 6eccd121 (verify pass; spec rev 3 vectors from python-qrcode; segno pads non-canonically); E4 live = operator promote + reinstall totp + enrol. V4 probe ~/k3dm-v4-probe.sh on m2 (first run died: hub_data.sh sets -euo on source; fixed with set +e); kept dr-drill cluster shows the diagnosed state.
- **2026-11-25:** hub-deploy of 9f274656 refused (lint red: ruff F841 unused `prefix` in Luna's TOTP pause test; local verify ran pytest, not lint-python). Fixed a1486486; promote that SHA once CI green.
- **2026-11-25:** HoverFocus v0.0.3 probe kit on m2 ~/hf-probe/ (hf-p2.sh: app matrix + Electron AX + key-window variants B/BM/BF/M, log ~/hf-p2-*.txt; hf-p3-signing.sh: self-signed identity + 3 builds, grant survival, log ~/hf-p3-*.txt). m2 install is ad-hoc (DR = cdhash). Waiting on operator at m2.
- **2026-11-25:** HoverFocus P3 run 1 INCONCLUSIVE: TCC row stayed auth 0 (denied) since the 04:23 tccutil reset, so the operator toggle never registered (stale Settings list); build 2/3 "fail" proves nothing. Identity "HoverFocus Local Signing" created (DR certificate leaf, stable across 3 builds). Script reworked (remove/re-add in fresh Settings, TCC row read each step, stops if grant absent); rerun pending. P2 not yet run.
- **2026-11-25:** HoverFocus P3 rerun: grant recorded (TCC auth 2, csreq 80B, 04:31:33), unchanged across builds 2 and 3 (distinct cdhashes, same certificate-leaf DR). Operator: build1 pass, build2 pass, build3 "fail" — but build 3 pid 67085 passed Controller.start isTrusted guard and owns an enabled event tap (mask e0000fe), so trust held; asked operator for a hover recheck. Likely P3 PASS.
- **2026-11-25:** HoverFocus P3 PASS (operator hover recheck on build 3 OK); results recorded in docs/plans/hoverfocus-v0.0.3-plan.md "Probe results". m5-air: install-web-console-totp done (status: not enrolled, as expected pre-enrol); next enrol.
- **2026-11-25:** TOTP enrol bug LIVE-VERIFIED: m5-air promoted a1486486, enrolled via Google Authenticator QR scan (entry name = URI issuer/label), status enrolled. Camera app route fails (file browser) -> how-to follow-up. Next TOTP live checks: R1-R4 login, lockout+recovery, RevokedKeys refusal; chmod bug E2 also satisfied by the install.
- **2026-11-25:** v1.45.1 TOTP L1 LIVE PASS (cert+code login, sshd-check C1-C7/C10 PASS, revoked_keys root 0644, test cert not revoked) and L2 LIVE PASS (recovery login 10->9, log +113 B = recovery lines). Plans totp-b/totp-a2 LIVE-VERIFIED. New bug captured: gate rejects pasted recovery code / 0-1-8 lookalikes silently (P2 proposed, Waiting on operator decision). Operator pasted 2 recovery codes in chat -> set regenerated (void).
- **2026-11-25:** Gate recovery paste/lookalike bug: P2, triaged patch -> v1.45.1 (operator: "file P2, Fable review, dispatch to Flash"). Spec rev 1 written (bracketed-paste off + ESC-sequence drop, 0/1/8 -> O/I/B for recovery input, local-rejection hint; E1-E3 offline, E4 live). Fable review running.
- **2026-11-25 HANDOFF (session restart for Claude update):** (1) Dispatch gate-recovery-paste RUNNING (Flash gemini-3.8-flash-medium, agy, spec docs/bugs/2026-11-25-console-gate-recovery-code-paste-and-lookalikes-rejected-silently.md rev 2 after Fable; worktree ~/.local/share/k3d-manager/worktrees/v1.45.1/gate-recovery-paste): check `bin/k3dm-codex-dispatch status gate-recovery-paste`, independent verify from Acceptance (E1/E2 red on 9cca0789 then green, whole test_web_console_totp.py), land with --test the pytest file, then promote + E4 live (operator pastes a recovery code; count drops by 1). (2) Open dispatch dirused-m10b3c-windows exited 0, awaiting operator b3c mutant option (1/2/3, rec 3). (3) m2 operator pending: ~/k3dm-v4-probe.sh (V4 LDAP resync proof -> record in docs/plans/v1.45.1-dr-drill-v4-ldap-resync.md, then dispatch V4 defect 1 to Luna) and ~/hf-probe/hf-p2.sh (HoverFocus app matrix; P3 PASS done). (4) Docs todo: istioctl hang bug E4 PASS -> LIVE-VERIFIED + parent istioctl bug E6/E7; P3 captures: host-key warning, timeout absent on macOS in install_istioctl.bats, slow drill preflight clone, how-to: scan QR from inside authenticator not Camera. (5) Release PR v1.45.1 after V4. (6) MEMORY.md over 9 KB: compress at a break. Release groom Sun 2026-11-29.
- **2026-11-24 (late):** lib-foundation fix LANDED af33f98 (verify pass, 11/20 red pre-fix), PR #94 open, CI green, Argon review: no defects, 1 low (timeout not on bare macOS, P3 candidate) — awaiting operator merge, then tag v0.5.10 + subtree pull. Web console part A installed on m5-air (sshd running :42722, check exit 0; first-install 'Unable to load host key' warning is harmless, P3 candidate); part C TOTP installed, enrolment blocked: no QR, recovery codes cleared instantly → P2 spec docs/bugs/2026-11-24-console-totp-enrol-no-qr-and-recovery-codes-cleared-instantly.md rev 2 (Fable NEEDS FIXES applied; UNAVAILABLE path also pauses), dispatched to Luna as totp-enrol-qr-pause.
- **2026-11-24:** two ideas rows added to docs/ideas.md for Sunday groom: independent second plan (Argon writes its own plan for large designs), cap spec review at 2 rounds. b3c correction 1 (trust store refuses junctions, spec rev 2) running with Luna; b3b windows CI green (run 45512746865).
- **2026-11-24:** b3c windows CI run 45514086420 red (elevated runner: trust.txt owned by Administrators, Load rejects); spec rev 3 (Save sets trust.tmp owner to the user), correction 2 running with Luna. Ideas row added: hybrid prior-art search (tsvector + RRF), from a reader comment.
- **2026-11-24 v1.45.1 operator steps:** hub istiod 1.31.1→1.31.4 done by operator on m5-air (istioctl SHA matched pin; 5 sidecars 1.31.1 until restart). m4-air istioctl already 1.31.4. R1 ruleset `cve-pins-hub` id 28034766 created by Claude via gh api at operator request (deletion, non_fast_forward, update; bypass repo admin). Pending: GIT_WRITE_TOKEN fine-grained PAT + Keychain + argocd_sync_git_writer_secret, then R1 probes; hub promote after CI green.
- **2026-11-24 R1 operator steps DONE:** fine-grained git-writer PAT (k3d-manager only, Contents RW, expires 2027-02-23) in hub Keychain + Secret synced; Claude probes PASS (private repo 404, other-repo write 403, own-repo write 422 zero-SHA, ruleset PUT/hooks/dispatch 403). Remind operator: delete the old git-writer token; add 2027-02-23 expiry to token reminders. Next: hub promote REF=fd5812a0 (CI green run 45514528556), then web-console installs, live checks, m2 E6/E7 + V4 probe.
- **2026-11-24 hub promote DONE** (operator: deploy/hub a06ad92..fd5812a). install-web-console-totp refused: part A never installed anywhere (first install, not upgrade). Operator made throwaway test CA; install-web-console-sshd exit 8: trace (Claude via SSH) shows `/usr/bin/chmod` (does not exist on macOS; /bin/chmod) at bin/k3dm-web-console-sshd:471, from totp-b d6e1e7a6. P1 filed docs/bugs/2026-11-24-web-console-sshd-install-usr-bin-chmod-missing-on-macos.md; waiting on operator intent approval, then Luna. m5-air clean after rollback. Also ideas row: replace broad classic tokens (3a2c26be).
- **2026-11-24:** chmod P1 LANDED `ee2416eb` (verify pass, E1 red pre-fix); bug doc LANDED, Waiting on live check. Review records release-hoverfocus-pr2-v0.0.2-review and release-lf-pr93-v0.5.9-review abandoned (PRs merged). E6/E7 script running on m2 (~/k3dm-e6e7.sh, drill under `script` for TTY; DR_DRILL_KEEP=1 for V4 probe). Next: promote REF after CI green → operator retries install-web-console-sshd (CA_FILE=~/.ssh/k3dm-console-test-ca.pub) + totp; b3c mutants/land.
- **2026-11-24 E6 run on m2 HUNG** 1h47m on `istioctl version --short` (drill KUBECONFIG names missing cluster; --remote=false returns instantly; reproduced). P1 filed docs/bugs/2026-11-24-istioctl-version-probe-hangs-on-unreachable-kubeconfig.md (operator: file, Fable review, dispatch Luna). lib-foundation release/v0.5.10 created from main 083c249. Fable review running. CI green on 5086e886 (run 45533552756) → promote REF given to operator for web-console retry. b3c mutant push blocked by classifier (public repo, weakened security code); options 1/2/3 put to operator, rec 3.

## Handoff — 2026-11-23 08:55 PST — hoverfocus v0.0.1 shipped; v0.0.2 planned; v1.45.0 merged — START HERE

**Operator:** at work today, home ~15:30 PT (only then: m2 live tests, hub promote). Batch every ask for that time.

**1. HoverFocus (repo `~/src/gitrepo/personal/hoverfocus`)**
- 2026-11-24 status: L1 `e4a7d51` and F1 `42273f0` landed + verified on v0.0.2; then operator installs on m2 and runs L1-EL/F1-EL + P1 app matrix.
- v0.0.1 SHIPPED: PR #1 merged `d426f18` (14:09Z), enforce_admins back on, tag `v0.0.1` + GitHub release with limitations.
- v0.0.2 plan: `docs/plans/hoverfocus-v0.0.2-bug-batches.md` — L1 Luna (`AppDelegate.swift`: reload fails open + watch
  trust without menu click), F1 Flash (Makefile/install_test/README: error-37 race, SSH `asuser` hint, sed/XML escaping,
  print `tccutil reset`), P1 live probe on m2 with operator ~15:30 (same-app key window without raise: AX
  `kAXMainAttribute`/`kAXFocusedAttribute`; check raise + terminal cursor), L2 Luna (`Controller.swift`/CSkyLight after
  P1 + AX element cache eviction). NOTHING dispatched.
- DONE 08:10: L1+F1 specs rev 2 (Fable reviewed, all findings applied), v0.0.2 branch pushed. Operator at home: approve intents, GUI `launchctl managername` on m2 (F1 gate), go. L1-EL gates the v0.0.2 merge. Was: write L1 and F1 child specs (Acceptance, must_not red on v0.0.1, `## Files`, intent lines
  `pending`), branch `v0.0.2` from `main` d426f18 on hoverfocus origin, Fable spec review. Then ask operator: approve
  intents + dispatch go. Open question for operator: create a local signing identity (stable TCC grant) or keep
  printing the reset step.
- Inputs: 3 bug docs `docs/bugs/2026-11-23-hoverfocus-*.md` (all `carry → v0.0.2`, Waiting on: dispatch) +
  `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md` (3 confirmed, 2 speculative).
- Facts: grant is per-build (ad-hoc): after reinstall `tccutil reset Accessibility com.wilddog64.hoverfocus`, re-grant,
  `launchctl kickstart -k gui/$(id -u)/com.wilddog64.hoverfocus`. Over SSH bootstrap needs `sudo launchctl asuser`.
  iTerm "Focus follows mouse" handles panes and coexists with HoverFocus (operator-tested); not a bug.
- Rules: hoverfocus personal machines only; no AutoRaise/yabai code; Fable review before dispatch; sandbox-exec deny
  sudo/launchctl for any install_test run.

**2. v1.45.0 release — PR #164**
- Merged 0c27b830, tagged, enforce_admins restored; next branch k3d-manager-v1.45.1.

**3. DR drill on the m2**
- V4 root cause filed `docs/bugs/2026-11-23-dr-drill-v4-ldap-admin-bind-err-exits-drill.md` (P2 proposed, Waiting on:
  operator decision): restored LDAP rejects drill admin bind (rc=49), and `_err` at `hub_data.sh:1000/1003` exits the
  whole drill (`_err` = print + `exit 1`, lib-foundation `system.sh:2114`).
- Kept `dr-drill` k3d cluster still up on m2: `k3d cluster delete dr-drill` (operator OK) before the next run.
- Then fix, rerun, `make dr-drill-publish`. Keychain bug priority also waits on operator.
- m2 remote shell is zsh: use `ssh m2 bash -s < script`, not `$VAR` word splitting.

**4. Owed specs / decisions**
- v1.45.1 = security + DR release (operator 2026-11-23): R1-R4 red-team P2s + 3 DR-drill bugs. Flow: Claude specs → Fable blind review → operator intents → Luna (logic) / Flash (docs) dispatch.
  - R4 token-in-argv: spec rev 1 written in bug doc (kubeconfig 0600, E1-E6; Luna). Open q: refuse insecure TLS?
  - istioctl pin 1.31.4: spec rev 1 written (children A lib-foundation Luna → subtree pull → B k3d-manager Luna → C changelog Flash); 4 sha256 checked by Claude against release assets.
  - R3 TOTP: spec rev 1 written (children B RevokedKeys Luna → A lock/log/socket Luna → C collector+alerts Flash). Open: same-uid DoS limit, permanent vs 24h lock, cert validity probe.
  - R1 pins: spec rev 1 (services-git.yaml index/kindIs guard, applicationsSync create-update, clusters generator first; ArgoCD v3.5.5 proof). Open O1-O3.
  - DR empty age identity: spec rev 1 (preflight presence check). DR V4: spec rev 1 for defect 2 (_err→printf+return); defect 1 (which admin password wins) = operator decision, Claude recommends restore Secret from backup.
  - Specs committed 918a148d. Fable review DR/istioctl DONE: all NEEDS FIXES. V4 blocker (bind helper's _kubectl exits before the ||; fix: --no-exit at :1000 and :1014) and age-identity → rev 2 applied by Claude (uncommitted). istioctl rev 2 done (refusal → _err; N5; survey: hub 1.31.1 ok, m4 1.30.0 REFUSED after fix, m2 1.32.0 refused). DR/istioctl rev 2 committed 0945fff0. R1/R3/R4 Fable: R4 2 blockers (trap placement; missing current-context falls back to in-cluster hub API, proven in alpine/k8s:1.33.13), R3 2 blockers (socket chown; dropped, scope split: metrics/alerts → v1.46.0), R1 5 should-fix (mergo deep-merge proven at argo-cd v3.5.5; new R4 selector guard). All rev 2. Operator decisions 2026-11-23: all intents approved; R1 O1-O3 per recommendation; V4 defect 1 (a) restore Secret; istioctl keep override + delete local copy; R3 24h final lock, decay yes, NEW unlock via recovery codes (child A waits for spec rev 3 + review); R2 spec → Fable + Argon independent review.
  - 2026-11-23 reviews: R2 spec rev 1 (11df6067) Fable+Argon NEEDS FIXES; Claude reproduced CDPATH (bash -p 3.2 does NOT ignore it), SCRIPT_DIR env, DEVELOPER_DIR→xcrun hijack of /usr/bin/git, sudo timestamp_timeout=60 on m4-air (ticket reuse blocker). Rev 2 fork running: adopt bootstrap `run <commit> <tool>` mode (env -i allowlist in root-owned code) instead of in-installer guard. R3 rev 3 + totp-a committed 2adc7f60; Argon NEEDS FIXES (global 60 s recovery rate limit = attacker DoS, collides with 60 s prompt_timeout; recovery.json.tmp not cleaned at startup; gate buffer truncation; scrollback on abort; test stubs); Fable R3 review running.
  - 3 ideas rows filed 65aded2f (operator go): console TOTP failures carry cert serial (ExposeAuthInfo), Slack one-tap cert revoke via Hermes, short-lived hardware-backed console certs. All inbox; rank at next /release-groom. R3 rev 4 fork running (rate limit dropped, A1/A2 split).
  - R3 rev 4 committed a300dcba (A1 3 files, A2 4 files new spec; intents pending: A1 E1/E4/E6, A2 E8-E12+L2, A2 Approval exception). R2 rev 2 committed e350217d (bootstrap `run` mode, 12 files, children A/B/C Luna + D Flash; B waits totp-b, D waits totp-c; intent pending); Fable round-2 review of the new design running.
  - Operator approved R2 rev 2 + R3 A1/A2 intents and the A2 patch exception (02763433). R4, R1, V4 Luna dispatches all exited 0 (R4 5 files, R1 4+1 new bats, V4 2 files); 3 independent Acceptance verifiers running; land each after PASS. Verifiers: V4 PASS (committed bc9fbbfe on task branch; land blocked only by stray untracked run.7cS9d7/ in repo root, likely R4 verifier scratch — remove after it finishes, then land); R1 PASS with one vacuous test (in-cluster server stub) → Luna resume running. UPDATE: V4 landed da956fbd, R1 landed 5f7ef7be (vacuous test fixed + mutant-checked by Claude), both pushed. R4 verifier FAIL on test coverage only (E3-E7 missing; code OK) → Luna resume 2 running. Dispatched Luna: totp-b-revoked-keys, totp-a-lock-and-recovery (WIP 3/3). Fable R2 rev 2 round 2: NEEDS FIXES — B1 sudo ticket reachable (stage→run gap, rollout no sudo -k, C-z/STOP), B2 evidence not runnable (install -o root, ancestor walk under tmp, $0 self-check, Linux CI skip), S1-S8 (S8: cut to ~8 files, defer web hardening to P3). Operator decisions pending: S8 scope cut; TMUX refusal (Q9); P12 probe `sudo /usr/bin/sudo -V | grep -i timestamp` at home. UPDATE: operator chose S8 cut + tmux allowed with TSTP ignored; R2 rev 3 = 98a30c55 (8 files; deferred P3 docs/bugs/2026-11-23-installer-direct-run-hardening-deferred.md). Intent approved: pending — re-approval needed for E1-E5, E7, E9, E12, E15 (E6/E8/E13 removed). R2 rev 3 intents re-approved by operator (dc9ac8f5); R2-A dispatch gated on P12 probe (at home) + a WIP slot; R2 child plan files A-D still to write. dirused (OOB): M9b decline path live-checked 2026-11-23 (N → held logs skipped, 9.8G deleted, 94.1%→89.2%); y path not yet live. Operator: M10b one-time schedule first, then M10c recurring rules (pattern+folder+service, caps, 30-day expiry); read-only truncate-in-place probe on ffm01 approved. M10b spec rev 1 + M10c draft landed f5e34572. M10b blind reviews 2026-11-23: Fable NEEDS FIXES (4 blockers: exe not protected, list read twice, interrupted run invisible, E1 not runnable in Portable), Astra NEEDS FIXES (agrees on list double-read, demand start, interruption, E1; adds pre-stop checks incomplete + Tomcat stranded if process killed). Both: split the spec. Operator decisions 2026-11-23: scheduled runs skip Tomcat-held files (no unattended stop/start; that + growth relaxation move to a later milestone needing a kill-surviving recovery path); split M10b into sequential children b1 engine / b2 schedule+list+cancel / b3 runplan+COM+ACL / b4 docs (Flash); ordinary files keep exact match. Operator 2026-11-23 added schedule preview: /schedule without /confirm previews only (registers nothing), /confirm prompts y/N, /confirm /yes no prompt; resolves O4; goes in m10b2. Operator 2026-11-23 "schedule at the node we like" → both: M10b = node picked by the list's UNC host (one plan per node; O6 proposed: refuse multi-host lists); later milestone = option to register the task on the target node (S4U/SYSTEM, dirused installed on server, needs server-owner approval). 2026-11-23: b3 switched from COM to `schtasks /create /xml` (switches can't set EndBoundary/offset/demand-start/catch-up); operator probe on jump box pending: where dirused + icacls exe/folder, test task \dirused-probe\t1 /it /sc once 23:00 + /query /xml + disconnected-fire check. Rev 2 landed d2cb805d/c7e2bc3b; schtasks /xml revision f1d90cc8 (TaskXml pure fn, UTF-16 BOM, read-back compare, no /f, own-file status). Pending operator: intents (b1-b4), O2/O3/O6/O7/O8, 6 baseline-red exceptions, jump-box proofs P1-P7,P10-P12 + parts of P8; Claude: P9 + P8 docs. Quick probe 2026-11-23 (6b18d4e4): exe ACL inherited full control for a 2nd domain account + unresolved SID (B1 real; O7 would refuse); schtasks defaults confirmed (no offset/EndBoundary, demand start on, battery flags true); P1 fire check after 23:00 pending. Follow-up: the extra full-control entries are inherited from the profile root (C:\Users\cliang), so a planted-exe swap via delete-child on a parent defeats the plan-folder exe copy; O7 check must walk all ancestors; scheduling blocked on this jump box until profile ACL fixed (operator/domain admin call). Shell not elevated (Medium IL) → non-elevated user can create task folder (P10 part 1). Operator 2026-11-23: keep the sysadmin profile grants until IT confirms (nothing removed; /remove:g processed 0). Proposed O7 revision: trusted-principal acceptance at /schedule, recorded in plan, re-walked at /runplan; unresolved SID never accepted by default; ask IT about S-1-5-21-…-8249. Fork writing rev 2 + children. Then dispatch queue: totp-b, A1, istioctl-a, R2-A, R2-C (R2 dispatch after Fable round-2 findings applied; R2 child plan files not yet written).
  - Dispatched (Luna, 3/3 WIP): R4 token-argv, V4 drill exit, R1 cve-pins. Queue: totp-b revoked-keys (Luna), istioctl-a lib-foundation (Luna, --repo), P3 argocd-alert-regex (Luna); then age-identity (after V4, hub_data.sh), V4 defect 1, istioctl-b (after v0.5.8 tag + subtree pull), P3 sync-branch + preflight rename (after R1); Flash: istioctl-c changelog, totp-c guides.
  - **Operator at-home steps (remind when operator says they are home):** (1) replace m4-air istioctl 1.30.0 with 1.31.4; (2) raise hub istiod to 1.31.4; (3) after promote: `make install-web-console-sshd` and `make install-web-console-totp`; (4) R1 ruleset on `cve-pins/hub` (promoter only, no delete/force-push); (5) scope `GIT_WRITE_TOKEN` (platform-ops-git-writer) to this repo, contents write only; (6) R1 probes (ruleset state, token scope).
  - Need operator decisions: R2 design (root installers source checkout), DR V4 LDAP bind, DR empty age identity.
- Carried: Argon classification of red-team + drill bugs; PR #158; weekly-live-check plan; E3 ordering; web-console B
  write-up (raw captures in `~/.local/share/k3d-manager/captures/2026-11-22-*`); delete probe branch; hub Istio ≥1.31.4;
  old m2 cluster on EOL Istio; v1.46.0 swaps for 3a/3b drafts.

**Dispatches:** 0 open (both review runs abandoned 2026-11-23 07:00).
**New:** `docs/bugs/2026-11-23-hoverfocus-safari-no-focus.md` — Safari never focuses; suspect 8-level AX parent walk in
`Controller.lookup`; add to P1 probe on m2 (tab bar vs page content; depth; `kAXWindowAttribute`), fix goes to L2.
agy.log read permission was one-off per run; ask again for a new review run.

**Standing facts:**
- Handoff guard: `.claude/hooks/handoff-on-clear.sh` reports STALE if commits land after this header; bump the time on edit.
- Older handoffs and logs, verbatim: `memory-bank/archive/activeContext-2026-11-23.md` (then `-2026-11-22.md`).
- Source of truth for open work: `docs/bugs/` Waiting-on lines, `bin/k3dm-codex-dispatch open`, plan Status lines.
- Known agent failure modes: Codex sandbox cannot commit; agents report suites they did not run; worker cd failures can
  delete untracked files in the main checkout; mutants can reach real sudo unless the suite stubs sudo/launchctl.
- Carried small items: ask-bash linked-worktree P3 unfiled; revoke the zshenv GitHub token; SHA-256 pin nit in
  agent_dispatch_dashboard.bats test 54; locked-Keychain WARNs in hub-deploy; M2 `~/.ssh/config` is a copy (ask first).



<!-- archived 2026-11-25 11:25 PST at /handoff after v1.45.1 release -->

## Handoff — 2026-11-25 06:10 PST — v1.45.1 live checks done; gate fix dispatched — START HERE

**Operator:** at home today (m5-air hub, m2 drill Mac reachable). Only the operator can: hub promote (`make hub-deploy
REF=…` then `make hub-promote-status`), live checks at a keyboard (m2 drill/HoverFocus, m5 console), the dirused b3c
choice, and the jump-box probe. **Undelivered reminder:** dirused overnight probe on the office jump box (normal window):
`tools/m10b3-probes.ps1` from dirused branch `m10b-scheduled-purge` → `setup`, `run12`, disconnect; next morning `collect`,
`cleanup`; send output (confirms P10, gates E-B3L1/E-B3L2). Ask whether it was started.

**1. Gate recovery-code paste/lookalike fix (P2, v1.45.1)** — `docs/bugs/2026-11-25-console-gate-recovery-code-paste-and-lookalikes-rejected-silently.md`
- Spec rev 2 (Fable "ready after should-fix", all taken) `125899d6`; dispatched to Flash (agy, gemini-3.8-flash-medium),
  slug `gate-recovery-paste`, worktree `~/.local/share/k3d-manager/worktrees/v1.45.1/gate-recovery-paste`.
- Next (Claude): `bin/k3dm-codex-dispatch status gate-recovery-paste`; independent verify from Acceptance only (E1/E2 red
  on `9cca0789` then green; whole `scripts/tests/bin/test_web_console_totp.py`; gate must stay Python 3.9 `-IS`); land
  with that pytest file as `--test`. Then operator: promote + `make install-web-console-totp` + E4 (paste a recovery code
  at the console; count drops by one; Claude checks log +113 B). Bug cannot close without E4.

**2. v1.45.1 release (branch `k3d-manager-v1.45.1`, HEAD pushed, hub promoted `a1486486`)**
- LIVE-VERIFIED today: TOTP enrol QR bug (E4), chmod install bug (E2), totp-b L1 and totp-a2 L2 (plans updated).
  istioctl pin bug + version-probe hang bug LIVE-VERIFIED `12489efd` (E6/E7/E4 read from m2 `~/k3dm-e6e7-20261124T193757/`; E7 proves M1).
- Blocking the release PR: V4 LDAP resync. Operator runs `~/k3dm-v4-probe.sh` on m2 (plain Terminal; kept `dr-drill`
  cluster, kubeconfig `~/.k3dm/dr-drill/kubeconfig`; only file on m2 is the 2026-11-24 20:28 first run that died — rerun owed); Claude reads `~/k3dm-v4-probe-*.txt`, records under "Pre-dispatch
  proof" in `docs/plans/v1.45.1-dr-drill-v4-ldap-resync.md`, then dispatches V4 defect 1 to Luna if the bind passes.
- Then release PR (normal, not draft; Argon blind review, Copilot capped until 2026-12-01), CI green, live smoke.
- P3 captures owed (short docs, Waiting on: operator decision): first-install "Unable to load host key" warning;
  `timeout` absent on bare macOS in lib-foundation `install_istioctl.bats`; drill preflight clone ~15 min on m2;
  TOTP how-to: scan the QR from inside the authenticator app, not the Camera app.

**3. HoverFocus v0.0.3** — `docs/plans/hoverfocus-v0.0.3-plan.md`
- P3 signing PASS (recorded in plan "Probe results"); m2 now runs the signed build ("HoverFocus Local Signing").
- Next: operator runs `~/hf-probe/hf-p2.sh` on m2 (iTerm needs Accessibility); log `~/hf-p2-*.txt` (04:38 run 2026-11-25 has the header only — no scenario results; ask operator). Then Claude writes
  child specs L3 (focus correctness, Luna), F2 (signing + README, Flash; README must say: quit Settings, remove, re-add),
  U1 (visible errors, Luna); U2 after L3. Fable review before dispatch. Branch `v0.0.3` not cut yet.

**4. dirused (OOB, office jump box)**
- Operator chose option 2 (2026-11-25): mutants applied inside the windows CI runner. Harness drafted in scratch
  (`scratchpad/b3c-mutants/`: mutants.yml, run-mutant.ps1, mutants.json; 6 mutants + control). After correction 1: review, commit
  code + harness on the task branch, push, read windows + mutants runs, land b3c. Then b3d, M10b4 docs, dirused PR.

**Dispatches:** 2 open of WIP 3 — `v4-ldap-resync` (Luna, running, spec rev 3 `1ed88a1f`), dirused b3c LANDED (dirused `a224279`, pushed). `v4-ldap-resync` LANDED `cf743007` (E5 live drill on m2 pending).

**Owed / carried:** MEMORY.md over 9 KB (compress at a break); release groom Sun 2026-11-29; triage of captured bugs;
argon classification backlog; PR #158 (dependabot wrangler-action) open; m5-air test cert `~/.ssh/k3dm-console-test*`
expires 2026-11-26 (operator may delete).

**Standing facts:**
- Handoff guard: `.claude/hooks/handoff-on-clear.sh` reports STALE if commits land after this header; bump the time on edit.
- Older handoffs and logs, verbatim: `memory-bank/archive/activeContext-2026-11-25.md` (then `-2026-11-23.md`, `-2026-11-22.md`).
- Source of truth for open work: `docs/bugs/` Waiting-on lines, `bin/k3dm-codex-dispatch open`, plan Status lines.
- Push via `SSH_AUTH_SOCK=/var/run/com.apple.launchd.uw3bpQR945/Listeners`; each push restarts CI; hub-promote refuses a
  SHA whose check runs are not all green (lint included: run `make lint-python RUFF=<ruff 0.15.8>` before landing Python).
- Never ask for or accept secrets in chat: the operator pasted two recovery codes 2026-11-25; set regenerated since.
- Known agent failure modes: Codex sandbox cannot commit; agents report suites they did not run; worker cd failures can
  delete untracked files in the main checkout; mutants can reach real sudo unless the suite stubs sudo/launchctl.
- Carried small items: ask-bash linked-worktree P3 unfiled; revoke the zshenv GitHub token; SHA-256 pin nit in
  agent_dispatch_dashboard.bats test 54; locked-Keychain WARNs in hub-deploy; m2 `~/.ssh/config` is a copy (ask first).

- 2026-11-25 post-merge: v1.45.1 merged 19d396ed, tagged and released; enforce_admins restored; now on k3d-manager-v1.46.0 (groomed 5/5). Open carry-overs: 5 LANDED P2/P3 live checks (totp a1 decay, totp gate lockout, cve-pins, make sync-branch, preflight rename); dirused jump-box probe collect 2026-11-26; HoverFocus probe rewrite; #158 deferred.
- 2026-11-25 11:55 Argon PR #165: 2 low (V1 _err via pipeline: refuted; totpctl fin/fout isatty: real, unreachable) → no change, docs/issues/2026-11-25-argon-pr165-review-findings.md. Waiting CI on final head, then enforce_admins off.
- 2026-11-25 11:40 PR #165 (v1.45.1) opened, not draft. Argon blind review dispatched (release-pr165-v1.45.1-review, agy gemini-4-argon-medium, pid 86935); CI on head running. Alerts L1 LIVE-VERIFIED; 5 P2/P3 still LANDED (listed in PR notes). #158 deferred (operator).
- 2026-11-25 11:10 root-installers E15 LIVE-VERIFIED (m5 console; bootstrap installed at 65fd63f2, stage --ref deploy/hub, sudo dropped both times). All v1.45.1 bugs LIVE-VERIFIED → release PR next.
- 2026-11-25 10:35 LIVE-VERIFIED: age-identity E6 (ssh -tt drill on m2: Phase 1 refusal in 2 s), token bug (E9 scan + operator accept), V4 bug (E5 + defect 2 waived). Idea filed: drill failure-path hook. Remaining for v1.45.1: root-installers E15 (operator at m5 console), then release PR.
- 2026-11-25 10:20 hub promoted 65fd63f2. Token bug E9: scan half PASS (app-cve-scan-e9, deleted); verify half not exercisable (6 events all applied) → operator decision. Open: defect 2 E4 decision, age-identity E6 (locked-Keychain SSH drill), root-installers E15 (m5 console). Note: product-catalog 82 HIGH/CRIT, candidate still 62 — rebuild loop may not converge.
- 2026-11-25 09:50 P3 captured: docs/bugs/2026-11-25-ci-copilot-cli-installed-unpinned-latest.md (CI run 45660622977 red at Copilot CLI checksum). Hub promote of 65fd63f2 waits on its CI (operator rerun when green).
- 2026-11-25 09:40 V4 defect 1 LIVE-VERIFIED: m2 drill 20261125T173312Z success, V0-V9 true, RTO 644 s (HEAD c5bcf645). Defect 2 E4 (V4-false path) not exercisable by a passing drill → operator decision. Next: v1.45.1 release PR.
- 2026-11-25 09:35 P3 captured: docs/bugs/2026-11-25-dr-drill-preflight-snapshots-clone-takes-15-minutes.md (preflight clone 09:07→09:22 on m2). E5 drill running on m2 (watching).
- 2026-11-25 09:05 dirused b3d LANDED `009fb14` (10/10 mutants, CI green; N2 state-isolation fix `009fb14`). Next dirused: jump-box probe collect 11-26 → E-B3L1 → M10b4 docs → PR.
- (prior) 2026-11-25 08:55 dirused b3d: windows CI green on task branch `e34100a` (114/114 + 391); 3 CI rounds fixed test defects (Claude reverted Luna's Pacific-zone production change; spec rev 2 M2 uses `22:30 PT`). Next: harness per-mutant filter (operator scope exception) → 4 mutants → land.

## Handoff (2026-11-25, after v1.45.1 release)

- **Objective done:** v1.45.1 shipped — PR #165 merged `19d396ed`, tag + GitHub release v1.45.1 (latest), enforce_admins
  restored, next branch `k3d-manager-v1.46.0` (groomed 5/5). Retro `docs/retro/2026-11-25-v1.45.1-retrospective.md`.
- **Evidence:** 9 bugs LIVE-VERIFIED with Live evidence lines (V4 drill 20261125T173312Z; age-identity E6 SSH drill 2 s;
  token E9 scan; root-installers E15 m5 console; alerts L1 hub Prometheus; gate paste; istioctl x2; sshd chmod; QR).
  Argon PR #165: 2 low, no change (`docs/issues/2026-11-25-argon-pr165-review-findings.md`). Hub smoke 30/30 healthy.
- **Decisions (operator):** V4 defect 2 E4 waived + drill failure-path hook idea; token E9 verify half accepted offline;
  #158 (wrangler-action v4) deferred; OOB client onboarding checklist idea filed (pilot dirused).
- **Open, next session:** (1) dirused jump-box probe collect 2026-11-26 → report.txt, cleanup, record E-B3L1/E-B3L2 gates;
  then E-B3L1 attended, M10b4 docs, dirused PR (b3d LANDED `009fb14`). (2) 5 LANDED P2/P3 live checks: totp a1 decay,
  totp gate lockout, cve-pins at-home steps, make sync-branch round trip, next sandbox preflight. (3) HoverFocus probe
  rewrite from upstream source at a tag. (4) P3 captures owed: host-key warning, lib-foundation `timeout` on macOS, QR
  how-to note, dirused flaky ProgramPurgeTests, hub_data export-path flake. (5) product-catalog 82 HIGH/CRIT, candidate 62:
  rebuild loop may not converge (base image?). (6) Triage due: several P3 captures from 2026-11-23..25.
- **Gotchas learned:** verified-stage needs the full 40-hex commit and `--ref deploy/hub` before a release reaches main;
  dr-drill needs a TTY (`ssh -tt`); check CI on the exact SHA before giving promote commands.
