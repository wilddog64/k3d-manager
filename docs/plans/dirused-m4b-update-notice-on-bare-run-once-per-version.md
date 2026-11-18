# dirused M4b: update notice on a bare run and `/help`, once per new version

**Filed:** 2026-11-18
**Status:** LANDED 442c259 (PR #27, CI green, blind Argon review: no findings); awaiting operator merge, then v0.0.13 / v0.0.14 for E2
**Repo / branch:** wilddog64/dirused / `m4b-notice-once` (from main 568a829)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low (stderr notice timing and state only; scan output, exit codes and `/update` unchanged)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.
**Depends on:** `docs/plans/dirused-m4-update-notice-and-self-update.md` (landed, v0.0.11)

## Problem

Operator, 2026-11-18, after `/update` took v0.0.11 to v0.0.12: "can we trigger the check when executing dirused, and ask
to execute dirused /update if there is a new version ... print to console v0.0.12 is available, run dirused /update.
only once."

Today (`src/Dirused.Cli/Program.cs` on 568a829) the check starts only on the scan path (`:63-67`). A bare `dirused`
returns the short usage error at `:35` (`ArgParser.cs:168`, exit 1) and `/help` returns at `:34`, both before any check.
The notice repeats every 24 hours for the same version (`UpdateCheck.cs:49`, `NoticedUtc`).

## Operator decision (2026-11-18)

"go with your suggestion":
1. A bare `dirused` (no arguments) and `/help` also start the update check and print the notice.
2. Each newer version is announced once. The next notice comes only when an even newer version is found.

## Change

- **`src/Dirused.Cli/Program.cs`:** move the check start (the condition and `new UpdateCheck(...)` at `:63-67`) into one
  private helper used by three paths: the scan path (as today), `args.Length == 0` (the bare run, which still prints
  `ShortUsageText` to `error` and returns 1), and `parsed.Usage` (`/help`, `-h`, `/?`, which still prints `UsageText` to
  `output` and returns 0). On the two new paths, start the check before printing the usage, then call
  `WaitAfterReport(check, TimeSpan.FromSeconds(1))` after printing it, so the notice line comes after the usage text.
  Other usage errors (e.g. `/json /csv` with a target, an unknown switch) do not check. The same opt-outs apply:
  `DIRUSED_NO_UPDATE_CHECK=1`, a non-numeric version, no release source (`Program.Run`). `/noupdatecheck` with `/help`
  also suppresses it. `/version` and `/update` are unchanged.
- **`src/Dirused.Common/Update/UpdateState.cs`:** add `string? NoticedVersion` (keep `NoticedUtc` so existing state files
  still read; it is no longer used for the rule).
- **`src/Dirused.Common/Update/UpdateCheck.cs` `PrintNotice`:** replace the 24-hour `NoticedUtc` rule with: skip when
  `state.NoticedVersion` equals the latest version string; otherwise print the same line as today and write
  `NoticedVersion = <latest>`. The daily lookup throttle (`AttemptedUtc`, 24 h) is unchanged, so a new release is found
  within a day and announced on the run after that if the 1 s grace ran out.
- **`README.md:119`:** "dirused checks GitHub at most once a day on a scan, a bare `dirused` or `/help`, and prints a
  one-line notice to stderr once for each newer version." Keep the rest of the paragraph.
- **`CHANGELOG.md` `[Unreleased]`:** "Update notice also appears on a bare `dirused` and `/help`, once per new version."

## Tests

Portable (`tests/Dirused.Tests.Portable/UpdateTests.cs`):
- **U2** (`:19`): its third block (after 24 h, same 0.0.11 found) now asserts `FindCalls == 2` and **no** notice; then set
  the fake's `Package` to a 0.0.12 package, advance another 24 h + 1 s, run the check and `WaitAfterReport`: the error
  contains `dirused 0.0.12 is available` (positive control). Rename to `U2_NoticeIsStderrOnlyOncePerVersion`.
- **U18_NoticeOncePerVersionSurvivesRestart:** one checker announces 0.0.11; a new checker on the same state path, 48 h
  later, finds 0.0.11 again and prints nothing; `NoticedVersion` in the state file is `0.0.11`.
- **U19_OldStateFileStillReads:** a state file written as `{"AttemptedUtc":...,"Latest":"0.0.11","NoticedUtc":...}`
  (no `NoticedVersion`) reads without error and announces 0.0.11 once.

Windows (`tests/Dirused.Tests/UpdateWiringTests.cs`, scratch state path asserted under the temp dir, env var saved and
restored as W1 does):
- **W4_BareRunShowsUsageThenNotice:** `RunWithReleaseSource(Array.Empty<string>(), ...)` returns 1; `error` contains
  `Run dirused /help for more.` and then (higher index) `dirused 0.0.11 is available`; `FindCalls == 1`;
  `DownloadCalls == 0`. A second bare run on the same state prints the usage and no notice.
- **W5_HelpShowsNotice:** `["/help"]` returns 0, `output` contains the usage, `error` contains the notice.
- **W6_OtherUsageErrorsAndOptOutsDoNotCheck:** `["/json", "/csv", scratch]` returns 1 with `FindCalls == 0`;
  `["/help", "/noupdatecheck"]` returns 0 with `FindCalls == 0` (if `ArgParser` rejects that combination, assert the
  return code it gives and still `FindCalls == 0`); a bare run with `DIRUSED_NO_UPDATE_CHECK=1` has `FindCalls == 0`
  and no notice.
- W1-W3 unchanged and passing; W2 still proves `Program.Run` never calls the source.

Red on main 568a829: U2 (renamed), U18, W4 and W5 fail there; paste the failing lines (W4/W5 from Windows CI on the PR
if they cannot run locally).

## Files

- `src/Dirused.Cli/Program.cs`
- `src/Dirused.Common/Update/UpdateCheck.cs`
- `src/Dirused.Common/Update/UpdateState.cs`
- `tests/Dirused.Tests.Portable/UpdateTests.cs`
- `tests/Dirused.Tests/UpdateWiringTests.cs`
- `README.md`
- `CHANGELOG.md`

## Contract readers

- State file `%LOCALAPPDATA%\dirused\update-check.json`: writer and reader `UpdateState.cs` only (`UpdateCheck.cs:18,26,33,51`).
  Adding a nullable field keeps old files readable (U19). `SelfUpdater` does not read it (grep `UpdateState` before editing; list any other reader here).
- Notice text: read by people and by `UpdateTests.cs`/`UpdateWiringTests.cs` (`is available`). Unchanged.
- Usage text and exit codes of a bare run (1) and `/help` (0): read by `ArgParserTests.cs:142`, `FleetRunnerTests.cs:226`. Unchanged.

## What NOT to Do

- Do not change the notice wording, the 1 s grace, the daily lookup throttle, `/update`, `/version`, scan output or exit codes.
- Do not check on usage errors other than the bare run, or print anything to stdout.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Known limitation (Claude, at verify, 2026-11-18)

`UpdateCheck.CheckAsync` writes `AttemptedUtc` before the lookup. On a bare run the process exits after the 1 s grace; if
the lookup is slower than that, it is cut off, `Latest` is never stored, and the daily throttle skips lookups for 24 h.
The notice then appears on the first scan or bare run after that day, not "the next run" as first stated. Pre-existing
in M4 (scans hit it rarely because they take longer). Not blocking; fix if E2 shows it (e.g. write `AttemptedUtc` only
after the lookup finishes, or retry within the day when `Latest` is missing).

## Acceptance

```yaml
must:
  - id: M1
    text: a bare `dirused` prints the short usage, then the update notice on stderr when a newer release exists, exit 1 as today
  - id: M2
    text: "`dirused /help` prints the usage, then the notice on stderr, exit 0 as today"
  - id: M3
    text: each newer version is announced once, across runs and restarts; a still newer version is announced again
  - id: M4
    text: opt-outs (/noupdatecheck, DIRUSED_NO_UPDATE_CHECK=1) and Program.Run still make no release lookup
must_not:
  - id: N1
    text: "a bare run makes no release lookup and prints no notice — red today (W4)"
  - id: N2
    text: "the same version is announced again 24 h later — red today (U2, U18)"
  - id: N3
    text: "a usage error other than the bare run (e.g. /json /csv) starts a release lookup (W6)"
  - id: N4
    text: "an existing state file without NoticedVersion fails to read or blocks the notice (U19)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    command: portable suite (U2, U18, U19) locally; Windows CI on the PR for W4-W6 (U2, U18, W4, W5 red on 568a829)
    intent: Typing just `dirused` tells you when a new version is out, and it tells you once, not every day.
  - id: E2
    proves: [M1, M3]
    kind: live
    command: "operator, work laptop: install the release with this change (N), Claude publishes N+1, then delete update-check.json and run bare `dirused` twice: the first run shows the usage and 'dirused <N+1> is available ... Run: dirused /update', the second shows the usage only"
    intent: On your laptop, a bare run announces the new version once and then stays quiet.
interface:
  - "stderr after usage: dirused X.Y.Z is available (you have A.B.C). Run: dirused /update"
```

**Intent approved:** operator, 2026-11-18
**Intent approval note:** "go with your suggestion" (approving the M4b proposal as stated in chat: bare run and /help check, once per version)
