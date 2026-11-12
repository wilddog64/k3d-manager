# shellcheck disable=SC2034,SC2154
setup() {
  export FIXTURE="$BATS_TEST_TMPDIR/fixture" ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export K3DM_WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktrees" HOME="$BATS_TEST_TMPDIR/home"
  export K3DM_DISPATCH_PUSHGATEWAY_URL="http://127.0.0.1:9" CODEX_HOME="$BATS_TEST_TMPDIR/codex-home"
  export K3DM_CODEX_BIN="$BATS_TEST_TMPDIR/codex-stub"
  mkdir -p "$FIXTURE" "$HOME" "$K3DM_WORKTREE_ROOT"
  export K3DM_DISPATCH_METRICS_BIN="$BATS_TEST_TMPDIR/metrics-stub"
  cat >"$K3DM_DISPATCH_METRICS_BIN" <<'METRICS'
#!/usr/bin/env bash
set -euo pipefail
printf 'start\n' >>"$METRICS_STARTS"
mkdir "$METRICS_ACTIVE" 2>/dev/null || : >"$METRICS_OVERLAP"
sleep 1
rmdir "$METRICS_ACTIVE" 2>/dev/null || true
METRICS
  chmod +x "$K3DM_DISPATCH_METRICS_BIN"
  export METRICS_STARTS="$BATS_TEST_TMPDIR/metrics-starts"
  export METRICS_ACTIVE="$BATS_TEST_TMPDIR/metrics-active" METRICS_OVERLAP="$BATS_TEST_TMPDIR/metrics-overlap"
  git init --bare "$ORIGIN" >/dev/null
  git clone "$ORIGIN" "$FIXTURE" >/dev/null
  git -C "$FIXTURE" checkout -b k3d-manager-v9.9.9 >/dev/null
  git -C "$FIXTURE" config user.email test@example.com; git -C "$FIXTURE" config user.name Test
  printf 'original\n' >"$FIXTURE/a.txt"
  mkdir -p "$FIXTURE/memory-bank"; touch "$FIXTURE/memory-bank/.keep"
  mkdir -p "$FIXTURE/docs/plans"; printf '# Readme\n\nNo files section here.\n' >"$FIXTURE/README.md"
  mkdir -p "$FIXTURE/scripts/tests" "$FIXTURE/docs"
  printf 'original test\n' >"$FIXTURE/scripts/tests/land.bats"
  printf 'original doc\n' >"$FIXTURE/docs/note.md"
  cat >"$FIXTURE/docs/plans/v9.9.9-demo.md" <<'EOF'
# Test spec

**Intent approved:** test, 2026-11-07

## Files

| File |
|---|
| `a.txt` |
| `scripts/tests/land.bats` |
| `docs/note.md` |
| `docs/plans/v9.9.9-demo.md` |
EOF
  mkdir -p "$FIXTURE/scripts/ci"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$FIXTURE/scripts/ci/fast_gate.sh"
  chmod +x "$FIXTURE/scripts/ci/fast_gate.sh"
  git -C "$FIXTURE" add a.txt README.md docs scripts docs/plans/v9.9.9-demo.md memory-bank/.keep; git -C "$FIXTURE" commit -m base >/dev/null
  git -C "$FIXTURE" push -u origin k3d-manager-v9.9.9 >/dev/null
  cat >"$K3DM_CODEX_BIN" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${STUB_ARGV:?}"
printf '%s\n' "$PWD" >>"${STUB_ARGV}.cwd"
[[ -z "${STUB_MODEL_LINE+x}" ]] || printf '%s\n' "$STUB_MODEL_LINE"
printf 'session id: 01a122dd-71c3-7763-87f0-3de505f10168\n'
[[ -z "${STUB_LOG_MARKER:-}" ]] || printf '%s\n' "$STUB_LOG_MARKER"
printf 'K3DM_REPO_ROOT=%s\nK3DM_JOB_DIR=%s\nK3DM_RUN_DIR=%s\nK3DM_STATE_DIR=%s\nK3DM_LOG_DIR=%s\nK3DM_TMP_ROOT=%s\nK3DM_PORT_CACHE_DIR=%s\nTMPDIR=%s\nHOME=%s\n' "$K3DM_REPO_ROOT" "$K3DM_JOB_DIR" "$K3DM_RUN_DIR" "$K3DM_STATE_DIR" "$K3DM_LOG_DIR" "$K3DM_TMP_ROOT" "$K3DM_PORT_CACHE_DIR" "$TMPDIR" "$HOME" >"${STUB_ENV:?}"
codex_dir="${K3DM_REPO_ROOT:-}"
out_file=""
while (($#)); do
  if [[ "$1" == -C ]]; then codex_dir="$2"; shift 2
  elif [[ "$1" == -o ]]; then out_file="$2"; shift 2
  else shift; fi
done
[[ -n "$codex_dir" ]] || exit 1
if [[ -n "$out_file" ]]; then printf 'stub last message\n' >"$out_file"; fi
[[ -z "${STUB_SLEEP:-}" ]] || sleep "$STUB_SLEEP"
if [[ "$*" != *"exec resume"* ]]; then
  IFS=, read -ra edits <<<"${STUB_EDITS:-a.txt}"
  for edit in "${edits[@]}"; do printf 'edited\n' >"$codex_dir/$edit"; done
fi
[[ "${STUB_TOKENS:-}" == none ]] || printf 'tokens used\n%s\n' "${STUB_TOKENS:-12,345}"
exit "${STUB_RC:-0}"
STUB
  chmod +x "$K3DM_CODEX_BIN"
  export K3DM_AGY_BIN="$BATS_TEST_TMPDIR/agy-stub"
  cat >"$K3DM_AGY_BIN" <<'AGY'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == models ]]; then
  printf 'Fetching available models...\n'
  printf 'gemini-4-argon-medium\tGemini 4 Argon (Medium)\n'
  printf 'gemini-4-argon-high\tGemini 4 Argon (High)\n'
  printf 'gemini-4-argon-low\tGemini 4 Argon (Low)\n'
  printf 'gemini-test\tGemini Test\n'
  exit 0
fi
printf '%s\n' "$*" >>"${AGY_ARGV:?}"
printf '%s\n' "$PWD" >>"${AGY_ARGV}.cwd"
printf 'K3DM_DISPATCH_SLUG=%s\n' "${K3DM_DISPATCH_SLUG:-}" >>"${AGY_ARGV}.env"
[[ "${AGY_EDIT:-0}" != 1 ]] || printf 'agy working-tree edit\n' >a.txt
if [[ "${AGY_NO_USAGE:-0}" == 1 ]]; then
  printf '{"conversation_id":"agy-conversation-1"}\n'
else
  printf '{"conversation_id":"agy-conversation-1","usage":{"input_tokens":11,"output_tokens":3}}\n'
fi
[[ "${AGY_COMMIT:-0}" != 1 ]] || { printf 'agy commit\n' >a.txt; git add -A; git commit -m agy-commit >/dev/null; }
AGY
  chmod +x "$K3DM_AGY_BIN"
}

dispatch() { (cd "$FIXTURE" && "$BATS_TEST_DIRNAME/../../../bin/k3dm-codex-dispatch" "$@"); }

s1_snapshot() {
  find "$K3DM_WORKTREE_ROOT" "$FIXTURE" -print | sort
  find "$K3DM_WORKTREE_ROOT" "$FIXTURE" -type f -exec shasum -a 256 {} \; | sort
}

s1_refused_unchanged() {
  local before after
  before="$(s1_snapshot)"
  run dispatch "$@"
  [ "$status" -eq 2 ]
  after="$(s1_snapshot)"
  [ "$before" = "$after" ]
}

s1_start_finished() {
  local slug="$1" run_dir="$K3DM_WORKTREE_ROOT/v9.9.9/$1.run" tries
  export STUB_ARGV="$BATS_TEST_TMPDIR/$slug.argv" STUB_ENV="$BATS_TEST_TMPDIR/$slug.env"
  dispatch start --spec docs/plans/v9.9.9-demo.md --slug "$slug" >/dev/null
  local pid=""
  for tries in {1..100}; do
    [[ -n "$pid" || ! -f "$run_dir/pid" ]] || pid="$(<"$run_dir/pid")"
    if [[ -f "$run_dir/exit" && -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then return 0; fi
    sleep 0.1
  done
  echo "worker did not finish: $slug" >&2
  return 1
}

