# Bug: dr-drill preflight spends about 15 minutes cloning the snapshots branch only to read the latest export's name

**Status:** OPEN — captured 2026-11-25, not triaged
**Priority:** P3 (operator, 2026-11-25: "go ahead to file P3") — slow, not broken: the drill completes; the clone adds about
**Classified:** P2 by gemini-4-argon-medium, 2026-11-25 — `dr-drill` preflight is degraded by a 15-minute full snapshot clone just to check export age, though the drill still completes
**Triage:** backlog — pull into a release that already touches `bin/dr-drill` (operator, 2026-11-25); Argon blind classification, Claude verified
15 minutes to every run before any cluster work starts.
**Introduced by:** v1.43.0 (`edfc9a5c`, preflight export-age check added with the drill)
**Should have been caught by:** live check (the first drill runs would have shown the duration; nobody timed the phase)
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-25
**Prior art:** docs/bugs/ exact-slug glob (no match); `make find-similar-docs` not run — vector store unavailable
(context `k3d-k3d-cluster` does not exist)

## Symptom

`make dr-drill` on m2-air, 2026-11-25 (commit at or after `cf743007`, branch `k3d-manager-v1.45.1`). Phase 1/6 preflight
ran `git clone --depth 1 --branch snapshots git@github-k3dm-hub-data:wilddog64/k3dm-hub-data.git …/preflight-repo` from
about 09:07 to about 09:22 local time; `bin/hub-up` started at 09:22. Observed by Claude polling the drill's child processes
over SSH once a minute (read-only), so the times are accurate to about one minute.

## Where

`bin/dr-drill:138-149` `_dr_drill_latest_export`: the clone exists only so `_hub_data_latest_export_dir` can find the newest
export directory and its timestamp, which feeds the export-age check (`<= 93600` seconds). None of the file contents are
read at this point.

## Not yet known

- Why a single-branch depth-1 clone takes 15 minutes: snapshot size at the tip, link speed on m2, or both. Not measured.
- Whether the later restore (`hub_data_restore`) clones the same branch again, which would double the cost.

## Candidate directions (for whoever investigates; not a decision)

- List the tip's tree without file contents (for example a blob-less clone, `--filter=blob:none --no-checkout`, then read
  the directory names from the tree), so the age check costs one small fetch.
- Reuse the preflight clone for the restore if the restore clones the same branch again.

## Acceptance (draft, for triage)

- must: the preflight export-age check takes under one minute on m2-air with the same snapshots branch.
- must_not: the age check accepts an export older than 93600 seconds, or passes when the snapshots branch cannot be read
  (both red on a stub that drops the check).
