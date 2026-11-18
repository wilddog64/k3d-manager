#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export HOME="$BATS_TEST_TMPDIR/home" K3DM_WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktrees"
  export K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9
  mkdir -p "$HOME" "$K3DM_WORKTREE_ROOT"
  export FIXTURE="$BATS_TEST_TMPDIR/manager" ORIGIN="$BATS_TEST_TMPDIR/manager.git"
  export DIRUSED="$BATS_TEST_TMPDIR/dirused" DORIGIN="$BATS_TEST_TMPDIR/dirused.git"
  export K3DM_PROJECTS_LIST="$BATS_TEST_TMPDIR/projects.list"
  git init --bare "$ORIGIN" >/dev/null
  git clone "$ORIGIN" "$FIXTURE" >/dev/null
  git -C "$FIXTURE" checkout -b k3d-manager-v1.44.2 >/dev/null
  git -C "$FIXTURE" config user.email test@example.com
  git -C "$FIXTURE" config user.name Test
  mkdir -p "$FIXTURE/docs/plans" "$FIXTURE/scripts/ci" "$FIXTURE/memory-bank"
  printf 'base\n' >"$FIXTURE/a.txt"
  printf '#!/bin/sh\nexit 0\n' >"$FIXTURE/scripts/ci/fast_gate.sh"
  printf '# Spec\n\n**Intent approved:** test, 2026-11-17\n\n## Files\n\n| File |\n|---|\n| `a.txt` |\n' >"$FIXTURE/docs/plans/v1.44.2-demo.md"
  git -C "$FIXTURE" add .
  git -C "$FIXTURE" commit -m base >/dev/null
  git -C "$FIXTURE" push -u origin k3d-manager-v1.44.2 >/dev/null
  git init --bare "$DORIGIN" >/dev/null
  git clone "$DORIGIN" "$DIRUSED" >/dev/null
  git -C "$DIRUSED" config user.email test@example.com
  git -C "$DIRUSED" config user.name Test
  git -C "$DIRUSED" checkout -b feat >/dev/null
  printf 'base\n' >"$DIRUSED/a.txt"
  git -C "$DIRUSED" add .; git -C "$DIRUSED" commit -m base >/dev/null
  git -C "$DIRUSED" push -u origin feat >/dev/null
  git -C "$DIRUSED" tag v0.0.4; git -C "$DIRUSED" push origin v0.0.4 >/dev/null
  printf 'k3d-manager|%s|wilddog64/k3d-manager|branch|main\ndirused|%s|wilddog64/dirused|tag|main\n' "$FIXTURE" "$DIRUSED" >"$K3DM_PROJECTS_LIST"
  [ -d "$FIXTURE/.git" ] && [ -d "$DIRUSED/.git" ] && [ -f "$K3DM_PROJECTS_LIST" ]
  export K3DM_CODEX_BIN="$BATS_TEST_TMPDIR/codex"
  cat >"$K3DM_CODEX_BIN" <<'EOF'
#!/bin/sh
printf 'session id: 01a122dd-71c3-7763-87f0-3de505f10168\n'
EOF
  chmod +x "$K3DM_CODEX_BIN"
}

dispatch() { (cd "$FIXTURE" && "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" "$@"); }

@test "project P1: registry parses; unknown and malformed projects are refused" {
  run dispatch start --project nope --spec docs/plans/v1.44.2-demo.md
  [ "$status" -eq 2 ]; [[ "$output" == *k3d-manager* && "$output" == *dirused* ]]
  printf 'bad|line|missing|tag\n' >"$K3DM_PROJECTS_LIST"
  run dispatch start --project bad --spec docs/plans/v1.44.2-demo.md
  [ "$status" -eq 2 ]; [[ "$output" == *line*1* ]]
}

@test "project P2: dirused start is versioned by the project, not k3d-manager" {
  run dispatch start --project dirused --spec docs/plans/v1.44.2-demo.md --slug p2 --branch feat
  [ "$status" -eq 0 ]; [ -f "$K3DM_WORKTREE_ROOT/v0.0.5/p2.run/project" ]
  [ "$(cat "$K3DM_WORKTREE_ROOT/v0.0.5/p2.run/project")" = dirused ]
  jq -e -s 'any(.[]; .slug=="p2" and .version=="v0.0.5" and .project=="dirused")' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch start --project dirused --version v0.1.0 --spec docs/plans/v1.44.2-demo.md --slug p2b --branch feat
  [ "$status" -eq 0 ]; [ -d "$K3DM_WORKTREE_ROOT/v0.1.0/p2b" ]
}

@test "project P3: k3d-manager start is unchanged" {
  run dispatch start --spec docs/plans/v1.44.2-demo.md --slug p3a
  [ "$status" -eq 0 ]; [ ! -e "$K3DM_WORKTREE_ROOT/v1.44.2/p3a.run/project" ]
  run dispatch start --project k3d-manager --spec docs/plans/v1.44.2-demo.md --slug p3b
  [ "$status" -eq 0 ]; [ ! -e "$K3DM_WORKTREE_ROOT/v1.44.2/p3b.run/project" ]
  jq -e -s 'all(.[]; .slug!="p3a" and .slug!="p3b" or (has("project")|not))' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch start --version v0.1.0 --spec docs/plans/v1.44.2-demo.md
  [ "$status" -eq 2 ]
}

@test "project P4: land, abandon and resume find a dirused task from a k3d-manager release branch" {
  mkdir -p "$K3DM_WORKTREE_ROOT/v0.0.5/p4.run"
  git -C "$DIRUSED" worktree add -b task/v0.0.5/p4 "$K3DM_WORKTREE_ROOT/v0.0.5/p4" origin/feat >/dev/null
  printf 'dirused\n' >"$K3DM_WORKTREE_ROOT/v0.0.5/p4.run/project"
  printf '%s\n' "$DIRUSED" >"$K3DM_WORKTREE_ROOT/v0.0.5/p4.run/repo"
  printf 'dirused\n' >"$K3DM_WORKTREE_ROOT/v0.0.5/p4.run/repo-name"
  printf 'feat\n' >"$K3DM_WORKTREE_ROOT/v0.0.5/p4.run/target"
  printf '{"event":"start","version":"v0.0.5","slug":"p4","project":"dirused"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch abandon --slug p4 --reason x --yes
  [ "$status" -eq 0 ]; jq -e -s '.[-1].version=="v0.0.5" and .[-1].project=="dirused"' "$K3DM_WORKTREE_ROOT/ledger.jsonl"

  run dispatch start --project dirused --spec docs/plans/v1.44.2-demo.md --slug p4-land --branch feat
  [ "$status" -eq 0 ]
  land_task="$K3DM_WORKTREE_ROOT/v0.0.5/p4-land"; land_run="$K3DM_WORKTREE_ROOT/v0.0.5/p4-land.run"
  for _ in {1..100}; do
    if [[ -f "$land_run/exit" ]]; then worker_pid="$(cat "$land_run/pid" 2>/dev/null || true)"; if [[ -z "$worker_pid" ]] || ! kill -0 "$worker_pid" 2>/dev/null; then break; fi; fi
    sleep 0.1
  done
  [ -f "$land_run/exit" ]; [[ -z "${worker_pid:-}" ]] || ! kill -0 "$worker_pid" 2>/dev/null
  printf 'landed edit\n' >"$land_task/a.txt"
  git -C "$land_task" add a.txt; git -C "$land_task" commit -m task-edit >/dev/null
  run dispatch land --slug p4-land --test true
  [ "$status" -eq 0 ]; [[ "$output" == *'landed: p4-land'* ]]
  jq -e -s 'any(.[]; .slug=="p4-land" and .event=="land" and .version=="v0.0.5" and .project=="dirused")' "$K3DM_WORKTREE_ROOT/ledger.jsonl"

  run dispatch start --project dirused --spec docs/plans/v1.44.2-demo.md --slug p4-resume --branch feat
  [ "$status" -eq 0 ]
  resume_run="$K3DM_WORKTREE_ROOT/v0.0.5/p4-resume.run"
  for _ in {1..100}; do
    if [[ -f "$resume_run/exit" ]]; then worker_pid="$(cat "$resume_run/pid" 2>/dev/null || true)"; if [[ -z "$worker_pid" ]] || ! kill -0 "$worker_pid" 2>/dev/null; then break; fi; fi
    sleep 0.1
  done
  [ -f "$resume_run/exit" ]; [[ -z "${worker_pid:-}" ]] || ! kill -0 "$worker_pid" 2>/dev/null
  printf 'continue\n' >"$BATS_TEST_TMPDIR/resume-prompt.md"
  run dispatch resume --slug p4-resume --prompt-file "$BATS_TEST_TMPDIR/resume-prompt.md" --reason correction
  [ "$status" -eq 0 ]
  jq -e -s 'any(.[]; .slug=="p4-resume" and .event=="resume" and .version=="v0.0.5" and .project=="dirused")' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  jq -e -s 'any(.[]; .slug=="p4-resume" and .event=="intervention" and .project=="dirused")' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
}

@test "project P5: same slug in two versions asks for --version" {
  for v in v0.0.5 v0.0.6; do mkdir -p "$K3DM_WORKTREE_ROOT/$v/s.run" "$K3DM_WORKTREE_ROOT/$v/s"; printf 'dirused\n' >"$K3DM_WORKTREE_ROOT/$v/s.run/project"; done
  run dispatch land --slug s --no-test
  [ "$status" -eq 2 ]; [[ "$output" == *'pass --version'* ]]
  run dispatch land --slug s --version v0.0.6 --no-test
  [ "$status" -eq 2 ]; [[ "$output" != *'pass --version'* ]]; [[ "$output" == *v0.0.6* ]]
}

@test "project P6: status lists dirused tasks; k3d-manager status output is unchanged" {
  mkdir -p "$K3DM_WORKTREE_ROOT/v1.44.2/manager.run"
  git -C "$FIXTURE" worktree add -b task/v1.44.2/manager "$K3DM_WORKTREE_ROOT/v1.44.2/manager" origin/k3d-manager-v1.44.2 >/dev/null
  printf 'k3d-manager-v1.44.2\n' >"$K3DM_WORKTREE_ROOT/v1.44.2/manager.run/target"
  printf 'k3d-manager\n' >"$K3DM_WORKTREE_ROOT/v1.44.2/manager.run/repo-name"
  run dispatch status
  manager="$output"
  [[ "$manager" == *'task: manager'* ]]
  mkdir -p "$K3DM_WORKTREE_ROOT/v0.0.5/d.run" "$K3DM_WORKTREE_ROOT/v0.0.5/d"
  printf 'dirused\n' >"$K3DM_WORKTREE_ROOT/v0.0.5/d.run/project"
  run dispatch status
  [[ "$output" == *'project: dirused'* ]]
  [ -z "$manager" ] || [[ "$output" == "$manager"* ]]
}

@test "project P7: open filters and tags rows; counts per project without review children" {
  cat >"$K3DM_WORKTREE_ROOT/ledger.jsonl" <<'EOF'
{"event":"start","version":"v1.44.2","slug":"manager","ts":1}
{"event":"start","version":"v0.0.5","slug":"dir-a","ts":1,"project":"dirused"}
{"event":"start","version":"v0.0.5","slug":"dir-b","ts":1,"project":"dirused"}
{"event":"start","version":"v0.0.5","slug":"review","ts":1,"project":"dirused","role":"review"}
EOF
  run dispatch open
  [ "$status" -eq 1 ]; grep -Eq '^v1\.44\.2 manager [0-9]+d start$' <<<"$output"; grep -Fq "v0.0.5 dir-a " <<<"$output"; grep -Fq " [dirused]" <<<"$output"
  run dispatch open --project k3d-manager
  [ "$status" -eq 1 ]; [[ "$output" == *'manager'* && "$output" != *'dir-a'* ]]
  run dispatch open --count
  [ "$status" -eq 0 ]; [[ "$output" == *'k3d-manager 1/3'* && "$output" == *'dirused 2/3'* && "$output" == *'all 3/6'* ]]
}
