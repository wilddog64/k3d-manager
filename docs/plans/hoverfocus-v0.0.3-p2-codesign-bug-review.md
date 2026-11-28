# Review: HoverFocus P2 bug — `make bundle` ignores a failed `codesign` (blind bug-doc review)

**Filed:** 2026-11-26
**Repo / branch:** `hoverfocus` / `v0.0.3` (head `4a3940f`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review; Fable reviews the same text separately

## Task

Review the bug report below against the code. You get the report and the repository, not any other discussion. Decide:
is the diagnosis right (does the evidence support the cause), is anything missed (other paths where signing can fail or
the identity file can lie, effects on `install`, `uninstall`, the README instructions, F2's offline tests), is P2 the right
priority, which fix option is best and what it must not break (CI and other Macs without the identity must still build;
an explicit `CODESIGN_IDENTITY=-` must still work), and whether the proposed test can fail on the current code.

### The bug report (verbatim)

> # Bug: HoverFocus `make bundle` ignores a failed `codesign` and records the local identity anyway
> 
> **Status:** OPEN — captured, not triaged
> **Priority:** P2
> **Introduced by:** HoverFocus v0.0.3 F2 (`7b42f63`, unreleased)
> **Should have been caught by:** offline test
> **Introducing change reviewed:** yes (Argon)
> **Waiting on:** operator decision — since 2026-11-26
> **Classified:** pending (Argon, from this doc alone)
> **Prior art:** none (exact-slug glob: no `docs/bugs/*hoverfocus*`; `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md` is unrelated; `make find-similar-docs` retrieval unavailable, cluster context missing)
> **Severity:** medium — defeats F2's purpose: every install from SSH silently produces an ad-hoc build, the Accessibility grant stops matching, HoverFocus stops working, and the reset hint is suppressed
> **Filed:** 2026-11-26, operator: "I consider these are bugs. the installation should handle application smoothly" (U2 E2 setup on m2)
> **Component:** HoverFocus `Makefile` `bundle` target (lines 35-50) and the `install` hint (line 63)
> 
> ## Symptom (m2, macOS 26.5.1, 2026-11-26)
> 
> `make install` was run from an SSH session. `build/.codesign-identity` reads `HoverFocus Local Signing`, but the installed
> app is `Signature=adhoc`, `Identifier=hoverfocus` (the linker signature), designated requirement `cdhash H"…"`.
> HoverFocus then reported "Needs Accessibility permission" while System Settings showed it enabled (and the switch would
> not turn off). The ad-hoc reset hint was not printed because the identity file claimed a real identity.
> 
> ## Cause (proved on m2, 2026-11-26)
> 
> - Over SSH the login Keychain is locked: `security show-keychain-info` → "User interaction is not allowed".
> - `codesign --force --sign "HoverFocus Local Signing"` on a copy of the bundle → `errSecInternalComponent`, rc 1.
> - The `bundle` recipe is one `sh -c` line chain with `;` and no `-e` (no `.SHELLFLAGS`), so the failure is ignored and
>   `echo "$$id" > build/.codesign-identity` still runs. The stub `codesign` in F2's offline tests always succeeds.
> 
> ## Fix options (for triage)
> 
> 1. Fail closed: stop with a clear message ("login Keychain is locked: run `security unlock-keychain` or run make install
>    at this Mac's keyboard") when signing with the local identity fails; write `.codesign-identity` only after success.
> 2. Verify after signing (`codesign -dv` shows `Authority=HoverFocus Local Signing`) before recording the identity.
> 3. Fall back to ad-hoc explicitly, record `-`, and print the reset hint (works, but loses the grant every SSH install).
> 
> Test: a stub `codesign` that exits 1 for the named identity; red on `7b42f63` (identity file written, rc 0).
> Recommended target: v0.0.3, since F2 introduced it there and is unreleased.

## Before You Start

1. Read `Makefile` (whole file), `packaging/signing-identity.sh`, `README.md` (install and Accessibility sections) and the
   F2 tests (`grep -rln codesign-identity tests scripts 2>/dev/null` and the selftest/BATS files they point to).
2. `git log --oneline -3` and confirm HEAD is `4a3940f`.

## Files

| File | Change |
|---|---|
| `Makefile` | read only |
| `packaging/signing-identity.sh` | read only |
| `README.md` | read only |

## What NOT to Do

- Do NOT edit, commit or push. Do NOT run `make bundle`, `make install`, `make signing-identity`, `codesign` or `security`
  against the real login Keychain; reason from the code.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back: a verdict on the diagnosis (confirmed / partly / wrong), the priority (agree or propose another), the
      recommended fix option with any changes, and one line per finding as
      `file:line — defect — concrete failure scenario — severity (high/medium/low)`, each marked verified-from-code or
      speculative; or `no findings`.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario; the report gives a diagnosis verdict, a priority and a fix recommendation
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has verdict, priority, fix and findings or "no findings"
    intent: A second model checks the signing-bug diagnosis and the fix before it is dispatched, so the fix targets the real cause.
interface: none
```

**Intent approved:** operator, 2026-11-26
**Approval words and scope:** "let's have Argon/Fable review P2 bug after you file it; the other two P3 can left for triage/grooming on Sunday"
