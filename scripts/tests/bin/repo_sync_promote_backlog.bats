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

@test "E4: missing upstream branch leaves hub sync healthy and backlog unknown" {
  assert_scratch_fixture

  git -C "$SCRATCH/seed" checkout -b k3d-manager-test >/dev/null 2>&1
  git -C "$SCRATCH/seed" push -u origin HEAD >/dev/null 2>&1
  git -C "$HUB_ROOT" fetch origin '+refs/heads/k3d-manager-test:refs/remotes/origin/k3d-manager-test' >/dev/null 2>&1
  git -C "$HUB_ROOT" branch --set-upstream-to=origin/k3d-manager-test main >/dev/null
  git -C "$SCRATCH/seed" checkout main >/dev/null 2>&1

  echo promoted > "$SCRATCH/seed/promoted.txt"
  git -C "$SCRATCH/seed" add promoted.txt
  git -C "$SCRATCH/seed" commit -m "promoted while release branch is deleted" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  promoted_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/upstream.git" branch -D k3d-manager-test >/dev/null

  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]

  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$promoted_sha" ]
  result="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repositories"][0]["result"])' "$SCRATCH/state/state.json")"
  [ "$result" != "fetch_failed" ]

  backlog="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["promote_backlog"])' "$SCRATCH/state/state.json")"
  [ "$backlog" = "None" ]

  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"promote backlog: unknown"* ]]
}

@test "E5: existing upstream branch keeps the correct backlog count" {
  assert_scratch_fixture

  git -C "$SCRATCH/seed" checkout -b k3d-manager-test >/dev/null 2>&1
  git -C "$SCRATCH/seed" push -u origin HEAD >/dev/null 2>&1
  git -C "$HUB_ROOT" fetch origin '+refs/heads/k3d-manager-test:refs/remotes/origin/k3d-manager-test' >/dev/null 2>&1
  git -C "$HUB_ROOT" branch --set-upstream-to=origin/k3d-manager-test main >/dev/null
  git -C "$SCRATCH/seed" checkout main >/dev/null 2>&1

  echo backlog1 > "$SCRATCH/seed/backlog1.txt"
  git -C "$SCRATCH/seed" add backlog1.txt
  git -C "$SCRATCH/seed" commit -m "backlog 1" >/dev/null
  echo backlog2 > "$SCRATCH/seed/backlog2.txt"
  git -C "$SCRATCH/seed" add backlog2.txt
  git -C "$SCRATCH/seed" commit -m "backlog 2" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/k3d-manager-test >/dev/null 2>&1

  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  backlog="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["promote_backlog"])' "$SCRATCH/state/state.json")"
  [ "$backlog" = "2" ]
}

@test "E6: pruned upstream tracking ref does not stop hub fast-forward" {
  assert_scratch_fixture

  git -C "$SCRATCH/seed" checkout -b k3d-manager-test >/dev/null 2>&1
  git -C "$SCRATCH/seed" push -u origin HEAD >/dev/null 2>&1
  git -C "$HUB_ROOT" fetch origin '+refs/heads/k3d-manager-test:refs/remotes/origin/k3d-manager-test' >/dev/null 2>&1
  git -C "$HUB_ROOT" branch --set-upstream-to=origin/k3d-manager-test main >/dev/null
  git -C "$SCRATCH/seed" checkout main >/dev/null 2>&1

  echo promoted > "$SCRATCH/seed/promoted.txt"
  git -C "$SCRATCH/seed" add promoted.txt
  git -C "$SCRATCH/seed" commit -m "promoted after deleting release branch" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  promoted_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/upstream.git" branch -D k3d-manager-test >/dev/null
  git -C "$HUB_ROOT" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  run git -C "$HUB_ROOT" remote prune origin
  [ "$status" -eq 0 ]
  [[ "$output" == *"[pruned] origin/k3d-manager-test"* ]]
  run git -C "$HUB_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
  [ "$status" -ne 0 ]

  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$promoted_sha" ]
  result="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repositories"][0]["result"])' "$SCRATCH/state/state.json")"
  [ "$result" = "updated" ]
  backlog="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["promote_backlog"])' "$SCRATCH/state/state.json")"
  [ "$backlog" = "None" ]

  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"promote backlog: unknown"* ]]
}

@test "E7: check mode reports promote backlog as unknown when refs are unfetched" {
  assert_scratch_fixture

  echo backlog1 > "$SCRATCH/seed/backlog1.txt"
  git -C "$SCRATCH/seed" add backlog1.txt
  git -C "$SCRATCH/seed" commit -m "unfetched backlog 1" >/dev/null
  echo backlog2 > "$SCRATCH/seed/backlog2.txt"
  git -C "$SCRATCH/seed" add backlog2.txt
  git -C "$SCRATCH/seed" commit -m "unfetched backlog 2" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
  [ "$(git -C "$HUB_ROOT" rev-parse origin/main)" != "$(git -C "$SCRATCH/seed" rev-parse main)" ]
  [ "$(git -C "$HUB_ROOT" rev-list --count origin/deploy/hub..origin/main)" = "0" ]

  run "$HUB_ROOT/bin/k3dm-repo-sync" --check
  [ "$status" -eq 0 ]
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$(git -C "$HUB_ROOT" rev-parse origin/main)" ]
  backlog="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["promote_backlog"])' "$SCRATCH/state/state.json")"
  [ "$backlog" = "None" ]

  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"promote backlog: unknown"* ]]
}

@test "E8: upstream fetch timeout leaves sync result healthy and backlog unknown" {
  assert_scratch_fixture

  git -C "$SCRATCH/seed" checkout -b k3d-manager-test >/dev/null 2>&1
  git -C "$SCRATCH/seed" push -u origin HEAD >/dev/null 2>&1
  git -C "$HUB_ROOT" fetch origin '+refs/heads/k3d-manager-test:refs/remotes/origin/k3d-manager-test' >/dev/null 2>&1
  git -C "$HUB_ROOT" branch --set-upstream-to=origin/k3d-manager-test main >/dev/null
  git -C "$SCRATCH/seed" checkout main >/dev/null 2>&1

  echo promoted > "$SCRATCH/seed/promoted.txt"
  git -C "$SCRATCH/seed" add promoted.txt
  git -C "$SCRATCH/seed" commit -m "promoted while upstream fetch is slow" >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  promoted_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"

  real_git_bin="$(command -v git)"
  capture_file="$SCRATCH/upstream-fetch-stub.capture"
  export REAL_GIT_BIN="$real_git_bin"
  export UPSTREAM_FETCH_CAPTURE="$capture_file"
  cat > "$SCRATCH/stubs/git" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = "+refs/heads/k3d-manager-test:refs/remotes/origin/k3d-manager-test" ]; then
    "$REAL_GIT_BIN" "$@" > "$UPSTREAM_FETCH_CAPTURE.output" 2>&1
    fetch_status=$?
    {
      printf 'host=%s date_utc=%s\n' "$(hostname)" "$(date -u +%Y-%m-%d)"
      printf 'fetch_status=%s\n' "$fetch_status"
      cat "$UPSTREAM_FETCH_CAPTURE.output"
    } > "$UPSTREAM_FETCH_CAPTURE"
    exec sleep 2
  fi
done
exec "$REAL_GIT_BIN" "$@"
SH
  chmod +x "$SCRATCH/stubs/git"
  export PATH="$SCRATCH/stubs:$PATH"
  export K3DM_REPO_SYNC_UPSTREAM_TIMEOUT=1

  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$promoted_sha" ]
  result="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repositories"][0]["result"])' "$SCRATCH/state/state.json")"
  [ "$result" = "updated" ]
  backlog="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["promote_backlog"])' "$SCRATCH/state/state.json")"
  [ "$backlog" = "None" ]
  [ -s "$capture_file" ]
  grep -Fqx 'fetch_status=0' "$capture_file"

  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"promote backlog: unknown"* ]]
}
