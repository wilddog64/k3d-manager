# Bug: `_install_tailscale_app` does not detect a leftover `brew services` LaunchAgent from the removed formula

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** lib-foundation v0.5.11 (`_install_tailscale_app`, subtree `f9974036`)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (both)
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone; batched at grooming 2026-11-29)
**Prior art:** none (exact-slug glob: no `docs/bugs/*tailscale*` or `docs/issues/*tailscale*`; `make find-similar-docs` retrieval unavailable, cluster context missing)
**Severity:** low — the leftover cannot run (its binary is gone) and is not a second network extension; it fails at every login and leaves a confusing loaded launchd job
**Filed:** 2026-11-26, operator: "file P3 for _install_tailscale_app" (after the leftover was found on m2 during plan 7 L-E1)
**Component:** lib-foundation `scripts/lib/system.sh` `_install_tailscale_app` (k3d-manager subtree `scripts/lib/foundation/scripts/lib/system.sh:801`); k3d-manager `make install-tailscale`

## Symptom

On m2 (macOS 26.5.1, 2026-11-26), `make install-tailscale` installed the Standalone app and reported success, while
`~/Library/LaunchAgents/homebrew.mxcl.tailscale.plist` (dated 2025-08-10) was still present and loaded in the user's
launchd domain, pointing at `/opt/homebrew/opt/tailscale/bin/tailscaled`, which no longer existed (`launchctl print`
showed it enabled, last exit 78). The formula had earlier been removed with `brew uninstall` without
`brew services stop` first. Claude removed it on operator approval (`launchctl bootout gui/$UID/homebrew.mxcl.tailscale`,
then `rm`).

On m4 the same file existed in `error` state alongside the installed formula; there the formula check refused, and the
runbook order (`brew services stop` before `brew uninstall`) cleaned it.

## Cause

The function's formula guard is `brew list --formula tailscale`, which passes once the formula is uninstalled, even
when its `brew services` LaunchAgent (user `~/Library/LaunchAgents` or system `/Library/LaunchDaemons`) remains.

## Fix options (for triage)

1. Refuse (like the formula and App Store cases) when `homebrew.mxcl.tailscale.plist` exists in either location, with
   the cleanup commands in the message.
2. Warn only, and continue.

Either way: a BATS row with a fixture plist under a fake HOME, red on v0.5.11. Upstream-first in lib-foundation, then
subtree pull.
