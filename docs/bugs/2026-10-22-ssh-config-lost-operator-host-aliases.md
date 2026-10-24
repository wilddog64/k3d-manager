# Bug: `~/.ssh/config` lost its operator host aliases; hub data export and M2 disk probe fail

**Filed:** 2026-10-22 (Claude, from firing HubDataExportFailed/Stale and HostDiskMetricsStale)
**Status:** VERIFIED 2026-10-24 (E2, guard half) — operator moved both aliases into `~/.ssh/config.d/operator` (08:10 PDT) with `Include` as line 1; both resolve (`github.com`, `m2-air.local`). Claude ran `_ssh_config_guard --repair` with `K3DM_SSH_CONFIG` on a copy without the `Include`: WARN for both aliases, `restored Include`, rc 0, both resolve from the copy; real config untouched. Pending: the 2026-10-25 03:30 export logs no guard WARN and HubDataExportStale stays clear. Was FIXED (offline) — `f3002d12` (2026-10-23): `_ssh_config_guard` restores the aliases from `~/.ssh/config.d/operator` before the nightly export and at cluster-up Step 0. Live E2 pending: the operator moves the aliases into the fragment; what emptied the file is still unidentified
**Priority:** P2 — nightly DR export stopped (last success 2026-10-21 03:32 PDT); workaround: restore the aliases by hand
**Fix commit:** `f3002d12`
**Severity:** medium
**Approval:** approved — operator, 2026-10-22: "go ahead for that ssh-config spec" (fix spec F1–F6)
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

## Root cause status (2026-10-22)

Not identified. The full canary BATS run (2307 tests) left a canary `~/.ssh/config` intact, which
rules out the repo's own tests. All k3d-manager writers (`acg.sh` `_acg_update_ssh_config` /
`_acg_upsert_ssh_host`, `k3s-gcp.sh` and `k3s-az.sh` add/remove) read the file and preserve other
hosts. The fix is therefore preventive: recover the aliases automatically, and record enough
to identify the culprit if it happens again.

An `Include` alone does not protect against this: emptying `~/.ssh/config` deletes the
`Include` line too. The operator's aliases need a home that no tool writes, plus a repair step
that restores the `Include`.

## Fix

- **F1.** New `scripts/lib/ssh_config_guard.sh` with `_ssh_config_guard [--repair] <alias>...`.
  - Fragment: `${K3DM_SSH_OPERATOR_FRAGMENT:-$HOME/.ssh/config.d/operator}`, owned by the operator
    and only ever read by tools. Config: `${K3DM_SSH_CONFIG:-$HOME/.ssh/config}`.
  - For each alias, it is **present** when `ssh -G -F <config> <alias>` reports a `hostname` that
    differs from the alias (an undefined alias resolves to itself).
  - All present: return 0 silently.
  - A missing alias: log `WARN: [ssh-guard] ~/.ssh/config missing alias(es): <list> (config <bytes>
    bytes, mtime <ISO time>)`. This line is the forensics record.
  - With `--repair`, and only when the fragment exists and defines every missing alias: copy the
    config to `<config>.k3dm-guard.<UTC timestamp>` (mode 600; keep the newest 5). Then insert
    `Include <fragment>` as the first line, unless that line already exists, and write via a temp
    file + `mv` with mode 600. Re-check; log `INFO: [ssh-guard] restored Include for <list>` and
    return 0 if every alias is now present, else return 1.
  - Without `--repair`, or without a usable fragment: return 1, and name the fragment path in
    the message.
  - It never writes inside the fragment and never removes or reorders existing lines.
- **F2.** `hub_data_export_scheduled` calls
  `_ssh_config_guard --repair github-k3dm-hub-data` before `hub_data_export`. If the guard fails,
  export fails as today (failure metric), and the log carries the guard line.
- **F3.** `bin/cluster-up` Step 0 calls `_ssh_config_guard --repair` with the aliases in
  `K3DM_SSH_REQUIRED_ALIASES` (default `github-k3dm-hub-data m2jump`). It warns and does not fail:
  a missing operator alias must not block a sandbox bring-up.
- **F4.** `docs/howto/hub-dr-drill.md`: a short "SSH aliases" section. Move `github-k3dm-hub-data`
  and `m2jump` into `~/.ssh/config.d/operator`, put `Include ~/.ssh/config.d/operator` at the top of
  `~/.ssh/config`, check with `ssh -G`, and note what the guard does and that its backups exist.
  The operator does the one-time move by hand; no tool migrates it.
- **F5.** Tests: `scripts/tests/lib/ssh_config_guard.bats` under a temp `HOME`, using
  `K3DM_SSH_CONFIG` and `K3DM_SSH_OPERATOR_FRAGMENT`. Real `ssh -G` (no network), with a stub only
  where `ssh` is absent. Cover: all present; config emptied and repaired; fragment missing; fragment
  lacks the alias; idempotent (a second repair adds no second `Include`); existing lines and
  ACG `Host ubuntu*` blocks preserved byte for byte after the `Include`; backup written and capped
  at 5. Add a hub_data test showing the guard runs before export and a failed guard fails the export.
- **F6.** `CHANGELOG.md` entry.

## Files

- `scripts/lib/ssh_config_guard.sh` (new)
- `scripts/plugins/hub_data.sh`
- `bin/cluster-up`
- `docs/howto/hub-dr-drill.md`
- `scripts/tests/lib/ssh_config_guard.bats` (new), `scripts/tests/plugins/hub_data.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: When ~/.ssh/config lacks a required alias and the operator fragment defines it, _ssh_config_guard --repair restores resolution of the alias by inserting a single Include line at the top, and returns 0.
  - id: M2
    text: Every guard run that finds a missing alias logs one WARN line naming the aliases, the config size and mtime.
  - id: M3
    text: Before any repair write, the previous config is saved to a timestamped .k3dm-guard backup (mode 600); at most 5 are kept.
  - id: M4
    text: hub_data_export_scheduled runs the guard with --repair for github-k3dm-hub-data before exporting; cluster-up Step 0 runs it for K3DM_SSH_REQUIRED_ALIASES and continues on failure.
must_not:
  - id: N1
    text: The guard must not remove, reorder or change any existing line of ~/.ssh/config (red against a naive rewrite).
  - id: N2
    text: A second --repair run must not add a second Include line.
  - id: N3
    text: The guard must not write the fragment, and must not modify the config when the fragment is missing or lacks the alias.
  - id: N4
    text: No test reads or writes the real $HOME/.ssh; nothing under scripts/lib/foundation/ changes.
  - id: N5
    text: cluster-up must not fail solely because an operator alias is missing.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4, N5]
    text: bats scripts/tests/lib/ssh_config_guard.bats scripts/tests/plugins/hub_data.bats green; the hub_data guard-ordering test red on the pre-fix plugin.
  - id: E2
    kind: live
    proves: [M1, M4]
    text: After the operator moves the aliases into the fragment, Claude runs the guard against a copy of ~/.ssh/config with the Include removed (K3DM_SSH_CONFIG pointing at the copy); ssh -G resolves both aliases afterwards. The next 03:30 export logs no guard WARN and HubDataExportStale stays clear.
interface:
  - _ssh_config_guard [--repair] <alias>... (scripts/lib/ssh_config_guard.sh)
  - K3DM_SSH_CONFIG, K3DM_SSH_OPERATOR_FRAGMENT, K3DM_SSH_REQUIRED_ALIASES
  - hub_data_export_scheduled
  - bin/cluster-up Step 0
```

## Definition of Done

- [ ] F1–F6 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 and the guard-ordering test shown red against the pre-fix code.
- [ ] `shellcheck scripts/lib/ssh_config_guard.sh` clean; the two suites green.
- [ ] Commit: `fix(ssh): restore operator ssh aliases from an included fragment before export and cluster-up`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT read or write the real `~/.ssh` in tests, read any private key, or print `IdentityFile` contents.
- Do NOT change `scripts/lib/foundation/` (ACG writers stay as they are).
- Do NOT migrate the operator's aliases automatically.

## Impact found 2026-10-22: the nightly DR export failed

The scheduled `hub_data_export_scheduled` run at 03:30 PDT on 2026-10-22 failed at the clone of
`github-k3dm-hub-data:wilddog64/k3dm-hub-data.git` ("Please make sure you have the correct access
rights"), because that Host alias was missing. It pushed the failure metric only, so
`HubDataExportStale` fired once 36h had passed since the last good export (2026-10-21 03:32 PDT),
at about 16:02 PDT. The 17:01 PDT run, after the alias was restored, succeeded (snapshot
`20261023T000111Z`) and pushed a fresh `k3dm_hub_data_export_last_success_timestamp_seconds`.
Losing the aliases silently breaks DR backups, so this raises the stakes of the preventive fix.
