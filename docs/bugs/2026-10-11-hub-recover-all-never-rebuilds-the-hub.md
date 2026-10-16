# Bug: `make hub-recover-all` never rebuilds the hub

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.2`
**Status:** LIVE-VERIFIED — live rebuild run `20261016T012103Z` (2026-10-15) rebuilt the hub; the manual recovery steps it exposed are filed separately. Was: IMPLEMENTED — landed `0214f363` (Codex a7e55457 + Claude: refuse on a failed `k3d cluster list`, real-wrapper test); `make test` 1594/1598 (4 reds = Python 3.15 `load_module` removal, env-only; 74/74 on 3.13), operator `make test-metrics` 3002 cases 0 failed. Pending the operator live proof below.
**Approval:** explicit 2026-10-11 "go ahead, please this a make <target> so that I won't make any mistake" (operator, to "Want me to file the `hub-recover-all` ordering bug")
**Priority:** P2 — the documented one-command rebuild cannot run; the workaround is a four-step manual sequence with a destructive teardown
**Severity:** medium — the operator needs this rebuild now to clear the dead kine compaction (`docs/bugs/2026-10-11-hermes-kine-sensor-misses-dead-compaction.md`)

## Symptom

`make hub-recover-all` is documented as "rebuild, credentials, then data" (`Makefile` comment,
`docs/howto/hub-dr-drill.md` "Restoring the hub", README v1.43.1 row). It cannot rebuild:

- **Hub running:** `hub_data_recover_preflight` passes, then `hub-recover` → `hub-up` → `bin/hub-up:37-38`
  prints `hub exists — skipping create`. The old cluster and its datastore stay. The data restore
  then runs on the same cluster. A dead kine compaction loop and a 1.9 GiB `state.db` survive.
- **Hub gone:** `hub_data_recover_preflight` calls `_hub_data_validate_target`
  (`scripts/plugins/hub_data.sh:849`), which requires a running `k3d-<cluster>-server-0`, the
  serverlb and the Vault/Keycloak/LDAP workloads. It returns 2, and nothing is rebuilt.

So the target only works on a hub that is already up, where it rebuilds nothing.

## Root cause

The recipe never deletes the hub, and the preflight assumes the hub is running. The rebuild was
done by hand on 2026-09-20 (`docs/howto/hub-rebuild-from-gitops-vault.md`, memory
`reference_hub_rebuild_hub_only_sequence`); that run also showed `k3d cluster delete` leaving a
container, network and volume that block re-creation. Neither step was put in the target.

## Fix

The approval stays first and is taken while the old hub can still be inspected. Then the target
deletes the hub, clears the leftovers, rebuilds, and resumes the data restore.

### 1. `scripts/plugins/hub_data.sh`, `hub_data_recover_preflight`

- Before `_hub_data_validate_target`, check whether the hub exists:
  `k3d cluster list 2>/dev/null | grep -q "^${cluster}[[:space:]]"`.
- **Present:** unchanged (validate, counts, `target.json`). Write `1` to `${run_dir}/hub_present`.
  Before the approval prompt, print to stderr:
  `[hub-recover] This DELETES the local hub '<cluster>' and rebuilds it, then restores export <ts>.`
- **Absent:** skip `_hub_data_validate_target`, the `server`/`nodes` reads and the live counts.
  Print `[hub-recover] No local hub '<cluster>': it will be built from scratch, then export <ts> restored.`
  to stderr. Write `target.json` with `server_url` and `nodes` empty, and `0` to `${run_dir}/hub_present`.
- The approval, `approval_time`, `approval_epoch`, `export_dir` and the `RUN_ID=` stdout line are
  unchanged in both cases.

### 2. `scripts/plugins/hub_data.sh`, new public `hub_data_recover_teardown`

`hub_data_recover_teardown <run_id>`. It reads `${K3DM_HUB_DATA_RECOVER_RUN_ROOT}/<run_id>/hub_present`;
a missing or unreadable file is an error (return 1).

- `hub_present` = `0`: print `[hub-recover] no hub to delete`, then go to the leftover check.
- `hub_present` = `1`: run
  `CLUSTER_PROVIDER=k3d HUB_CLUSTER_NAME=<cluster> "${_HUB_DATA_ROOT}/bin/cluster-down" --confirm --delete-hub`
  through a private wrapper `_hub_data_cluster_down` so tests can stub it. Never pass
  `--discard-hub-data`. A non-zero return is returned as-is (the snapshot guard's `exit 2` stops the run).
- Then, if `k3d cluster list` still lists the cluster, `_err` and return 1.
- **Leftovers**, removed by exact name, only when present, and only after the cluster is gone:
  - containers: each name from `docker ps -a --filter "label=k3d.cluster=<cluster>" --format '{{.Names}}'`
    with `docker rm -f -- <name>`;
  - network `k3d-<cluster>` with `docker network rm -- k3d-<cluster>`;
  - volume `k3d-<cluster>-images` with `docker volume rm -- k3d-<cluster>-images`.
  - Never remove `k3d-<cluster>-recovery-server-data` or any other volume, and never use a name
    pattern.
- After removal, if the label filter still lists a container, `_err` naming it and return 1.
- `<cluster>` is `${K3DM_HUB_DATA_CLUSTER:-k3d-cluster}`, as in the preflight.

### 3. `Makefile`, `hub-recover-all`

Insert the teardown between the preflight and `hub-recover`:

```make
	run_id=$$(sed -n 's/^RUN_ID=//p' "$$preflight"); \
	test -n "$$run_id"; \
	K3DM_HUB_DATA_RECOVER_RUN_ROOT="$$run_root" ./scripts/k3d-manager hub_data_recover_teardown "$$run_id"; \
	$(MAKE) --no-print-directory hub-recover; \
	RESUME=$$run_id ./scripts/k3d-manager hub_data_recover
```

Update the comment above the target to:
`## Full hub disaster recovery: approve, delete the hub, rebuild, credentials, then data (Terminal.app; approval typed at the prompt)`.

`hub_data_recover` on `RESUME` re-runs `_hub_data_validate_target` against the rebuilt hub and
reuses the recorded approval; `target.json` is report-only. Check that this holds and do not change it.

### 4. Docs

- `docs/howto/hub-dr-drill.md` "Restoring the hub": `make hub-recover-all` now deletes and
  rebuilds the hub after the typed approval, works when the hub is already gone, and clears the
  three k3d leftovers. The snapshot guard in `bin/cluster-down` still refuses without a verified
  snapshot. Data changed after the selected export is lost.
- `docs/howto/hub-rebuild-from-gitops-vault.md`: "Dead kine compaction" and "One command" name
  `make hub-recover-all` as the rebuild for a stalled kine. Keep the do-not-restart warning. Add the
  success check: `docker logs k3d-k3d-cluster-server-0 2>&1 | grep 'msg="COMPACT deleted'` returns
  a line about every 5 minutes.
- `CHANGELOG.md` `[Unreleased]` → `### Fixed`.

## Files

| File | Change |
|---|---|
| `scripts/plugins/hub_data.sh` | preflight present/absent; `hub_data_recover_teardown`, `_hub_data_cluster_down` |
| `Makefile` | `hub-recover-all` teardown step and comment |
| `scripts/tests/plugins/hub_data.bats` | tests below |
| `docs/howto/hub-dr-drill.md`, `docs/howto/hub-rebuild-from-gitops-vault.md` | sections above |
| `CHANGELOG.md` | `[Unreleased]` entry |

## Tests

`scripts/tests/plugins/hub_data.bats`. Stub `k3d`, `docker` and `_hub_data_cluster_down` with
functions or a fake `PATH`; no test may run a real `k3d`, `docker`, `bin/cluster-down` or `make up`.

1. **Preflight, hub present:** `k3d` lists the cluster → `_hub_data_validate_target` is called,
   stderr contains `DELETES the local hub`, `hub_present` is `1`, stdout is only `RUN_ID=`.
2. **Preflight, hub absent:** `k3d` lists nothing → `_hub_data_validate_target` is NOT called,
   stderr contains `built from scratch`, `hub_present` is `0`, the approval is still asked, rc 0.
3. **Teardown, present:** `_hub_data_cluster_down` is called once with `--confirm --delete-hub`, and
   the args never contain `--discard-hub-data`; after it, `k3d` lists nothing; `docker` stub lists
   container `k3d-k3d-cluster-agent-1` → the docker log shows exactly `rm -f -- k3d-k3d-cluster-agent-1`,
   `network rm -- k3d-k3d-cluster`, `volume rm -- k3d-k3d-cluster-images`, and no
   `recovery-server-data`.
4. **Teardown, absent:** `_hub_data_cluster_down` is not called; leftovers are still checked.
5. **Teardown, guard refuses:** `_hub_data_cluster_down` returns 2 → teardown returns 2 and no
   `docker` removal runs.
6. **Teardown, cluster survives:** `k3d` still lists the cluster after cluster-down → rc 1, no
   `docker` removal.
7. **Teardown, missing `hub_present`:** rc 1, `_hub_data_cluster_down` not called.
8. **Recipe order:** extend the B4-20 style test. Copy the repo, replace `scripts/k3d-manager`
   with a stub that prints `RUN_ID=t1` for `hub_data_recover_preflight` and logs its first argument
   otherwise, and pass `MAKE=<fake make that logs its args>` on the command line so `hub-recover`
   never runs for real. Assert the log order is `hub_data_recover_teardown`, then the fake make
   with `hub-recover`, then `hub_data_recover`.
9. **Recipe, teardown fails:** the stub returns 2 for `hub_data_recover_teardown` → make exits
   non-zero and neither `hub-recover` nor `hub_data_recover` is logged.

The existing B4-20 (refused preflight prevents `hub-recover`) must stay green and also assert that
`hub_data_recover_teardown` is not logged.

Mutations (each must turn a test red; restore with `cmp` against a snapshot):
- remove the teardown line from the recipe → test 8;
- pass `--discard-hub-data` → test 3;
- drop the "cluster still listed" check → test 6;
- call `_hub_data_validate_target` when the hub is absent → test 2.

Gates: `bats scripts/tests/plugins/hub_data.bats`, `shellcheck scripts/plugins/hub_data.sh`,
`make test` (read the per-suite counts).

## Proof it works

The operator runs `make hub-recover-all` in Terminal.app on the M4 against the current hub, whose
kine compaction has been dead since 2026-10-08. After the run:

- `k3d cluster list` shows a newly created `k3d-cluster`;
- `docker logs k3d-k3d-cluster-server-0 2>&1 | grep 'msg="COMPACT deleted'` returns a line about every 5 minutes;
- the report under `~/.k3dm/hub-recover/<run_id>/` is green;
- `HubKineCompactionStalled` resolves and the Hermes kine row shows `last compaction <N>m ago`.

## What NOT to Do

- Do NOT restart the k3s server or container as a shortcut.
- Do NOT pass `--discard-hub-data`, or bypass the snapshot guard in `bin/cluster-down`.
- Do NOT remove Docker objects by pattern, and never remove `k3d-<cluster>-recovery-server-data`.
- Do NOT move the approval after the teardown.
- Do NOT run `make hub-recover-all`, `make down` or any real `k3d`/`docker` mutation in tests or while verifying.
- Do NOT commit, push or create a PR. Claude verifies and commits.
- Do NOT modify files outside the Files list.

## Live proof 2026-10-15 — run `20261016T012103Z` (rebuild works; recovery needed manual steps)

The fix did what this bug asked: `make hub-recover-all` deleted and rebuilt the hub. Kine compaction
on the new server is healthy: `COMPACT deleted` every 5 minutes from the 02:01Z start, 17 runs by
03:06Z. The run finished with all 9 restore steps `rc 0`, verify checks V1–V5 and V8 `true`, and
an RTO of 4295 s.

It did not finish unattended. Six manual interventions were needed, filed as:

- `2026-10-15-hub-recover-all-checks-keychain-after-deleting-the-hub.md` (P2)
- `2026-10-15-hub-only-rebuild-never-creates-the-identity-application.md` (P2; also the ArgoCD/Keycloak port-forward agents)
- `2026-10-15-hub-recover-all-overwrites-the-dr-shards-its-restore-needs.md` (P1)
- `2026-10-15-hub-data-recover-steps-6-7-fail-on-a-fresh-hub.md` (P2; D1–D3, plus Grafana and credential-audit notes)

The `monitoring` namespace race in `make up` recurred on the hub path; see
`2026-06-24-observability-acg-monitoring-namespace-race.md`.
