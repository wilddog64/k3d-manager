# dirused M10b2a: `TaskXml` — build and parse the scheduled task's XML (pure, no scheduler)

**Status:** OPEN — SPEC rev 1, 2026-11-24; intents approved; Fable + Argon blind reviews before dispatch
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
    public static string? SecurityDescriptorOf(byte[] bytes);
    public static (string Start, string End) BoundariesOf(byte[] bytes);
}
```

`Build` writes a Task Scheduler 1.2 document (namespace `http://schemas.microsoft.com/windows/2004/02/mit/task`, `version="1.2"`,
declaration `<?xml version="1.0" encoding="UTF-16"?>`), elements in the schema's required order (see "Schema facts"):

- `RegistrationInfo`: `Description` (the task's description, may be empty element), `SecurityDescriptor`
  `D:P(A;;FA;;;<UserSid>)(A;;FA;;;SY)(A;;FA;;;BA)`.
- `Triggers`: exactly one `TimeTrigger` with `StartBoundary` = `Run` and `EndBoundary` = `Expires`, both
  `yyyy-MM-ddTHH:mm:ss` plus the instant's own offset (`-08:00`, `-07:00`, `+00:00` — never `Z`, never local without offset), and
  `Enabled` `true`.
- `Principals`: one `Principal` `id="Author"` with `UserId` = `UserSid`, `LogonType` `InteractiveToken`, `RunLevel` `LeastPrivilege`.
- `Settings`: `MultipleInstancesPolicy` `IgnoreNew`, `DisallowStartIfOnBatteries` `false`, `StopIfGoingOnBatteries` `false`,
  `AllowHardTerminate` `true`, `StartWhenAvailable` `false`, `AllowStartOnDemand` `false`, `Enabled` `true`, `Hidden` `false`,
  `ExecutionTimeLimit` `PT2H`, `DeleteExpiredTaskAfter` `P30D`.
- `Actions Context="Author"`: one `Exec` with `Command` `<PlanDir>\dirused.exe`, `Arguments` `/runplan <Id>`, `WorkingDirectory`
  `<PlanDir>`.

All text goes through an XML writer (`XmlWriter` with `Encoding = new UnicodeEncoding(false, true)`, indent allowed), never string
concatenation, so `&`, `<`, `>`, `"` and `'` in `PlanDir` or `Description` are escaped.

`Parse` reads the same fields back into a `PlanTask`: `Id` from the `/runplan <id>` argument, `PlanDir` from `WorkingDirectory`,
`Run`/`Expires` as instants (`DateTimeOffset.Parse` with invariant culture). It throws `FormatException` with a message naming the
first missing or unexpected field when: the namespace or version differs; there is not exactly one `TimeTrigger`; `Command` is not
`<WorkingDirectory>\dirused.exe`; `Arguments` is not `/runplan <id>` with a valid id; `UserId` is not a SID; any Settings or
Principal value above differs (for example `AllowStartOnDemand` `true`, `LogonType` `Password`, `RunLevel` `HighestAvailable`,
`StartWhenAvailable` `true`); or the `Actions Context` does not match the Principal `id`. Two fields are **not** judged by `Parse`, because the docs
do not say how `schtasks` stores them: `SecurityDescriptor` (returned by `TaskXml.SecurityDescriptorOf(bytes)`, a string or null)
and a boundary without offset (`Parse` returns it as given via `TaskXml.BoundariesOf(bytes)` → `(string start, string end)`, and
parses `Run`/`Expires` only when an offset is present; with no offset it throws `FormatException("StartBoundary has no offset")`).
M10b3 decides the compare after P1, P9 and P10. Unknown extra elements that `schtasks /query /xml` adds (for example `RegistrationInfo/URI`, `Author`, `Date`,
`Settings/IdleSettings`, `Settings/Priority`) are ignored.

## Files

- `src/Dirused.Common/TaskXml.cs` (new)
- `tests/Dirused.Tests.Portable/TaskXmlTests.cs` (new)

## What NOT to Do

- No other file. No `schtasks`, process, COM, registry or file I/O; `Build`/`Parse` work on bytes only.
- No `Environment.NewLine` in the test file; compare parsed values, not raw XML text, except where a test names exact bytes.
- Leave changes uncommitted; do not push.

## Acceptance

```yaml
must:
  - id: X-M1
    text: "Build for Run 2026-11-23T22:30:00-08:00, Expires 2026-11-24T21:00:00-08:00 (and a PDT case 2026-06-01T22:30-07:00, and a UTC +00:00 case): bytes start FF FE; decoded text starts '<?xml version=\"1.0\" encoding=\"UTF-16\"?>'; the Task element has the namespace and version 1.2; TimeTrigger children in the order StartBoundary, EndBoundary, Enabled; StartBoundary and EndBoundary text end with the exact offset ('-08:00', '-07:00', '+00:00'); every element and value listed in Scope is present with that exact text, in the order Schema facts gives"
  - id: X-M2
    text: "Parse(Build(t)) equals t (record equality) for: the three cases above; a PlanDir 'C:\\Users\\o p\\AppData\\Local\\dirused\\plans\\20261123-2230-a1b2 & \"x\" <y> \\'z\\''; an empty Description; a Description with '&<>'"
  - id: X-M3
    text: "Parse accepts the same document re-encoded as UTF-16 LE without BOM and as UTF-8 with and without BOM, and a document with extra RegistrationInfo/URI, Author, Date, Settings/IdleSettings and Settings/Priority elements, and returns the same PlanTask"
  - id: X-M4
    text: "Parse throws FormatException naming the field for each single mutation of a built document: AllowStartOnDemand true; StartWhenAvailable true; LogonType Password; RunLevel HighestAvailable; MultipleInstancesPolicy Parallel; ExecutionTimeLimit PT72H; DeleteExpiredTaskAfter removed; a second TimeTrigger; StartBoundary without offset; Command in another folder; Arguments '/runplan bad'; UserId 'Administrator'; Actions Context not matching the Principal id; wrong namespace; and SecurityDescriptorOf returns the built SDDL exactly while a document with an extra ACE still parses (SD is not judged by Parse)"
must_not:
  - id: X-N1
    text: "a PlanDir or Description containing &, <, >, \" or ' produces a document that is not well-formed or parses back different (the X-M2 cases). Positive control: the plain-path case round-trips. Baseline: compile failure on 966b32b (TaskXml absent); mutant 'build with string concatenation' turns it red"
  - id: X-N2
    text: "StartBoundary/EndBoundary written in machine-local time without offset or as UTC 'Z' (X-M1 exact offset text). Baseline: mutant 'ToString(\"s\")' turns it red"
  - id: X-N3
    text: "TaskXml.cs references File, Directory, Process, Registry, Console or any schtasks string (source scan in TaskXmlTests). Positive control: mutant adding 'File.WriteAllBytes' turns the scan red"
evidence:
  - id: E-X
    proves: [X-M1, X-M2, X-M3, X-M4, X-N1, X-N2, X-N3]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable on m4, and the windows CI job on the integration branch head; TaskXmlTests do not compile on 966b32b; mutants each red: string concatenation; ToString(\"s\") boundaries; UTF-8 output; Settings order swapped; Parse ignores AllowStartOnDemand; Parse accepts a second trigger"
    intent: "The scheduled task dirused writes asks Windows for exactly one run at the time you chose, as you, without admin rights, never on demand and never late — and dirused can read a task back and notice if any of that was changed."
interface:
  - "PlanTask(Id, Run, Expires, UserSid, PlanDir, Description)"
  - "TaskXml.Build(PlanTask) -> byte[]"
  - "TaskXml.Parse(byte[]) -> PlanTask (FormatException on mismatch)"
  - "TaskXml.SecurityDescriptorOf(byte[]) -> string?"
  - "TaskXml.BoundariesOf(byte[]) -> (string Start, string End)"
```

## Schema facts (Microsoft Learn, fetched 2026-11-24)

Sources: https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-schema (full XSD), and the task, registrationinfo,
triggers, timetrigger, startboundary, endboundary, principals, logontype, runlevel, settings, actions and exec element pages under
https://learn.microsoft.com/en-us/windows/win32/taskschd/. Several Settings, Exec and SecurityDescriptor element pages return 404;
those items come from the XSD only.

- **Namespace:** `http://schemas.microsoft.com/windows/2004/02/mit/task` (XSD `targetNamespace`).
- **Version:** the published XSD is 1.3 (`fixed="1.3"`). The jump box's own `schtasks /query /xml` wrote `version="1.2"` (probe
  2026-11-23), so `Build` writes `1.2`; `Parse` accepts `1.2`, `1.3` and `1.4`.
- **Order:** Task, RegistrationInfo, Principal, Settings and Exec children are `xs:all` (any order); Actions and Triggers "can be
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
