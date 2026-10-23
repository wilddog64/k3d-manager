#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-land-pending"
  export FIXTURE="$BATS_TEST_TMPDIR/fixture" ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export K3DM_WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktrees"
  export K3DM_CODEX_DISPATCH_BIN="$BATS_TEST_TMPDIR/dispatch-stub" STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  export STUB_STATE="exited successfully"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$FIXTURE" 2>/dev/null
  git -C "$FIXTURE" checkout -q -b k3d-manager-v9.9.9
  git -C "$FIXTURE" config user.email test@example.com; git -C "$FIXTURE" config user.name Test
  mkdir -p "$FIXTURE/docs/bugs" "$FIXTURE/memory-bank"
  printf 'original\n' >"$FIXTURE/a.txt"
  printf '# Progress\n' >"$FIXTURE/memory-bank/progress.md"
  cat >"$FIXTURE/docs/bugs/demo.md" <<'EOF'
# Bug: demo

**Status:** OPEN
**Priority:** P3

## Definition of Done

- [ ] Commit: `fix(demo): change a`
EOF
  git -C "$FIXTURE" add -A; git -C "$FIXTURE" commit -q -m base
  git -C "$FIXTURE" push -q -u origin k3d-manager-v9.9.9 2>/dev/null
  git -C "$FIXTURE" worktree add -q -b task/v9.9.9/demo "$K3DM_WORKTREE_ROOT/v9.9.9/demo" 2>/dev/null
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/demo" config user.email test@example.com
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/demo" config user.name Test
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/demo.run"
  printf 'docs/bugs/demo.md\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/demo.run/spec"
  printf 'changed\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/demo/a.txt"
  cat >"$K3DM_CODEX_DISPATCH_BIN" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_LOG"
case "$1" in
  status) echo "task: $2"; echo "state: $STUB_STATE" ;;
  land) git -C "$FIXTURE" merge -q --ff-only task/v9.9.9/demo ;;
esac
STUB
  chmod +x "$K3DM_CODEX_DISPATCH_BIN"
}

@test "commits with the spec's message, lands, pushes and marks the spec review pending" {
  cd "$FIXTURE"
  run "$SCRIPT" --slug demo --test "true"
  [ "$status" -eq 0 ]
  [[ "$output" == *"review pending"* ]]
  grep -q -- "land --slug demo --test true" "$STUB_LOG"
  [ "$(git -C "$FIXTURE" log -1 --format=%s HEAD~1)" = "fix(demo): change a" ]
  grep -q '^\*\*Status:\*\* LANDED — Claude review pending (`' docs/bugs/demo.md
  run grep -c '^\*\*Status:\*\*' docs/bugs/demo.md
  [ "$output" = 1 ]
  grep -q '\*\*demo\*\* landed .* Claude review + live evidence pending' memory-bank/progress.md
  [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse k3d-manager-v9.9.9)" ]
}

@test "never marks a task verified or fixed" {
  cd "$FIXTURE"
  run "$SCRIPT" --slug demo --test "true"
  [ "$status" -eq 0 ]
  run grep -i -E 'verified|FIXED' docs/bugs/demo.md memory-bank/progress.md
  [ "$status" -ne 0 ]
}

@test "refuses a task that has not exited successfully, before committing or landing" {
  export STUB_STATE="running"
  cd "$FIXTURE"
  run "$SCRIPT" --slug demo --test "true"
  [ "$status" -ne 0 ]
  [[ "$output" == *"has not exited successfully"* ]]
  run grep -q '^land' "$STUB_LOG"
  [ "$status" -ne 0 ]
  [ -n "$(git -C "$K3DM_WORKTREE_ROOT/v9.9.9/demo" status --porcelain)" ]
}

@test "refuses when the checkout is not on a release branch" {
  cd "$FIXTURE"
  git checkout -q -b feature
  run "$SCRIPT" --slug demo --test "true"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a release branch"* ]]
}

@test "refuses a dirty main checkout" {
  cd "$FIXTURE"
  printf 'local edit\n' >>a.txt
  run "$SCRIPT" --slug demo --test "true"
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
  run grep -q '^land' "$STUB_LOG"
  [ "$status" -ne 0 ]
}

@test "refuses a spec with no commit line" {
  cd "$FIXTURE"
  sed -i.bak '/Commit:/d' docs/bugs/demo.md && rm -f docs/bugs/demo.md.bak
  git commit -q -am "drop commit line" && git push -q origin k3d-manager-v9.9.9 2>/dev/null
  run "$SCRIPT" --slug demo --test "true"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no '- [ ] Commit:"* ]]
}

@test "requires --test" {
  cd "$FIXTURE"
  run "$SCRIPT" --slug demo
  [ "$status" -eq 2 ]
}

@test "reads the 'Commit message:' form too" {
  source "$SCRIPT"
  printf -- '- [ ] Commit message: `feat(x): y`.\n' >"$BATS_TEST_TMPDIR/spec.md"
  [ "$(_lp_commit_message "$BATS_TEST_TMPDIR/spec.md")" = "feat(x): y" ]
}
