# dirused M10b2a: `TaskXml` — build and parse the scheduled task's XML (pure, no scheduler)

**Status:** LANDED — `cf07ace` on `m10b-scheduled-purge` (2026-11-24); independent Sonnet verifier (round 1 FAIL → correction 1) and Claude mutant re-run PASS; E-XW windows CI on push run 45455761460 pending
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §4.7 (split out of [M10b2](dirused-m10b2-schedule-preview-list-cancel.md) on 2026-11-24 so it can run
beside M10b1; no shared file with M10b1).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge` (integration branch from `main` `966b32b`)
**Risk:** low — two new files; nothing calls them until M10b2/M10b3
**Implementer:** Flash (agy)
**Verifier:** Claude, offline, from Acceptance only; plus the windows CI job
**Filed:** 2026-11-24
**Intent approved:** operator, 2026-11-24
**Approval:** operator, 2026-11-24 — "intents approved, and you write a spec and have Fable/Argon review then dispatch between Flash and Luna"
**Proofs:** P8 (c) schema names and order — Microsoft Learn Task Scheduler schema, recorded under "Schema facts" (2026-11-24).
P8 (a) UTF-16 LE + BOM acceptance by `schtasks` and P8 (b) `/query /xml` bytes are jump-box items for M10b3; this child only
produces and parses bytes.

## Why

M10b2 writes `task.xml` for a plan and M10b3 registers it with `schtasks /create /xml` and reads it back with `/query /xml` to verify
every field. Both need one pure builder and one parser that agree exactly.

## Scope

New `src/Dirused.Common/TaskXml.cs`:

```csharp
public sealed record PlanTask(
    string Id,                 // ^[0-9]{8}-[0-9]{4}-[0-9a-f]{4}$
    DateTimeOffset Run,        // instant; written with its own offset
    DateTimeOffset Expires,
    string UserSid,            // ^S-1-[0-9]+(-[0-9]+)+$
    string PlanDir,            // absolute Windows path; any characters incl. space & " < > '
    string Description);       // free text, may be empty

public static class TaskXml
{
    public static byte[] Build(PlanTask task);          // UTF-16 LE with BOM FF FE
    public static PlanTask Parse(byte[] bytes);         // accepts UTF-16 LE with BOM, UTF-16 LE without BOM, UTF-8 with or without BOM
    public static string? SecurityDescriptorOf(byte[] bytes);          // null when absent; FormatException on malformed XML
    public static (string? Start, string? End) BoundariesOf(byte[] bytes); // raw text; null when absent; FormatException on malformed XML
}
```

`Build` writes a Task Scheduler document with namespace `http://schemas.microsoft.com/windows/2004/02/mit/task` and
`version="1.2"`. It emits elements **in exactly the order listed below** (the order Windows' own export uses, valid whether or not
`schtasks` enforces a sequence). Task children are RegistrationInfo, Triggers, Principals, Settings, Actions.

- `RegistrationInfo`: `Description` (empty element when empty), `SecurityDescriptor`
  `D:P(A;;FA;;;<UserSid>)(A;;FA;;;SY)(A;;FA;;;BA)`.
- `Triggers`: exactly one `TimeTrigger` with children `StartBoundary` = `Run`, `EndBoundary` = `Expires`, `Enabled` `true`.
  Boundaries use the format string `"yyyy-MM-dd'T'HH:mm:sszzz"` with `CultureInfo.InvariantCulture`, so the text ends with the
  instant's own offset (`-08:00`, `-07:00`, `+00:00`); never `Z`, never without offset.
- `Principals`: one `Principal id="Author"` with `UserId` = `UserSid`, `LogonType` `InteractiveToken`, `RunLevel` `LeastPrivilege`.
- `Settings`: `MultipleInstancesPolicy` `IgnoreNew`, `DisallowStartIfOnBatteries` `false`, `StopIfGoingOnBatteries` `false`,
  `AllowHardTerminate` `true`, `StartWhenAvailable` `false`, `AllowStartOnDemand` `false`, `Enabled` `true`, `Hidden` `false`,
  `ExecutionTimeLimit` `PT2H`, `DeleteExpiredTaskAfter` `P30D`.
- `Actions Context="Author"`: one `Exec` with `Command` `<PlanDir>\dirused.exe`, `Arguments` `/runplan <Id>`, `WorkingDirectory`
  `<PlanDir>`. The join is the literal string `PlanDir.TrimEnd('\\') + "\\dirused.exe"`, never `Path.Combine` (it gives `/` on
  macOS).

**Writing.** `XmlWriter` over a `MemoryStream` with `XmlWriterSettings { Encoding = new UnicodeEncoding(false, true),
OmitXmlDeclaration = true, Indent = false }`. The declaration `<?xml version="1.0" encoding="UTF-16"?>` (upper case; `XmlWriter`
would write `utf-16`) is written first with `WriteRaw`, after the BOM. With `Indent = false` the bytes contain no newline and are the
same on every OS. All values go through the writer (never string concatenation), so text containing `&`, `<`, `>`, `"` or `'`
round-trips.

**Build input checks.** `ArgumentException` when `Id` does not match `^[0-9]{8}-[0-9]{4}-[0-9a-f]{4}$`, `UserSid` does not match
`^S-1-[0-9]+(-[0-9]+)+$`, `PlanDir` is empty, or `Run`/`Expires` has a non-zero sub-second part (callers pass whole minutes).

**Parsing.** Detect the encoding from the bytes: `FF FE` → UTF-16 LE (skip BOM); `EF BB BF` → UTF-8 (skip BOM); else `bytes.Length
>= 2 && bytes[1] == 0` → UTF-16 LE; else UTF-8. Decode to a string, then read it with `XmlReader.Create(new StringReader(text),
new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null })`; the declaration's `encoding` value is
ignored. Any XML error, including a DOCTYPE, becomes `FormatException`.

`Parse` reads the fields into a `PlanTask`: `Id` from `Arguments`, `PlanDir` from `WorkingDirectory`, `Run`/`Expires` from the
boundaries (`DateTimeOffset.ParseExact` with the Build format and invariant culture), `Description` (missing → `""`). Child order is
not checked. The `version` attribute must be `1.2`, `1.3` or `1.4`. `FormatException` messages start with the element or attribute
local name, then `: ` (for example `AllowStartOnDemand: expected false, got true`), and are thrown when:

- namespace differs (`Task: ...`) or version is outside 1.2–1.4 (`version: ...`);
- not exactly one trigger under `Triggers`, or it is not a `TimeTrigger` (`Triggers: ...`);
- `StartBoundary` or `EndBoundary` missing or not matching `^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$` — `Z` and no-offset are both
  rejected (`StartBoundary: ...` / `EndBoundary: ...`);
- `Command` is not `<WorkingDirectory>\dirused.exe` (ordinal case-insensitive) (`Command: ...`); `Arguments` is not exactly
  `/runplan <valid id>` (`Arguments: ...`);
- `UserId` missing or not a SID (`UserId: ...`); `Actions` `Context` differs from the `Principal` `id` (`Context: ...`);
- a Settings, Principal or trigger value differs from the one listed above. **A missing element is accepted only when its schema
  default equals the required value**, because `schtasks /query /xml` omits default-valued elements (probe 2026-11-23): may be
  missing — `StartWhenAvailable`, `Hidden`, `Settings/Enabled`, trigger `Enabled`, `RunLevel` (default LeastPrivilege),
  `AllowHardTerminate`, `MultipleInstancesPolicy`; must be present — `LogonType`, `AllowStartOnDemand`,
  `DisallowStartIfOnBatteries`, `StopIfGoingOnBatteries`, `ExecutionTimeLimit`, `DeleteExpiredTaskAfter`.

`SecurityDescriptor` is **not** judged by `Parse` (the docs do not say whether `schtasks` stores it as given); M10b3 compares
`SecurityDescriptorOf` after P10. Extra elements that `schtasks /query /xml` adds (`RegistrationInfo/URI`, `Author`, `Date`,
`Settings/IdleSettings`, `Settings/Priority`, and so on) are ignored.

## Files

- `src/Dirused.Common/TaskXml.cs` (new)
- `tests/Dirused.Tests.Portable/TaskXmlTests.cs` (new)

## What NOT to Do

- No other file. No `schtasks`, process, COM, registry or file I/O; `Build`/`Parse` work on bytes only.
- No `Environment.NewLine` in the test file; compare parsed values, not raw XML text, except where a test names exact bytes.
- The X-N3 source scan finds `TaskXml.cs` by walking up from `AppContext.BaseDirectory` to the directory holding `dirused.sln`
  (or the `.sln` the repo has), then `src/Dirused.Common/TaskXml.cs`; it strips `//` comments before matching.
- Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: X-M1
    text: "Build for Run 2026-11-23T22:30:00-08:00 / Expires 2026-11-24T21:00:00-08:00, a PDT case Run 2026-06-01T22:30:00-07:00 / Expires 2026-06-02T21:00:00-07:00, and a UTC case with +00:00: bytes start FF FE; decoded text starts exactly '<?xml version=\"1.0\" encoding=\"UTF-16\"?>'; the text contains no '\\r' or '\\n'; Task has the namespace and version 1.2; Task children, TimeTrigger children, Principal children, Settings children and Exec children appear in exactly the Scope order; StartBoundary/EndBoundary text equal '2026-11-23T22:30:00-08:00' / '2026-11-24T21:00:00-08:00' (and the PDT/UTC equivalents); every Scope value present with that exact text; Command is '<PlanDir>\\dirused.exe' also when PlanDir ends with a backslash"
  - id: X-M2
    text: "Parse(Build(t)) equals t, and Parse(Build(t)).Run.Offset equals t.Run.Offset, for: the three cases above; PlanDir 'C:\\Users\\o p\\AppData\\Local\\dirused\\plans\\20261123-2230-a1b2 & \"x\" <y> \'z\''; an empty Description; a Description with '&<>'. Build(t) is byte-identical across two calls"
  - id: X-M3
    text: "Parse returns the same PlanTask for the built document re-encoded (declaration text unchanged) as UTF-16 LE without BOM, UTF-8 with BOM and UTF-8 without BOM; for a version 1.3 document; for a document with extra RegistrationInfo/URI, Author, Date, Settings/IdleSettings and Settings/Priority; for a document with children in another order; and for a document with StartWhenAvailable, Hidden, both Enabled, RunLevel, AllowHardTerminate and MultipleInstancesPolicy removed (Windows' readback form). SecurityDescriptorOf returns the built SDDL; BoundariesOf returns the two boundary strings; both return null for a missing element"
  - id: X-M4
    text: "Parse throws FormatException whose message starts with the named element or attribute for each single mutation of a built document: AllowStartOnDemand true or removed [AllowStartOnDemand]; StartWhenAvailable true [StartWhenAvailable]; LogonType Password [LogonType]; RunLevel HighestAvailable [RunLevel]; MultipleInstancesPolicy Parallel [MultipleInstancesPolicy]; ExecutionTimeLimit PT72H [ExecutionTimeLimit]; DeleteExpiredTaskAfter removed [DeleteExpiredTaskAfter]; DisallowStartIfOnBatteries removed [DisallowStartIfOnBatteries]; a second TimeTrigger [Triggers]; StartBoundary without offset and with 'Z' [StartBoundary]; EndBoundary removed [EndBoundary]; Command in another folder [Command]; Arguments '/runplan bad' [Arguments]; UserId 'Administrator' [UserId]; Context 'Other' [Context]; wrong namespace [Task]; version 1.1 [version]. A document with an extra ACE in SecurityDescriptor still parses"
  - id: X-M5
    text: "Build throws ArgumentException for Id 'bad', UserSid 'Administrator', empty PlanDir, and Run with 500 ms"
must_not:
  - id: X-N1
    text: "a PlanDir or Description containing &, <, >, \" or ' produces a document that is not well-formed or parses back different (X-M2 cases). Positive control: the plain-path case round-trips. Baseline: compile failure on 966b32b (TaskXml absent); mutant 'build Exec by string concatenation' turns it red"
  - id: X-N2
    text: "StartBoundary/EndBoundary written without offset or as 'Z' (X-M1 exact text). Mutants 'ToString(\"s\")' and 'UtcDateTime ... Z' each turn it red"
  - id: X-N3
    text: "TaskXml.cs (comments stripped) matches \\b(File|Directory|Process|Registry|Console)\\s*\\. or, case-insensitively, 'schtasks'. Positive control: mutant adding 'File.WriteAllBytes' turns the scan red"
  - id: X-N4
    text: "Parse of a document with a DOCTYPE or an internal entity returns a PlanTask (it must throw FormatException). Positive control: the same document without the DOCTYPE parses. Mutant 'DtdProcessing.Parse' turns it red"
evidence:
  - id: E-X
    proves: [X-M1, X-M2, X-M3, X-M4, X-M5, X-N1, X-N2, X-N3, X-N4]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4; TaskXmlTests do not compile on 966b32b; mutants each red with the catching test named: string concatenation [X-N1]; ToString(\"s\") boundaries [X-N2, X-M1]; XmlWriter declaration (lower-case utf-16) [X-M1]; Indent = true [X-M1]; UTF-8 output [X-M1]; Settings order swapped [X-M1]; Parse ignores AllowStartOnDemand [X-M4]; Parse accepts a second trigger [X-M4]; Parse requires StartWhenAvailable present [X-M3]; DtdProcessing.Parse [X-N4]; Path.Combine join [X-M1]"
    intent: "The scheduled task dirused writes asks Windows for exactly one run at the time you chose, as you, without admin rights, never on demand and never late — and dirused can read a task back and notice if any of that was changed."
  - id: E-XW
    proves: [X-M1, X-M2]
    kind: offline
    command: "after landing: the windows CI job on the m10b-scheduled-purge push run is green on the landed commit"
    intent: "The same tests pass on Windows, where dirused actually runs."
interface:
  - "PlanTask(Id, Run, Expires, UserSid, PlanDir, Description)"
  - "TaskXml.Build(PlanTask) -> byte[] (ArgumentException on bad input)"
  - "TaskXml.Parse(byte[]) -> PlanTask (FormatException '<element>: ...' on mismatch)"
  - "TaskXml.SecurityDescriptorOf(byte[]) -> string?"
  - "TaskXml.BoundariesOf(byte[]) -> (string? Start, string? End)"
```

## Schema facts (Microsoft Learn, fetched 2026-11-24)

Sources: https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-schema (full XSD), and the task, registrationinfo,
triggers, timetrigger, startboundary, endboundary, principals, logontype, runlevel, settings, actions and exec element pages under
https://learn.microsoft.com/en-us/windows/win32/taskschd/. Several Settings, Exec and SecurityDescriptor element pages return 404;
those items come from the XSD only.

- **Namespace:** `http://schemas.microsoft.com/windows/2004/02/mit/task` (XSD `targetNamespace`).
- **Version:** the published XSD is 1.3 (`fixed="1.3"`). The jump box's own `schtasks /query /xml` wrote `version="1.2"` (probe
  2026-11-23), so `Build` writes `1.2`; `Parse` accepts `1.2`, `1.3` and `1.4`.
- **Order (Build uses one fixed order regardless, see Scope):** Task, RegistrationInfo, Principal, Settings and Exec children are `xs:all` (any order); Actions and Triggers "can be
  added in any order". **TimeTrigger is a sequence**, and the sources disagree: the TimeTrigger page says "These elements must be
  added in the sequence shown below: StartBoundary, EndBoundary, Enabled, Repetition, ExecutionTimeLimit"; the XSD's triggerBaseType
  puts `Enabled` first. `Build` follows the page (StartBoundary, EndBoundary, Enabled). M10b3's real `schtasks /create /xml` (P1, P9)
  proves it; if refused, M10b3 switches to the XSD order. `Parse` accepts either order.
- **Values:** `LogonType` enum S4U, Password, InteractiveToken, InteractiveTokenOrPassword ("InteractiveToken: User must already be
  logged on"); `RunLevel` LeastPrivilege or HighestAvailable; `MultipleInstancesPolicy` Parallel, Queue, IgnoreNew, StopExisting;
  durations are `xs:duration` (`PT2H`, `P30D` valid); boolean defaults: AllowStartOnDemand true, StartWhenAvailable false, Hidden
  false, Enabled true, DisallowStartIfOnBatteries true, StopIfGoingOnBatteries true, Settings ExecutionTimeLimit PT72H — so every
  non-default the plan needs is written explicitly.
- **Principal:** `id` is an optional `xs:ID`; `Actions Context` is an `xs:IDREF` that must match it. `UserId` is a string; the
  jump box's readback showed the user SID there (probe 2026-11-23).
- **Not answered by the docs** (left to M10b3's probes, not to `Parse`): whether `StartBoundary`/`EndBoundary` keep a UTC offset
  after registration (P1, P9); whether `SecurityDescriptor` is stored as given or normalised (P10); the file encoding
  `schtasks /create /xml` expects (P8a).

## Review adjudication (rev 1, 2026-11-24)

Fable: READY WITH FIXES. Argon: READY WITH FIXES.

| Finding | Source | Action |
|---|---|---|
| `XmlWriter` writes lower-case `utf-16` | Argon 1, Fable 1 | Applied: OmitXmlDeclaration + WriteRaw upper-case declaration |
| Indented bytes differ by OS (`NewLineChars`) | Fable 2 | Applied: `Indent = false`; X-M1 no CR/LF; X-M2 byte-identical |
| Order unjudgeable / Argon says strict sequences | Argon 2, Fable 3 | Applied: Build emits one fixed order (Windows export order), Parse any order. Argon's "strict sequence" claim conflicts with the fetched XSD (`xs:all`); the fixed order is valid under both, M10b3's real `/create` proves it |
| Version contradiction | Fable 4 | Applied: write 1.2, accept 1.2–1.4; X-M3 1.3, X-M4 1.1 |
| Re-encoding under-specified | Fable 5 | Applied: byte sniff, decode, parse from string |
| No DTD rule on `schtasks` output | Fable 6 | Applied: DtdProcessing.Prohibit, XmlResolver null; X-N4 |
| `schtasks` readback omits default-valued elements | Fable 7 | Applied: missing accepted only when default equals required; X-M3 readback form |
| Build input validation, sub-second, Path.Combine | Fable 8, Argon 4 | Applied: X-M5; format string; literal join with TrimEnd |
| Boundary rules contradictory; `Z`; nullable helpers | Fable 9 | Applied: regex, `Z` rejected, helpers return null |
| Exception message tokens | Argon 3 | Applied: `<element>: ...`; X-M4 names each |
| Source-scan regex and path | Fable 10, Argon 5 | Applied |
| CI in offline evidence | Fable 11 | Applied: E-XW after landing |
