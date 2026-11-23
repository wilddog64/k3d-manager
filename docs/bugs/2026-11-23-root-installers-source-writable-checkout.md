# Bug: root installers source libraries from the operator-writable checkout

**Status:** OPEN — captured 2026-11-23
**Priority:** P2 (operator, 2026-11-23: doc + bug, does not block v1.45.0)
**Introduced by:** v1.45.0 plans 2c, web-console A and C
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** a same-uid process becomes root at the operator's next install; defeats the promote authority's goal of surviving a compromised operator uid.
**Findings:** Fable 3 (Medium). Claude: confirmed (`bin/k3dm-promote-authority:3-5` sources `scripts/lib/system.sh`, which provides `_run_command`, from the checkout).

## What is wrong

`bin/k3dm-promote-authority`, `bin/k3dm-web-console-sshd` and `bin/k3dm-web-console-totp` source `scripts/lib/system.sh` (and
`web_console_common.sh`) from the working tree, then run privileged steps through `_run_command` under the operator's sudo. Taking
payload blobs from `HEAD` (`k3dm-promote-authority:76-86`) protects the payload against uncommitted edits only: not the installer,
its sourced libraries, or a local commit.

## Workaround (documented in docs/howto/promote-authority.md)

Run installs from a fresh clone of the protected remote ref, at a commit checked on a second channel.

## Fix direction

Installer refuses to run unless started from a fresh clone at a commit reachable from a ruleset-protected ref, verified against an
operator-typed commit or signed tag; print the commit and blob hashes before asking for sudo.
