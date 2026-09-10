# Online Kine rollback archive was truncated

## Attempt

During the controlled hub-datastore rebuild backup rung, an online tar stream
was captured from the running k3d server's Kine database directory.

## Actual output

```text
tar: Truncated input file (needed 8831115264 bytes, only 0 available)
tar: Error exit delayed from previous errors.
```

The resulting `kine-state-online.tgz` must be treated as invalid and is not a
rollback artifact.

## Impact

The destructive rebuild rung is blocked. No cluster resource, volume, or
datastore has been removed.

The hub nodes were briefly stopped to capture raw offline inputs, then restarted.
The control plane recovered successfully:

```text
ok
```

The raw offline copies include `server/db`, the server token, and every node's
local storage tree, but the combined archive/checksum gate was not completed in
this execution environment. They remain **unverified** and cannot satisfy the
rebuild gate until a persistent copy/verification run succeeds.

## Follow-up

Capture the Kine database only after the control plane is stopped/quiesced, then
list and checksum-verify the archive before progressing. Preserve the valid
manifest/Secret/PV exports separately; do not rely on the invalid DB stream.

## External-copy attempt (2026-09-10)

The consistent raw offline inputs are being copied from M4 to M2 as the second
recovery copy. M2's SSH host key was verified against the existing
`m2-air.local` trust record. mDNS resolution of `m2-air.local` was intermittent,
so the transfer uses its verified MeshHome address with
`HostKeyAlias=m2-air.local`; this preserves strict host-key verification.

Two initial transfer invocations failed before copying data because the macOS
system `rsync` does not support the Linux-only `-A` or `--info=progress2`
options. The corrected resumable command uses `rsync -aHE --partial --progress`.
It must finish and then pass a checksum comparison before the destructive rung
can be considered. No invalid `.tgz` file is a recovery artifact.
