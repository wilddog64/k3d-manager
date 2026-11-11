#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  TEST_SYNC_BIN="${REPO_SYNC_BIN:-$PROJECT_ROOT/bin/k3dm-repo-sync}"
  SCRATCH="$BATS_TEST_TMPDIR/repo-sync-backlog"
  case "$SCRATCH" in "$BATS_TEST_TMPDIR"/*) ;; *) return 1 ;; esac
  [ "$SCRATCH" != "$PROJECT_ROOT" ]

  mkdir -p "$SCRATCH/bin" "$SCRATCH/home/.config/k3d-manager" "$SCRATCH/state" "$SCRATCH/stubs"
  printf 'hub\n' > "$SCRATCH/home/.config/k3d-manager/machine-role"

  export HOME="$SCRATCH/home"
  export XDG_CONFIG_HOME="$SCRATCH/home/.config"
  export K3DM_REPO_SYNC_STATE_DIR="$SCRATCH/state"
  export K3DM_REPO_SYNC_TIMEOUT=3
  export PUSHGATEWAY_URL="http://127.0.0.1:9"

  git config --global init.defaultBranch main
  git config --global user.email test@example.invalid
  git config --global user.name test

  # Stub make for appsets-check (captured read-only on m5-air, 2026-11-10)
  cat > "$SCRATCH/stubs/make" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'INFO: [argocd] Expected values branch: deploy/hub' 'INFO: [argocd] All Applications reference values branch deploy/hub'
SH

  # Stub curl to absorb Pushgateway metric pushes without live network
  cat > "$SCRATCH/stubs/curl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$SCRATCH/stubs"/*
  export PATH="$SCRATCH/stubs:$PATH"

  git init --bare "$SCRATCH/upstream.git" >/dev/null
  git clone "$SCRATCH/upstream.git" "$SCRATCH/seed" >/dev/null 2>&1
  git -C "$SCRATCH/seed" checkout -b main >/dev/null
  echo base > "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" add file
  git -C "$SCRATCH/seed" commit -m base >/dev/null
  git -C "$SCRATCH/seed" push -u origin HEAD:main >/dev/null 2>&1
  git -C "$SCRATCH/seed" branch --set-upstream-to=origin/main main >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1

  HUB_ROOT="$SCRATCH/hub-checkout"
  git clone -b main "$SCRATCH/upstream.git" "$HUB_ROOT" >/dev/null 2>&1
  mkdir -p "$HUB_ROOT/bin" "$HUB_ROOT/scripts/lib/foundation/scripts/lib" "$HUB_ROOT/scripts/etc/machine"
  cp "$TEST_SYNC_BIN" "$HUB_ROOT/bin/k3dm-repo-sync"
  cp "$PROJECT_ROOT/scripts/lib/system.sh" "$HUB_ROOT/scripts/lib/system.sh"
  cp "$PROJECT_ROOT/scripts/lib/foundation/scripts/lib/system.sh" "$HUB_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
  cp "$PROJECT_ROOT/scripts/etc/machine/deploy-paths.tsv" "$HUB_ROOT/scripts/etc/machine/deploy-paths.tsv"
  chmod +x "$HUB_ROOT/bin/k3dm-repo-sync"

  export K3DM_REPO_SYNC_REPOS="$HUB_ROOT"
}

assert_scratch_fixture() {
  case "$SCRATCH" in "$BATS_TEST_TMPDIR"/*) ;; *) return 1 ;; esac
  case "$HOME" in "$SCRATCH"/*) ;; *) return 1 ;; esac
  [ "$SCRATCH" != "$PROJECT_ROOT" ]
  [ -d "$SCRATCH/upstream.git" ]
  [ -d "$HUB_ROOT/.git" ]
}

@test "E1: hub-sync promote backlog equals commits upstream has that deploy/hub lacks even when local ref was stale" {
  assert_scratch_fixture

  # Advance deploy/hub on remote by 1 commit
  echo promoted > "$SCRATCH/seed/promoted.txt"
  git -C "$SCRATCH/seed" add promoted.txt
  git -C "$SCRATCH/seed" commit -m "promoted commit" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1

  # Advance main on remote by 2 commits beyond deploy/hub
  echo backlog1 > "$SCRATCH/seed/backlog1.txt"
  git -C "$SCRATCH/seed" add backlog1.txt
  git -C "$SCRATCH/seed" commit -m "backlog 1" >/dev/null
  echo backlog2 > "$SCRATCH/seed/backlog2.txt"
  git -C "$SCRATCH/seed" add backlog2.txt
  git -C "$SCRATCH/seed" commit -m "backlog 2" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1

  # Local upstream ref in HUB_ROOT has not been fetched yet and is stale
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]

  [ -f "$SCRATCH/state/state.json" ]
  promote_count="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["promote_backlog"])' "$SCRATCH/state/state.json")"
  [ "$promote_count" = "2" ]

  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"promote backlog: 2"* ]]
  [[ "$output" != *"promote backlog: 0"* ]]
  [[ "$output" != *"promote backlog: unknown"* ]]
}

@test "E2: fetching upstream branch does not advance hub checkout past origin deploy/hub" {
  assert_scratch_fixture

  echo promoted > "$SCRATCH/seed/promoted.txt"
  git -C "$SCRATCH/seed" add promoted.txt
  git -C "$SCRATCH/seed" commit -m "promoted commit" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  promoted_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"

  echo backlog > "$SCRATCH/seed/backlog.txt"
  git -C "$SCRATCH/seed" add backlog.txt
  git -C "$SCRATCH/seed" commit -m "backlog commit" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
  main_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"

  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]

  hub_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
  [ "$hub_head" = "$promoted_sha" ]
  [ "$hub_head" != "$main_sha" ]
  [ -z "$(git -C "$HUB_ROOT" status --porcelain --untracked-files=no)" ]
}

@test "E3: if upstream fetch fails promote backlog says unknown instead of a wrong number" {
  assert_scratch_fixture

  # Initial sync runs and succeeds so local refs exist
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]

  # Break origin remote URL so fetch fails
  git -C "$HUB_ROOT" remote set-url origin "file://$SCRATCH/nonexistent.git"

  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]

  [ -f "$SCRATCH/state/state.json" ]
  promote_val="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["promote_backlog"])' "$SCRATCH/state/state.json")"
  [ "$promote_val" = "None" ]

  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"promote backlog: unknown"* ]]
  [[ ! "$output" =~ "promote backlog: "[0-9]+ ]]
}

@test "E3 positive control: when fetch succeeds promote backlog is numeric not unknown" {
  assert_scratch_fixture

  echo backlog > "$SCRATCH/seed/backlog.txt"
  git -C "$SCRATCH/seed" add backlog.txt
  git -C "$SCRATCH/seed" commit -m "backlog commit" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1

  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]

  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"promote backlog: 1"* ]]
  [[ "$output" != *"promote backlog: unknown"* ]]
}
