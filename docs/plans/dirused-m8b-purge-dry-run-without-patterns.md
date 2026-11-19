# dirused M8b: `/purge` dry run works without `/largest` patterns; only `/confirm` needs them

**Filed:** 2026-11-19
**Status:** READY — operator said dispatch to Luna, 2026-11-19
**Repo / branch:** wilddog64/dirused / `m8b-purge-dry-run` (from main fa3a07c, M8 merge)
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Bug:** `docs/dirused/bugs/2026-11-19-dirused-purge-dry-run-refuses-without-pattern.md` (P3)
**Risk:** medium (it loosens a guard on the delete feature; the delete path must stay exactly as guarded as in M8)
**Implementer:** Luna (Codex). **Verifier:** Claude. Live check by the operator on the work laptop.
**Intent approved:** operator, 2026-11-19
Intent note: operator read the proposed change in the bug doc and replied "go ahead to dispatch this to Luna" (2026-11-19).

## Problem

Operator, 2026-11-19, dirused 0.0.18:

```
dirused /top 3 /warn 30 /crit 45 /html /file server-list.txt /largest /purge
/purge requires /largest with file patterns, e.g. /largest *.log
```

"user might not know what need to be deleted in the first place until they saw the report". A run without `/confirm` is a dry
run that deletes nothing (M8), but `ArgParser.cs:222-224` refuses it anyway when the pattern list is missing, match-all, or
starts with `+`.

## Change

1. **`src/Dirused.Common/ArgParser.cs:222-224`:** the three refusals apply only when `confirm` is true. New messages:
   - no pattern (`!largestExplicit`): `"/purge /confirm requires /largest with file patterns, e.g. /largest *.log"`
   - match-all: `"/purge /confirm cannot be used with a match-all pattern; name the file types to delete, e.g. /largest *.log"`
   - `+` list: `"/purge /confirm needs the full pattern list; '+' adds to the default list, e.g. write /largest *.log;*.zip"`

   `"/purge requires /largest"` (line 220, no `/largest` at all) is unchanged and still applies with or without `/confirm`.
   Every other `/purge` check (days, `/minsize`, `/summary /csv`, purge log, Windows only) is unchanged.
2. **`src/Dirused.Common/Options.cs`:** append `bool PurgeNeedsPatterns = false` at the end of the positional record.
   `ArgParser` sets it to true when `purge && !confirm` and any of the three refusals above would have fired.
3. **`src/Dirused.Cli/Program.cs:129`:** when `options.PurgeNeedsPatterns`, the dry-run summary line ends with
   `" To delete, rerun with /largest <patterns> /purge /confirm, e.g. /largest *.log"` in place of
   `" Add /confirm to delete them."`. The counts portion of the line is unchanged.
4. **Help (`ArgParser.cs:56`):** `"Needs /largest with file patterns. Without /confirm"` becomes text saying patterns are needed
   only with /confirm, and that without patterns the dry run lists what /largest finds. Keep the 80-column layout.
   `ShortUsageText` line 19 becomes `[/largest [<patterns>] [/purge [days] [/minsize <size>] [/confirm]]]`.
5. **`README.md` and `CHANGELOG.md` `[Unreleased]`:** one line each on the change.

## Tests

- `tests/Dirused.Tests.Portable/ArgParserTests.cs:59-63`: the existing assertions for `/largest /purge`, each match-all
  pattern and `+*.zip` without `/confirm` become `Assert.Null(...Error)` with `PurgeNeedsPatterns == true`; the same arguments
  plus `/confirm` assert the new messages. `/largest catalina.out /purge /confirm` asserts the no-pattern message. A positive
  control: `/largest *.log /purge` has `PurgeNeedsPatterns == false`, and `/largest *.log /purge /confirm` parses with no error.
- `tests/Dirused.Tests/ProgramPurgeTests.cs` (Windows CI): `/largest /purge` on a fixture tree with an old 2 GB-reported file
  exits 0, reports it `would delete`, prints the new hint, and leaves the tree hash unchanged; `/largest * /purge /confirm`
  exits 1 with the match-all message and leaves the tree hash unchanged; the purge log is not created by either run.

## Files

- `src/Dirused.Common/ArgParser.cs`
- `src/Dirused.Common/Options.cs`
- `src/Dirused.Cli/Program.cs`
- `tests/Dirused.Tests.Portable/ArgParserTests.cs`
- `tests/Dirused.Tests/ProgramPurgeTests.cs`
- `README.md`
- `CHANGELOG.md`

## Contract readers

- `Options` positional record: constructed at `ArgParser.cs` (main construction and `RejectUnavailable` call at :213) only; the
  new field is last with a default, so other call sites stay valid.
- Refusal strings: `ArgParserTests.cs:58-63` (change), `README.md` (grep the old strings; update any copy).
- Dry-run summary line: `Program.cs:129`; tests that match `"Add /confirm to delete them."` keep passing for explicit patterns.

## What NOT to Do

- Do not let any `/confirm` run proceed without an explicit, non-match-all, non-`+` pattern list.
- Do not change what a dry run does: it opens, renames or deletes no file and creates no purge log.
- Do not change output, JSON, CSV or exit codes for runs without `/purge`, or for `/purge` runs with explicit patterns,
  except the help text.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "`/largest /purge`, `/largest * /purge` and `/largest +*.zip /purge` (no /confirm) parse with no error and run a dry run that lists each /largest file as would delete or skipped, ending with the rerun hint"
  - id: M2
    text: "the same three pattern forms with /confirm are refused with the new /purge /confirm messages and exit 1 (usage error, Program.cs:51); no file changes and no purge log is created"
  - id: M3
    text: "`/largest *.log /purge` still ends with 'Add /confirm to delete them.' and `/largest *.log /purge /confirm` still parses (positive control)"
  - id: M4
    text: "/help and the short usage say patterns are needed only with /confirm"
must_not:
  - id: N1
    text: "a no-pattern, match-all or '+' /purge dry run is refused (red on main fa3a07c: ArgParserTests no-confirm assertions fail)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1]
    kind: offline
    command: "dotnet test tests/Dirused.Tests.Portable locally; new no-confirm assertions red on main fa3a07c; mutant 'drop the confirm condition from the three refusals' makes M1 red; mutant 'drop the three refusals entirely' makes M2 red; Windows CI runs ProgramPurgeTests"
    intent: A purge with no file types only shows you what it would delete; deleting still needs you to name the file types.
  - id: E2
    kind: live
    proves: [M1, M2, M4]
    command: "operator, work laptop: `dirused C:\\temp\\purgetest /largest /purge` shows the list and the hint; `dirused C:\\temp\\purgetest /largest /purge /confirm` is refused; then the screenshot command (`/file server-list.txt /largest /purge /html`) produces the report"
    intent: On your laptop, run your original command and see the would-delete list for every server, with nothing deleted.
interface:
  - "/purge requires /largest"
  - "/purge /confirm requires /largest with file patterns, e.g. /largest *.log"
  - "/purge /confirm cannot be used with a match-all pattern; name the file types to delete, e.g. /largest *.log"
  - "/purge /confirm needs the full pattern list; '+' adds to the default list, e.g. write /largest *.log;*.zip"
  - "To delete, rerun with /largest <patterns> /purge /confirm, e.g. /largest *.log"
```
