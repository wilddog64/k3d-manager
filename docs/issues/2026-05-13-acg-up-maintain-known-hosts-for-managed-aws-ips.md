# acg-up should maintain `known_hosts` for managed AWS IPs

## What was observed
- `~/.ssh/known_hosts` accumulated stale public AWS IP entries across sandbox rebuilds.
- The current AWS instance key should stay present.
- Only the managed AWS host entries from `~/.ssh/config` should be updated or pruned.

## Expected behavior
- When `acg_provision` / `acg_status` updates the managed AWS host IPs in `~/.ssh/config`, `known_hosts` should:
  - remove stale managed AWS IPs that are no longer referenced
  - keep the current managed AWS IPs
  - leave unrelated host keys alone

## Follow-up
- The ACG lifecycle now syncs `known_hosts` for `ubuntu`, `ubuntu-tunnel`, `ubuntu-1`, and `ubuntu-2` only.
- If additional managed SSH hosts are added later, they should be included in the same sync list.
