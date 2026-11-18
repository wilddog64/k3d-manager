# dirused M2a-b — live checks know exit 4 and check the fullness levels (Argon review of #14)

**Filed:** 2026-11-17
**Status:** ready for dispatch
**Repo / branch:** wilddog64/dirused / `m2a-fullness-levels` (PR #14, head 6f09162)
**Tracked:** separately from k3d-manager releases. This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Risk:** low (test script and its README only)
**Implementer:** Luna (Codex). **Verifier:** Claude (parse check, diff); live run by the operator at the office.

## Problem

M2a (PR #14) added exit code 4 (a volume at or above `/crit`, default 90%). `tools/live-check.ps1` predates it:

- `F1` (`:129`) and `F2` (`:133`) accept only exit 0 or 3, so on a real server list with one volume at 90% both fail
  (Argon blind review of #14, 2026-11-17, verified by Claude).
- `L3` (`:56`, `\\localhost /summary`) and `L8` (`:98`, `C:\Windows\Web /summary`) require exit 0, so both fail on a PC whose
  own system drive is at 90% (found by Claude while verifying the Argon finding).
- No live check covers the fullness levels themselves.

## Change (`tools/live-check.ps1`)

1. `L3` and `L8`: append `'/warn', '99', '/crit', '100'` to their `Invoke-Dirused` argument lists, so they keep asserting
   exit 0 exactly whatever the PC's disk level. Leave their check text and conditions unchanged.
2. `F1` and `F2`: accept exit 0, 3 or 4; F2's text becomes `... finishes, exit 0, 3 or 4`.
3. New checks after `L10`, using the existing `Invoke-Dirused` / `Test-Check` helpers:
   - `L11` `'/summary with /warn 1 /crit 2 tags the volume [CRIT], prints the footer, exit 4'`:
     `Invoke-Dirused @('C:\Windows\Web', '/summary', '/warn', '1', '/crit', '2')`; pass when `rc -eq 4`, `out -match '\[CRIT\]'`
     and `out -match '1 volume\(s\): 1 at or above 2%, 0 at or above 1%'`. (L8 is its positive control: the same folder with
     `/warn 99 /crit 100` exits 0.)
   - `L12` `'/warn at or above /crit is rejected as a usage error, exit 1'`: `Invoke-Dirused @('C:\Windows\Web', '/warn', '95')`;
     pass when `rc -eq 1` and `out -match '/warn must be below /crit'`.
4. `tools/PACKAGE-README.txt:5`: `L1-L10` → `L1-L12`.

## Files

| File | Change |
|---|---|
| `tools/live-check.ps1` | Changes 1-3 |
| `tools/PACKAGE-README.txt` | Change 4 |

## Contract readers

`grep -rn "live-check\|L1-L10" README.md tools .github` (2026-11-17, 6f09162): `tools/PACKAGE-README.txt:5,37,38` (count and
usage); the release workflow packages the script. No other reader. `Invoke-Dirused` returns `.rc` and `.out` (`:14-20`).

## What NOT to Do

- Do NOT change product code, tests, or any other check's condition.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- Keep the script's existing style (single-quoted ids, `Test-Check` one-liners); LF endings; no refactors.

## Gates

`pwsh -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path tools/live-check.ps1), [ref]$null, [ref]$e); $e.Count'`
prints `0`. The checks need Windows and `dirused.exe`; they run live at the office.

## Definition of Done

- [ ] Changes 1-4; `git status` shows only the two files.
- [ ] Parse gate output pasted.
- [ ] Report: diff summary. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: live-check.ps1 treats exit 4 as a valid fleet result (F1, F2) and L3/L8 still demand exit 0 on any PC
  - id: M2
    text: a live check proves a crit volume is tagged, counted in the footer and exits 4, and that /warn >= /crit is refused
must_not:
  - id: N1
    text: F1 or F2 fails only because a fleet volume is at or above /crit — red today
  - id: N2
    text: L3 or L8 fails only because the PC's own drive is at or above /crit — red today
evidence:
  - id: E1
    proves: [M1, M2]
    kind: offline
    command: pwsh parse gate (0 errors) and Claude's read of the diff against Changes 1-4
    intent: The office check script is updated for the new exit code before you run it.
  - id: E2
    proves: [M1, M2, N1, N2]
    kind: live
    command: "operator, office, after v0.0.5: powershell -ExecutionPolicy Bypass -File .\\live-check.ps1 -Targets fleet.txt — L1-L12 and F1-F2 PASS"
    intent: One run of the check script at the office proves the colours/levels work on real servers and nothing else broke.
interface:
  - "tools/live-check.ps1 checks L11, L12; F1/F2 accept exit 0|3|4"
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "when slot allowed, can you also dispatch dirused tasks?" (M2a, PR #14); this fixes the verified finding of #14's blind Argon review before merge.
