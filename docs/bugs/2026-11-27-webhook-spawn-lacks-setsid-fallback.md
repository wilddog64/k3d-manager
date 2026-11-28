# Bug: the webhook's own posix_spawn calls lack the setsid fallback the helper got

**Status:** OPEN — capture
**Priority:** P3
**Introduced by:** pre-existing (fallback added only to `scripts/lib/webhook/proc.py` in `5625527b`)
**Should have been caught by:** review
**Introducing change reviewed:** yes (Argon)
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** `docs/bugs/2026-11-25-cloud-request-helper-dies-where-posix-spawn-setsid-unsupported.md` (exact topic) — read, same class, different caller
**Filed:** 2026-11-27, Claude, from Argon review of PR #166 (finding A1)

## Evidence

- `bin/k3dm-webhook:593` (`_posix_spawn_capture`) and `:1493` (`_posix_spawn_job`) call
  `os.posix_spawn(..., setsid=True)` directly. `scripts/lib/webhook/proc.py:44-50` retries with `setpgroup=0` on
  `NotImplementedError`.
- The webhook runs on the hub (macOS Homebrew Python supports `POSIX_SPAWN_SETSID`), so this does not fail today; it
  would on a Python built without it.

## Notes for triage

Route both sites through the `proc.py` helper (or the same fallback) so the timeout still stops the whole tree.
