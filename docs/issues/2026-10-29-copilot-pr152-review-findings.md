# PR #152 review findings

**Date:** 2026-10-29
**PR:** #152, the v1.43.9 release (`k3d-manager-v1.43.9` → `main`)

## Finding 1 — Copilot: a second, unbracketed `## Unreleased` heading in CHANGELOG.md

**Flagged:** `CHANGELOG.md:11`. A bare `## Unreleased` section with two entries (the Cloudflare posture helper and the webhook incident doctor) sat above the bracketed `## [Unreleased]`. That duplicated the heading and broke the bracketed convention.

**Fix:** the stray section was removed.
- The Cloudflare posture entry moved under `## [1.43.9] - 2026-10-29` → `### Added`, because the helper ships in this release.
- The doctor entry duplicated the existing `make webhook-doctor` bullet, so its details were folded into that bullet.
- `## [Unreleased]` is now the only Unreleased heading, and it is empty.

**Root cause:**
- An agent-written checkpoint (`e4f6823e`) added its entries under a new `## Unreleased` heading instead of the existing `## [Unreleased]`.
- Release prep matched only the bracketed heading with `^## \[`, so the bare one was never seen and stayed above the promoted version.

**Process note:** during milestone promotion, check for any Unreleased heading, bracketed or not: `grep -n -i '^## \[\?unreleased' CHANGELOG.md` must return exactly one line.

## Finding 2 — CodeQL `py/insecure-protocol`: TLS 1.0/1.1 allowed in `bin/k3dm-cloudflare-posture:249`

**Not changed; intentional.** `probe_tls` pins one TLS version per handshake (minimum = maximum) to prove the Cloudflare edge rejects TLS 1.0 and 1.1. It reads only the negotiated version and sends no data. Code-scanning alert #35 was dismissed as won't-fix with this reason.
