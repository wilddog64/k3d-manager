#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch: open lists only unfinished tasks without writes" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  # Event shapes copied from the M4 ledger, 2026-11-01.
  cat >"$K3DM_WORKTREE_ROOT/ledger.jsonl" <<'LEDGER'
{"ts":1,"event":"start","version":"v9.9.9","slug":"pending","repo":"k3d-manager"}
{"ts":2,"event":"codex_exit","version":"v9.9.9","slug":"pending","repo":"k3d-manager"}
{"ts":1,"event":"start","version":"v9.9.9","slug":"done","repo":"k3d-manager"}
{"ts":2,"event":"land","version":"v9.9.9","slug":"done","repo":"k3d-manager"}
{"ts":1,"event":"start","version":"v8.0.0","slug":"other","repo":"k3d-manager"}
LEDGER
  cp "$K3DM_WORKTREE_ROOT/ledger.jsonl" "$BATS_TEST_TMPDIR/before"
  run dispatch open --version v9.9.9
  [ "$status" -eq 1 ]; [[ "$output" == *"v9.9.9 pending "*" codex_exit"* ]]
  [[ "$output" != *done* && "$output" != *other* ]]
  run dispatch open --version v7.0.0
  [ "$status" -eq 0 ]; [ -z "$output" ]
  cmp "$BATS_TEST_TMPDIR/before" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$(find "$K3DM_WORKTREE_ROOT" -mindepth 1 | wc -l | tr -d ' ')" -eq 1 ]
}

