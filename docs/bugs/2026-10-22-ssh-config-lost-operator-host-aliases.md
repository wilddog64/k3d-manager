# Bug: `~/.ssh/config` lost its operator host aliases; hub data export and M2 disk probe fail

**Filed:** 2026-10-22 (Claude, from firing HubDataExportFailed/Stale and HostDiskMetricsStale)
**Status:** OPEN — symptom and impact confirmed; what emptied the file is not yet identified
**Priority:** P2 — nightly DR export stopped (last success 2026-10-21 03:32 PDT); workaround: restore the aliases by hand
**Severity:** medium
**Approval:** pending — investigation approved by the operator 2026-10-22 ("go ahead"); no fix dispatched
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** M4 `~/.ssh/config`; ACG SSH config writers in lib-foundation `scripts/lib/acg/acg.sh`
(`_acg_update_ssh_config`, `_acg_upsert_ssh_host`); `scripts/plugins/hub_data.sh`; `bin/k3dm-disk-metrics`
**Related:** `docs/bugs/2026-10-11-hub-data-export-fails-under-launchd-and-dr-alerts-never-deployed.md`,
`docs/bugs/2026-10-21-k3s-aws-ssh-target-uses-alias-instead-of-ip.md`, `docs/howto/hub-dr-drill.md`

## Symptom

- `HubDataExportFailed` and `HubDataExportStale` fire on the hub. The 2026-10-22 03:30 PDT launchd
  run (`com.k3d-manager.hub-data-export`, last exit 1) logged
  `ssh: Could not resolve hostname github-k3dm-hub-data` and pushed nothing.
- `HostDiskMetricsStale` fires. `bin/k3dm-disk-metrics` (run by Hermes) probes target
  `m2=m2jump:k3dm-snapshots`; `ssh -G m2jump` now resolves to hostname `m2jump`, i.e. no alias.

## Evidence

- `~/.ssh/config` was last written 2026-10-21 19:36 PDT and is 365 bytes. It holds only
  `Host ubuntu-1`, `Host ubuntu-2` and `Host ubuntu` (ACG sandbox nodes). The
  `github-k3dm-hub-data` and `m2jump` entries the export and disk probe depend on are gone.
- The file's exact shape (leading blank line, no blank line between blocks, `ubuntu-1`, `ubuntu-2`,
  then `ubuntu`) matches `_acg_upsert_ssh_host` appending three new blocks to an **empty** file.
  So the file was emptied or recreated before 19:36, and the ACG provisioning then repopulated only
  its own hosts. `_acg_update_ssh_config` and `_acg_upsert_ssh_host` rewrite the file in place but
  do not truncate other hosts, so they are not by themselves the cause.
- No `~/.ssh/config` backup exists. `known_hosts.bak` (18:53) and `known_hosts` (19:40) show SSH
  housekeeping ran in that window; `bin/cluster-up` Step 0 prunes `known_hosts`, not `config`.
- The 2026-10-21 03:32 export succeeded, so the alias existed then.

## Open question (root cause)

What emptied or replaced `~/.ssh/config` between 2026-10-21 03:32 and 19:36 PDT. Candidates to
check: a test that wrote the real `$HOME/.ssh/config` instead of a temp `HOME`; an agent or manual
edit during the 2026-10-21 k3s-aws SSH-target work; a sandbox teardown path.

## Recovery (operator)

Restore the two aliases in `~/.ssh/config` (above the ACG blocks): `github-k3dm-hub-data`
(`HostName github.com`, `User git`, `IdentityFile ~/.ssh/k3dm-hub-data-write`, `IdentitiesOnly yes`,
per `docs/howto/hub-dr-drill.md`) and `m2jump` (operator's own values). Then
`ssh -o BatchMode=yes -T git@github-k3dm-hub-data` and `ssh -G m2jump`, and run
`launchctl kickstart gui/$(id -u)/com.k3d-manager.hub-data-export` to export today.

## Fix direction (after root cause)

Keep operator aliases out of the file tools rewrite: put them in `~/.ssh/config.d/operator` and have
`~/.ssh/config` start with `Include ~/.ssh/config.d/*`, or move ACG hosts to their own included file
written by `acg.sh`. Either way, any test touching SSH config must run under a temp `HOME`. An
Acceptance block is added once the cause is known.
