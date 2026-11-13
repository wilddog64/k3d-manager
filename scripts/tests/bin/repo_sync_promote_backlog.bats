#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

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
printf '%s\n' "$*" >> "$MAKE_LOG"
printf '%s\n' 'INFO: [argocd] Expected values branch: deploy/hub' 'INFO: [argocd] All Applications reference values branch deploy/hub'
SH

  # Stub curl to absorb Pushgateway metric pushes without live network
  cat > "$SCRATCH/stubs/curl" <<'SH'
#!/usr/bin/env bash
while (($#)); do
  if [[ "$1" == --data-binary ]]; then shift; printf '%s\n' "$1" > "$CURL_BODY"; fi
  shift
done
exit 0
SH
  cat > "$SCRATCH/stubs/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
sha="${3#*/commits/}"
sha="${sha%%/*}"
# gh api check-runs shape captured read-only on m4-air.local, 2026-11-11: records contain conclusion, name, status.
if [[ "${GH_FAIL_SHA:-}" == "$sha" ]]; then exit 1; fi
if [[ "${GH_GREEN_SHA:-}" == "$sha" ]]; then printf '{"status":"completed","conclusion":"success","name":"CI"}\n'; else printf '{"status":"in_progress","conclusion":null,"name":"CI"}\n'; fi
SH
  chmod +x "$SCRATCH/stubs"/*
  export CURL_BODY="$SCRATCH/curl.body" GH_LOG="$SCRATCH/gh.log" MAKE_LOG="$SCRATCH/make.log"
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
  cp "$PROJECT_ROOT/bin/k3dm-hub-promote" "$HUB_ROOT/bin/k3dm-hub-promote"
  cp "$PROJECT_ROOT/scripts/lib/system.sh" "$HUB_ROOT/scripts/lib/system.sh"
  cp "$PROJECT_ROOT/scripts/lib/foundation/scripts/lib/system.sh" "$HUB_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
  cp "$PROJECT_ROOT/scripts/etc/machine/deploy-paths.tsv" "$HUB_ROOT/scripts/etc/machine/deploy-paths.tsv"
  chmod +x "$HUB_ROOT/bin/k3dm-repo-sync"

  export K3DM_REPO_SYNC_REPOS="$HUB_ROOT"
}

@test "E1: hub sync publishes the newest green commit and checks no more than ten" {
  assert_scratch_fixture
  for n in {1..12}; do
    echo "$n" > "$SCRATCH/seed/change"
    git -C "$SCRATCH/seed" add change
    git -C "$SCRATCH/seed" commit -m "candidate $n" >/dev/null
  done
  newest="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  deploy_before="$(git -C "$SCRATCH/seed" rev-parse origin/deploy/hub)"
  hub_before="$(git -C "$HUB_ROOT" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  GH_GREEN_SHA="$(git -C "$SCRATCH/seed" rev-parse HEAD~9)"
  export GH_GREEN_SHA
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q "k3dm_repo_sync_promotable{repo=\"k3d-manager\",sha=\"${GH_GREEN_SHA:0:7}\",branch=\"main\"} 1" "$CURL_BODY"
  [[ "$(wc -l < "$GH_LOG" | tr -d ' ')" -eq 10 ]]
  grep -q "promotable: ${GH_GREEN_SHA:0:7}" <("$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary)
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" != "$newest" ]
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$hub_before" ]
  [ "$(git -C "$SCRATCH/upstream.git" rev-parse refs/heads/deploy/hub)" = "$deploy_before" ]
  if grep -Eq 'hub-promote|platform-ops|appsets-reapply' "$MAKE_LOG"; then return 1; fi
}

@test "E2: lookup failure reports unknown and publishes no SHA" {
  assert_scratch_fixture
  echo candidate > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m candidate >/dev/null
  candidate="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  export GH_FAIL_SHA="$candidate"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q 'k3dm_repo_sync_promote_lookup_failed{repo="k3d-manager"} 1' "$CURL_BODY"
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [[ "$output" == *"promotable: unknown"* ]]
}

@test "E3: no green candidate publishes no promotable series and worker publishes nothing" {
  assert_scratch_fixture
  echo pending > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m pending >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [[ "$output" == *"promotable: none"* ]]

  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
  grep -q 'k3dm_repo_sync_promote_backlog_commits{repo="k3d-manager"} 0' "$CURL_BODY"

  printf 'worker\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  rm -f "$CURL_BODY"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  [ ! -e "$CURL_BODY" ]
  [ "$(wc -l < "$GH_LOG" | tr -d ' ')" -eq 1 ]
}

@test "E4: exhausting ten checks in a backlog of twelve reports unknown" {
  assert_scratch_fixture
  for n in {1..12}; do
    echo "$n" > "$SCRATCH/seed/change"
    git -C "$SCRATCH/seed" add change
    git -C "$SCRATCH/seed" commit -m "pending $n" >/dev/null
  done
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$GH_LOG" | tr -d ' ')" -eq 10 ]
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
  grep -q 'k3dm_repo_sync_promote_lookup_failed{repo="k3d-manager"} 0' "$CURL_BODY"
  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [[ "$output" == *"promotable: unknown"* ]]
}

@test "E5: one failed check lookup carries an unpromoted SHA through the unknown cycle" {
  assert_scratch_fixture
  echo green > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m green >/dev/null
  candidate="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  export GH_GREEN_SHA="$candidate"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q "sha=\"${candidate:0:7}\"" "$CURL_BODY"

  export GH_FAIL_SHA="$candidate"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q 'k3dm_repo_sync_promote_lookup_failed{repo="k3d-manager"} 1' "$CURL_BODY"
  grep -q "k3dm_repo_sync_promotable{repo=\"k3d-manager\",sha=\"${candidate:0:7}\",branch=\"main\"} 1" "$CURL_BODY"

  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
  grep -q 'k3dm_repo_sync_promote_backlog_commits{repo="k3d-manager"} 0' "$CURL_BODY"
}

@test "E6: an is-green output decode exception reports unknown" {
  assert_scratch_fixture
  echo candidate > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m candidate >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  cat > "$HUB_ROOT/bin/k3dm-hub-promote" <<'SH'
#!/usr/bin/env bash
printf '\377'
SH
  chmod +x "$HUB_ROOT/bin/k3dm-hub-promote"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [[ "$output" == *"promotable: unknown"* ]]
  grep -q 'k3dm_repo_sync_promote_lookup_failed{repo="k3d-manager"} 1' "$CURL_BODY"
  deploy_sha="$(git -C "$SCRATCH/seed" rev-parse origin/deploy/hub)"
  [[ "$output" == *"deploy/hub ${deploy_sha:0:7}"* ]]
}

@test "E7: sync reuses the upstream branch resolved before the backlog query" {
  assert_scratch_fixture
  echo green > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m green >/dev/null
  candidate="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  GH_GREEN_SHA="$candidate"
  REAL_GIT_BIN="$(command -v git)"
  GIT_ALLOWED_ROOT="$HUB_ROOT"
  export GH_GREEN_SHA REAL_GIT_BIN GIT_ALLOWED_ROOT
  cat > "$SCRATCH/stubs/git" <<'SH'
#!/usr/bin/env bash
[[ "$*" == *"$GIT_ALLOWED_ROOT"* ]] || exit 98
if [[ -e "$BACKLOG_READ" && " $* " == *" rev-parse --abbrev-ref --symbolic-full-name @{upstream}"* ]]; then
  exit 1
fi
if [[ " $* " == *" rev-list --count origin/deploy/hub..origin/main "* ]]; then : > "$BACKLOG_READ"; fi
exec "$REAL_GIT_BIN" "$@"
SH
  export BACKLOG_READ="$SCRATCH/backlog-read"
  chmod +x "$SCRATCH/stubs/git"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$GH_LOG" | tr -d ' ')" -eq 1 ]
  grep -q "sha=\"${candidate:0:7}\"" "$CURL_BODY"
}

@test "E8: promotable range uses the configured remote, not origin" {
  assert_scratch_fixture
  git init --bare "$SCRATCH/other-upstream.git" >/dev/null
  git -C "$SCRATCH/seed" push "$SCRATCH/other-upstream.git" HEAD:refs/heads/main >/dev/null 2>&1
  git -C "$SCRATCH/seed" push "$SCRATCH/other-upstream.git" HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  echo green > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m green >/dev/null
  candidate="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push "$SCRATCH/other-upstream.git" HEAD:refs/heads/main >/dev/null 2>&1
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  git -C "$HUB_ROOT" remote add upstream "$SCRATCH/other-upstream.git"
  git -C "$HUB_ROOT" config branch.main.remote upstream
  git -C "$HUB_ROOT" config branch.main.merge refs/heads/main
  git -C "$HUB_ROOT" fetch origin +refs/heads/deploy/hub:refs/remotes/origin/deploy/hub >/dev/null 2>&1
  export GH_GREEN_SHA="$candidate"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q "k3dm_repo_sync_promotable{repo=\"k3d-manager\",sha=\"${candidate:0:7}\",branch=\"main\"} 1" "$CURL_BODY"
}

@test "E9: is-green errors other than not-green report lookup failure" {
  assert_scratch_fixture
  echo candidate > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m candidate >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  cat > "$HUB_ROOT/bin/k3dm-hub-promote" <<'SH'
#!/usr/bin/env bash
printf '[hub-promote] ERROR: synthetic die-style failure\n' >&2
exit "${IS_GREEN_RC:-1}"
SH
  chmod +x "$HUB_ROOT/bin/k3dm-hub-promote"
  export IS_GREEN_RC=1
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q 'k3dm_repo_sync_promote_lookup_failed{repo="k3d-manager"} 1' "$CURL_BODY"
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
  export IS_GREEN_RC=127
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q 'k3dm_repo_sync_promote_lookup_failed{repo="k3d-manager"} 1' "$CURL_BODY"
  run "$HUB_ROOT/bin/k3dm-repo-sync" --hub-summary
  [[ "$output" == *"promotable: unknown"* ]]
}

@test "E10: fetch failure carries the prior SHA using local tracking refs" {
  assert_scratch_fixture
  echo green > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m green >/dev/null
  candidate="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  export GH_GREEN_SHA="$candidate"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q "sha=\"${candidate:0:7}\"" "$CURL_BODY"

  git -C "$HUB_ROOT" remote set-url origin "$SCRATCH/missing-origin.git"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q "k3dm_repo_sync_promotable{repo=\"k3d-manager\",sha=\"${candidate:0:7}\",branch=\"main\"} 1" "$CURL_BODY"

  git -C "$HUB_ROOT" update-ref refs/remotes/origin/deploy/hub "$candidate"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
}

@test "E11: lookup failure does not carry a SHA already deployed" {
  assert_scratch_fixture
  echo X > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m X >/dev/null
  old_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  export GH_GREEN_SHA="$old_sha"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]

  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  echo Y >> "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" commit -am Y >/dev/null
  new_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  export GH_FAIL_SHA="$new_sha"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q 'k3dm_repo_sync_promote_lookup_failed{repo="k3d-manager"} 1' "$CURL_BODY"
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
}

@test "E12: lookup failure does not carry a SHA absent from upstream history" {
  assert_scratch_fixture
  echo X > "$SCRATCH/seed/change"
  git -C "$SCRATCH/seed" add change
  git -C "$SCRATCH/seed" commit -m X >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/main >/dev/null 2>&1
  GH_GREEN_SHA="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  export GH_GREEN_SHA
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]

  git -C "$SCRATCH/seed" checkout --orphan replacement >/dev/null 2>&1
  git -C "$SCRATCH/seed" rm -rf . >/dev/null 2>&1
  echo Y > "$SCRATCH/seed/replacement"
  git -C "$SCRATCH/seed" add replacement
  git -C "$SCRATCH/seed" commit -m replacement >/dev/null
  new_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push --force origin HEAD:refs/heads/main >/dev/null 2>&1
  export GH_FAIL_SHA="$new_sha"
  run "$HUB_ROOT/bin/k3dm-repo-sync"
  [ "$status" -eq 0 ]
  grep -q 'k3dm_repo_sync_promote_lookup_failed{repo="k3d-manager"} 1' "$CURL_BODY"
  if grep -q 'k3dm_repo_sync_promotable{' "$CURL_BODY"; then return 1; fi
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
