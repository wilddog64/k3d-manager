#!/usr/bin/env bash
set -euo pipefail
run_limited() {
  perl -MPOSIX -e '
    my $limit = shift;
    $limit =~ /^[1-9][0-9]*$/ or die "timeout must be a positive integer\n";
    my $pid = fork(); defined $pid or die "fork: $!\n";
    if (!$pid) { POSIX::setsid() >= 0 or die "setsid: $!\n"; exec @ARGV; die "exec: $!\n"; }
    my $expired = 0;
    $SIG{ALRM} = sub { $expired = 1; die "timeout\n"; };
    alarm $limit;
    my $waited;
    eval { $waited = waitpid($pid, 0); };
    if ($expired) {
      my %children;
      open my $ps, "-|", "ps", "-axo", "pid=,ppid=" or die "ps: $!\n";
      while (<$ps>) { if (/^\s*(\d+)\s+(\d+)/) { push @{$children{$2}}, $1; } }
      close $ps;
      my @pending = ($pid); my @descendants;
      while (@pending) { my $p = shift @pending; push @descendants, $p; push @pending, @{$children{$p} || []}; }
      kill "KILL", reverse @descendants;
      kill "KILL", -$pid;
      waitpid($pid, 0) unless defined $waited;
      print STDERR "timed out after ${limit}s\n";
      exit 124;
    }
    alarm 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "${FAST_GATE_SUITE_TIMEOUT:-900}" "$@"
}
worker() {
  local work=$1 index=$2 kind=$3 file=$4 label="" begin=$SECONDS rc=0 no_tests=0
  local -a command=() pytest_cmd=() docs=()
  case "$kind" in
    bats) label=$file; command=(bats "$file") ;;
    pytest)
      label=$file
      if [[ -n "${PYTEST:-}" ]]; then read -r -a pytest_cmd <<< "$PYTEST"
      elif command -v pytest >/dev/null 2>&1; then pytest_cmd=(pytest)
      elif python3 -m pytest --version >/dev/null 2>&1; then pytest_cmd=(python3 -m pytest)
      elif [[ -x "$HOME/.pyenv/shims/python3" ]] && "$HOME/.pyenv/shims/python3" -m pytest --version >/dev/null 2>&1; then pytest_cmd=("$HOME/.pyenv/shims/python3" -m pytest)
      fi
      if (( ${#pytest_cmd[@]} == 0 )); then
        printf 'SKIP pytest 0s (not installed)\n' > "$work/result.$index"
        return
      fi
      command=(scripts/tests/tripwire.sh "${pytest_cmd[@]}" "$file")
      case "$file" in
        scripts/tests/bin/test_dispatch_metrics.py|scripts/tests/bin/test_dashboard_queries.py|scripts/tests/bin/test_orbstack_metrics.py|scripts/tests/observability/test_cve_fix_available_alert.py)
          if ! command -v promtool >/dev/null 2>&1; then
            run_limited scripts/tests/tripwire.sh "${pytest_cmd[@]}" --collect-only -q -m external "$file" > "$work/collect.$index" 2>&1 || rc=$?
            if (( rc != 0 && rc != 5 )); then
              printf 'FAIL %s 0s (pytest collection)\n' "$file" > "$work/result.$index"
              tail -n 20 "$work/collect.$index" >> "$work/result.$index"
              : > "$work/fail.$index"
              return
            fi
            command+=( -m 'not external' )
          fi ;;
      esac ;;
    shellcheck) label="shellcheck $file"; command=(shellcheck -S error "$file") ;;
    yamllint) label="yamllint $file"; command=(yamllint "$file") ;;
    docs)
      while IFS= read -r line; do docs+=("$line"); done < "$work/docs"
      label="doc-links (${#docs[@]} files)"
      command=(python3 scripts/check-doc-links.py "${docs[@]}") ;;
  esac
  if ! command -v "${command[0]}" >/dev/null 2>&1; then
    printf 'SKIP %s 0s (not installed)\n' "${command[0]}" > "$work/result.$index"
    return
  fi
  rc=0
  run_limited "${command[@]}" > "$work/output.$index" 2>&1 || rc=$?
  if [[ "$kind" == pytest && -f "$work/collect.$index" && "$rc" == 5 ]] && grep -Eq '[0-9]+ deselected' "$work/output.$index"; then rc=0; no_tests=1; fi
  local elapsed=$((SECONDS - begin))
  if (( no_tests )); then
    printf 'SKIP %s %ss (no tests remain)\n' "$label" "$elapsed" > "$work/result.$index"
  elif (( rc == 0 )); then
    printf 'PASS %s %ss\n' "$label" "$elapsed" > "$work/result.$index"
  else
    printf 'FAIL %s %ss\n' "$label" "$elapsed" > "$work/result.$index"
    tail -n 20 "$work/output.$index" >> "$work/result.$index"
    : > "$work/fail.$index"
  fi
  if [[ -f "$work/collect.$index" ]]; then
    while IFS= read -r line; do
      case "$line" in "$file"::*) printf 'SKIP %s promtool tests (promtool not installed): %s\n' "$file" "$line" >> "$work/result.$index" ;; esac
    done < "$work/collect.$index"
  fi
  printf '%s\n%s\n' "$elapsed" "$label" > "$work/time.$index"
}
if [[ "${1:-}" == --worker ]]; then
  shift
  worker "$@"
  exit
fi
tree=$(git rev-parse --show-toplevel)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX
cd "$tree"
start=$SECONDS
failed=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
snapshot_repo() {
  local target=$1
  git config --local --get-all core.bare > "$target.bare" || :
  git config --local --get-regexp '^user\.' > "$target.user" || :
  git for-each-ref --format='%(refname)' refs/heads > "$target.branches"
  git worktree list --porcelain | sed -n 's/^worktree //p' > "$target.worktrees"
}
snapshot_repo "$work/before"
branch=$(git symbolic-ref --quiet --short HEAD || true)
base=${1:-}
if [[ -z "$base" ]]; then
  base=$(git merge-base HEAD "origin/$branch" 2>/dev/null || git merge-base HEAD origin/main)
fi
git diff --name-only --diff-filter=ACMR "$base" HEAD > "$work/changed"
: > "$work/tests"
add_test() {
  case "$1" in scripts/tests/*.bats|scripts/tests/test_*.py|scripts/tests/*/test_*.py) [[ -f "$1" ]] && printf '%s\n' "$1" >> "$work/tests" ;; esac
  return 0
}
while IFS= read -r file || [[ -n "$file" ]]; do
  [[ -z "$file" || "$file" == \#* ]] && continue
  if [[ ! -f "$file" ]]; then
    printf 'FAIL %s 0s (static suite missing)\n' "$file"
    failed=1
  else
    add_test "$file"
  fi
done < scripts/etc/fast-gate/static.list
while IFS= read -r file; do add_test "$file"; done < "$work/changed"
: > "$work/patterns"
while IFS= read -r file; do
  case "$file" in scripts/tests/*.bats|scripts/tests/test_*.py|scripts/tests/*/test_*.py) continue ;; esac
  printf '%s\n%s\n' "$file" "${file##*/}" >> "$work/patterns"
done < "$work/changed"
: > "$work/matched"
if [[ -s "$work/patterns" ]]; then
  find scripts/tests -type f \( -name '*.bats' -o -name 'test_*.py' \) -print0 |
    xargs -0 grep -lF -f "$work/patterns" > "$work/matched" || true
fi
sort -u "$work/tests" -o "$work/tests"
sort -u "$work/matched" -o "$work/matched"
comm -23 "$work/matched" "$work/tests" > "$work/extra"
count=$(wc -l < "$work/extra" | tr -d ' ')
if (( count > 40 )); then printf 'fast-gate: %s more tests name touched files — run make test\n' "$((count - 40))"; fi
head -n 40 "$work/extra" >> "$work/tests"
jobs=${FAST_GATE_JOBS:-4}
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  printf 'FAIL FAST_GATE_JOBS 0s (expected a positive integer)\n'
  exit 1
fi
index=0
: > "$work/queue"
: > "$work/priority"
: > "$work/preflight"
queue_check() {
  index=$((index + 1))
  if [[ "$2" == scripts/tests/bin/ask_bash_scope.bats ]]; then
    printf '%s\0%s\0%s\0' "$index" "$1" "$2" >> "$work/preflight"
  elif [[ "$2" == scripts/tests/bin/codex_dispatch.bats ]]; then
    printf '%s\0%s\0%s\0' "$index" "$1" "$2" >> "$work/priority"
  else
    printf '%s\0%s\0%s\0' "$index" "$1" "$2" >> "$work/queue"
  fi
}
while IFS= read -r file; do
  case "$file" in
    *.bats) queue_check bats "$file" ;;
    *.py) queue_check pytest "$file" ;;
  esac
done < "$work/tests"
: > "$work/docs"
while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  case "$file" in
    *.sh) queue_check shellcheck "$file" ;;
    .github/workflows/*.yml) queue_check yamllint "$file" ;;
    *.md) printf '%s\n' "$file" >> "$work/docs" ;;
  esac
done < "$work/changed"
if [[ -s "$work/docs" ]]; then queue_check docs docs; fi
# This suite creates temporary files in the repository, which tree-copying tests
# can otherwise observe while they disappear.
if [[ -s "$work/preflight" ]]; then
  xargs -0 -n 3 -P "$jobs" /bin/bash scripts/ci/fast_gate.sh --worker "$work" < "$work/preflight" || failed=1
fi
if [[ -s "$work/priority" || -s "$work/queue" ]]; then
  cat "$work/priority" "$work/queue" | xargs -0 -n 3 -P "$jobs" /bin/bash scripts/ci/fast_gate.sh --worker "$work" || failed=1
fi
snapshot_repo "$work/after"
for part in bare user branches worktrees; do
  if ! cmp -s "$work/before.$part" "$work/after.$part"; then
    printf 'FAIL repository %s changed during fast gate\n' "$part"
    diff -u "$work/before.$part" "$work/after.$part" || :
    failed=1
  fi
done
slowest=-1
slowest_label="none"
for (( i=1; i<=index; i++ )); do
  if [[ -f "$work/result.$i" ]]; then cat "$work/result.$i"; else printf 'FAIL check %s 0s (worker failed)\n' "$i"; failed=1; fi
  [[ ! -f "$work/fail.$i" ]] || failed=1
  if [[ -f "$work/time.$i" ]]; then
    { IFS= read -r elapsed; IFS= read -r label; } < "$work/time.$i"
    if (( elapsed > slowest )); then slowest=$elapsed; slowest_label=$label; fi
  fi
done
if (( slowest < 0 )); then slowest=0; fi
printf 'SLOWEST %s %ss\n' "$slowest_label" "$slowest"
printf 'TOTAL %ss\n' "$((SECONDS - start))"
exit "$failed"
