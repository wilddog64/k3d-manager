# dirused M6: `/file` rejects a switch as its path; update notice gains opt-out and release-notes lines

**Filed:** 2026-11-18
**Status:** LANDED — PR wilddog64/dirused#29 merged 8ccf307; released v0.0.16 (pre-release, 2 zips + sha256) 2026-11-18. Awaiting operator E2 (step 1 on v0.0.16: /file error; step 2 when v0.0.17 exists: three-line notice every run)
**Repo / branch:** wilddog64/dirused / `m6-file-notice` (from main 9d8735f)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low (one parser error message; two extra stderr lines after the existing notice line)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.

## Problem

1. Operator, 2026-11-18, ran `dirused /summary /file /html server-list.txt`. `/file` took `/html` as its path
   (`src/Dirused.Common/ArgParser.cs:106-108`), and the run failed with `Cannot read target file '/html': Could not find file
   'C:\html'` (`ArgParser.cs:237`). The message does not say that the argument order was wrong.
2. Operator, 2026-11-18: "I borrowed the idea from clink for dirused". Clink's notice also tells you how to stop the checks
   and where the release notes are. dirused prints only one line (`src/Dirused.Common/Update/UpdateCheck.cs:51`).

## Operator decision (2026-11-18)

"go ahead", on Claude's proposal: (a) `/file` followed by a switch gives `/file requires a file name`; (b) the notice gains a
"how to stop checking" line and a release-notes link.

## Change

- **`src/Dirused.Common/ArgParser.cs`, `case "file"`:** keep `/file requires a path` for a missing or blank argument. Add the
  same switch test `/output` uses (`ArgParser.cs:100`): if `args[i]` starts with `-`, or starts with `/` but not `//`, return
  `Error: $"/file requires a file name before the next switch (got '{args[i]}')"`. A UNC path (`\\host\share\list.txt`) or
  any relative or drive path is accepted as today. Same rule and same limit as `/output`: a rooted forward-slash path
  (`/lists/servers.txt`) or a file name starting with `-` must be written `\lists\servers.txt` or `.\-servers.txt`; README
  says so in one sentence next to `/file`. `//host/share/list.txt` is accepted (not a switch).
- **`src/Dirused.Common/Update/UpdateCheck.cs` `PrintNotice`:** keep the first line byte-for-byte. After it, write two lines:
  - `  To stop checking, add /noupdatecheck or set DIRUSED_NO_UPDATE_CHECK=1.`
  - `  Release notes: https://github.com/wilddog64/dirused/releases/tag/v<latest>` (e.g. `.../tag/v0.0.15`)

  All three lines go to the same `_error` writer, inside the existing once-per-version guard (printed together or not at all).
  Stdout is unchanged.
- **`README.md:137`:** after "prints a one-line notice", change to "prints a short notice (the new version, how to update,
  how to stop checking and a release-notes link) to stderr once for each newer version." Keep the rest.
- **`CHANGELOG.md` `[Unreleased]`:** "`/file` followed by another switch now says the file name is missing. The update notice
  also says how to stop checking and links the release notes."

## Tests

Portable:
- **A1 (`ArgParserTests.cs`) `FileFollowedBySwitchIsRejected`:** `["/summary", "/file", "/html", "server-list.txt"]` gives an
  Error containing `/file requires a file name` and `'/html'`; same for `["/file", "-json", "x.txt"]`. Positive control:
  write a scratch `servers.list` (one target line) under a temp dir (assert the path is under `Path.GetTempPath()`
  first); `["/file", <that path>, "/html"]` gives `Error == null`, `Options.File == <that path>`, `Options.Html == true`.
  `["/file", @"\\nohost\share\list.txt"]` and `["/file", "//nohost/share/list.txt"]` give an Error starting with
  `Cannot read target file '` (accepted as a path, then unreadable). `["/file"]` still gives `/file requires a path`.
- **U20 (`UpdateTests.cs`) `NoticeHasStopAndReleaseNotesLines`:** with the fake finding 0.0.11, after `WaitAfterReport` 
  `var lines = error.ToString().TrimEnd().Split(new[] { "\r\n", "\n" }, StringSplitOptions.None)` has exactly 3 lines,
  each equal (exact, including the two leading spaces on lines 2-3) to the three `interface:` strings with X.Y.Z = 0.0.11 and
  the fake's current version; stdout empty.
  A second check on the same state prints nothing (all three lines are suppressed together).
- Existing U2, U18, U19, W4-W6 stay green unchanged (they use `Contains`).

Red on main 9d8735f: A1 (first two asserts) and U20 fail there; paste the failing lines.

## Files

- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Common/Update/UpdateCheck.cs`
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `tests/Dirused.Tests.Portable/UpdateTests.cs`
- `README.md`
- `CHANGELOG.md`

## Contract readers

- Notice text: read by people and by `UpdateTests.cs:22,25,37,53,149` and `UpdateWiringTests.cs:21,63,67,81,96` (all `Contains` /
  `IndexOf` on the first line). The first line does not change.
- `/file` error text: grep `requires a path` in `tests/` before editing; the existing message stays for a missing or blank
  argument. `/output` (`ArgParser.cs:100`, `ArgParserTests.cs:77-79`) is the precedent and is unchanged.

## What NOT to Do

- Do not change the first notice line, the once-per-version rule, the daily throttle, `/update` or exit codes.
- Do not change how `/output` or other switches parse; do not reject `//` or `\\` paths.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "`/file` followed by a switch (`-x`, or `/x` but not `//`) fails with '/file requires a file name before the next switch (got '<arg>')'"
  - id: M2
    text: the update notice prints the existing line, then a stop-checking line and a release-notes link for that version, on stderr, once per version
must_not:
  - id: N1
    text: "`/file /html x.txt` tries to read a file named /html — red today (A1)"
  - id: N2
    text: "the notice lacks the stop-checking and release-notes lines — red today (U20)"
  - id: N3
    text: "`/file servers.list /html` or a UNC path is rejected by the new check (A1 positive controls)"
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    command: portable suite (A1, U20) locally and on PR CI; A1 and U20 red on 9d8735f
    intent: Putting /file in the wrong place now tells you so, and the update message says how to turn it off and where to read what changed.
  - id: E2
    proves: [M1, M2]
    kind: live
    command: "operator, work laptop, on the release with this change: `dirused /summary /file /html server-list.txt` shows the new error; after Claude publishes the next release, a bare `dirused` shows the three-line notice"
    intent: On your laptop, the wrong /file order gives a clear message, and the next update notice looks like Clink's.
interface:
  - "/file requires a file name before the next switch (got '/html')"
  - "  To stop checking, add /noupdatecheck or set DIRUSED_NO_UPDATE_CHECK=1."
  - "  Release notes: https://github.com/wilddog64/dirused/releases/tag/vX.Y.Z"
```

## Amendment 1 (Claude, 2026-11-18, blind Argon review)

1. Rooted `/`-paths and `-`-names: kept the `/output` rule (consistency), documented the `\` / `.\` workaround, added a `//host` positive control.
2. A1 positive controls strengthened: a real scratch file gives no error and sets `File`; unreadable UNC paths fail with `Cannot read target file`.
3. U20 splits on `\r\n` or `\n` after `TrimEnd`, asserts 3 exact lines (Windows-safe).
4. Contract readers add `UpdateWiringTests.cs:81,96`.

## Amendment 2 (operator, 2026-11-18, after dispatch): notice on every run until updated

Operator: "basically show each run until updated or give /noupdatecheck to stop it". This reverses the M4b once-per-version rule.

- **`UpdateCheck.cs` `PrintNotice`:** remove the `state.NoticedVersion == latestVersion` early return and stop writing
  `NoticedUtc`/`NoticedVersion` (no `TryWrite` in `PrintNotice`). Keep both fields in `UpdateState.cs` untouched so old state
  files still read. The notice prints whenever cached `Latest` is newer than the running version: on every scan, bare run and
  `/help`, including runs inside the 24 h lookup throttle (they use the cached `Latest`, `UpdateCheck.cs:19-23`). It stops by
  itself after `/update` (version no longer older). Opt-outs unchanged.
- **Tests that asserted silence on a repeat (now assert the notice again):** `UpdateTests.cs` U2 (rename
  `U2_NoticeIsStderrOnlyAndRepeatsUntilUpdated`; same 0.0.11 after 24 h prints again, `FindCalls == 2`; plus a run 1 h later
  with `FindCalls` unchanged still prints, from cache), U18 (rename `U18_NoticeRepeatsAcrossRestart`; second checker prints
  again), U19 (old state file reads and announces), U20 (second check on the same state prints the three lines again);
  `tests/Dirused.Tests/UpdateWiringTests.cs` W4 (second bare run prints the usage **and** the notice again).
- **New U21 `NoticeStopsOnceUpToDate`:** state `Latest = 0.0.11`, running version 0.0.11: no notice (positive control:
  running version 0.0.10 on the same state prints it).
- **README.md:137 / CHANGELOG:** "prints a short notice ... to stderr on each run while a newer version exists; stop it with
  `/noupdatecheck` or `DIRUSED_NO_UPDATE_CHECK=1`." CHANGELOG adds "The update notice now repeats on each run until you
  update (was once per version)."
- **Files added:** `tests/Dirused.Tests/UpdateWiringTests.cs` (land with `--allow-out-of-scope`, recorded: the dispatch-time
  snapshot predates this amendment).
- **Acceptance change:** M2 becomes "... on stderr on every run while a newer version exists"; new must_not N4: "the same
  version is announced only once (red on 9d8735f: U2/U18/W4 repeat asserts)"; new must_not N5: "a notice appears when the
  running version equals Latest (U21)".

**Intent approved:** operator, 2026-11-18
**Intent approval note:** Amendment 2 approved by operator answer "basically show each run until updated or give /noupdatecheck to stop it" (2026-11-18). Original: "go ahead" (approving Claude's proposal in chat: /file-followed-by-switch error, plus Clink-style stop-checking and release-notes lines)

## Verification (Claude, 2026-11-18)

- Blind Argon diff review of PR #29: NONE.
- Red on 9d8735f: A1, U2, U18, U19, U20. U21 is a regression guard (passes on old code too, as expected).
