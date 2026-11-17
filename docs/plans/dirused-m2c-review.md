# Review: dirused PR #17 (M2c bare thresholds, one walk per volume) — blind diff review

**Filed:** 2026-11-17
**Repo / branch:** `dirused` / `m2c-bare-thresholds` (head 18ed937; diff `2ced52d..18ed937`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff 2ced52d..18ed937` blind. Intended behaviour:

- `/warn` and `/crit` take the next argument as the number only when it is non-empty and all ASCII digits (the `/deep`
  rule). Then today's range check and error text apply. Otherwise the default (85 / 90) is kept and the next argument is
  not consumed. `/warn must be below /crit` is unchanged.
- Usage text and README show `[/warn [1-100]] [/crit [1-100]]`, `/warn [n]`, `/crit [n]`, with column alignment kept.
- `SummaryRenderer.VolumeKey(ScanResult)` holds the key `Prepare` used before (host plus serial number, or host plus
  drive when the serial number is 0), with identical key text. `Prepare` uses it.
- `TopFolders.Attach` walks only the first warn/crit target per `VolumeKey`, in results order. Later targets on the same
  key keep their result unchanged (no walk, no `Directories`, no note).
- live-check `L14`: `C:\Windows\Web /summary /crit /warn` passes on rc 0 or 4 and the footer
  `1 volume(s): \d+ at or above 90%, \d+ at or above 85%`. PACKAGE-README says L1-L14.

Look for:
- an argument that is digits-like but not ASCII digits, an empty string, or a negative number handled differently from spec;
- a target name made only of digits after `/warn` (e.g. a folder named `95`), and whether the docs say what happens;
- the key text changing so `Prepare` dedups differently from before;
- the dedup in `Attach` skipping a target that is the first on its volume, or pairing walks with the wrong result index;
- tests that assert parallel finish order or share an unsynchronised collection across workers;
- tests that cannot fail;
- usage text, README or PACKAGE-README disagreeing with the code;
- L14's regex matching something it shouldn't.

## Before You Start

1. Read `src/Dirused.Common/ArgParser.cs`, `src/Dirused.Common/TopFolders.cs`,
   `src/Dirused.Common/Renderers/SummaryRenderer.cs`, `src/Dirused.Common/Renderers/JsonRenderer.cs`, `README.md`,
   `tools/live-check.ps1`, `tools/PACKAGE-README.txt` and the changed tests.
2. `git log --oneline -3` and confirm HEAD is 18ed937.

## Files

| File | Change |
|---|---|
| `src/Dirused.Common/ArgParser.cs` | read only |
| `src/Dirused.Common/TopFolders.cs` | read only |
| `src/Dirused.Common/Renderers/SummaryRenderer.cs` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT run tests that need Windows; reason from the code. `dotnet test tests/Dirused.Tests.Portable -m:1 -p:NuGetAudit=false` may be run.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back one line per finding: `file:line — defect — concrete failure scenario — severity (high/medium/low)`.
      If there are none, report `no findings`. Mark each finding as verified-from-code or speculative.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report lists findings or "no findings"
    intent: An independent model checks the bare-switch change before you try it at the office.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "/crit and /warn without numbers should use default values" (M2c); dirused PRs get a blind Argon review per the PR review budget.
