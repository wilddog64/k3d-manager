# M2 recovery copy verified; the M4 source has been deleted

## Why this was checked

The owner asked whether the M2 backup Codex left behind can safely be deleted.
Per `docs/plans/v1.33.0-hub-kine-controlled-rebuild.md` the retention rule is:
retain the M4 source **and** the verified M2 copy through acceptance plus a
seven-day rollback window, then retain the M2 copy for 30 days.

## Answer: no, and the situation is worse than the question assumed

**The M4 source no longer exists.** Searched and absent:

```text
~/k3dm-backups
~/k3dm-hub-rebuild-20260909
~/.local/share/k3d-manager/backups
large state.db outside docker: none
```

Only `~/Library/Logs/k3dm-hub-rebuild-{copy,monitor}.log` survive. The two-copy
requirement is therefore already violated, and **M2 holds the only surviving
copy** of the pre-rebuild hub state.

## What was verified on M2 (read-only)

Location: `m2-air.local:~/k3dm-backups/k3dm-hub-rebuild-20260909` (13,649,780 KB).

Datastore - structurally sound and provably not truncated:

```text
page_size 4096 x page_count 2156034 = 8831115264 bytes
                           file size = 8831115264 bytes   <- exact match
PRAGMA quick_check                   = ok
SELECT COUNT(*) FROM kine            = 769843
SQLite header                        = "SQLite format 3"
state.db-wal                         = 0 bytes (clean offline capture)
```

The file size equals the documented pre-rebuild size `8831115264` exactly. The
page arithmetic matching the file size is what rules out truncation - the
failure mode that invalidated the earlier `.tgz`
(`docs/issues/2026-09-09-hub-rebuild-online-kine-backup-truncated.md`).

Row count is lower than the 1,013,597 recorded on 2026-09-09; that is expected,
since compaction events ran between that measurement and the capture.

All seven logical claims are present in the correct node directories, matching
`_hub_recovery_records()` in `scripts/plugins/hub_recovery.sh` one-for-one:
`secrets/data-vault-0`, `identity/postgres-keycloak-pvc`,
`identity/ldap-data-pvc`, `identity/data-openldap-0`,
`identity/ldap-config-pvc`, `trivy-system/data-trivy-server-0`,
`monitoring/prometheus-...-prometheus-0`.

Supporting exports are valid and substantial: `pv-pvc.yaml` (535 lines),
`secrets.yaml` (823), `configmaps.yaml` (12873),
`argocd-applications.yaml` (10386), plus `server-token`.

No rsync partial or temporary files remain, indicating a clean completion.

## Two caveats that cannot be closed

1. **The `COPY_CHECKSUM_VERIFIED` marker is unsubstantiated.** It appears in the
   monitor log but records no checksum value and no method - only the word. With
   the source deleted, a source-versus-copy comparison is now permanently
   impossible. The evidence above is independent of that marker.
2. **A 2.57 GiB size gap** between the monitor-logged `16347868` KB and the
   `13649780` KB present. The absence of rsync partials and the internal
   consistency of the contents make `--partial` cleanup the likely explanation,
   but it cannot be proven without the source.

## Recommendation

Do not delete the M2 copy. Earliest reconsideration is **2026-09-17** (acceptance
plus the seven-day rollback window), after which the policy still allows 30 days.
Acceptance is not met: Findings 2, 3, 4 and 6 of
`docs/issues/2026-09-11-hub-post-rebuild-verification-gaps.md` remain open.

Before any deletion, make a second independent copy so the two-copy requirement
is satisfied again, and record real checksums this time - a marker without values
is not evidence.

## Process fix

The backup monitor must write actual checksum values and the comparison method
into its log, not a bare `COPY_CHECKSUM_VERIFIED` token, and must never be read
as proof on its own.
