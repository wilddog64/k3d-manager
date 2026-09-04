# E2E publish-back key: make the `from=` source-pin + IPv4 transport durable in code

**Date:** 2026-08-24
**Status:** OPEN (live hardening applied by hand; not yet expressed in the repo)
**Area:** `scripts/plugins/e2e_remote.sh` — M2→M4 result publish-back

## Context

The M2→M4 result publish-back uses a dedicated ed25519 key
(`~/.ssh/e2e-m4-publisher` on M2) whose M4 `authorized_keys` entry is a
forced-command principal built by `e2e_result_publisher_install()`
(`command="… e2e_result_publish",restrict,no-pty,no-*-forwarding`).

On 2026-08-24 the key was rotated (old `SwC+H3C7…` → new `WwhGtx7C5KUt…`) and a
source restriction was added **by hand** to the live M4 line:

```
from="192.168.39.0/24",command="…/k3d-manager e2e_result_publish",restrict,… <key> e2e-m2-publisher
```

Because mDNS resolves `m4-air.local` to **both** an IPv6 link-local
(`fe80:b::…`) and the IPv4 `192.168.39.169`, default `ssh` prefers IPv6 and the
source address then falls **outside** the IPv4 `/24`, so the pin rejects a
legitimate M2 connection. This was worked around by prepending an M2-side
`~/.ssh/config` block:

```
Host m4-air.local
  AddressFamily inet
```

## Problem

Both mitigations live **outside the repo** (M4 `authorized_keys`, M2 `~/.ssh/config`):

1. `e2e_result_publisher_install()` rebuilds the forced-command line **without**
   the `from=` clause. Any reinstall — or the line-rebuild step of a key
   rotation — **silently drops the source pin**.
2. The IPv4-transport requirement is invisible to `_e2e_publish_back_push()`
   (`e2e_remote.sh:661`). If M2's `~/.ssh/config` is lost/rebuilt, publish-back
   reverts to IPv6 and the pin blocks it — a silent publish-back outage that
   darkens the E2E result gate.

## Proposed fix (minimal patch)

1. **`e2e_result_publisher_install()`** — accept an optional source pin via env
   `E2E_PUBLISH_FROM`, **default empty** (no `from=`, byte-identical to today's
   line — backward compatible). When non-empty, prefix the entry with
   `from="${E2E_PUBLISH_FROM}",`. Do NOT hardcode a subnet default — the
   home-LAN value (`192.168.39.0/24`) is operator config, exported at install
   time, never baked into this general tool. Keep the existing marker/idempotency.
   Update the BATS assertion in `scripts/tests/plugins/e2e_remote.bats`
   (publisher-install test) to cover BOTH the unpinned default and the
   `E2E_PUBLISH_FROM`-set pinned form.
2. **`_e2e_publish_back_push()`** (or `_e2e_remote_ssh_opts` if shared is
   acceptable) — add `-o AddressFamily=inet` so IPv4 is forced in-code and the
   publish path no longer depends on M2's `~/.ssh/config`.
3. **Optional rotation helper** — factor the verified stage→install→verify→
   revoke cutover (used by hand on 2026-08-24) into `e2e_result_publisher_rotate`
   so future rotations preserve both the pin and the IPv4 opt. Not required for
   the pin-only policy, but the natural home if time-based rotation is ever added.

## Acceptance

- `E2E_PUBLISH_FROM=192.168.39.0/24 e2e_result_publisher_install <pub>` produces
  a line beginning `from="192.168.39.0/24",command="…`.
- Publish-back succeeds from M2 (192.168.39.0/24) with the M2 `~/.ssh/config`
  block **removed** (proves the in-code `AddressFamily=inet`).
- A connection sourced outside the `/24` is rejected at auth.
- BATS green.

## Decision context

Policy chosen 2026-08-24: **source-pin only, no scheduled rotation** (per-deploy
and time-based auto-rotation both declined — blast radius is one schema-validated
ConfigMap write behind a forced command; frequent rotation adds a silent-lockout
failure mode for ~no gain). The pin defeats the realistic threat (key exfiltrated
and used off-LAN) with no recurring maintenance.
