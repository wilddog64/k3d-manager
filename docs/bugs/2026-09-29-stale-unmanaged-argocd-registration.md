# Stale unmanaged ArgoCD registrations survive ACG sandbox cleanup

**Filed:** 2026-09-29
**Status:** FIXED in `39193aae` — evidence: `bin/cleanup-stale-registration:33-82` (triaged 2026-10-08, Codex)

## Symptom

After an ACG `k3s-aws` sandbox disappeared, ArgoCD retained ten `Unknown`
Applications named `ubuntu-k3s-*`. They pointed at the unreachable server
`https://host.k3d.internal:6443`.

`make cleanup-stale-sandbox CONFIRM=1` removed the local sandbox agents and
kube context, but the ten remote Applications remained. The hub still had the
`cluster-ubuntu-k3s` cluster Secret.

## Cause

The local cleanup target manages only local state. The remote cleanup target
selects only registrations labeled `k3d-manager/managed=true` with expiry
metadata. This registration was labeled `k3d-manager/managed=false` and had no
expiry, so `make cleanup-stale-clusters` correctly ignored it but no explicit
operator workflow existed for removing a known stale legacy registration.

## Fix

Add an exact-name, dry-run-by-default target:

```bash
make cleanup-stale-registration CLUSTER=ubuntu-k3s
make cleanup-stale-registration CLUSTER=ubuntu-k3s CONFIRM=1
```

The command verifies that exactly one ArgoCD cluster registration matches the
name, lists only Applications targeting that cluster or its registered server,
deletes the Secret first, and then removes matching Applications with
non-blocking deletion. It refuses to guess when the name is missing or multiple
registrations match.

## Prevention

New ACG registrations should always carry `k3d-manager/managed=true`,
`k3d-manager/expires-at`, and a sandbox identifier. The explicit cleanup target
is intentionally separate from automatic cleanup so an unmanaged or retained
registration cannot be deleted based only on an unreachable endpoint.
