# Hub snapshot retention: prune deletes the newest snapshots, and nothing prunes automatically

**Filed:** 2026-10-08, Claude (operator: "be sure we have a retention policy as we don't have unlimited space")
**Branch:** k3d-manager-v1.42.0
**Status:** SPEC — not started
**Priority:** P1 — the one retention tool we have deletes exactly the snapshots it should keep
**Severity:** High
**Component:** `scripts/plugins/hub_snapshot.sh` (`hub_snapshot_prune`, `hub_snapshot_capture`)
**Related:** `docs/bugs/2026-09-20-no-capture-producer-hub-pvc-data-unrecoverable.md` (rounds 1–5)

## Symptom

There is a retention setting, `K3DM_SNAPSHOT_KEEP` (default 3), and a `make snapshot-prune` target.
Two problems:

1. **`hub_snapshot_prune` keeps the oldest N and deletes the newest.** `_hub_snapshot_remote_names`
   returns names sorted ascending (`| sort`, line 184). The prune loop counts from the first
   entry and removes every entry after `_keep` — the newest ones. With four snapshots
   `0919 0920 0921 0922` and `KEEP=3`, it deletes `0922`. If that was the only snapshot under 24h
   old, the `DELETE_HUB=1` guard then refuses teardown and the freshest DR copy is gone.
2. **Nothing runs it.** `hub_snapshot_capture` never prunes. Each run adds ~3.3 GB to the M2 and
   the directory grows without bound unless the operator remembers `make snapshot-prune`.

Why the tests missed it: `prune keeps the configured verified snapshots` (hub_snapshot.bats:276)
only counts the survivors (`-eq 3`), never which ones survive.

## Context — M2 capacity (read 2026-10-08)

`df -h ~` on `m2jump`: 926 GiB, 369 GiB free. `KEEP=3` × ~3.3 GB ≈ 10 GB, so the default is
fine. The risk is unbounded growth and a full disk on the host that also runs the e2e runner, not
the default value.

## Fix (spec for Codex)

All in `scripts/plugins/hub_snapshot.sh` unless noted.

### 1. Prune keeps the newest N

In `hub_snapshot_prune`, iterate the verified names **newest first**. Change the verified loop so
the list it walks is in descending order, e.g. fill `_good` from
`_hub_snapshot_remote_names | sort -r`, or walk `_good` from the last index down. Keep everything
else in the function as is (incomplete removal, the "no verified snapshots" refusal, the
positive-integer check).

### 2. Extract a verified-only prune helper

Add `_hub_snapshot_prune_verified <keep>`: lists remote names, ignores `*.INCOMPLETE`, and removes
verified snapshots beyond the newest `<keep>`. It never removes anything when there are `<= keep`
verified snapshots. `hub_snapshot_prune` uses it for the verified half, so there is one ordering
implementation.

### 3. Capture prunes automatically after success

New setting at the top of the file, next to `K3DM_SNAPSHOT_KEEP`:

```bash
K3DM_SNAPSHOT_AUTO_PRUNE="${K3DM_SNAPSHOT_AUTO_PRUNE:-1}"
```

At the end of `hub_snapshot_capture`, **after** the stamp is written and the `captured` message is
printed:

- if `K3DM_SNAPSHOT_AUTO_PRUNE` is `1`, call `_hub_snapshot_prune_verified "$K3DM_SNAPSHOT_KEEP"`;
- if that fails, `_warn` (or `_err`) `[hub-snapshot] auto-prune failed; run make snapshot-prune`
  and still return 0 — the capture itself succeeded and is verified;
- auto-prune does **not** remove `*.INCOMPLETE` entries. A concurrent capture (terminal plus Slack
  `/k3dm snapshot`) uploads into its own `.INCOMPLETE` directory, and deleting it mid-upload would
  break that run. Instead, if any `*.INCOMPLETE` entries exist, print one line:
  `[hub-snapshot] N incomplete snapshot(s) on <host>; remove with make snapshot-prune`.

Manual `make snapshot-prune` keeps today's behaviour of removing all `*.INCOMPLETE` entries; it is
operator-run and not concurrent with itself.

Because the newest verified snapshot is always kept and `KEEP >= 1` is enforced, the snapshot just
captured can never be pruned. Validate `K3DM_SNAPSHOT_KEEP` before the upload, so a bad value fails
the run before any data moves rather than after.

### 4. Free-space preflight on the M2

New setting:

```bash
K3DM_SNAPSHOT_MIN_FREE_GB="${K3DM_SNAPSHOT_MIN_FREE_GB:-20}"
```

After `_hub_snapshot_checksums "$_stage"` and the remote `mkdir -p`, before rsync:

- local need: `du -sk "$_stage"` (KiB);
- remote free: `_hub_snapshot_ssh "df -Pk '$K3DM_SNAPSHOT_DIR' | awk 'NR==2 {print \$4}'"` (KiB;
  `-P` gives the same columns on macOS and Linux);
- if `free < need + MIN_FREE_GB*1024*1024`, `_err` naming the host, free GB and needed GB, remove the
  empty `${_remote}.INCOMPLETE` directory, and `return 1` without writing the stamp;
- a non-numeric `df` result is an error, not a pass.

Order the remote `mkdir -p` so `df` runs on a directory that exists.

### 5. Check the final rename (round-5 minor finding)

```bash
_hub_snapshot_ssh "mv -- '${_remote}.INCOMPLETE' '${_remote}'"
```

becomes a checked call: on failure, `_err "[hub-snapshot] rename failed for ${_timestamp}; left
${_remote}.INCOMPLETE"` and `return 1` — no stamp, no `captured` message, no auto-prune.

### 6. Docs

`docs/howto/hub-snapshots.md`, retention section:
- `make snapshot` now prunes to the newest `K3DM_SNAPSHOT_KEEP` (default 3) verified snapshots after
  a successful capture; `K3DM_SNAPSHOT_AUTO_PRUNE=0` turns that off;
- auto-prune leaves incomplete uploads alone; `make snapshot-prune` removes them;
- the free-space preflight and `K3DM_SNAPSHOT_MIN_FREE_GB`;
- rough sizing: ~3.3 GB per snapshot today.

CHANGELOG `[Unreleased]` → `### Fixed`: one entry for the ordering bug, `### Added` for auto-prune
and the preflight.

## Tests (`scripts/tests/plugins/hub_snapshot.bats`)

Existing stubs run `_hub_snapshot_ssh` against the local `$K3DM_SNAPSHOT_DIR`; reuse them.

1. **Prune keeps the newest N** — seed `0919 0920 0921 0922`, `KEEP=3`: `0919` is gone, `0920`,
   `0921`, `0922` all exist. Assert names, not a count.
2. **Capture auto-prunes** — seed three verified older snapshots, run `hub_snapshot_capture`
   (timestamp `20260922T000000Z`): exactly 3 verified remain, the new one is among them, the oldest
   is gone.
3. **Auto-prune leaves incomplete entries** — seed an older `*.INCOMPLETE`; after capture it still
   exists and the output names `make snapshot-prune`.
4. **`K3DM_SNAPSHOT_AUTO_PRUNE=0`** — seed three older verified; after capture all four exist.
5. **Auto-prune failure does not fail the capture** — override `_hub_snapshot_prune_verified` to
   return 1: status 0, stamp written, output contains `auto-prune failed`.
6. **Insufficient space** — `K3DM_SNAPSHOT_MIN_FREE_GB=999999999`: status non-zero, output names the
   host, rsync was not called (`RSYNC_LOG` empty or absent), no stamp, no `.INCOMPLETE` left.
7. **Non-numeric `df`** — override the df call path so it prints garbage: capture fails.
8. **Rename failure** — make `_hub_snapshot_ssh` fail only on a command containing `mv --`: status
   non-zero, no stamp, output contains `rename failed`, no prune happened (seeded older snapshots
   still present).

Update the existing count-only test at line 276 to assert names (or replace it with test 1).

**RED:** tests 1, 2, 5, 6 and 8 must fail against the pre-fix `hub_snapshot.sh` (temp worktree at
the pre-fix commit). Paste the failing names.

**GREEN:** `bats scripts/tests/plugins/hub_snapshot.bats scripts/tests/plugins/hub_recovery.bats`
and `shellcheck scripts/plugins/hub_snapshot.sh` — zero new warnings.

## Live verification (operator)

- `make snapshot` → `captured <ts>`, then the M2 holds at most 3 verified snapshots, newest kept.
- `make snapshot-list` shows the expected set.
- `make snapshot-prune` removes `20261009T014249Z.INCOMPLETE` (replaces the manual `rm -rf`).

## What NOT to do

- Do not change `_hub_snapshot_latest_verified`, the teardown guard, restore, or `bin/cluster-down`.
- Do not expose prune over Slack or the cloud bridge.
- Do not run a real `ssh`, `rsync`, `make snapshot` or `make snapshot-prune`.
- Do not touch `bin/cluster-status-summary` (its UNKNOWN-path item is a separate follow-up).
- No PR, no merge, no `main`, no `--no-verify`.
