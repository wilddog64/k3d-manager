# ACG sandbox SSH hosts are written into `~/.ssh/config`, which is a tracked dotfile

**Status:** OPEN — captured 2026-11-21, not triaged.
**Priority:** P2 (Argon P2 accepted, grooming 2026-11-22, operator; was: P3)
**Triage:** carry → v1.46.0 — grooming 2026-11-22, operator
**Re-triage:** 2026-11-27 — check first in v1.46.0 — close if already resolved, else decide (operator 2026-11-27)
**Branch:** `k3d-manager-v1.46.0`
**Introduced by:** dd54b653 (2026-06-26, `_acg_upsert_ssh_host`)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (ACG sandbox setup mutates tracked `~/.ssh/config` in place with `StrictHostKeyChecking no` and stale host IPs, requiring manual `git checkout` cleanup.)
**Waiting on:** dispatch — since 2026-11-27 (check: still present)
**Prior art:** not run (find-similar-docs: vector store unavailable); exact-slug glob found none. Read, different root cause: `docs/bugs/2026-10-22-ssh-config-lost-operator-host-aliases.md` (operator aliases lost on rewrite; fixed by `~/.ssh/config.d/operator` + guard).

## Symptom

On m5-air, `~/.ssh/config` is a symlink to `zshdotfiles/ssh/m5-air/config`. On 2026-11-21 that repo showed
`ssh/m5-air/config` modified: three hosts `ubuntu`, `ubuntu-1`, `ubuntu-2` with AWS public IPs, `User ubuntu`,
`IdentityFile ~/.ssh/k3d-manager-key.pem`, `StrictHostKeyChecking no`, written 2026-11-14 13:45 by a k3s-aws (ACG) sandbox
run. The sandbox was gone, so the entries pointed at dead or reassigned IPs. Claude removed them with `git checkout` on
the operator's go (2026-11-21).

## Cause

lib-foundation `scripts/lib/acg/acg.sh:18` (`_ACG_SSH_CONFIG="${HOME}/.ssh/config"`), `:71` `_acg_update_ssh_config`,
`:93` `_acg_upsert_ssh_host` (block at `:110`) edit the operator's main ssh config in place. Each sandbox leaves a
dotfiles change; nothing removes the entries at teardown; `StrictHostKeyChecking no` lands in tracked config.
`scripts/lib/providers/k3s-gcp.sh:86-102` and `k3s-az.sh:88-102` write the same shape.

## Fix sketch

Upstream first in lib-foundation, then subtree-pull. Writers target their own file,
`${K3DM_SSH_SANDBOX_FRAGMENT:-$HOME/.ssh/config.d/k3dm-sandbox}` (0600 in a 0700 dir), never `~/.ssh/config`. The
operator config starts with `Include ~/.ssh/config.d/operator` only (m5, 2026-11-21), so the fix adds a one-time
`Include ~/.ssh/config.d/k3dm-sandbox` line (operator-approved dotfile change, or documented setup step); the writer checks
for it and warns instead of editing the main file. Sandbox teardown (`acg-down`) deletes the fragment. Offline test: fake HOME
with `~/.ssh/config` as a symlink; after upsert the symlink target is byte-identical and the fragment holds the hosts;
positive control that `ssh -G -F <fake config> ubuntu` resolves the IP.

## Check — 2026-11-27 (Claude, read-only)

Still present in code: `scripts/lib/foundation/scripts/lib/acg/acg.sh:18` `_ACG_SSH_CONFIG="${HOME}/.ssh/config"`;
`scripts/lib/providers/k3s-gcp.sh:86,286` and `k3s-az.sh:88,287` `local ssh_config="${HOME}/.ssh/config"`. Not resolved →
fix in v1.46.0, upstream in lib-foundation first, then subtree pull (spec, Fable + Neon review, dispatch).
