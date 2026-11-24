# dirused M10b3: `/runplan`, the real Windows seam classes, Program wiring — split into b3a–b3d

**Status:** OPEN — SPEC rev 4, 2026-11-24; rev 3 reviewed blind by Fable and Argon (both READY WITH FIXES, both: too big, split). Split
into four children; fixes applied in them (table below). The children are what get dispatched; this file holds the gates and the
adjudication.
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §5, §6, §8, D14; [M10b2 shared contract](dirused-m10b2-schedule-preview-list-cancel.md)
rev 5 (copied into each child).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (head `ab98677`)
**Risk:** high — the unattended delete path, real `schtasks.exe` and ACL calls
**Filed:** 2026-11-23 (rev 3 and rev 4 2026-11-24)
**Intent approved:** operator, 2026-11-24 (each child carries one approved intent unchanged)
**Approval:** operator, 2026-11-23 — D9 (no service stop), D3 (logged-on only, no password); operator, 2026-11-24 — D14, "intents approved"

## Children and order

| Child | Scope | Worker | Starts |
|---|---|---|---|
| [b3a](dirused-m10b3a-runplan-engine.md) | `PlanRunner.RunPlan`, run report, `IPlanStore.MoveNew`, `PurgeList.ToResults` (portable) | Luna | now |
| [b3b](dirused-m10b3b-schtasks-and-rights.md) | `SchtasksTaskScheduler`, `IProcessRunner`, `AclRights.FromMask` (portable) | Luna | P10 form taken from P9 (verbatim round-trip); jump-box P10 confirms |
| [b3c](dirused-m10b3c-windows-seams.md) | `ScheduleWindows.cs`: real store, ACL, trust store, resolver, process runner, `WindowsSchedule` (windows CI) | Luna | after b3a and b3b land (P6 and P9 PASS) |
| [b3d](dirused-m10b3d-program-wiring.md) | Program wiring, `ProgramTestSeams`, interim refusal removed (windows CI) | Luna | after b3c |

Live checks E-B3L1 and E-B3L2 (below) follow b3d and the jump-box probes P1–P3, P12. Then M10b4 (docs, usage text), then one PR.

## Jump-box probe script (2026-11-24)

`tools/m10b3-probes.ps1` in the dirused repo (branch `m10b-scheduled-purge`; moved from this repo 2026-11-24, run it as `m10b3-probes.ps1`) covers P1, P2, P3, P8 (a, b, d), P10 (descriptor readback; the
second-account check is manual) and P12. It creates tasks only under `\dirused-probe\<SID>\` and files only under
`%LOCALAPPDATA%\dirused-probe\`; P3 runs `dir` and `icacls` on the share (read-only). Run order: `setup` (afternoon, prints the
steps and times), `run12`, disconnect / sign-out steps as printed, leave disconnected, next morning `collect`, paste `report.txt`,
then `cleanup`. P5, P6 and P9 are not in it (P9 is a CI workflow, Claude's).

**P6 second half, 2026-11-24 14:07 PT, jump box (operator screenshot), normal window:** `icacls ...\dirused-probe\p6 /inheritance:r
/grant:r "%USERNAME%":(OI)(CI)F` and `/setowner "%USERNAME%"` both `Successfully processed 1 files`; readback one entry
`PROD\cliang:(OI)(CI)(F)`; `dir /q` owner of `p6` `PROD\cliang`. **PASS.** The parent `dirused-probe` shows owner
`BUILTIN\Administrators` (creation context unknown); the default owner of a new file and subfolder was then checked.
**Default owner, 2026-11-24 14:52 PT:** from an elevated window (`whoami /groups`: High Mandatory Level, Administrators `Group
owner`) new files were owned by `BUILTIN\Administrators`; from a normal window (Medium, Administrators `Group used for deny only`)
`f.txt` and `sub` are owned by `PROD\cliang`. **PASS:** `IsIntact`'s owner = user rule holds for plans made from a normal window,
and `/schedule` already refuses High tokens. No spec change.

**P9, 2026-11-24, wilddog64/dirused Actions run 45510934313 (windows-latest, scratch branch `p9-schtasks-probe`, deleted after):**
runner account `runneradmin` (High, elevated). Production-shape XML (UTF-16 LE BOM) under `\dirused-ci\<SID>\purge-<id>`:
`/create` exit 0; `/query /xml` exit 0; second `/create` without `/f` exit 1 (`Cannot create a file when that file already exists`);
`/run` exit 1 (`The task settings do not allow the task to start on demand`, P12 on CI); `/query` exit 0; `/delete /f` exit 0;
`/query` after delete exit 1. **PASS.** Findings:
- The readback omits every setting equal to the Windows default (`RunLevel`, `StartWhenAvailable`, `AllowHardTerminate`,
  `Settings/Enabled`, `Hidden`, trigger `Enabled`) and adds `URI` and `IdleSettings`. `TaskXml.Parse` on the exact readback bytes
  (Claude, local, 2026-11-24): **PARSE OK**, every `PlanTask` field equal to the written one.
- `SecurityDescriptor` reads back verbatim: `D:P(A;;FA;;;<SID>)(A;;FA;;;SY)(A;;FA;;;BA)` (P10 form on CI; the jump-box probe
  confirms it for a standard user).
- `/query /xml` redirected by `cmd` is single-byte text without BOM (`3C 3F 78 6D`) although it declares `encoding="UTF-16"`;
  `TaskXml.Parse` decodes it (UTF-8 fallback). A non-ASCII character in the Description (list file name) could then fail the
  compare: fail-closed (task removed, `error: scheduled task does not match the plan (Description)`); accepted residual.
- Probe bug, not a product finding: the probe's id suffix `p9a1` is not hex, so `TaskXml.Parse` refused `Arguments` until the
  suffix was a valid one.

**Gates.** Dispatch: P6 second half (a standard user can set owner = self and a protected one-ACE DACL; a 4-line `icacls` check the
operator runs), P9 (Claude: a scratch-branch windows-latest workflow registers, queries and deletes an interactive-token task in
`\dirused-ci\`), P10 readback (the SDDL that `/query /xml` returns for the descriptor, so the verify compare uses the right form). P8 (b)
no longer gates: `TaskXml.Parse` already decodes UTF-16 with or without BOM and UTF-8 with BOM (`TaskXml.cs:336-352`). Live checks
only: P1 production-XML form, P2, P3, P12.


## Live checks (after b3d)

```yaml
evidence:
  - id: E-B3L1
    kind: live
    command: "operator, jump box, attended, after P1-P3, P10, P12: trust the accounts the /schedule refusal names (operator's call for S-1-5-21-…-8249); save a list of 2-3 small non-held test files in a scratch share folder; dirused /fromlist t.txt /purge /schedule <now+5min> PT (preview), then the same with /confirm, answer y; stay connected; after the run: dirused /schedule /list shows done; report.txt shows them deleted; then schedule a second plan and /schedule /cancel it: list shows cancelled and the files remain"
    intent: "While you watch, a scheduled run deletes a few test files from a list you reviewed, and a cancelled plan deletes nothing."
  - id: E-B3L2
    kind: live
    command: "operator, jump box, disconnected: dirused \\\\us03p02ffm01\\d$\\Tomcat /largest *.log /purge /savelist m10b.txt; review; /schedule <evening time> PT /confirm, y; disconnect RDP (do not sign out); next morning: /schedule /list shows done; report.txt lists deleted rotated logs and the held tomcat85-stderr/stdout rows as 'skipped: held by Tomcat85 — scheduled runs do not stop services'; sc \\\\us03p02ffm01 query tomcat85 shows RUNNING with an unchanged start time; free space on d$ rose by the reported amount"
    intent: "You schedule tonight's purge, disconnect, and in the morning see the old logs gone, the logs Tomcat holds left alone, and Tomcat never restarted."
```

## Review adjudication (rev 3, 2026-11-24)

Fable: READY WITH FIXES (blocking 9, 14, 15, 25, 26, 28, 29, 30, 36). Argon: READY WITH FIXES (blocking 1, 2, 5, 9, 10, 14, 16, 17, 18,
22). Each finding was checked against the code at `ab98677`.

| Finding | Source | Action |
|---|---|---|
| Too big for one dispatch | Fable 36, Argon 21 | Applied: b3a–b3d (Fable's split) |
| `log` callback must throw when `AppendLog` fails (Purge undoes a delete only on a throw, `Purge.cs:1050-1064`) | Fable 9, Argon 23 | Applied in b3a (B3a-M6) |
| `RealProcessRunner` deadlock / throw | Fable 14, Argon 11 | Applied in b3c: async both streams, timeout parameter, never throws; b3b treats a throw as exit -1 |
| Trust store integrity (a profile writer can pre-create `trust.txt`) | Fable 15 | Applied in b3c: `Load` checks owner/ACL/links; `Add`/`Remove` always `Secure` |
| `RunWithSchedule` lacks version, fs, services, clock, purge log | Fable 25, Argon 16 | Applied in b3d: `ProgramTestSeams` forwards all |
| Position of `/schedule <time>` wiring; `/schedule needs Windows` untestable | Fable 26, Argon 14 | Applied in b3d: explicit order; `IsWindows` seam; B3d-M2, M3 |
| Fakes `internal`, list-read-once unobservable | Fable 28, Argon 14 | Applied in b3d: link `ScheduleFakes.cs`; read-once by diff review |
| B3-N1 mutants cannot turn it red | Fable 29 | Applied in b3a: real PlanRunner mutant (copy Stat into rows) |
| SecurityDescriptor compare placeholder, no acceptance | Fable 30, Argon 19 | Applied in b3b: P10 gate, field-table row, mutant |
| Field names per mismatch ambiguous | Fable 2, Argon 2 | Applied in b3b: field table (checked against `TaskXml.cs:286-312`) |
| `Secure` owner set fails for non-elevated admin | Argon 1 | Refuted by P6 (2026-11-24, owner set from a normal window); still set the owner only when it differs (b3c) |
| Report newlines `\r\n` from `StringWriter` on Windows | Argon 5 | Applied in b3a |
| List with errors or no files at run time | Argon 5 | Applied in b3a step 9 |
| Drive check vs missing order; `QueryDosDeviceW` signature and 0 return | Fable 17, Argon 9 | Applied in b3c |
| `IsIntact` vs real ACLs | Argon 10 | No change: protected one-ACE folder, files inherit it; owner = default owner (P6 default-owner check pending) |
| Report-direct mutant not killed | Fable 32, Argon 18 | Applied in b3a: store call sequence asserted |
| `MoveNew` overwrite mutant is Windows-only | Fable 32 | Applied: moved to b3c |
| 5b time format | Argon 22 | Applied in b3a: exact example |
| PlanTrust first-line shapes; trailing `.` | Fable 1 | Applied in b3a |
| ScheduleTests lines 58-70 | Fable 3, Argon 15 | Applied in b3d |
| Plan validation weaker than `/schedule /list` | Fable 5, Argon 3 | Applied in b3a: same required fields plus strict rules |
| `ToResults` uses `System.IO.Path` | Fable 6 | Accepted, stated in b3a |
| `CleanupUpdateFiles` touches the plan dir | Fable 7 | Applied in b3d: skipped for schedule forms; `Cleanup` seam so it is testable |
| Usage text still "preview" | Fable 8 | Deferred to M10b4 (stated in b3d) |
| Stale `report.txt` without claim misleads | Fable 11 | Applied in b3a: step 5c refuses before the claim |
| Claim race prints the wrong message | Fable 10 | Applied in b3a: 3 re-reads; b2e `Cancel` unchanged (fail-closed, message only) |
| Exception after the claim | Fable 12 | Applied in b3a: `refused: error during run` |
| `IsReparsePoint` other errors | Fable 18, Argon 24 | Applied in b3c: true (fail closed) |
| `CreateDirectory` check-then-create | Fable 19 | Accepted, stated in b3c |
| CI runner owner differs; token with UAC off | Fable 20, 21 | Stated in b3c |
| SID regex case; translate cache | Fable 22, 24 | Applied in b3c |
| NULL DACL; callback ACEs | Fable 16 | NULL DACL applied in b3c; callback ACEs a documented residual |
| `/query /xml` may be OEM-encoded | Fable 23 | Fail-closed (task removed); P8 (b) row stays in the probe script |
| B3-N6 vacuous half; positive control; mutant | Fable 31 | Applied in b3a (RunPlan only) |
| Missing acceptance (claim error, trust store, resolver, Create, runner timeout, report-failure log) | Fable 33 | Applied across b3a, b3c |
| B3-M1 fixture facts; B3-N4 control | Fable 34, 35 | Applied in b3a |
| Step 9 stderr summary; `trust.tmp`; lazy seams; contract-reader rows | Fable 37-40 | Applied in b3a, b3c, b3d |
| `RunWithSchedule` and `ConfirmUnavailable` wording | Fable 27 | Applied in b3d ("neither output contains") |
