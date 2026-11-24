# dirused M10b2c: seam interfaces, the D14 trust check, `/schedule /trust` and `/untrust` (pure, with fakes)

**Status:** OPEN — SPEC rev 2, 2026-11-24; intents approved (carries E-B2); round-2 reviews applied (parent table); **not dispatchable until the P-ACL tables below are filled**
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b2 shared contract](dirused-m10b2-schedule-preview-list-cancel.md) (rev 4: Interfaces, Trust rules); design D14.
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (tip `e19783f`); runs beside [b2b](dirused-m10b2b-parser-usage.md) (no shared file)
**Risk:** medium — the security check that decides whether a plan may be created; no real ACL or registry call here
**Implementer:** Luna (Codex)
**Verifier:** Claude, offline, from Acceptance only; plus the windows CI job after landing
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Intent note:** carries the approved E-B2 intent unchanged (parent); this child is its trust part.
**Approval:** operator, 2026-11-24 — D14 "secure but not over restricted"; "intents approved"
**Proof before dispatch:** P-ACL (parent) recorded into the `StockSystemDrive` fixture.

## Scope

1. **`src/Dirused.Common/ScheduleSeams.cs`**: exactly the parent's Interfaces block (records, enums, interfaces, `ScheduleSeams`,
   `ScheduleRequest`), nothing added.
2. **`src/Dirused.Common/PlanTrust.cs`**:
   ```csharp
   public enum PathRole { Leaf, Ancestor }
   public sealed record TrustPath(string FullPath, PathRole Role, bool MayBeMissing);
   public sealed record TrustCheck(bool Ok, IReadOnlyList<string> Lines);   // Lines = stderr lines on refusal, empty when Ok
   public static class PlanTrust
   {
       public static bool IsBroad(string sid);
       public static IReadOnlyList<TrustPath>? PathsToCheck(string exePath, string planRoot, out string? error); // null + error line when a path is not drive-rooted
       public static TrustCheck Check(string exePath, string planRoot, string userSid, IReadOnlyCollection<TrustedAccount> trusted, IPlanStore store, IPlanFolderSecurity security);
   }
   ```
   Rules exactly as the parent's "Trust rules": drive-rooted paths; leaves (exe, exe folder, `...\dirused`, `<PlanRoot>`; the last two
   `MayBeMissing = true`) and ancestors in the stated order; normalisation; allowed writers; reparse check on every existing path;
   `AclRead` handling; deny and inherit-only ignored; owner pseudo-entry; broad SIDs; findings merge and order; refusal lines and
   rights wording — all as the parent states. `Check` calls `store.IsReparsePoint` then (unless it is a link) `security.ReadAcl` once
   per path, in `PathsToCheck` order; the first reparse or read failure ends the check and its line is the only output (earlier ACL
   findings are discarded). Otherwise it reads every path and prints the first finding as the two-line refusal and the rest as
   `  also:` lines.
3. **`src/Dirused.Common/TrustCommands.cs`**:
   ```csharp
   public static class TrustCommands
   {
       public static int Trust(string? account, ITrustStore store, IAccountResolver accounts, TextWriter stdout, TextWriter stderr);
       public static int Untrust(string account, ITrustStore store, IAccountResolver accounts, TextWriter stdout, TextWriter stderr);
   }
   ```
   - `Trust(null)`: each stored account as `  <sid>  <display>`, sorted by display (ordinal, ignore case), or `No trusted accounts.`;
     exit 0.
   - `Trust(acct)`: `Resolve(acct)`; null and `acct` matches `^S-1-[0-9]+(-[0-9]+)+$` → account `(acct, "unresolved account " + acct)`;
     null otherwise → stderr `unknown account: <acct>`, exit 1. Broad (`IsBroad`) → stderr `<display> is too wide to trust`, exit 1.
     Already stored (by SID) → `<display> is already trusted.`, exit 0. Else `Add`; failure → stderr
     `error: could not save the trust list: <error>`, exit 3; success → `Trusted <display> (<sid>).`, exit 0.
   - `Untrust(acct)`: the SID is `Resolve(acct)?.Sid`, or `acct` itself when it matches the SID pattern; if no SID or not stored →
     stderr `<acct> is not trusted.`, exit 1. Else `Remove`; failure → exit 3 `error: could not save the trust list: <error>`; success
     → `Removed <stored display>.`, exit 0.

## Files

- `src/Dirused.Common/ScheduleSeams.cs`, `src/Dirused.Common/PlanTrust.cs`, `src/Dirused.Common/TrustCommands.cs` (new)
- `tests/Dirused.Tests.Portable/ScheduleFakes.cs` (new): `internal sealed` in-memory fakes `FakePlanStore`, `FakeFolderSecurity`,
  `FakeTaskScheduler`, `FakeTrustStore`, `FakeAccountResolver`, each recording calls in one shared ordered `List<string>` log, plus
  `internal static` fixture builders `StockSystemDrive()` and `JumpBoxProfile()`. b2d and b2e reuse them.
- `tests/Dirused.Tests.Portable/PlanTrustTests.cs`, `tests/Dirused.Tests.Portable/TrustCommandsTests.cs` (new)

## What NOT to Do

- No other file. No `System.IO.Path`, `File`, `Directory`, registry, `NTAccount`, `SecurityIdentifier` or any Windows API here; paths
  are strings split on `\`.
- Tests: writers `NewLine = "\n"`, literal `"\n"` expectations; no `Environment.NewLine`.
- Leave changes uncommitted; do not push.

## Acceptance

### P-ACL tables (jump box, `icacls` and `dir /q`, operator, 2026-11-24)

Account names are placeholders with the same shape as the jump box: `PROD\op` (`S-1-5-21-1-2-3-1104`) is the user, `PROD\admin2`
(`S-1-5-21-1-2-3-2001`) stands for the second domain admin, and `S-1-5-21-9-9-9-8249` stands for the unresolved SID (no display
name; `Resolve` returns null). Rights: `F` = `GenericAll`; `M` = `Write | Append | Delete`; `RX`, `GR,GE` = `None`. `(IO)` =
inherit-only; `(I)` = inherited (not inherit-only).

| Path | Owner | Entries (all allow) |
|---|---|---|
| `C:\` | TrustedInstaller (assumed; `dir /q` cannot show it) | pending `icacls C:\` |
| `C:\Program Files` | `S-1-5-80-956008885-...-2271478464` TrustedInstaller | TrustedInstaller `GenericAll`; TrustedInstaller IO `GenericAll`; SYSTEM `Write\|Append\|Delete`; SYSTEM IO `GenericAll`; Administrators `Write\|Append\|Delete`; Administrators IO `GenericAll`; Users `None`; Users IO `None`; CREATOR OWNER IO `GenericAll`; `S-1-15-2-1` ALL APPLICATION PACKAGES `None`; its IO `None`; `S-1-15-2-2` ALL RESTRICTED APPLICATION PACKAGES `None`; its IO `None` |
| `C:\Program Files\dirused`, `dirused.exe` | TrustedInstaller | inherited (not IO) copies of Program Files' IO entries: TrustedInstaller, SYSTEM, Administrators `GenericAll`; Users and both package groups `None` (CREATOR OWNER's copy is not created) |
| `C:\Users` | SYSTEM | SYSTEM `GenericAll`; Administrators `GenericAll`; Users `None`; Users IO `None`; Everyone `None`; Everyone IO `None` |
| `C:\Users\op` (profile) | Administrators | SYSTEM, Administrators, `PROD\op` `GenericAll`; **`S-1-5-21-9-9-9-8249` `GenericAll`; `PROD\admin2` `GenericAll`** (all explicit, OI CI) |
| `...\AppData` | `PROD\op` | the five profile entries, inherited (not IO) |
| `...\AppData\Local` | `PROD\op` | the five profile entries, inherited (not IO) |
| `...\Local\dirused`, `...\plans` | — | missing (first run) |

Fixture `StockSystemDrive` (fake `IPlanFolderSecurity`): the P-ACL tables for `C:\`, `C:\Program Files`, `C:\Users`, the profile
`C:\Users\op` **without** the `PROD\admin2` and `-8249` entries (and the same removed from `AppData` and `Local`), `...\AppData`, `...\AppData\Local`; `C:\Program Files\dirused` and its `dirused.exe` inherit Program Files' entries;
`...\Local\dirused` and `plans` missing. User SID `S-1-5-21-1-2-3-1104`. Fixture `JumpBoxProfile` = the P-ACL tables as recorded: the profile, `AppData` and `Local` carry `PROD\\admin2` (`S-1-5-21-1-2-3-2001`,
resolves) and `S-1-5-21-9-9-9-8249` (unresolved) with `GenericAll`, explicit on the profile and inherited below.

```yaml
must:
  - id: T-M1
    text: "PathsToCheck('C:\\\\Program Files\\\\dirused\\\\dirused.exe', 'C:\\\\Users\\\\op\\\\AppData\\\\Local\\\\dirused\\\\plans') returns, in order with roles: exe Leaf, 'C:\\\\Program Files\\\\dirused' Leaf, 'C:\\\\Program Files' Ancestor, 'C:\\\\' Ancestor, '...\\\\Local\\\\dirused' Leaf MayBeMissing, '...\\\\Local\\\\dirused\\\\plans' Leaf MayBeMissing, '...\\\\AppData\\\\Local' Ancestor, '...\\\\AppData' Ancestor, 'C:\\\\Users\\\\op' Ancestor, 'C:\\\\Users' Ancestor ('C:\\\\' not repeated); '\\\\\\\\srv\\\\share\\\\dirused.exe' and 'dirused.exe' return null with '/schedule: dirused.exe must be on a local drive to schedule (<path>)'; a relative plan root returns null with the plan-folder message"
  - id: T-M2
    text: "Check on StockSystemDrive with no trusted accounts is Ok with no lines (no /trust needed for an IT install plus a normal profile)"
  - id: T-M3
    text: "Check on JumpBoxProfile with no trusted accounts refuses with exactly these lines: '/schedule: C:\\\\Users\\\\op can be changed by PROD\\\\admin2 (full control).', '  If you trust this account, run once: dirused /schedule /trust \"PROD\\\\admin2\"', '  also: C:\\\\Users\\\\op by unresolved account S-1-5-21-9-9-9-8249', '  also: C:\\\\Users\\\\op\\\\AppData by PROD\\\\admin2', '  also: C:\\\\Users\\\\op\\\\AppData by unresolved account S-1-5-21-9-9-9-8249', '  also: C:\\\\Users\\\\op\\\\AppData\\\\Local by PROD\\\\admin2', '  also: C:\\\\Users\\\\op\\\\AppData\\\\Local by unresolved account S-1-5-21-9-9-9-8249' (shallowest path first, then SID ordinal). With only PROD\\\\admin2 trusted it refuses with first line '/schedule: C:\\\\Users\\\\op can be changed by unresolved account S-1-5-21-9-9-9-8249 (full control).' and '  If you trust this account, run once: dirused /schedule /trust \"S-1-5-21-9-9-9-8249\"'. With both trusted it is Ok"
  - id: T-M4
    text: "single-entry cases on the exe folder (Leaf): Users with Append → refused with the IT line ('  This group is too wide to trust; ask IT to remove this permission or move dirused.exe.'); a domain user with Write → refused with the /trust line; the same entry InheritOnly → Ok; the same entry Deny → Ok; a read-only entry → Ok. On 'C:\\\\Program Files' (Ancestor): a domain user with Append or Write or GenericWrite → Ok; with Delete, DeleteChild, WriteDac, WriteOwner or GenericAll → refused, rights text 'delete', 'delete child', 'change permissions', 'take ownership', 'full control' respectively"
  - id: T-M5
    text: "owner: the exe folder owned by a domain user → refused with '(owner)'; owned by Administrators or TrustedInstaller → Ok. An unresolved SID entry prints 'unresolved account <sid>' as display and the SID (quoted) in the /trust line"
  - id: T-M6
    text: "IsReparsePoint true on 'C:\\\\Program Files\\\\dirused' → exactly '/schedule: C:\\\\Program Files\\\\dirused is a link; dirused does not schedule through links', and no ReadAcl after that path; ReadAcl Ok=false on 'C:\\\\Users' → '/schedule: cannot read permissions of C:\\\\Users: <error>'; Missing on '...\\\\Local\\\\dirused\\\\plans' → Ok; Missing on 'C:\\\\Program Files\\\\dirused' → '/schedule: cannot read permissions of C:\\\\Program Files\\\\dirused: not found'"
  - id: T-M7
    text: "IsBroad true for S-1-1-0, S-1-5-11, S-1-5-32-545, S-1-5-4, S-1-5-21-1-2-3-513, S-1-5-21-1-2-3-515; false for S-1-5-21-1-2-3-2001, S-1-5-32-544, S-1-5-18"
  - id: T-M8
    text: "TrustCommands: list sorted by display or 'No trusted accounts.'; Trust resolved → 'Trusted PROD\\\\admin2 (S-1-5-21-1-2-3-2001).' and stored; again → 'PROD\\\\admin2 is already trusted.' exit 0; unresolved SID → stored as 'unresolved account <sid>'; unknown non-SID → exit 1 'unknown account: bob'; 'Everyone' resolving to S-1-1-0 → exit 1 'Everyone is too wide to trust', nothing stored; Add failure → exit 3 'error: could not save the trust list: disk full'; Untrust stored → 'Removed PROD\\\\admin2.'; absent → exit 1 'bob is not trusted.'"
must_not:
  - id: T-N1
    text: "Check is Ok while an untrusted non-broad account has DeleteChild on an Ancestor, or Write on a Leaf. Positive control: T-M2 Ok. Mutant-only (PlanTrust absent on e19783f): mutants 'ancestors use the leaf rights set', 'leaves use the ancestor rights set', 'trusted SIDs ignored' each turn T-M2, T-M3 or T-M4 red"
  - id: T-N2
    text: "a read failure or a missing non-MayBeMissing path is treated as an empty ACL (Check Ok). Positive control: Missing plans folder Ok. Mutant 'AclRead Ok=false treated as no entries' turns T-M6 red"
  - id: T-N3
    text: "a broad group can be trusted (stored by Trust, or accepted by Check because it is in the trusted list). Positive control: PROD\\\\admin2 trusted. Mutant 'IsBroad ignored in Check' turns T-M4 red"
  - id: T-N4
    text: "PlanTrust.cs or TrustCommands.cs (comments stripped) match (?<![\\\\w.])(File|Directory|Path|Registry|NTAccount|SecurityIdentifier|Process)\\\\s*[.(] — positive control: mutant adding 'System.IO.Path.GetDirectoryName' turns the scan red"
evidence:
  - id: E-T
    proves: [T-M1, T-M2, T-M3, T-M4, T-M5, T-M6, T-M7, T-M8, T-N1, T-N2, T-N3, T-N4]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4; new tests do not compile on e19783f; mutants each red with the catching test named: inherit-only honoured for non-CREATOR-OWNER [T-M2]; Append counted on ancestors [T-M2]; leaf Write ignored [T-M4]; owner not checked [T-M5]; reparse not checked [T-M6]; read failure as empty [T-M6]; IsBroad ignored [T-M4, T-M8]; /trust line unquoted [T-M3]; also-lines dropped [T-M3]"
    intent: "Typing /schedule shows you exactly what would run — when, which list, how many files and how much space — and schedules nothing until you add /confirm and say yes; you can list and cancel plans, and a cancel can never race a run that already started. Before scheduling, dirused checks who else could change the program or plan folders and tells you exactly which account to trust, once."
  - id: E-TW
    proves: [T-M1, T-M2]
    kind: offline
    command: "after landing: the windows CI job on the m10b-scheduled-purge push run is green on the landed commit"
    intent: "The same tests pass on Windows, where dirused actually runs."
interface:
  - "PlanTrust.IsBroad(sid) / PathsToCheck(exe, planRoot, out error) / Check(...) -> TrustCheck(Ok, Lines)"
  - "TrustCommands.Trust(account?, store, accounts, stdout, stderr) / Untrust(account, ...) -> int"
  - "/schedule: <path> can be changed by <display> (<rights>)."
  - "  If you trust this account, run once: dirused /schedule /trust \"<account>\""
  - "  This group is too wide to trust; ask IT to remove this permission or move dirused.exe."
  - "/schedule: <path> is a link; dirused does not schedule through links"
  - "/schedule: cannot read permissions of <path>: <error>"
  - "/schedule: dirused.exe must be on a local drive to schedule (<path>)"
  - "/schedule: the plan folder must be on a local drive (<path>)"
  - "Trusted <display> (<sid>)." / "<display> is already trusted." / "unknown account: <acct>" / "<display> is too wide to trust"
  - "Removed <display>." / "<acct> is not trusted." / "No trusted accounts." / "error: could not save the trust list: <error>"
```
