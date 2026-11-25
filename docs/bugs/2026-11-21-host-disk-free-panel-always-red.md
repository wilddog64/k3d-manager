# Bug: Host Disk "Free" panel is red for every host

**Status:** OPEN — captured 2026-11-21 from an operator screenshot
**Priority:** P3 (cosmetic: the values are right, the colour reads as an alarm)
**Triage:** patch → v1.46.1 (operator, 2026-11-25: "go with patch release v1.46.1"); Argon blind classification, Claude verified
**Branch:** `k3d-manager-v1.46.1` (not cut yet)
**Introduced by:** unknown
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Cosmetic Grafana threshold misconfiguration where the Host Disk "Free" bytes panel renders every host above 80 bytes in red.)
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** exact-slug glob none; read 2026-10-30-host-disk-labels-the-new-hub-as-m4-and-cannot-reach-m2.md (different root cause); `make find-similar-docs` not run (vector store unavailable)

## Symptom

Grafana Host Disk, 2026-11-21: Free shows hostinger 156 GiB, m2 405 GiB, m4 197 GiB, m5 772 GiB, all in red. Used % on the
same hosts is 16.7-57.3 %, green. m4-air `df -h /` the same evening: 461G size, 197G avail, 58 %.

## Cause

`scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml` panel 2 (`Free`, unit `bytes`,
`k3dm_disk_avail_bytes`) has no `thresholds`, so Grafana's default (green, red at 80) applies to bytes: anything above
80 bytes is red.

## Fix direction (not decided)

Give panel 2 a fixed neutral colour, or thresholds in bytes that mirror Used % (for example red below 10 % of
`k3dm_disk_size_bytes` needs a ratio, so a fixed colour is simpler).
