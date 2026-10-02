# No standalone way to generate the cloudflared config, or detect drift

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. The live `~/.cloudflared/config.yml` drifted to the hub origin and the public
frontend returned 404 for weeks. Nothing reported the drift, and the only way to regenerate the
file was a full `bin/cluster-up` or `hub_recovery_reconcile`.
**Status:** FIXED
**Related:** `2026-10-01-hub-recovery-points-public-frontend-at-hub.md`

## Background

The source of truth is in the repo:
- `scripts/etc/cloudflared/config.yml`
- `scripts/etc/cloudflared/origins.tsv`, rendered per provider by
  `_hub_recovery_render_cloudflared_config <provider> <config> <table>` in
  `scripts/plugins/hub_recovery.sh`

The live file is a generated artifact. The tunnel credentials JSON and `cert.pem` stay out of git:
they are backed up to Keychain/Vault by `make cloudflared-backup`.

## Fix

### A. `make cloudflared-config` (Makefile)

Add the target to `.PHONY` with a `##` help comment.

- **Provider:** `CF_PROVIDER ?= k3s-hostinger`. This is the permanent app cluster. Do **not**
  default to `$(CLUSTER_PROVIDER)`: its default `k3s-aws` is wrong for the edge.
- **Render** with the existing function, sourcing only what it needs. If sourcing
  `hub_recovery.sh` standalone drags in too much, move the render function into a small
  dependency-free file `scripts/lib/cloudflared_render.sh`, and source that from both
  `hub_recovery.sh` and `bin/cluster-up`. The function body stays byte-identical.
- **Output:** write the render to a temp file. Then:
  - `CF_CONFIG ?= $(HOME)/.cloudflared/config.yml`.
  - Identical to `CF_CONFIG` → print `cloudflared config up to date (<provider>)`, exit 0, and
    write nothing.
  - Different → print a unified diff. Without `APPLY=1`, exit 1 with
    `drift: rerun with APPLY=1 to install`.
  - With `APPLY=1`: copy the old file to `config.yml.bak.<UTC timestamp>`, install the render,
    and print the `launchctl kickstart -k "gui/$(id -u)/com.k3d-manager.cloudflare-tunnel"` hint.
  - Do **not** kickstart automatically.
- **Unknown `CF_PROVIDER`:** one that does not appear in `origins.tsv` → error, exit 2, and
  write nothing.

### B. Drift line in `/cluster-status` for k3s-hostinger (optional; skip if it touches more than `scripts/lib/webhook/smoke.py` + its test)

Add a `Cloudflared origin` result. If the live config routes `frontend.3ai-talk.org` somewhere
other than the `k3s-hostinger` origin in `origins.tsv`, it is a WARN that names both origins.
A missing file is also a WARN. It reads files only and makes no network call.

### C. Docs

Add a short "Regenerating the tunnel config" section to the existing cloudflared/edge guide. Find it
with `grep -rl cloudflared docs/guides docs/howto`, and pick the page an operator would open.
Add a CHANGELOG `Added` bullet.

## Tests

Use `scripts/tests/bin/makefile_cloudflared_config.bats`. Run the target with `CF_CONFIG` pointing
into `$BATS_TEST_TMPDIR`. Never touch the real `~/.cloudflared`.

- A file identical to the render → exit 0, the file is not rewritten (same mtime/inode), and the
  output says "up to date".
- The frontend line is set to `127.0.0.1:8000` with `CF_PROVIDER=k3s-hostinger` → exit 1, the diff
  shows `127.0.0.2:80`, and the file is unchanged.
- The same with `APPLY=1` → exit 0, the file now matches the render, and a `.bak.` file exists with
  the old content.
- `CF_PROVIDER=k3d` → the render has `127.0.0.1:8000`.
- `CF_PROVIDER=bogus` → exit 2, and no file is written.
- If a shared lib was extracted: the existing hub_recovery render tests stay green unchanged.
- If B is done: pytest cases for match, mismatch and missing file.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) write even without `APPLY=1` → drift test red;
(b) skip the backup → apply test red;
(c) default `CF_PROVIDER` to `k3d` → drift test red.

## Rules

- Linux-portable shell (CI is Ubuntu); no `sed -i ''`.
- `shellcheck` adds no new warnings. The new bats file and `hub_recovery.bats` are green, plus
  pytest if B is done, plus `make check-doc-links`.
- Touch only: `Makefile`, an optional `scripts/lib/cloudflared_render.sh`,
  `scripts/plugins/hub_recovery.sh` and `bin/cluster-up` (only to source the extracted function),
  the new bats file, B's files if done, the guide, `CHANGELOG.md`, and this doc (Resolution
  section, Status FIXED).
- No live cluster calls, no kickstart, and never read the tunnel credentials JSON or `cert.pem`.

## Resolution

Added `make cloudflared-config` with a `k3s-hostinger` default, provider validation, read-only
drift reporting, opt-in backup and installation, and an explicit launchd kickstart hint. The
shared renderer is sourced by both hub recovery and `bin/cluster-up`; the existing renderer body
is unchanged. Added offline BATS coverage, operator documentation, and a changelog entry.
