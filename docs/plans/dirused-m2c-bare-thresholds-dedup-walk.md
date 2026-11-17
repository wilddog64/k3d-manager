# dirused M2c — bare `/warn` and `/crit` use their defaults; one top-folder walk per volume

**Filed:** 2026-11-17
**Status:** ready for dispatch
**Repo / branch:** wilddog64/dirused / `m2c-bare-thresholds` (from main 2ced52d)
**Tracked:** separately from k3d-manager releases. This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low
**Implementer:** Luna (Codex). **Verifier:** Claude. Live run by the operator at the office.

## Problem

1. Operator, 2026-11-17, on a Windows PC: `dirused /summary /crit /warn /file servers.list` fails with
   `/crit requires an integer between 1 and 100`. `ArgParser` (`src/Dirused.Common/ArgParser.cs:83-88`) always takes the
   next argument as the number, so here `/crit` swallows `/warn`. The operator wants a bare `/warn` or `/crit` to mean its
   default (85 and 90). `/deep` already takes an optional number (`:89-100`: it takes the next argument only when that
   argument is all ASCII digits).
2. From the blind Argon review of PR #15 (verified by Claude): `TopFolders.Attach` (`src/Dirused.Common/TopFolders.cs`) walks
   every warn/crit target. `SummaryRenderer.Prepare` (`src/Dirused.Common/Renderers/SummaryRenderer.cs:32-50`) then keeps
   only the first target per volume (key: host plus serial number, or host plus drive when the serial number is 0).
   `JsonRenderer(summary: true)` does the same. So `dirused C:\ C:\sub /summary` on a crit volume walks twice, for up to
   60s each, and throws one result away.

## Change

1. `ArgParser`, `warn` and `crit` cases: take the next argument as the number only when it is non-empty and all ASCII
   digits (the same test `/deep` uses). In that case keep today's range check and error text
   (`/warn requires an integer between 1 and 100`; same for `/crit`). Otherwise keep the default (85 or 90) and do not
   consume the next argument. The `/warn must be below /crit` check is unchanged.
2. Usage text, in `ShortUsageText`, `UsageText` and `README.md`:
   - `[/warn <1-100>] [/crit <1-100>]` becomes `[/warn [1-100]] [/crit [1-100]]`;
   - `/warn <n>` becomes `/warn [n]`, and `/crit <n>` becomes `/crit [n]`;
   - the descriptions stay `(default: 85)` and `(default: 90)`.
   Keep the column alignment.
3. Make volume-key logic shared. Move the key from `Prepare` into an `internal static string VolumeKey(ScanResult r)` on
   `SummaryRenderer`, keeping the same key text. `Prepare` uses it.
4. `TopFolders.Attach`: of the warn/crit targets, walk only the first one per `VolumeKey`, in results order. Any later
   target with the same key keeps its result unchanged: no second walk, no `Directories`, no note. A target that is not
   `Complete` has no level, so it is never walked (unchanged).
5. `tools/live-check.ps1`: new `L14` after `L13`.
   - Text: `'bare /warn and /crit use defaults 85 and 90'`.
   - Run: `Invoke-Dirused @('C:\Windows\Web', '/summary', '/crit', '/warn')`.
   - Pass when `rc -in 0,4` and `out -match '1 volume\(s\): \d+ at or above 90%, \d+ at or above 85%'`.
   - `tools/PACKAGE-README.txt`: `L1-L13` becomes `L1-L14`, in both places.

## Tests (portable)

`tests/Dirused.Tests.Portable/ArgParserTests.cs`:
- A1 `C:\ /crit /warn` gives Warn 85, Crit 90, targets `[C:\]`, no error.
- A2 `/summary /crit /warn /file servers.list` gives Warn 85, Crit 90, File `servers.list`, Summary true. This is the
  operator's command.
- A3 `/warn C:\` gives Warn 85 and target `C:\`, which is not consumed.
- A4 positive control: `/warn 70 /crit 80 C:\` gives 70 and 80.
- A5 `/crit 150` still errors `/crit requires an integer between 1 and 100`.
- A6 `/crit /warn 95` errors `/warn must be below /crit`.

`tests/Dirused.Tests.Portable/TopFoldersTests.cs`:
- T7 two crit targets with the same `Volume.SerialNumber` and host, plus a third crit target on a different serial number:
  exactly 2 walks (the first and the third). The second result keeps empty `Directories` and a null `TopFoldersNote`.
- T8 positive control: two crit targets with different serial numbers both get walked.
- T9 two crit targets with serial number 0 and the same drive and host are walked once.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/ArgParser.cs` | Changes 1-2 |
| `README.md` | Change 2 |
| `src/Dirused.Common/Renderers/SummaryRenderer.cs` | Change 3 |
| `src/Dirused.Common/TopFolders.cs` | Change 4 |
| `tools/live-check.ps1`, `tools/PACKAGE-README.txt` | Change 5 |
| `tests/Dirused.Tests.Portable/ArgParserTests.cs`, `tests/Dirused.Tests.Portable/TopFoldersTests.cs` | Tests |

## Contract readers

- `Options.Warn` and `Options.Crit` are read by `Program.cs:33,40,41` and the renderers. Their values are unchanged.
- `Prepare` is called by `SummaryRenderer.Render` and `JsonRenderer`. Its behaviour is unchanged (same key).
- The usage text is asserted in `tests/Dirused.Tests.Portable/ArgParserTests.cs` and Windows `tests/Dirused.Tests`.
  Run `grep -rn "warn <" tests` and update every assertion that matches the old text.

## What NOT to Do

- Do NOT change any exit code, renderer output, or any other switch.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Keep the existing style. LF line endings. No refactors beyond Change 3.

## Gates

- `dotnet build -m:1 -p:NuGetAudit=false`: 0 errors, 0 new warnings.
- `dotnet test tests/Dirused.Tests.Portable -c Release -m:1 -p:NuGetAudit=false`: all pass. Paste the summary line.
- pwsh parse check of `tools/live-check.ps1` prints `0`:
  `pwsh -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path tools/live-check.ps1), [ref]$null, [ref]$e); $e.Count'`.
- `git diff --check` is clean.

## Definition of Done

- [ ] Changes 1-5 and tests A1-A6, T7-T9 are done, and `git status` shows only files from the Files table.
- [ ] Gate output is pasted into the report, along with a diff summary. Nothing is committed.

## Acceptance

```yaml
must:
  - id: M1
    text: a bare /warn or /crit means 85 or 90 and leaves the next argument alone; a number after it still sets it
  - id: M2
    text: out-of-range numbers and /warn >= /crit are still refused with today's messages
  - id: M3
    text: in a /summary run, a warn/crit volume named by several targets is walked once
must_not:
  - id: N1
    text: "dirused /summary /crit /warn /file servers.list fails with a usage error — red today (A2)"
  - id: N2
    text: two targets on the same warn/crit volume trigger two folder walks — red today (T7)
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    command: portable tests A1-A6; A2 and A1 red on main 2ced52d
    intent: The command you typed at work runs, using the default levels.
  - id: E2
    proves: [M3, N2]
    kind: offline
    command: portable tests T7-T9; T7 red on main 2ced52d
    intent: A server list that names the same disk twice does not scan it twice.
  - id: E3
    proves: [M1]
    kind: live
    command: "operator, office: live-check.ps1 -Targets fleet.txt — L1-L14 and F1-F2 PASS"
    intent: One office run proves the bare switches work on Windows.
interface:
  - "/warn [1-100], /crit [1-100]: a bare switch uses 85 / 90"
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "/crit and /warn without numbers should use default values" (operator, 2026-11-17, with a
screenshot of the error); Argon finding 2 of PR #15, deferred to M2c by Claude and reported to the operator.
