# restart-webhook prints a transient "Bootstrap failed: 5" that its own retry then recovers

**Status:** OPEN — filed 2026-11-22
**Priority:** P3 (cosmetic: the restart succeeds, the message reads like a failure)
**Triage:** backlog — pull into a release that already touches `Makefile` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** pre-existing (`Makefile` `restart-webhook`, lines 672-690)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-22
**Prior art:** docs/bugs/2026-10-28-restart-webhook-misleading-root-hint.md (exact-slug pass) — read, related: that fix filters only the "re-running as root" hint line; the error line itself is still printed on every failed attempt

## Symptom

Operator, 2026-11-22 14:46, `make restart-webhook` on the M5:

    Bootstrap failed: 5: Input/output error
    [restart-webhook] reloaded LaunchAgent definition

The webhook and cloud bridge restarted (new PIDs 64328/64334 at 14:46:32) and `/k3dm help` served the new code.

## Cause (from the target's code)

`launchctl bootout` returns before launchd has finished removing the service; the immediate `launchctl bootstrap`
then fails with error 5 while the old instance is still unloading. The target retries up to 5 times, 1 s apart, and
prints each failed attempt's stderr, so a normal first-attempt race shows as an error.

## Proposed fix

Hold failed-attempt output and print it only if all 5 attempts fail; optionally wait for `launchctl print` to stop
finding the service after bootout before the first bootstrap. Test: a stub launchctl failing once then succeeding
prints only the success line; failing 5 times prints the errors and exits 1.
