#!/usr/bin/env bats

setup() {
  root=$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)
  fixture="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$fixture/scripts/ci" "$fixture/scripts/etc/fast-gate" "$fixture/scripts/tests/lib"
  [ "$fixture" != "$root" ]
  cp "$root/scripts/ci/fast_gate.sh" "$fixture/scripts/ci/"
  cp "$root/scripts/tests/tripwire.sh" "$fixture/scripts/tests/"
  printf '%s\n' scripts/tests/lib/static.bats > "$fixture/scripts/etc/fast-gate/static.list"
  printf '#!/usr/bin/env bats\n@test "static" { true; }\n' > "$fixture/scripts/tests/lib/static.bats"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email test@example.com
  git -C "$fixture" config user.name Test
  printf 'old\n' > "$fixture/thing.txt"
  for name in one two; do printf '#!/usr/bin/env bats\n# thing.txt\n@test "%s" { true; }\n' "$name" > "$fixture/scripts/tests/lib/$name.bats"; done
  printf '#!/usr/bin/env bats\n@test "unrelated" { true; }\n' > "$fixture/scripts/tests/lib/unrelated.bats"
  git -C "$fixture" add .
  git -C "$fixture" commit -qm base
  base=$(git -C "$fixture" rev-parse HEAD)
}

@test "fast gate: selects named tests and static suite only" {
  printf 'new\n' >> "$fixture/thing.txt"
  git -C "$fixture" commit -qam change
  run bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS scripts/tests/lib/one.bats'* && "$output" == *'PASS scripts/tests/lib/two.bats'* ]]
  [[ "$output" == *'PASS scripts/tests/lib/static.bats'* && "$output" != *unrelated.bats* && "$output" == *TOTAL* ]]
  [[ "$output" != *'ok 1 '* && "$output" == *'SLOWEST scripts/tests/lib/'* ]]
}

@test "fast gate: failing tests fail the gate" {
  printf '#!/usr/bin/env bats\n@test "failure" { false; }\n' > "$fixture/scripts/tests/lib/static.bats"
  git -C "$fixture" commit -qam change
  run bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -ne 0 ]
  [[ "$output" == *'FAIL scripts/tests/lib/static.bats'*'not ok 1 failure'* ]]
}

@test "fast gate: pre-push rejects lint failure and preserves main guard" {
  mkdir -p "$fixture/.githooks"
  cp "$root/.githooks/pre-push" "$fixture/.githooks/pre-push"
  cp "$root/scripts/tests/lib/bats_negation_lint.bats" "$fixture/scripts/tests/lib/"
  printf '%s\n' scripts/tests/lib/bats_negation_lint.bats > "$fixture/scripts/etc/fast-gate/static.list"
  git -C "$fixture" add .
  git -C "$fixture" commit -qm hook
  git init --bare -q "$BATS_TEST_TMPDIR/remote.git"
  git -C "$fixture" remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git -C "$fixture" -c core.hooksPath=/dev/null push -q origin HEAD:refs/heads/topic
  git -C "$fixture" config core.hooksPath .githooks
  printf '  %s grep x file\n' '!' >> "$fixture/scripts/tests/lib/one.bats"
  git -C "$fixture" commit -qam broken
  run git -C "$fixture" push origin HEAD:refs/heads/topic
  [ "$status" -ne 0 ]
  [[ "$output" == *'FAIL scripts/tests/lib/bats_negation_lint.bats'* ]]
  run git -C "$fixture" push origin HEAD:refs/heads/main
  [ "$status" -ne 0 ]
  [[ "$output" == *'refusing to push'* ]]
  run env K3DM_SKIP_FAST_GATE=1 git -C "$fixture" push origin HEAD:refs/heads/topic
  [ "$status" -eq 0 ]
  [[ "$output" == *'fast gate skipped'* ]]
}

@test "fast gate: reports a missing yamllint" {
  mkdir -p "$fixture/.github/workflows" "$BATS_TEST_TMPDIR/path"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/path/bats"
  chmod +x "$BATS_TEST_TMPDIR/path/bats"
  printf 'name: example\n' > "$fixture/.github/workflows/example.yml"
  git -C "$fixture" add .github/workflows/example.yml
  git -C "$fixture" commit -qm workflow
  run bash -c 'cd "$1" && PATH="$3:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base" "$BATS_TEST_TMPDIR/path"
  [ "$status" -eq 0 ]
  [[ "$output" == *'SKIP yamllint 0s'* ]]
}

@test "fast gate: shellcheck uses CI error severity" {
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck unavailable"
  cat > "$fixture/info.sh" <<'SH'
#!/bin/bash
echo '$HOME'
SH
  run shellcheck "$fixture/info.sh"
  [ "$status" -ne 0 ]; [[ "$output" == *SC2016* ]]
  git -C "$fixture" add info.sh
  git -C "$fixture" commit -qm info
  run bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -eq 0 ]; [[ "$output" == *'PASS shellcheck info.sh'* ]]
  printf '#!/bin/bash\nif then\n' > "$fixture/error.sh"
  git -C "$fixture" add error.sh
  git -C "$fixture" commit -qm error
  run bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -ne 0 ]; [[ "$output" == *'FAIL shellcheck error.sh'* ]]
}

@test "fast gate: parallel and serial results preserve selection order" {
  for name in three four five six seven; do
    printf '#!/usr/bin/env bats\n# thing.txt\n@test "%s" { true; }\n' "$name" > "$fixture/scripts/tests/lib/$name.bats"
  done
  git -C "$fixture" add scripts/tests/lib
  printf 'new\n' >> "$fixture/thing.txt"
  git -C "$fixture" commit -qam change
  run bash -c 'cd "$1" && FAST_GATE_JOBS=1 scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -eq 0 ]
  serial=$(printf '%s\n' "$output" | sed -n 's/^PASS \(.*\) [0-9][0-9]*s$/\1/p')
  run bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -eq 0 ]
  parallel=$(printf '%s\n' "$output" | sed -n 's/^PASS \(.*\) [0-9][0-9]*s$/\1/p')
  [ "$serial" = "$parallel" ]
  [ "$(printf '%s\n' "$parallel" | wc -l | tr -d ' ')" -eq 8 ]
}

@test "fast gate: workers preserve SIGINT disposition at default and one job" {
  cat > "$fixture/scripts/tests/lib/signal.bats" <<'BATS'
#!/usr/bin/env bats
@test "SIGINT is not ignored" {
  python3 -c 'import signal; assert signal.getsignal(signal.SIGINT) != signal.SIG_IGN'
}
BATS
  git -C "$fixture" add scripts/tests/lib/signal.bats
  git -C "$fixture" commit -qm signal
  for jobs in 1 4; do
    if [ "$jobs" -eq 1 ]; then
      run bash -c 'cd "$1" && FAST_GATE_JOBS=1 scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
    else
      run bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
    fi
    [ "$status" -eq 0 ]; [[ "$output" == *'PASS scripts/tests/lib/signal.bats'* ]]
  done
}

@test "fast gate: without promtool deselects marked tests and runs the rest" {
  local python
  python=$(python3 -c 'import sys; print(sys.executable)')
  if ! "$python" -m pytest --version >/dev/null 2>&1 && [[ -x "$HOME/.pyenv/shims/python3" ]]; then
    python="$HOME/.pyenv/shims/python3"
  fi
  "$python" -m pytest --version >/dev/null 2>&1 || skip "pytest unavailable"
  mkdir -p "$fixture/scripts/tests/bin" "$BATS_TEST_TMPDIR/path"
  cat > "$fixture/scripts/tests/bin/test_dashboard_queries.py" <<'PYTEST'
import pytest
@pytest.mark.external
def test_requires_promtool():
    assert False

def test_panel_count():
    assert True
PYTEST
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/path/bats"
  chmod +x "$BATS_TEST_TMPDIR/path/bats"
  git -C "$fixture" add scripts/tests/bin/test_dashboard_queries.py
  git -C "$fixture" commit -qm pytest
  run bash -c 'cd "$1" && PATH="$3:/usr/bin:/bin:/usr/sbin:/sbin" PYTEST="$4 -m pytest" /bin/bash scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base" "$BATS_TEST_TMPDIR/path" "$python"
  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS scripts/tests/bin/test_dashboard_queries.py'* ]]
  [[ "$output" == *'SKIP scripts/tests/bin/test_dashboard_queries.py promtool tests (promtool not installed): scripts/tests/bin/test_dashboard_queries.py::test_requires_promtool'* ]]
}

@test "fast gate: tree-mutating suite finishes before parallel tree copies" {
  mkdir -p "$fixture/scripts/tests/bin"
  cat > "$fixture/scripts/tests/bin/ask_bash_scope.bats" <<'BATS'
#!/usr/bin/env bats
@test "temporary tree file" {
  touch tree-copy-marker
  sleep 1
  rm tree-copy-marker
}
BATS
  cat > "$fixture/scripts/tests/bin/machine_setup_acceptance.bats" <<'BATS'
#!/usr/bin/env bats
@test "tree copy" {
  [ ! -e tree-copy-marker ]
}
BATS
  git -C "$fixture" add scripts/tests/bin
  git -C "$fixture" commit -qm suites
  run bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS scripts/tests/bin/ask_bash_scope.bats'* && "$output" == *'PASS scripts/tests/bin/machine_setup_acceptance.bats'* ]]
}

@test "fast gate: linked worktree push isolates fixture git and guard detects repository changes" {
  mkdir -p "$fixture/.githooks"
  cp "$root/.githooks/pre-push" "$fixture/.githooks/pre-push"
  git init --bare -q "$BATS_TEST_TMPDIR/remote.git"
  git -C "$fixture" remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git -C "$fixture" config core.bare false
  cat > "$fixture/scripts/tests/lib/static.bats" <<'BATS'
#!/usr/bin/env bats
@test "fixture git environment" {
  [ -z "${GIT_DIR+x}${GIT_WORK_TREE+x}${GIT_INDEX_FILE+x}${GIT_COMMON_DIR+x}${GIT_OBJECT_DIRECTORY+x}${GIT_ALTERNATE_OBJECT_DIRECTORIES+x}${GIT_NAMESPACE+x}${GIT_PREFIX+x}" ]
  mkdir "$BATS_TEST_TMPDIR/probe"
  git -C "$BATS_TEST_TMPDIR/probe" init -q
  (cd "$BATS_TEST_TMPDIR/probe" && git config core.bare true)
  [ "$(git -C "$BATS_TEST_TMPDIR/probe" config core.bare)" = true ]
}
BATS
  git -C "$fixture" add .
  git -C "$fixture" commit -qm probe
  git -C "$fixture" -c core.hooksPath=/dev/null push -q origin HEAD:refs/heads/topic
  git -C "$fixture" config core.hooksPath .githooks
  git -C "$fixture" worktree add -qb linked "$BATS_TEST_TMPDIR/linked"
  [ "$(cd "$(git -C "$BATS_TEST_TMPDIR/linked" rev-parse --git-common-dir)" && pwd -P)" = "$(cd "$fixture/.git" && pwd -P)" ]
  git -C "$fixture" config --local --list > "$BATS_TEST_TMPDIR/config.before"
  git -C "$fixture" branch --list > "$BATS_TEST_TMPDIR/branches.before"
  git -C "$fixture" worktree list --porcelain > "$BATS_TEST_TMPDIR/worktrees.before"
  printf 'change\n' >> "$BATS_TEST_TMPDIR/linked/thing.txt"
  git -C "$BATS_TEST_TMPDIR/linked" commit -qam change
  # The commit advances the linked branch; capture the state immediately before push.
  git -C "$fixture" branch --list > "$BATS_TEST_TMPDIR/branches.before"
  git -C "$fixture" worktree list --porcelain > "$BATS_TEST_TMPDIR/worktrees.before"
  run git -C "$BATS_TEST_TMPDIR/linked" push origin HEAD:refs/heads/topic
  [ "$status" -eq 0 ]; [[ "$output" == *'PASS scripts/tests/lib/static.bats'* ]]
  [ "$(git -C "$fixture" config core.bare)" = false ]
  git -C "$fixture" config --local --list > "$BATS_TEST_TMPDIR/config.after"
  git -C "$fixture" branch --list > "$BATS_TEST_TMPDIR/branches.after"
  git -C "$fixture" worktree list --porcelain > "$BATS_TEST_TMPDIR/worktrees.after"
  cmp "$BATS_TEST_TMPDIR/config.before" "$BATS_TEST_TMPDIR/config.after"
  cmp "$BATS_TEST_TMPDIR/branches.before" "$BATS_TEST_TMPDIR/branches.after"
  cmp "$BATS_TEST_TMPDIR/worktrees.before" "$BATS_TEST_TMPDIR/worktrees.after"
  # Control: the hook's inherited worktree gitdir redirects an unqualified write.
  mkdir "$BATS_TEST_TMPDIR/control"
  git -C "$BATS_TEST_TMPDIR/control" init -q
  local gitdir
  gitdir=$(git -C "$BATS_TEST_TMPDIR/linked" rev-parse --absolute-git-dir)
  (cd "$BATS_TEST_TMPDIR/control" && GIT_DIR="$gitdir" git config core.bare true)
  [ "$(git --git-dir="$fixture/.git" config core.bare)" = true ]
  git --git-dir="$fixture/.git" config core.bare false
  # A suite that explicitly targets the pushed repository must trip the guard.
  cat > "$BATS_TEST_TMPDIR/linked/scripts/tests/lib/static.bats" <<BATS
#!/usr/bin/env bats
@test "mutate repository" { git -C "$fixture" config user.name Intruder; }
BATS
  run bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$BATS_TEST_TMPDIR/linked" "$base"
  [ "$status" -ne 0 ]; [[ "$output" == *'FAIL repository user changed'* ]]
}

@test "fast gate: timeout kills a hung suite and permits a short suite" {
  cat > "$fixture/scripts/tests/lib/static.bats" <<BATS
#!/usr/bin/env bats
@test "hung probe" { echo \$\$ > "$BATS_TEST_TMPDIR/probe.pid"; exec sleep 300; }
BATS
  run bash -c 'cd "$1" && FAST_GATE_SUITE_TIMEOUT=5 scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -ne 0 ]
  [[ "$output" == *'FAIL scripts/tests/lib/static.bats'*'timed out after 5s'* ]]
  run kill -0 "$(cat "$BATS_TEST_TMPDIR/probe.pid")"
  [ "$status" -ne 0 ]
  printf '#!/usr/bin/env bats\n@test "short probe" { sleep 1; }\n' > "$fixture/scripts/tests/lib/static.bats"
  run bash -c 'cd "$1" && FAST_GATE_SUITE_TIMEOUT=5 scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS scripts/tests/lib/static.bats'* ]]
}
