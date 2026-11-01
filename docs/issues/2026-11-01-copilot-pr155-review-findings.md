# Copilot PR #155 review findings

**PR:** wilddog64/k3d-manager#155 (v1.43.13)
**Date:** 2026-11-01

## Finding 1: `scripts/etc/machine/secrets.hub.list:43`, a dead Slack bot token entry

Copilot flagged `k3d-manager-slack-bot-token|cliang|...`. It names a Keychain service no code reads and hardcodes an
operator account. The webhook bot token lives under `k3d-manager-slack-bot-token-bot` (`Makefile` `update-webhook-slack`,
`bin/hub-new:115`), which line 5 of the same manifest already lists. On a hub whose user is not `cliang`,
`make machine-check ROLE=hub` would report a false `missing`.

**Fix:** removed the entry, and removed it from the hub-manifest test in `scripts/tests/bin/machine_setup.bats`.

**Root cause:** `fd25a55d` added the entry when it listed the hub-read Keychain items, but no reader of that service exists in
the tree. The test only checked that the entry was present in the manifest, so it
could not catch an entry no code reads.

**Process note:** a manifest entry must name the code that reads it. A spec that adds inventory items should require a
grep of each service name in `bin/`, `scripts/` and `Makefile`.
