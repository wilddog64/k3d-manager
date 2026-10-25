# agy-wrapper-install would replace the real agy binary with a symlink

**Filed:** 2026-10-24
**Status:** FIXED — Claude, same day, before any install ran
**Priority:** P1
**Severity:** High (destroys the real agy binary; the wrapper then finds no agy and exits 127)
**Component:** `Makefile` (`agy-wrapper-install`), `docs/howto/codex-dispatch.md`
**Found by:** Claude, during the v1.43.6 plan 3 E6 live check (`docs/plans/v1.43.6-dispatch-codex-solo-activity.md`)

## Problem

The agy installer puts the real binary at `~/.local/bin/agy` (a 192 MB file on the operator's Mac).
`make agy-wrapper-install` defaulted `AGY_WRAPPER_DIR` to `~/.local/bin` and ran
`ln -sf bin/k3dm-agy ~/.local/bin/agy`, which unlinks the real binary and puts the wrapper in its
place. The wrapper then skips itself on `PATH`, finds no other agy, and exits 127. The operator did
not run the target; the defect was caught when `type -a agy` showed the real binary at that path.

Plan 3's offline review passed because every test used a temp `AGY_WRAPPER_DIR` or none at all.

## Fix

- Default `AGY_WRAPPER_DIR` is now `~/.local/share/k3d-manager/bin`, a directory only the wrapper uses.
- The target refuses (exit 1) when `$(AGY_WRAPPER_DIR)/agy` exists and is not already a symlink to
  this repo's wrapper, and leaves it untouched. Reinstalling over its own symlink still works.
- It prints a reminder when the directory is not on `PATH`; the operator puts it first.
- The how-to says so, and says never to point `AGY_WRAPPER_DIR` at the real binary's directory.

## Acceptance

```yaml
must:
  - id: M1
    text: make agy-wrapper-install with a dedicated dir creates the symlink, and running it again succeeds.
must_not:
  - id: N1
    text: The install must not replace or remove an existing agy in the target dir that is not the wrapper symlink (red on the pre-fix Makefile).
  - id: N2
    text: The default AGY_WRAPPER_DIR must not be ~/.local/bin (red on the pre-fix Makefile).
evidence:
  - id: E1
    kind: offline
    proves: [M1, N1, N2]
    text: bats scripts/tests/bin/agy_wrapper.bats tests 10 and 11, both shown red on the pre-fix Makefile and green after.
  - id: E2
    kind: live
    proves: [M1]
    text: The operator runs make agy-wrapper-install, puts the dir first on PATH, and type -a agy lists the wrapper before ~/.local/bin/agy, whose size is unchanged.
interface:
  - make agy-wrapper-install / agy-wrapper-uninstall (AGY_WRAPPER_DIR)
```
