#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load codex_dispatch_helpers

@test "codex dispatch S1 resolves mark link and combine versions from ledger starts" {
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$K3DM_DISPATCH_PUSHGATEWAY_URL" == http://127.0.0.1:9 ]]
  git -C "$FIXTURE" checkout -q -b feature/s1-no-version
  local sha evidence before
  sha="$(git -C "$FIXTURE" rev-parse HEAD)"
  evidence="$BATS_TEST_TMPDIR/s1-evidence"; printf 'offline evidence\n' >"$evidence"
  mkdir -p "$K3DM_WORKTREE_ROOT/v8.8.8/task.run" "$K3DM_WORKTREE_ROOT/v9.9.9/task.run"
  printf '%s\n' "$FIXTURE" >"$K3DM_WORKTREE_ROOT/v8.8.8/task.run/repo"
  printf '%s\n' "$FIXTURE" >"$K3DM_WORKTREE_ROOT/v9.9.9/task.run/repo"
  cat >"$K3DM_WORKTREE_ROOT/ledger.jsonl" <<'EOF'
{"ts":1,"event":"start","version":"v8.8.8","slug":"task","run":1}
{"ts":2,"event":"start","version":"v8.8.8","slug":"part-a","run":1,"parent":"bundle","role":"build"}
{"ts":3,"event":"start","version":"v8.8.8","slug":"part-b","run":1,"parent":"bundle","role":"build"}
{"ts":4,"event":"start","version":"v9.9.9","slug":"later","run":1}
EOF
  dispatch link --slug task --parent p-one --role build
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.event+":"+.version+":"+.slug')" = link:v8.8.8:task ]
  dispatch mark --slug task --state offline_tested --sha "$sha" --evidence "$evidence" --by operator
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.event+":"+.version+":"+.state')" = state_mark:v8.8.8:offline_tested ]
  dispatch combine --parent bundle --parts part-a,part-b --conflicts 0 --result pass --evidence "$evidence" --by operator
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.event+":"+.version+":"+(.parts|join(","))')" = combine:v8.8.8:part-a,part-b ]
  printf '%s\n' '{"ts":5,"event":"start","version":"v9.9.9","slug":"task","run":1}' >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  before="$(s1_snapshot)"
  s1_refused_unchanged link --slug task --parent p-one --role build
  s1_refused_unchanged mark --slug task --state offline_tested --sha "$sha" --evidence "$evidence" --by operator
  dispatch link --slug task --version v8.8.8 --parent p-one --role build
  dispatch mark --slug task --version v8.8.8 --state offline_tested --sha "$sha" --evidence "$evidence" --by operator
  s1_refused_unchanged link --slug missing --parent p --role build
  s1_refused_unchanged mark --slug missing --state offline_tested --sha "$sha" --evidence "$evidence" --by operator
  s1_refused_unchanged mark --slug task --state offline_tested --sha "$sha" --evidence "$evidence"
  s1_refused_unchanged mark --slug task --version v8.8.8 --state offline_tested --sha "$sha" --evidence "$evidence"
  s1_refused_unchanged link --slug task --parent p
  s1_refused_unchanged link --slug task --version v8.8.8 --parent p
  dispatch link --slug task --version v8.8.8 --parent p-one --role build
  dispatch mark --slug task --version v8.8.8 --state offline_tested --sha "$sha" --evidence "$evidence" --by operator
  printf '%s\n' '{"ts":7,"event":"start","version":"v9.9.9","slug":"other-part","run":1,"parent":"bundle","role":"build"}' >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  before="$(s1_snapshot)"
  run dispatch combine --parent bundle --parts part-a,other-part --conflicts 0 --result pass --evidence "$evidence" --by operator
  [ "$status" -eq 2 ]
  [ "$before" = "$(s1_snapshot)" ]
  dispatch combine --version v8.8.8 --parent bundle --parts part-a,part-b --conflicts 0 --result pass --evidence "$evidence" --by operator
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.event+":"+.version+":"+(.parts|join(","))')" = combine:v8.8.8:part-a,part-b ]
}

s1_add_open_gates() {
  local slug="$1"
  printf '%s\n' \
    "{\"ts\":2000000001,\"event\":\"resume\",\"version\":\"v9.9.9\",\"slug\":\"$slug\",\"run\":2,\"n\":2,\"reason\":\"correction\"}" \
    "{\"ts\":2000000002,\"event\":\"codex_exit\",\"version\":\"v9.9.9\",\"slug\":\"$slug\",\"run\":2,\"exit\":1}" \
    "{\"ts\":2000000003,\"event\":\"resume\",\"version\":\"v9.9.9\",\"slug\":\"$slug\",\"run\":3,\"n\":3,\"reason\":\"correction\"}" \
    "{\"ts\":2000000004,\"event\":\"scope_gate\",\"version\":\"v9.9.9\",\"slug\":\"$slug\",\"gate_state\":\"opened\",\"paths\":[\"x.sh\"],\"risk\":\"normal\",\"assessor\":\"claude\",\"baseline_sha\":\"1111111111111111111111111111111111111111\"}" \
    "{\"ts\":2000000005,\"event\":\"architecture_review\",\"version\":\"v9.9.9\",\"slug\":\"$slug\",\"decision\":\"diagnose_first\",\"reviewer\":\"agy\",\"baseline_sha\":\"1111111111111111111111111111111111111111\"}" \
    >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
}

@test "codex dispatch S1 gate-status matches hand-derived fixture and is read-only" {
  local gates="$BATS_TEST_DIRNAME/../fixtures/dispatch-gates"
  [[ "$K3DM_WORKTREE_ROOT" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$FIXTURE" == "$BATS_TEST_TMPDIR/"* ]]
  [[ "$K3DM_DISPATCH_PUSHGATEWAY_URL" == http://127.0.0.1:9 ]]
  cp "$gates/synthetic.jsonl" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  local before after listing_before listing_after slug expected actual
  listing_before="$(find "$K3DM_WORKTREE_ROOT" "$FIXTURE" -print | sort)"
  before="$(find "$K3DM_WORKTREE_ROOT" "$FIXTURE" -type f -exec shasum -a 256 {} \; | sort)"
  while IFS= read -r slug; do
    expected="$(jq -c --arg slug "$slug" '.synthetic.tasks[$slug]' "$gates/expected.json")"
    actual="$(dispatch gate-status --slug "$slug" --version v9.9.9 --json)"
    [ "$(jq -cS . <<<"$actual")" = "$(jq -cS . <<<"$expected")" ] || { echo "slug=$slug"; diff -u <(jq -S . <<<"$expected") <(jq -S . <<<"$actual"); return 1; }
  done < <(jq -r '.synthetic.tasks | keys[]' "$gates/expected.json")
  listing_after="$(find "$K3DM_WORKTREE_ROOT" "$FIXTURE" -print | sort)"
  after="$(find "$K3DM_WORKTREE_ROOT" "$FIXTURE" -type f -exec shasum -a 256 {} \; | sort)"
  [ "$before" = "$after" ]
  [ "$listing_before" = "$listing_after" ]
  cp "$gates/ca-trust-stall.jsonl" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  actual="$(dispatch gate-status --slug 2026-11-02-acg-up-stalls-at-system-keychain-trust --version v1.43.14 --as-of 1793622701 --json)"
  [ "$(jq -r '.stall+":"+(.streak|tostring)' <<<"$actual")" = clear:1 ]
  actual="$(dispatch gate-status --slug 2026-11-02-acg-up-stalls-at-system-keychain-trust --version v1.43.14 --as-of 1793622702 --json)"
  [ "$(jq -r '.stall+":"+(.streak|tostring)' <<<"$actual")" = open:2 ]
  actual="$(dispatch gate-status --slug 2026-11-02-acg-up-stalls-at-system-keychain-trust --version v1.43.14 --json)"
  [ "$(jq -r '.stall+":"+(.streak|tostring)+":"+(.runs|tostring)+":"+(.human_interventions|tostring)' <<<"$actual")" = closed:13:24:23 ]
  cp "$gates/synthetic.jsonl" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  sed -i.bak '/"event":"gate_coverage_start"/d' "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  actual="$(dispatch gate-status --slug boundary-task --version v9.9.9 --json)"
  [ "$(jq -r '.ladder.offline_tested+":"+.ladder.deployed+":"+.ladder.live_verified' <<<"$actual")" = unknown:unknown:unknown ]
  actual="$(dispatch gate-status --slug boundary-task --version v9.9.9 --json)"
  [ "$(jq -r '.ladder.implemented+":"+.ladder.independently_verified+":"+.ladder.landed' <<<"$actual")" = pending:pending:pending ]
}

@test "codex dispatch S1 writes coverage marker once and records split link" {
  cp "$BATS_TEST_DIRNAME/../fixtures/dispatch-gates/synthetic.jsonl" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  dispatch gate-coverage-start
  dispatch gate-coverage-start
  dispatch link --slug part-a --version v9.9.9 --parent p-one --role build
  [ "$(grep -c '"event":"gate_coverage_start"' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  [ "$(grep -c '"event":"link".*"role":"build"' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  sed '/"event":"gate_coverage_start"/d; /deliberately corrupt/d' "$BATS_TEST_DIRNAME/../fixtures/dispatch-gates/synthetic.jsonl" >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  dispatch gate-coverage-start
  dispatch gate-coverage-start
  [ "$(grep -c '"event":"gate_coverage_start"' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  sed '/deliberately corrupt/d' "$BATS_TEST_DIRNAME/../fixtures/dispatch-gates/synthetic.jsonl" >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  export STUB_ARGV="$BATS_TEST_TMPDIR/parented.argv" STUB_ENV="$BATS_TEST_TMPDIR/parented.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug parented --parent split-story --role build >/dev/null
  [ "$(jq -r -s '[.[]|select(.slug=="parented" and .event=="start")][-1] | .parent+":"+.role' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = split-story:build ]
}

@test "codex dispatch S1 marks and gate-record validate without side effects on refusal" {
  local sha evidence empty dir
  sha="$(git -C "$FIXTURE" rev-parse HEAD)"
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/task.run"
  printf '%s\n' "$FIXTURE" >"$K3DM_WORKTREE_ROOT/v9.9.9/task.run/repo"
  printf '%s\n' '{"ts":0,"event":"gate_coverage_start","version":"v9.9.9","repo":"k3d-manager"}' '{"ts":1,"event":"start","version":"v9.9.9","slug":"task","run":1,"agent":"codex","worker_identity":{"model":"gpt-6-luna"}}' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  evidence="$BATS_TEST_TMPDIR/evidence.txt"; printf 'offline test output\n' >"$evidence"
  empty="$BATS_TEST_TMPDIR/empty.txt"; : >"$empty"
  dir="$BATS_TEST_TMPDIR/evidence-dir"; mkdir "$dir"
  s1_refused_unchanged mark --slug task --version v9.9.9 --state offline_tested --sha "$sha" --evidence "$empty" --by operator
  s1_refused_unchanged mark --slug task --version v9.9.9 --state offline_tested --sha "$sha" --evidence "$evidence"
  dispatch mark --slug task --version v9.9.9 --state offline_tested --sha "$sha" --evidence "$evidence" --by operator
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.event+":"+.state')" = state_mark:offline_tested ]
  local actual
  actual="$(dispatch gate-status --slug task --version v9.9.9 --json)"
  [ "$(jq -r '.ladder.offline_tested+":"+.ladder.live_verified' <<<"$actual")" = done:pending ]
  s1_refused_unchanged mark --slug task --version v9.9.9 --state live_verified --sha "$sha" --evidence "$evidence" --by operator
  s1_refused_unchanged mark --slug task --version v9.9.9 --state live_verified --sha "$sha" --evidence "$BATS_TEST_TMPDIR/absent-evidence" --by operator
  printf 'artifact: sha-%s\nenvironment: scratch\ncommand: test\nrc: 0\n---\n' "$sha" >"$evidence"
  s1_refused_unchanged mark --slug task --version v9.9.9 --state deployed --sha "$sha" --evidence "$evidence" --by operator
  printf 'artifact: sha-%s\nenvironment: scratch\ncommand: test\nrc: 0\n---\nobserved output\n' "$sha" >"$evidence"
  dispatch mark --slug task --version v9.9.9 --state live_verified --sha "$sha" --evidence "$evidence" --by operator
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.state')" = live_verified ]
  actual="$(dispatch gate-status --slug task --version v9.9.9 --json)"
  [ "$(jq -r '.ladder.live_verified' <<<"$actual")" = done ]
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event attempt_assessed --run 77 --outcome progress --assessor claude --baseline-sha "$sha"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event attempt_assessed --run not-a-number --outcome progress --assessor claude --baseline-sha "$sha"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event stall_gate --runs 1,nope --reason test --assessor claude --baseline-sha "$sha"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event replan_reviewed --decision narrow_fix --reviewer agy --plan "$evidence" --baseline-sha "$sha"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event replan_reviewed --decision approved --reviewer agy --plan "$evidence" --baseline-sha "$sha" --unlisted x
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event architecture_review --decision approved --reviewer agy --evidence "$evidence" --baseline-sha "$sha"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event replan_reviewed --decision approved --reviewer gpt-6-luna --plan "$evidence" --baseline-sha "$sha"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event replan_reviewed --decision approved --reviewer agy --plan "$dir" --baseline-sha "$sha"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event replan_reviewed --decision approved --reviewer agy --plan "$evidence" --baseline-sha "not-a-commit"
  dispatch gate-record --slug task --version v9.9.9 --event replan_reviewed --decision approved --reviewer agy --plan "$evidence" --baseline-sha "$sha"
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.event+":"+.decision')" = replan_reviewed:approved ]
  dispatch gate-record --slug task --version v9.9.9 --event attempt_assessed --run 1 --outcome progress --assessor operator --baseline-sha "$sha"
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.new_evidence_path == null and .new_evidence_sha256 == null')" = true ]
  printf '%s\n' '{"ts":2,"event":"start","version":"v9.9.9","slug":"part","run":1}' >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  dispatch link --slug part --version v9.9.9 --parent bundle --role build
  dispatch combine --version v9.9.9 --parent bundle --parts part --conflicts 0 --result pass --evidence "$evidence" --by operator
  [ "$(tail -n 1 "$K3DM_WORKTREE_ROOT/ledger.jsonl" | jq -r '.event+":"+.parent+":"+(.parts|join(","))+":"+.result')" = combine:bundle:part:pass ]
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event gate_cleared --gate scope --by operator --evidence "$evidence"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event gate_cleared --gate stall --evidence "$evidence"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event gate_cleared --gate arch --evidence "$evidence"
  s1_refused_unchanged gate-record --slug task --version v9.9.9 --event attempt_assessed --run
  s1_refused_unchanged mark --slug task --version v9.9.9 --state offline_tested --sha
  s1_refused_unchanged mark --slug task --version v9.9.9 --state offline_tested --sha "$sha" --evidence "$evidence"
}

@test "codex dispatch S1 malformed ledger bytes are counted and status stays read-only" {
  printf '%s\n' '{"ts":1,"event":"start","version":"v9.9.9","slug":"binary","run":1}' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  printf '\377\n' >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  local before after actual
  before="$(s1_snapshot)"
  actual="$(dispatch gate-status --slug binary --version v9.9.9 --json)"
  [ "$(jq -r '.bad_lines' <<<"$actual")" -eq 1 ]
  after="$(s1_snapshot)"
  [ "$before" = "$after" ]
}

@test "codex dispatch S1 resolution, rework rules, and read-only edge cases" {
  local gates="$BATS_TEST_DIRNAME/../fixtures/dispatch-gates" before after actual
  cp "$gates/synthetic.jsonl" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  git -C "$FIXTURE" checkout -q -b feature/s1-resolution
  before="$(s1_snapshot)"
  actual="$(dispatch gate-status --slug old-task --json)"
  [ "$(jq -r '.version' <<<"$actual")" = v9.9.9 ]
  after="$(s1_snapshot)"; [ "$before" = "$after" ]
  printf '%s\n' '{"ts":2100000000,"event":"start","version":"v1.0.0","slug":"duplicate","run":1}' >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  printf '%s\n' '{"ts":2100000001,"event":"start","version":"v2.0.0","slug":"duplicate","run":1}' >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  before="$(s1_snapshot)"
  run dispatch gate-status --slug duplicate --json
  [ "$status" -eq 2 ]
  after="$(s1_snapshot)"; [ "$before" = "$after" ]
  actual="$(dispatch gate-status --slug duplicate --version v2.0.0 --json)"
  [ "$(jq -r '.version+":"+.stall' <<<"$actual")" = v2.0.0:clear ]
  run dispatch gate-status --slug no-start --version v9.9.9 --json
  [ "$status" -eq 2 ]
  actual="$(dispatch gate-status --slug cleared-task --version v9.9.9 --json)"
  [ "$(jq -c '.unsuccessful' <<<"$actual")" = '[1,2]' ]
  [ "$(jq -r '.streak' <<<"$actual")" -eq 0 ]
  actual="$(dispatch gate-status --slug double-count --version v9.9.9 --json)"
  [ "$(jq -r '(.human_interventions|tostring)+":"+(.unsuccessful|tostring)' <<<"$actual")" = '1:[1]' ]
  actual="$(dispatch gate-status --slug replan-rejected --version v9.9.9 --json)"
  [ "$(jq -r '(.streak|tostring)+":"+.stall' <<<"$actual")" = '2:open' ]
  actual="$(dispatch gate-status --slug evidence-reset --version v9.9.9 --json)"
  [ "$(jq -r '.streak' <<<"$actual")" -eq 1 ]
  cp "$gates/synthetic.jsonl" "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  before="$(s1_snapshot)"
  run dispatch gate-status --slug absent --version v9.9.9 --json
  [ "$status" -eq 2 ]
  after="$(s1_snapshot)"; [ "$before" = "$after" ]
  : >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  before="$(s1_snapshot)"
  run dispatch gate-status --slug old-task --version v9.9.9 --json
  [ "$status" -eq 2 ]
  after="$(s1_snapshot)"; [ "$before" = "$after" ]
  rm "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  before="$(s1_snapshot)"
  run dispatch gate-status --slug old-task --version v9.9.9 --json
  [ "$status" -eq 2 ]
  after="$(s1_snapshot)"; [ "$before" = "$after" ]
}

@test "codex dispatch S1 runs counts start and resume only, not a run named by an exit" {
  [ "$K3DM_WORKTREE_ROOT" != "$HOME/.local/share/k3d-manager/worktrees" ]
  local actual
  printf '%s\n' \
    '{"ts":100,"event":"start","version":"v9.9.9","slug":"exit-only","run":1}' \
    '{"ts":101,"event":"codex_exit","version":"v9.9.9","slug":"exit-only","run":1,"exit":0}' \
    '{"ts":102,"event":"codex_exit","version":"v9.9.9","slug":"exit-only","run":7,"exit":3}' \
    >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  actual="$(dispatch gate-status --slug exit-only --version v9.9.9 --json)"
  [ "$(jq -r '.runs' <<<"$actual")" -eq 1 ]
  printf '%s\n' '{"ts":103,"event":"resume","version":"v9.9.9","slug":"exit-only","run":2,"reason":"other"}' >>"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  actual="$(dispatch gate-status --slug exit-only --version v9.9.9 --json)"
  [ "$(jq -r '.runs' <<<"$actual")" -eq 2 ]
}

@test "codex dispatch S1 open advisory gates do not block resume, land, or a new task" {
  local prompt="$BATS_TEST_TMPDIR/followup.md" open_rc clear_rc open_events clear_events
  printf 'continue safely\n' >"$prompt"
  : >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  s1_start_finished resume-open
  s1_start_finished resume-clear
  s1_add_open_gates resume-open
  export STUB_ARGV="$BATS_TEST_TMPDIR/resume-open.argv" STUB_ENV="$BATS_TEST_TMPDIR/resume-open.env"
  run dispatch resume --slug resume-open --prompt-file "$prompt" --reason continue_prompt
  open_rc="$status"
  export STUB_ARGV="$BATS_TEST_TMPDIR/resume-clear.argv" STUB_ENV="$BATS_TEST_TMPDIR/resume-clear.env"
  run dispatch resume --slug resume-clear --prompt-file "$prompt" --reason continue_prompt
  clear_rc="$status"
  [ "$open_rc" -eq "$clear_rc" ] && [ "$open_rc" -eq 0 ]
  [ "$(grep -c 'exec resume' "$BATS_TEST_TMPDIR/resume-open.argv")" -eq 1 ]
  [ "$(grep -c 'exec resume' "$BATS_TEST_TMPDIR/resume-clear.argv")" -eq 1 ]
  open_events="$(jq -c -s '[.[]|select(.slug=="resume-open" and (.event=="intervention" or (.event=="resume" and .reason=="continue_prompt")))|{event,reason,run,n}]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  clear_events="$(jq -c -s '[.[]|select(.slug=="resume-clear" and (.event=="intervention" or (.event=="resume" and .reason=="continue_prompt")))|{event,reason,run,n}]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  [ "$open_events" = "$clear_events" ] || { echo "open=$open_events clear=$clear_events"; return 1; }
  open_events="$(jq -c -s '[.[]|select(.slug=="resume-open" and (.event=="intervention" or (.event=="resume" and .reason=="continue_prompt")))|keys_unsorted|map(select(.!="ts" and .!="slug" and .!="version" and .!="pid" and .!="duration"))|sort]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  clear_events="$(jq -c -s '[.[]|select(.slug=="resume-clear" and (.event=="intervention" or (.event=="resume" and .reason=="continue_prompt")))|keys_unsorted|map(select(.!="ts" and .!="slug" and .!="version" and .!="pid" and .!="duration"))|sort]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  [ "$open_events" = "$clear_events" ]

  s1_start_finished land-open
  s1_start_finished land-clear
  s1_add_open_gates land-open
  for slug in land-open land-clear; do
    printf 'committed edit\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/$slug/a.txt"
    git -C "$K3DM_WORKTREE_ROOT/v9.9.9/$slug" add a.txt
    git -C "$K3DM_WORKTREE_ROOT/v9.9.9/$slug" commit -m "$slug" >/dev/null
  done
  run dispatch land --slug land-open --no-test
  open_rc="$status"
  [ "$open_rc" -eq 0 ] || { echo "$output"; return 1; }
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  run dispatch land --slug land-clear --no-test --superseding land-open
  clear_rc="$status"
  [ "$open_rc" -eq "$clear_rc" ] && [ "$open_rc" -eq 0 ] || echo "land-open=$open_rc land-clear=$clear_rc output=$output"
  [ "$(jq -r -s '[.[]|select(.slug=="land-open" and .event=="land")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  [ "$(jq -r -s '[.[]|select(.slug=="land-clear" and .event=="land")]|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  open_events="$(jq -c -s '[.[]|select(.slug=="land-open" and (.event=="land" or .event=="land_refused"))|keys_unsorted|map(select(.!="ts" and .!="slug" and .!="version" and .!="pid" and .!="duration" and .!="wait_seconds"))|sort]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  clear_events="$(jq -c -s '[.[]|select(.slug=="land-clear" and (.event=="land" or .event=="land_refused"))|keys_unsorted|map(select(.!="ts" and .!="slug" and .!="version" and .!="pid" and .!="duration" and .!="wait_seconds"))|sort]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  [ "$open_events" = "$clear_events" ]
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9

  s1_start_finished context-open
  s1_add_open_gates context-open
  export STUB_ARGV="$BATS_TEST_TMPDIR/new-open.argv" STUB_ENV="$BATS_TEST_TMPDIR/new-open.env"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug new-open
  open_rc="$status"
  export STUB_ARGV="$BATS_TEST_TMPDIR/new-clear.argv" STUB_ENV="$BATS_TEST_TMPDIR/new-clear.env"
  run dispatch start --spec docs/plans/v9.9.9-demo.md --slug new-clear
  clear_rc="$status"
  [ "$open_rc" -eq "$clear_rc" ] && [ "$open_rc" -eq 0 ]
  local tries
  for slug in new-open new-clear; do
    for tries in {1..100}; do [[ -f "$K3DM_WORKTREE_ROOT/v9.9.9/$slug.run/exit" ]] && break; sleep 0.1; done
    [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/$slug.run/exit" ]
    [ -s "$BATS_TEST_TMPDIR/$slug.argv" ]
  done
  open_events="$(jq -c -s '[.[]|select(.slug=="new-open" and .event=="start")|{event,run,agent,model,parent,role}]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  clear_events="$(jq -c -s '[.[]|select(.slug=="new-clear" and .event=="start")|{event,run,agent,model,parent,role}]' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  [ "$open_events" = "$clear_events" ]
}


@test "codex dispatch: explicit primary, handoff, and landing actor are separate ledger facts" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/codex.argv" STUB_ENV="$BATS_TEST_TMPDIR/codex.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug primary --primary-coordinator openai/gpt-6-luna >/dev/null
  sleep 1
  dispatch handoff --slug primary --acting-coordinator openai/gpt-6-luna --reason quota_exhausted >/dev/null
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/primary" add -A
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/primary" commit -qm candidate
  dispatch land --slug primary --test true --landing-actor codex --landing-model openai/gpt-6-luna --review-pending >/dev/null
  jq -s -e 'map(select(.slug=="primary")) as $e | ($e|map(select(.event=="primary_coordinator"))[0].primary_coordinator_identity.vendor) == "openai" and ($e|map(select(.event=="start"))[0].worker_identity.vendor) == "openai" and ($e|map(select(.event=="handoff"))[0].handoff_reason) == "quota_exhausted" and ($e|map(select(.event=="land"))[0].landing_actor.actor) == "codex" and ($e|map(select(.event=="review_pending"))[0].review_status) == "pending"' "$K3DM_WORKTREE_ROOT/ledger.jsonl" >/dev/null
}

@test "codex dispatch: start records the spec path in the ledger" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/one.argv" STUB_ENV="$BATS_TEST_TMPDIR/one.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  [ "$(jq -r -s '.[0].spec' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = "docs/plans/v9.9.9-demo.md" ]
}

@test "codex dispatch: land completes when the ledger is unwritable" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  printf 'edited\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  rm "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  mkdir "$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch land --slug one --no-test
  [ "$status" -eq 0 ]
  [ ! -d "$K3DM_WORKTREE_ROOT/v9.9.9/one" ]
  [ -f "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/landed" ]
}

@test "codex dispatch: ledger snapshots Codex output and restores the index" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  ledger="$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$(jq -s 'length' "$ledger")" -eq 3 ]
  [ "$(jq -r -s '.[0].event' "$ledger")" = start ]
  [ "$(jq -r -s '.[1].event' "$ledger")" = primary_coordinator ]
  [ "$(jq -r -s '.[2].event' "$ledger")" = codex_exit ]
  [ "$(jq -r -s '.[2].tokens' "$ledger")" = 12345 ]
  [ "$(jq -r -s '.[0].spec' "$ledger")" = docs/plans/v9.9.9-demo.md ]
  [[ "$(jq -r -s '.[2].tree' "$ledger")" =~ ^[0-9a-f]{40}$ ]]
  [ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/codex-tree" ]
  [ -z "$(git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" diff --cached --name-only)" ]
}

@test "codex dispatch: verify records pass tokens only for a landed task" {
  printf '{"ts":1,"event":"land","version":"v9.9.9","slug":"verified"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  sha="$(git -C "$FIXTURE" rev-parse HEAD)"
  [ "$FIXTURE" != "$(git rev-parse --show-toplevel)" ]
  [ "$K3DM_WORKTREE_ROOT" = "$BATS_TEST_TMPDIR/worktrees" ]
  printf 'verifier: codex\ntests_from: acceptance\nfix_sha: %s\ncommand: bats test\nrc: 0\npre_fix_sha: %s\npre_fix_command: bats test\npre_fix_rc: 1\n---\noutput\n' "$sha" "$sha" >"$BATS_TEST_TMPDIR/evidence"
  run dispatch verify --slug verified --result pass --tokens 456 --verifier codex --evidence "$BATS_TEST_TMPDIR/evidence"
  [ "$status" -eq 0 ]
  [ "$(jq -r -s '.[-1].event' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = verify ]
  [ "$(jq -r -s '.[-1].result' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = pass ]
  [ "$(jq -r -s '.[-1].tokens' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 456 ]
  [ "$(jq -r -s '.[-1].verifier' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = codex ]
  copy="$K3DM_WORKTREE_ROOT/$(jq -r -s '.[-1].evidence_path' "$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  [ -f "$copy" ]
  [ "$(shasum -a 256 "$copy" | cut -d' ' -f1)" = "$(jq -r -s '.[-1].evidence_sha256' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" ]
}

@test "codex dispatch: verify refusals do not append ledger events" {
  printf '{"ts":1,"event":"start","version":"9.9.9","slug":"unlanded"}\n' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  before="$(wc -l <"$K3DM_WORKTREE_ROOT/ledger.jsonl")"
  run dispatch verify --slug unlanded --result pass
  [ "$status" -ne 0 ]
  run dispatch verify --slug absent --result pass
  [ "$status" -ne 0 ]
  run dispatch verify --slug absent --result maybe
  [ "$status" -ne 0 ]
  run dispatch verify --slug absent --result pass --tokens 1.5
  [ "$status" -ne 0 ]
  run dispatch verify --slug absent --result pass --tokens ""
  [ "$status" -ne 0 ]
  [ "$(wc -l <"$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq "$before" ]
}

@test "codex dispatch: ledger records verifier lines before a release rebase" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  printf 'edited\nextra\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/one/a.txt"
  git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" add a.txt; git -C "$K3DM_WORKTREE_ROOT/v9.9.9/one" commit -m edit >/dev/null
  printf 'release\n' >"$FIXTURE/release.txt"
  git -C "$FIXTURE" add release.txt; git -C "$FIXTURE" commit -m release >/dev/null
  git -C "$FIXTURE" push -q origin k3d-manager-v9.9.9
  run dispatch land --slug one --no-test
  [ "$status" -eq 0 ]
  [ "$(jq -r -s '.[-1].event' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = land ]
  [ "$(jq -r -s '.[-1].verifier_lines' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = 1 ]
  [ "$(jq -r -s '.[-1].wait_seconds' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -ge 0 ]
}

@test "codex dispatch: ledger records a Codex exit with no token count" {
  export STUB_TOKENS=none STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null; sleep 1
  ledger="$K3DM_WORKTREE_ROOT/ledger.jsonl"
  [ "$(jq -r -s 'map(select(.event == "codex_exit"))[0].tokens' "$ledger")" = null ]
  [[ "$(jq -r -s 'map(select(.event == "codex_exit"))[0].tree' "$ledger")" =~ ^[0-9a-f]{40}$ ]]
}

@test "codex dispatch: usage-backfill is idempotent" {
  export STUB_ARGV="$BATS_TEST_TMPDIR/a.argv" STUB_ENV="$BATS_TEST_TMPDIR/a.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug one >/dev/null
  sleep 1
  for _ in {1..50}; do [[ -s "$K3DM_WORKTREE_ROOT/v9.9.9/one.run/exit" ]] && break; sleep 0.1; done
  for _ in {1..50}; do [[ ! -d "$K3DM_WORKTREE_ROOT/metrics.lock" ]] && break; sleep 0.1; done
  : >"$METRICS_STARTS"
  mkdir -p "$CODEX_HOME/sessions/2026/10/23"
  cat >"$CODEX_HOME/sessions/2026/10/23/rollout-test-01a122dd-71c3-7763-87f0-3de505f10168.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"01a122dd-71c3-7763-87f0-3de505f10168","timestamp":"2026-10-23T10:00:00Z"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
{"type":"event_msg","payload":{"info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}}}
EOF
  run dispatch usage-backfill
  [ "$status" -eq 0 ]; [[ "$output" == *"backfilled: 1"* ]]; [[ "$output" == *"missing: 0"* ]]
  sleep 1.2
  [ "$(wc -l <"$METRICS_STARTS" | tr -d ' ')" -eq 1 ]
  run dispatch usage-backfill
  [ "$status" -eq 0 ]; [[ "$output" == *"backfilled: 0"* ]]
  [ "$(wc -l <"$METRICS_STARTS" | tr -d ' ')" -eq 1 ]
  [ "$(jq -s 'map(select(.event == "codex_usage")) | length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
}

@test "codex dispatch: intervention records reason and starts explicit coverage once" {
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/known.run"
  printf 'k3d-manager\n' >"$K3DM_WORKTREE_ROOT/v9.9.9/known.run/repo-name"
  printf '%s\n' '{"ts":1,"event":"start","version":"v9.9.9","slug":"known"}' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch intervention --slug known --reason continue_prompt
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run dispatch intervention --slug known --reason clarification
  [ "$status" -eq 0 ]
  [ "$(jq -s '[.[] | select(.event == "intervention_coverage_start")] | length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  [ "$(jq -s '[.[] | select(.event == "intervention")] | length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 2 ]
  [ "$(jq -r -s '[.[] | select(.event == "intervention")][-1].reason' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = clarification ]
}

@test "codex dispatch: intervention refuses unknown task invalid reason and worker self-report" {
  mkdir -p "$K3DM_WORKTREE_ROOT/v9.9.9/known.run"
  printf '%s\n' '{"ts":1,"event":"start","version":"v9.9.9","slug":"known"}' >"$K3DM_WORKTREE_ROOT/ledger.jsonl"
  run dispatch intervention --slug missing --reason other
  [ "$status" -ne 0 ]
  run dispatch intervention --slug known --reason guess
  [ "$status" -ne 0 ]
  run env K3DM_WORKTREE_ROOT="$K3DM_WORKTREE_ROOT" K3DM_REPO_ROOT="$K3DM_WORKTREE_ROOT/v9.9.9/known" \
    "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" intervention --slug known --reason other
  [ "$status" -ne 0 ]
  run env K3DM_WORKTREE_ROOT="$K3DM_WORKTREE_ROOT" \
    K3DM_JOB_DIR="$K3DM_WORKTREE_ROOT/v9.9.9/known.run/state/jobs" \
    "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" intervention --slug known --reason other
  [ "$status" -ne 0 ]
  [ "$(wc -l <"$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
}

@test "codex dispatch: release-merged records one merge timestamp idempotently" {
  local dispatch="${PRE_FIX_DISPATCH:-$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch}"
  local root="$BATS_TEST_DIRNAME/../../.."
  run make -s -n -C "$root" codex-release-merged VERSION=v1.43.8 PR=145 MERGED_AT=2026-10-18T19:01:51Z
  [ "$status" -eq 0 ] && [[ "$output" == *"release-merged --version 'v1.43.8' --pr '145' --merged-at '2026-10-18T19:01:51Z'"* ]]
  run "$dispatch" release-merged --version v1.43.8 --pr 145 --merged-at 2026-10-18T19:01:51Z
  [ "$status" -eq 0 ] && [[ "$output" == *"recorded release merge"* ]]
  [ "$(jq -s 'map(select(.event=="release_merged"))|length' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" -eq 1 ]
  [ "$(jq -r 'select(.event=="release_merged")|[.version,.slug,.pr,.merged_at]|@tsv' "$K3DM_WORKTREE_ROOT/ledger.jsonl")" = $'v1.43.8\trelease\t145\t1792350111' ]
  before="$(wc -l <"$K3DM_WORKTREE_ROOT/ledger.jsonl" | tr -d ' ')"
  run "$dispatch" release-merged --version v1.43.8 --pr 145 --merged-at 2026-10-18T19:01:51Z
  [ "$status" -eq 0 ] && [[ "$output" == *"already recorded"* ]]
  [ "$(wc -l <"$K3DM_WORKTREE_ROOT/ledger.jsonl" | tr -d ' ')" -eq "$before" ]
}

@test "codex dispatch: invalid release-merged args leave ledger unchanged" {
  local dispatch="${PRE_FIX_DISPATCH:-$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch}"
  for args in \
    "--version v1.43.8 --pr 145 --merged-at 2026-02-30T19:01:51Z" \
    "--version v1.43.8 --pr 0 --merged-at 2026-10-18T19:01:51Z" \
    "--version main --pr 145 --merged-at 2026-10-18T19:01:51Z"; do
    before="$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl" 2>/dev/null || true)"
    run "$dispatch" release-merged $args
    [ "$status" -eq 2 ]
    [ "$(cat "$K3DM_WORKTREE_ROOT/ledger.jsonl" 2>/dev/null || true)" = "$before" ]
  done
}

