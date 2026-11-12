#!/usr/bin/env bats

# Captures for deterministic command stubs (M4 Air, 2026-11-07 UTC):
# git ls-remote origin refs/heads/deploy/hub refs/heads/k3d-manager-v1.43.15
#   07b81638d32841067f1dc5364d946203808db982 refs/heads/k3d-manager-v1.43.15
# gh api repos/wilddog64/k3d-manager/commits/07b81638d32841067f1dc5364d946203808db982/check-runs
#   m4-air.local, 2026-11-07 20:28:49 UTC: {"total_count":0,"check_runs":[]}
# Test pages use that response shape; each run includes status and conclusion.
# kubectl get nodes -o wide
#   Unable to connect to the server 127.0.0.1:55730 (read-only capture; context unavailable)

setup() {
  REPO="${BATS_TEST_DIRNAME}/../../.."
  REPO="$(cd "$REPO" && pwd)"
  WORK="${BATS_TEST_TMPDIR}/scratch-repo"
  ORIGIN="${BATS_TEST_TMPDIR}/origin.git"
  HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME/.config/k3d-manager"
  printf 'hub\n' > "$HOME/.config/k3d-manager/machine-role"
  export HOME
  export XDG_CONFIG_HOME="$HOME/.config"
  git init --bare -q "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  WORK="$(cd "$WORK" && pwd -P)"
  ORIGIN="$(cd "$ORIGIN" && pwd -P)"
  origin_url="$(git -C "$WORK" remote get-url origin)"
  origin_url="$(cd "$origin_url" && pwd -P)"
  [ "$origin_url" = "$ORIGIN" ]
  git -C "$WORK" config user.name 'Hub promote tests'
  git -C "$WORK" config user.email 'hub-promote-tests@example.invalid'
  mkdir -p "$WORK/bin" "$WORK/scripts" "$WORK/scripts/etc/argocd/platform-ops"
  mkdir -p "$WORK/scripts/lib/foundation/scripts/lib"
  cp "$REPO/Makefile" "$WORK/Makefile"
  cp "$REPO/bin/k3dm-require-role" "$WORK/bin/"
  cp "$REPO/bin/k3dm-hub-promote" "$WORK/bin/" 2>/dev/null || true
  cp "$REPO/scripts/lib/foundation/scripts/lib/system.sh" "$WORK/scripts/lib/foundation/scripts/lib/"
  cat > "$WORK/scripts/k3d-manager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -f .fixture-root ]] || exit 88
printf 'DEPLOY_CWD=%s\n' "$PWD" >> "$CALLS"
printf 'BRANCH=%s %s\n' "${K3D_MANAGER_BRANCH:-}" "$*" | tee -a "$CALLS"
[[ "${FAIL_DEPLOY:-0}" != 1 ]] || exit 23
kubectl apply -f scripts/etc/argocd/platform-ops/test.yaml
EOF
  chmod +x "$WORK/scripts/k3d-manager"
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: tracked\n' > "$WORK/scripts/etc/argocd/platform-ops/test.yaml"
  printf 'scratch-repo\n' > "$WORK/.fixture-root"
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  REAL_GIT_PATH="$(command -v git)"
  REAL_DATE_PATH="$(command -v date)"
  export REAL_DATE_PATH DATE_COUNTER="$BATS_TEST_TMPDIR/date-counter"
  printf '0\n' > "$DATE_COUNTER"
  cat > "$BATS_TEST_TMPDIR/stubs/git" <<'EOF'
#!/usr/bin/env bash
# Git operations are constrained to the named scratch clone or its bare origin.
allowed=0
for arg in "$@"; do
  [[ "$arg" == "$SCRATCH_REPO" || "$arg" == "$MOVE_SOURCE_REPO" || "$arg" == "$TEST_ORIGIN" || "$arg" == "--git-dir=$TEST_ORIGIN" ]] && allowed=1
done
[[ "$allowed" == 1 ]] || { echo "git stub refused a non-fixture target: $*" >&2; exit 97; }
if [[ "${CHERRY_FAIL:-0}" == 1 && " $* " == *" cherry "* ]]; then
  echo "stubbed git cherry failure" >&2
  exit 1
fi
if [[ -n "${CAT_FILE_FAIL_SHA:-}" && "$*" == *"cat-file -e $CAT_FILE_FAIL_SHA^"* ]]; then
  echo "stubbed unavailable commit $CAT_FILE_FAIL_SHA" >&2
  exit 1
fi
if [[ "${MOVE_ON_LS_REMOTE:-0}" == 1 && ! -e "$MOVE_ONCE_FILE" && "$*" == *"ls-remote origin refs/heads/deploy/hub"* ]]; then
  : > "$MOVE_ONCE_FILE"
  "$REAL_GIT_PATH" -C "$MOVE_SOURCE_REPO" push "$TEST_ORIGIN" "$MOVE_HUB_SHA:refs/heads/race-promoter" >/dev/null 2>&1
  "$REAL_GIT_PATH" --git-dir="$TEST_ORIGIN" update-ref refs/heads/deploy/hub "$MOVE_HUB_SHA"
fi
exec "$REAL_GIT_PATH" "$@"
EOF
  cat > "$BATS_TEST_TMPDIR/stubs/gh" <<'EOF'
#!/usr/bin/env bash
# Read-only capture: m4-air.local, 2026-11-07 20:28:49 UTC:
# gh api repos/.../check-runs => {"total_count":0,"check_runs":[]}.
[[ "$1" == api && "$2" == --paginate && "$3" == repos/wilddog64/k3d-manager/commits/*/check-runs && "$4" == --jq && "$5" == '.check_runs[]' ]] || exit 97
if [[ "${GH_STUB_MODE:-empty}" == success ]]; then
  printf '{"status":"completed","conclusion":"success"}\n'
elif [[ "${GH_STUB_MODE:-empty}" == pending ]]; then
  printf '{"status":"in_progress","conclusion":null}\n'
elif [[ "${GH_STUB_MODE:-empty}" == failed ]]; then
  printf '{"status":"completed","conclusion":"failure"}\n'
elif [[ "${GH_STUB_MODE:-empty}" == page31 ]]; then
  page1="$(jq -cn '{total_count:31,check_runs:[range(0;30)|{status:"completed",conclusion:"success"}]}')"
  page2='{"total_count":31,"check_runs":[{"status":"completed","conclusion":"failure"}]}'
  jq -c '.check_runs[]' <<< "$page1"
  jq -c '.check_runs[]' <<< "$page2"
else
  :
fi
EOF
  cat > "$BATS_TEST_TMPDIR/stubs/date" <<'EOF'
#!/usr/bin/env bash
if [[ "$#" == 2 && "$1" == -u && "$2" == +%Y%m%dT%H%M%SZ ]]; then
  count="$(cat "$DATE_COUNTER")"
  count=$((count + 1))
  printf '%s\n' "$count" > "$DATE_COUNTER"
  printf '20261107T2100%02dZ\n' "$count"
else
  exec "$REAL_DATE_PATH" "$@"
fi
EOF
  cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'EOF'
#!/usr/bin/env bash
# Captured read-only output: M4 Air, 2026-11-07 UTC, kubectl get nodes -o wide => connection refused at 127.0.0.1:55730.
[[ "$1" == apply && "$2" == -f ]] || exit 2
[[ -f .fixture-root && "$(cat .fixture-root)" == scratch-repo ]] || exit 98
printf 'TARGET=%s\n' "$PWD" >> "$CALLS"
cat "$3" >> "$KUBECTL_CAPTURE"
printf 'The connection to the server 127.0.0.1:55730 was refused - did you specify the right host or port?\n'
EOF
  chmod +x "$BATS_TEST_TMPDIR/stubs/gh" "$BATS_TEST_TMPDIR/stubs/kubectl" "$BATS_TEST_TMPDIR/stubs/date"
  chmod +x "$BATS_TEST_TMPDIR/stubs/git"
  export REAL_GIT_PATH SCRATCH_REPO="$WORK" TEST_ORIGIN="$ORIGIN"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  git -C "$WORK" add Makefile scripts bin .fixture-root
  git -C "$WORK" commit -qm initial
  git -C "$WORK" branch -M k3d-manager-v1.43.15
  git -C "$WORK" push -q origin HEAD:refs/heads/k3d-manager-v1.43.15
  git -C "$WORK" checkout -qb feature/test
  git -C "$WORK" push -q origin HEAD:refs/heads/feature/test
  git -C "$WORK" branch deploy/hub
  git -C "$WORK" push -q origin HEAD:refs/heads/deploy/hub
  : > "$BATS_TEST_TMPDIR/calls"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  : > "$BATS_TEST_TMPDIR/kubectl-calls"
  export KUBECTL_CAPTURE="$BATS_TEST_TMPDIR/kubectl-calls"
}

_run_promoter_tty() {
  local answer="$1"
  local mode="$2"
  shift 2
  run env GH_STUB_MODE="$mode" TEST_ORIGIN="$ORIGIN" MOVE_HUB_SHA="${MOVE_HUB_SHA:-}" REAL_GIT="${REAL_GIT_PATH:-$(command -v git)}" python3 - "$WORK/bin/k3dm-hub-promote" "$HOME" "$XDG_CONFIG_HOME" "$PATH" "$ORIGIN" "$answer" "$@" <<'PY'
import os, pty, select, subprocess, sys, time

script, home, config, path, origin, answer, *args = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(HOME=home, XDG_CONFIG_HOME=config, PATH=path,
                      GH_STUB_MODE=os.environ.get("GH_STUB_MODE", "empty"),
                      TEST_ORIGIN=origin, MOVE_HUB_SHA=os.environ.get("MOVE_HUB_SHA", ""),
                      REAL_GIT=os.environ.get("REAL_GIT", "git"))
    os.execv(script, [script, *args])
data = b""
sent = reaped = False
deadline = time.time() + 10
while time.time() < deadline:
    ready, _, _ = select.select([fd], [], [], 0.2)
    if ready:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        data += chunk
        if b"Type 'promote' to continue:" in data and not sent:
            move_sha = os.environ.get("MOVE_HUB_SHA", "")
            if move_sha:
                subprocess.run([os.environ["REAL_GIT"], f"--git-dir={origin}",
                                "update-ref", "refs/heads/deploy/hub", move_sha], check=True)
            os.write(fd, (answer + "\n").encode())
            sent = True
    done, status = os.waitpid(pid, os.WNOHANG)
    if done:
        reaped = True
        break
if not reaped:
    _, status = os.waitpid(pid, 0)
sys.stdout.write(data.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(status))
PY
}

_prepare_promotion_history() {
  local label
  for label in A B C D; do
    printf '%s\n' "$label" > "$WORK/promotion-$label.txt"
    git -C "$WORK" add "promotion-$label.txt"
    git -C "$WORK" commit -qm "promotion $label"
    case "$label" in
      A) A_SHA="$(git -C "$WORK" rev-parse HEAD)" ;;
      B) B_SHA="$(git -C "$WORK" rev-parse HEAD)" ;;
      C) C_SHA="$(git -C "$WORK" rev-parse HEAD)" ;;
      D) D_SHA="$(git -C "$WORK" rev-parse HEAD)" ;;
    esac
  done
  git -C "$WORK" push -q origin "$D_SHA:refs/heads/k3d-manager-v1.43.15"
}

_make_candidate() {
  git -C "$WORK" checkout -q k3d-manager-v1.43.15
  printf 'candidate\n' > "$WORK/candidate.txt"
  git -C "$WORK" add candidate.txt
  git -C "$WORK" commit -qm candidate
  git -C "$WORK" push -q origin HEAD:refs/heads/k3d-manager-v1.43.15
}

_promote_sha() {
  _run_promoter_tty promote success promote "$1" 0
  [ "$status" -eq 0 ]
}

_rollback_to() {
  local expected="$1"
  local tag_ref tag_data
  _run_promoter_tty promote empty rollback
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  local actual
  actual="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  if [ "$actual" != "$expected" ]; then
    printf 'expected rollback target %s; got %s\n' "$expected" "$actual" >&2
    return 1
  fi
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}' | sort -r | head -1)"
  git -C "$WORK" fetch -q origin "$tag_ref"
  tag_data="$(git -C "$WORK" cat-file -p FETCH_HEAD)"
  grep -Fxq 'action: rollback' <<< "$tag_data"
  grep -Fxq "new: $expected" <<< "$tag_data"
}

_seed_exhausted_promotion_stack() {
  _prepare_promotion_history
  initial="$(git -C "$WORK" rev-parse HEAD~4)"
  git -C "$WORK" tag -a hub-promote/20261107T210001Z "$A_SHA" -m "action: promote
old: $initial
new: $A_SHA
REF: $A_SHA"
  git -C "$WORK" tag -a hub-promote/20261107T210002Z "$B_SHA" -m "action: promote
old: $A_SHA
new: $B_SHA
REF: $B_SHA"
  git -C "$WORK" tag -a hub-promote/20261107T210003Z "$C_SHA" -m "action: promote
old: $B_SHA
new: $C_SHA
REF: $C_SHA"
  git -C "$WORK" tag -a hub-promote/20261107T210004Z "$B_SHA" -m "action: rollback
old: $C_SHA
new: $B_SHA
REF: $B_SHA
rollback: yes"
  git -C "$WORK" tag -a hub-promote/20261107T210005Z "$A_SHA" -m "action: rollback
old: $B_SHA
new: $A_SHA
REF: $A_SHA
rollback: yes"
  git -C "$WORK" push -q origin refs/tags/hub-promote/20261107T210001Z refs/tags/hub-promote/20261107T210002Z refs/tags/hub-promote/20261107T210003Z refs/tags/hub-promote/20261107T210004Z refs/tags/hub-promote/20261107T210005Z
  git --git-dir="$ORIGIN" update-ref refs/heads/deploy/hub "$A_SHA"
  printf '5\n' > "$DATE_COUNTER"
}

@test "M3 N3: promoter commit arriving between fetch and ls-remote is preserved" {
  _prepare_promotion_history
  git -C "$WORK" fetch -q origin
  git -C "$WORK" branch -f k3d-manager-v1.43.15 "$D_SHA"
  git -C "$WORK" checkout -q feature/test
  MOVE_SOURCE_REPO="$BATS_TEST_TMPDIR/race-source"
  export MOVE_SOURCE_REPO
  git clone -q --branch k3d-manager-v1.43.15 "$ORIGIN" "$MOVE_SOURCE_REPO"
  git -C "$MOVE_SOURCE_REPO" config user.name 'Race promoter'
  git -C "$MOVE_SOURCE_REPO" config user.email 'race-promoter@example.invalid'
  echo promoter > "$MOVE_SOURCE_REPO/promoter-arrival.txt"
  git -C "$MOVE_SOURCE_REPO" add promoter-arrival.txt
  git -C "$MOVE_SOURCE_REPO" commit -qm "promoter arrival"
  MOVE_HUB_SHA="$(git -C "$MOVE_SOURCE_REPO" rev-parse HEAD)"
  export MOVE_HUB_SHA MOVE_SOURCE_REPO MOVE_ONCE_FILE="$BATS_TEST_TMPDIR/move-once" MOVE_ON_LS_REMOTE=1
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"deploy/hub contains 1 commit"* ]]
  [[ "$output" == *"promoter arrival"* ]]
  [[ "$output" != *"no commits between refs"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$MOVE_HUB_SHA" ]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "M3: promote fails closed on git cherry error and succeeds when restored" {
  _make_candidate
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  export CHERRY_FAIL=1
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot check deploy/hub containment"* ]]
  [[ "$output" == *"stubbed git cherry failure"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
  export CHERRY_FAIL=0
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" != "$old" ]
}

@test "M3: promote names an unavailable deploy/hub SHA and succeeds when available" {
  _make_candidate
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  export CAT_FILE_FAIL_SHA="$old"
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"deploy/hub commit $old is not available locally; refusing to promote"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
  export CAT_FILE_FAIL_SHA=
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" != "$old" ]
}

@test "N3: appsets-reapply pins deploy/hub despite BRANCH and checked-out branch" {
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CALLS="$CALLS" make -C "$WORK" --no-print-directory appsets-reapply BRANCH=feature/test APPSETS_STAGE=hub
  [ "$status" -eq 0 ]
  [[ "$output" == *"BRANCH=deploy/hub deploy_argocd_applicationsets --confirm"* ]]
}

@test "N2: promote refuses missing checks without changing refs or tags" {
  _make_candidate
  [ -n "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub)" ]
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH="$PATH" "$WORK/bin/k3dm-hub-promote" promote k3d-manager-v1.43.15 < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"check runs"* || "$output" == *"checks"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$(git -C "$WORK" rev-parse deploy/hub)" ]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "M2 bootstrap creates deploy/hub only after the normal confirmation" {
  git --git-dir="$ORIGIN" update-ref -d refs/heads/deploy/hub
  _run_promoter_tty promote success promote HEAD 0
  [ "$status" -eq 0 ]
  sha="$(git -C "$WORK" rev-parse HEAD)"
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$sha" ]
  [[ "$output" == *"bootstrap: deploy/hub does not exist yet"* ]]
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}')"
  git -C "$WORK" fetch -q origin "$tag_ref"
  [[ "$(git -C "$WORK" cat-file -p FETCH_HEAD)" == *"old: 0000000000000000000000000000000000000000"* ]]
}

@test "N2: pending and failed check runs refuse without moving deploy/hub" {
  _make_candidate
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  for mode in pending failed; do
    run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH="$PATH" GH_STUB_MODE="$mode" "$WORK/bin/k3dm-hub-promote" promote k3d-manager-v1.43.15 < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"pending or failed"* ]]
    [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
    [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
  done
}

@test "N2: a failure on the second check-runs page refuses promotion" {
  _make_candidate
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH="$PATH" GH_STUB_MODE=page31 "$WORK/bin/k3dm-hub-promote" promote k3d-manager-v1.43.15 < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"pending or failed"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "N2: a local-only commit is refused and leaves origin unchanged" {
  printf 'local only\n' > "$WORK/local-only.txt"
  git -C "$WORK" add local-only.txt
  git -C "$WORK" commit -qm local-only
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH="$PATH" "$WORK/bin/k3dm-hub-promote" promote HEAD 1 < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"not reachable from an origin branch"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "N2: non-TTY and wrong confirmation refuse without changing refs or tags" {
  _make_candidate
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH="$PATH" GH_STUB_MODE=success "$WORK/bin/k3dm-hub-promote" promote k3d-manager-v1.43.15 < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a TTY"* ]]
  _run_promoter_tty nope success promote k3d-manager-v1.43.15 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not match promote"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "M2: promote updates deploy/hub with lease and records an annotated tag" {
  git -C "$WORK" checkout -q k3d-manager-v1.43.15
  printf 'promoted control\n' > "$WORK/promoted.txt"
  git -C "$WORK" add promoted.txt
  git -C "$WORK" commit -qm 'promoted control'
  git -C "$WORK" push -q origin HEAD:refs/heads/k3d-manager-v1.43.15
  new="$(git -C "$WORK" rev-parse HEAD)"
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"--force-with-lease"* || "$output" == *"moved deploy/hub"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$new" ]
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}')"
  [[ "$tag_ref" =~ ^refs/tags/hub-promote/[0-9]{8}T[0-9]{6}Z$ ]]
  tag_name="${tag_ref#refs/tags/}"
  git -C "$WORK" fetch -q origin "$tag_ref"
  tag_data="$(git -C "$WORK" cat-file -p FETCH_HEAD)"
  grep -Fxq "old: $old" <<< "$tag_data"
  grep -Fxq "new: $new" <<< "$tag_data"
  grep -Fxq 'REF: k3d-manager-v1.43.15' <<< "$tag_data"
  [[ "$tag_data" == *"action: promote"* ]]
  [ -n "$tag_name" ]
}

@test "M1: promoting current deploy/hub is a no-op" {
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH="$PATH" "$WORK/bin/k3dm-hub-promote" promote "$old" 1 < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at $old"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "M2: rollback skips duplicate consecutive promotions and returns to prior distinct commit" {
  _prepare_promotion_history
  initial="$(git -C "$WORK" rev-parse "$A_SHA^" )"
  for spec in "20261107T210011Z $initial $A_SHA" "20261107T210012Z $A_SHA $B_SHA" "20261107T210013Z $B_SHA $B_SHA"; do
    read -r stamp prior promoted <<< "$spec"
    git -C "$WORK" tag -a "hub-promote/$stamp" "$promoted" -m "action: promote
old: $prior
new: $promoted
REF: $promoted"
  done
  git -C "$WORK" push -q origin refs/tags/hub-promote/20261107T210011Z refs/tags/hub-promote/20261107T210012Z refs/tags/hub-promote/20261107T210013Z
  git --git-dir="$ORIGIN" update-ref refs/heads/deploy/hub "$B_SHA"
  printf '13\n' > "$DATE_COUNTER"
  [ "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')" -eq 3 ]
  _rollback_to "$A_SHA"
}

@test "M3: non-lease push failure reports git reason without lease rejection" {
  git -C "$WORK" checkout -q k3d-manager-v1.43.15
  printf 'hook failure control\n' > "$WORK/hook-failure.txt"
  git -C "$WORK" add hook-failure.txt
  git -C "$WORK" commit -qm hook-failure
  git -C "$WORK" push -q origin HEAD:refs/heads/k3d-manager-v1.43.15
  mkdir -p "$WORK/.git/hooks"
  printf '#!/bin/sh\necho pre-push-blocked >&2\nexit 1\n' > "$WORK/.git/hooks/pre-push"
  chmod +x "$WORK/.git/hooks/pre-push"
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"pre-push"* || "$output" == *"hook"* ]]
  [[ "$output" == *"pre-push-blocked"* ]]
  [[ "$output" != *"lease rejected"* ]]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "M4: divergent local and origin branch is rejected with both SHAs" {
  _prepare_promotion_history
  git -C "$WORK" checkout -q k3d-manager-v1.43.15
  git -C "$WORK" reset --hard -q "$A_SHA"
  old="$(git -C "$ORIGIN" rev-parse refs/heads/k3d-manager-v1.43.15)"
  local_sha="$(git -C "$WORK" rev-parse HEAD)"
  [ "$old" != "$local_sha" ]
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH="$PATH" "$WORK/bin/k3dm-hub-promote" promote k3d-manager-v1.43.15 1 < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"$local_sha"* && "$output" == *"$old"* ]]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "H4: break glass skips only checks and still needs confirmation and records mode" {
  _make_candidate
  _run_promoter_tty promote empty promote k3d-manager-v1.43.15 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"moved deploy/hub"* ]]
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}')"
  git -C "$WORK" fetch -q origin "$tag_ref"
  [[ "$(git -C "$WORK" cat-file -p FETCH_HEAD)" == *"mode: break-glass"* ]]
}

@test "M3: two rollbacks after A, B, C reach B then A" {
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  _promote_sha "$B_SHA"
  _promote_sha "$C_SHA"
  _rollback_to "$B_SHA"
  [[ "$output" == *"action: rollback"* || "$output" == *"moved deploy/hub"* ]]
  _rollback_to "$A_SHA"
}

@test "M3: after rollback to B and promote D, rollback returns to B" {
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  _promote_sha "$B_SHA"
  _promote_sha "$C_SHA"
  _rollback_to "$B_SHA"
  _promote_sha "$D_SHA"
  _rollback_to "$B_SHA"
}

@test "N5: exhausted promotion stack refuses after returning to bootstrap state" {
  _seed_exhausted_promotion_stack
  initial="$(git -C "$WORK" rev-parse "$A_SHA^")"
  _rollback_to "$initial"
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  tag_count="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')"
  _run_promoter_tty promote empty rollback
  [ "$status" -ne 0 ]
  [[ "$output" == *"no earlier promotion"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
  [ "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')" = "$tag_count" ]
}

@test "N5: bootstrap-only history refuses rollback without changes" {
  _make_candidate
  git --git-dir="$ORIGIN" update-ref -d refs/heads/deploy/hub
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 1
  [ "$status" -eq 0 ]
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  tag_count="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')"
  _run_promoter_tty promote empty rollback
  [ "$status" -ne 0 ]
  [[ "$output" == *"bootstrap"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
  [ "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')" = "$tag_count" ]
}

@test "M1 N1 E1: rollback preserves a promoter commit present before the last promotion" {
  [ "$(cd "$(git -C "$WORK" remote get-url origin)" && pwd -P)" = "$ORIGIN" ]
  [[ "$ORIGIN" != *"github.com"* ]]
  _prepare_kept_pin_promotion
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$B_WITH_X" ]

  _run_promoter_tty promote empty rollback
  [ "$status" -eq 0 ]
  [[ "$output" == *"will be removed from deploy/hub"* ]]
  [[ "$output" == *"promotion B"* ]]
  [[ "$output" != *"no commits between refs"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$X_SHA" ]
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}' | sort -r | head -1)"
  git -C "$WORK" fetch -q origin "$tag_ref"
  tag_data="$(git -C "$WORK" cat-file -p FETCH_HEAD)"
  grep -Fxq 'action: rollback' <<< "$tag_data"
  grep -Fxq "old: $B_WITH_X" <<< "$tag_data"
  grep -Fxq "new: $X_SHA" <<< "$tag_data"
}

@test "N1 E1: the rollback target retains X that was live before the last promotion" {
  _prepare_kept_pin_promotion
  _run_promoter_tty promote empty rollback
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$X_SHA" ]
}

@test "N3 E2: rollback with dropped commits never says no commits between refs" {
  _prepare_kept_pin_promotion
  _run_promoter_tty promote empty rollback
  [ "$status" -eq 0 ]
  [[ "$output" != *"no commits between refs"* ]]
}

@test "M2 E2: rollback confirmation lists the commits removed" {
  _prepare_kept_pin_promotion
  _run_promoter_tty promote empty rollback
  [ "$status" -eq 0 ]
  [[ "$output" == *"will be removed from deploy/hub"* ]]
  [[ "$output" == *"promotion B includes X"* ]]
}

@test "M3: after rollback keeps X, the next rollback removes X and B and reaches A" {
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  _promote_sha "$B_SHA"
  git -C "$WORK" fetch -q origin deploy/hub
  git -C "$WORK" checkout -q -B deploy/hub origin/deploy/hub
  printf 'CVE pin X\n' > "$WORK/cve-pin-x.txt"
  git -C "$WORK" add cve-pin-x.txt
  git -C "$WORK" commit -qm 'fix(cve): pin image X'
  X_SHA="$(git -C "$WORK" rev-parse HEAD)"
  B_WITH_X="$X_SHA"
  git -C "$WORK" push -q origin HEAD:refs/heads/deploy/hub
  git -C "$WORK" checkout -q -B feature/promotion-C "$X_SHA"
  printf 'promotion C\n' > "$WORK/promotion-C.txt"
  git -C "$WORK" add promotion-C.txt
  git -C "$WORK" commit -qm 'promotion C includes X'
  C_WITH_X="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/feature/promotion-C
  _promote_sha feature/promotion-C
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$C_WITH_X" ]

  _rollback_to "$B_WITH_X"
  _rollback_to "$A_SHA"
  [[ "$output" == *"will be removed from deploy/hub"* ]]
  [[ "$output" == *"fix(cve): pin image X"* ]]
  [[ "$output" == *"promotion B"* ]]
}

@test "M4: a BREAK_GLASS rollback tag replays before a second rollback" {
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  _promote_sha "$B_SHA"
  _promote_sha "$C_SHA"
  git -C "$WORK" fetch -q origin deploy/hub
  git -C "$WORK" checkout -q -B deploy/hub origin/deploy/hub
  printf 'uncontained Y\n' > "$WORK/uncontained-y.txt"
  git -C "$WORK" add uncontained-y.txt
  git -C "$WORK" commit -qm 'uncontained Y'
  Y_SHA="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/deploy/hub

  _run_promoter_tty promote empty rollback 1
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$B_SHA" ]
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}' | sort -r | head -1)"
  git -C "$WORK" fetch -q origin "$tag_ref"
  tag_data="$(git -C "$WORK" cat-file -p FETCH_HEAD)"
  grep -Fxq 'action: rollback' <<< "$tag_data"
  grep -Fxq "old: $Y_SHA" <<< "$tag_data"
  grep -Fxq "new: $B_SHA" <<< "$tag_data"
  _rollback_to "$A_SHA"
}

@test "M2: rollback confirmation lists commits added from a divergent target" {
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  git -C "$WORK" checkout -q -B feature/divergent-promotion "$A_SHA^"
  printf 'divergent promotion\n' > "$WORK/divergent.txt"
  git -C "$WORK" add divergent.txt
  git -C "$WORK" commit -qm 'divergent target commit'
  target="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/feature/divergent-promotion
  _run_promoter_tty promote success promote feature/divergent-promotion 1
  [ "$status" -eq 0 ]

  _run_promoter_tty promote empty rollback
  [ "$status" -eq 0 ]
  [[ "$output" == *"will be added to deploy/hub"* ]]
  [[ "$output" == *"promotion A"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$A_SHA" ]
  [ "$target" != "$A_SHA" ]
}

@test "N2: rollback fails closed when the tag old SHA is absent locally" {
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  _promote_sha "$B_SHA"
  missing=1111111111111111111111111111111111111111
  if git -C "$WORK" cat-file -e "$missing^{commit}" 2>/dev/null; then false; fi
  git -C "$WORK" tag -a hub-promote/20261107T211500Z "$B_SHA" -m "action: promote
old: $missing
new: $B_SHA
REF: $B_SHA"
  git -C "$WORK" push -q origin refs/tags/hub-promote/20261107T211500Z
  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  _run_promoter_tty promote empty rollback
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot list rollback commits in range $missing..$old"* ]]
  [[ "$output" != *"Type 'promote' to continue"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
}

@test "M4: rollback replay warns and continues when old SHA cannot be fetched" {
  [ "$(cd "$(git -C "$WORK" remote get-url origin)" && pwd -P)" = "$ORIGIN" ]
  [[ "$ORIGIN" != *"github.com"* ]]
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  _promote_sha "$B_SHA"
  _promote_sha "$C_SHA"
  missing=1111111111111111111111111111111111111111
  if git -C "$WORK" cat-file -e "$missing^{commit}" 2>/dev/null; then false; fi
  printf '4\n' > "$DATE_COUNTER"
  git -C "$WORK" tag -a hub-promote/20261107T210004Z "$B_SHA" -m "action: rollback
old: $missing
new: $B_SHA
REF: $B_SHA
rollback: yes"
  git -C "$WORK" push -q origin refs/tags/hub-promote/20261107T210004Z
  git --git-dir="$ORIGIN" update-ref refs/heads/deploy/hub "$B_SHA"

  _run_promoter_tty promote empty rollback
  [ "$status" -eq 0 ]
  if [[ "$output" != *"WARNING: rollback tag refs/tags/hub-promote/20261107T210004Z old SHA $missing is unavailable locally"* ]]; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$A_SHA" ]
}

@test "N5: rollback refuses when deploy/hub moved outside the promotion stack" {
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  _promote_sha "$B_SHA"
  git -C "$WORK" update-ref refs/heads/outside "$D_SHA"
  git --git-dir="$ORIGIN" update-ref refs/heads/deploy/hub "$D_SHA"
  tag_count="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')"
  _run_promoter_tty promote empty rollback
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match the promotion stack top"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$D_SHA" ]
  [ "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')" = "$tag_count" ]
}

@test "M5: status reports deploy/hub, tags and ahead count without changing refs" {
  before_branches="$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | sort)"
  before_head="$(git -C "$WORK" rev-parse HEAD)"
  before_index="$(git -C "$WORK" write-tree)"
  before_worktree="$(git -C "$WORK" status --porcelain)"
  sha="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" RELEASE_BRANCH=k3d-manager-v1.43.15 PATH="$PATH" "$WORK/bin/k3dm-hub-promote" status < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy/hub: $sha"* ]]
  [[ "$output" == *"k3d-manager-v1.43.15 ahead of deploy/hub: 0"* ]]
  [ "$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | sort)" = "$before_branches" ]
  [ "$(git -C "$WORK" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$WORK" write-tree)" = "$before_index" ]
  [ "$(git -C "$WORK" status --porcelain)" = "$before_worktree" ]
}

@test "G regression: non-TTY promoter test completes when suite stdin is a terminal" {
  clean_path="${PATH#"$BATS_TEST_TMPDIR/stubs:"}"
  clean_path="$(printf '%s' "$clean_path" | tr ':' '\n' | grep -v '/libexec/bats-core$' | paste -sd: -)"
  if script --version 2>/dev/null | grep -q util-linux; then
    inner="$(printf '%q ' bats --tap -f 'N2: non-TTY' "$BATS_TEST_FILENAME")"
    run env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" PATH="$clean_path" \
      perl -e 'alarm 60; exec @ARGV' script -qec "$inner" /dev/null
  else
    run env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" PATH="$clean_path" \
      perl -e 'alarm 60; exec @ARGV' script -q /dev/null bats -f 'N2: non-TTY' "$BATS_TEST_FILENAME"
  fi
  [ "$status" -eq 0 ]
}

@test "M5: status counts origin and reports stale local release position" {
  git -C "$WORK" checkout -q k3d-manager-v1.43.15
  for index in 1 2 3 4 5; do
    printf 'release %s\n' "$index" >> "$WORK/release.txt"
    git -C "$WORK" add release.txt
    git -C "$WORK" commit -q -m "release $index"
    if [ "$index" -eq 2 ]; then second="$(git -C "$WORK" rev-parse HEAD)"; fi
  done
  git -C "$WORK" push -q origin HEAD:refs/heads/k3d-manager-v1.43.15
  git -C "$WORK" fetch -q origin
  git -C "$WORK" reset --hard -q "$second"
  before_branches="$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | sort)"
  before_head="$(git -C "$WORK" rev-parse HEAD)"
  before_index="$(git -C "$WORK" write-tree)"
  before_worktree="$(git -C "$WORK" status --porcelain)"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" RELEASE_BRANCH=k3d-manager-v1.43.15 PATH="$PATH" "$WORK/bin/k3dm-hub-promote" status < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3d-manager-v1.43.15 ahead of deploy/hub: 5"* ]]
  [[ "$output" == *"local k3d-manager-v1.43.15 is 3 behind / 0 ahead of origin"* ]]
  [ "$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | sort)" = "$before_branches" ]
  [ "$(git -C "$WORK" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$WORK" write-tree)" = "$before_index" ]
  [ "$(git -C "$WORK" status --porcelain)" = "$before_worktree" ]
}

@test "Makefile hub-promote passes REF and break-glass to the command" {
  _make_candidate
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH="$PATH" GH_STUB_MODE=empty make -C "$WORK" --no-print-directory hub-promote REF=HEAD BREAK_GLASS=1 < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"action: promote"* ]]
  [[ "$output" == *"REF: HEAD"* ]]
  [[ "$output" == *"confirmation requires a TTY"* ]]
}

@test "M4: platform-ops removes the archive tree when deployment fails" {
  : > "$CALLS"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CALLS="$CALLS" KUBECTL_CAPTURE="$KUBECTL_CAPTURE" FAIL_DEPLOY=1 make -C "$WORK" --no-print-directory platform-ops
  [ "$status" -ne 0 ]
  target="$(sed -n 's/^DEPLOY_CWD=//p' "$CALLS" | tail -1)"
  [ -n "$target" ]
  [ "$target" != "$WORK" ]
  [ ! -e "$target" ]
}

@test "M4: platform-ops applies deploy/hub SHA and removes the archive on success" {
  sha="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CALLS="$CALLS" KUBECTL_CAPTURE="$KUBECTL_CAPTURE" make -C "$WORK" --no-print-directory platform-ops
  [ "$status" -eq 0 ]
  [[ "$output" == *"applied deploy/hub $sha"* ]]
  target="$(sed -n 's/^DEPLOY_CWD=//p' "$CALLS" | tail -1)"
  [ -n "$target" ]
  [ "$target" != "$WORK" ]
  [ ! -e "$target" ]
}

@test "N4: stale lease refuses and creates no promotion tag" {
  git -C "$WORK" checkout -qb feature/moved
  printf 'moved deployment ref\n' > "$WORK/moved.txt"
  git -C "$WORK" add moved.txt
  git -C "$WORK" commit -qm moved
  moved_sha="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/feature/moved
  git -C "$WORK" checkout -q feature/test
  git -C "$WORK" checkout -qb feature/promoted
  printf 'promoted target\n' > "$WORK/promoted.txt"
  git -C "$WORK" add promoted.txt
  git -C "$WORK" commit -qm promoted
  git -C "$WORK" push -q origin HEAD:refs/heads/feature/promoted
  MOVE_HUB_SHA="$moved_sha" _run_promoter_tty promote success promote HEAD 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"lease"* || "$output" == *"changed"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$moved_sha" ]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
}

@test "N1: platform-ops ignores an uncommitted manifest edit" {
  printf 'UNCOMMITTED_SECRET\n' >> "$WORK/scripts/etc/argocd/platform-ops/test.yaml"
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CALLS="$CALLS" KUBECTL_CAPTURE="$KUBECTL_CAPTURE" make -C "$WORK" --no-print-directory platform-ops
  [ "$status" -eq 0 ]
  [[ "$output" != *UNCOMMITTED_SECRET* ]]
  if grep -q UNCOMMITTED_SECRET "$KUBECTL_CAPTURE"; then
    echo "uncommitted platform manifest reached kubectl" >&2
    return 1
  fi
}

@test "N1 positive control: committed manifest reaches platform-ops source" {
  printf 'COMMITTED_CONTROL\n' >> "$WORK/scripts/etc/argocd/platform-ops/test.yaml"
  git -C "$WORK" add scripts/etc/argocd/platform-ops/test.yaml
  git -C "$WORK" commit -qm 'platform control'
  git -C "$WORK" push -q origin HEAD:refs/heads/deploy/hub
  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CALLS="$CALLS" KUBECTL_CAPTURE="$KUBECTL_CAPTURE" make -C "$WORK" --no-print-directory platform-ops
  [ "$status" -eq 0 ]
  grep -q COMMITTED_CONTROL "$KUBECTL_CAPTURE"
}

_create_promoter_commit_on_hub() {
  local msg="${1:-fix(cve): pin shopping-cart-frontend to sha256:14bf71a5}"
  git -C "$WORK" fetch -q origin deploy/hub
  git -C "$WORK" checkout -q -B deploy/hub origin/deploy/hub
  printf 'sha256:14bf71a5\n' > "$WORK/cve-pin.txt"
  git -C "$WORK" add cve-pin.txt
  git -C "$WORK" commit -qm "$msg"
  PROMOTER_SHA="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/deploy/hub
}

_prepare_kept_pin_promotion() {
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  git -C "$WORK" fetch -q origin deploy/hub
  git -C "$WORK" checkout -q -B deploy/hub origin/deploy/hub
  printf 'CVE pin X\n' > "$WORK/cve-pin-x.txt"
  git -C "$WORK" add cve-pin-x.txt
  git -C "$WORK" commit -qm 'fix(cve): pin image X'
  X_SHA="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/deploy/hub
  git -C "$WORK" checkout -q -B feature/promotion-B "$X_SHA"
  printf 'promotion B\n' > "$WORK/promotion-B.txt"
  git -C "$WORK" add promotion-B.txt
  git -C "$WORK" commit -qm 'promotion B includes X'
  B_WITH_X="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/feature/promotion-B
  _promote_sha feature/promotion-B
}

@test "N1: promote refuses when deploy/hub contains uncontained promoter commit (E1)" {
  [ "$(cd "$(git -C "$WORK" remote get-url origin)" && pwd -P)" = "$ORIGIN" ]
  [[ "$ORIGIN" != *"github.com"* ]]
  _make_candidate
  _create_promoter_commit_on_hub
  promoter_sha="$PROMOTER_SHA"
  promoter_short="$(git -C "$WORK" rev-parse --short "$promoter_sha")"
  hub_before="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  [ "$hub_before" = "$promoter_sha" ]

  # Promotion without BREAK_GLASS must refuse and name the dropped commit
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"$promoter_short"* ]]
  [[ "$output" == *"fix(cve): pin shopping-cart-frontend"* ]]
  [[ "$output" == *"git cherry-pick -x"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$hub_before" ]
  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]

  # BREAK_GLASS=1 skips containment refusal
  _run_promoter_tty promote success promote k3d-manager-v1.43.15 1
  [ "$status" -eq 0 ]
  new_head="$(git -C "$WORK" rev-parse refs/remotes/origin/k3d-manager-v1.43.15)"
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$new_head" ]
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}')"
  git -C "$WORK" fetch -q origin "$tag_ref"
  [[ "$(git -C "$WORK" cat-file -p FETCH_HEAD)" == *"mode: break-glass"* ]]
}

@test "M1: promote succeeds when target contains promoter commit by cherry-pick" {
  [ "$(cd "$(git -C "$WORK" remote get-url origin)" && pwd -P)" = "$ORIGIN" ]
  [[ "$ORIGIN" != *"github.com"* ]]
  _make_candidate
  _create_promoter_commit_on_hub
  promoter_sha="$PROMOTER_SHA"
  git -C "$WORK" checkout -q k3d-manager-v1.43.15
  git -C "$WORK" cherry-pick -x "$promoter_sha"
  candidate_sha="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/k3d-manager-v1.43.15

  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$candidate_sha" ]
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}')"
  [ -n "$tag_ref" ]
}

@test "M1 positive control: promote succeeds when target contains deploy/hub by ancestry" {
  [ "$(cd "$(git -C "$WORK" remote get-url origin)" && pwd -P)" = "$ORIGIN" ]
  [[ "$ORIGIN" != *"github.com"* ]]
  git -C "$WORK" checkout -q deploy/hub
  git -C "$WORK" checkout -qb feature/ancestor-candidate
  printf 'feature on deploy/hub\n' > "$WORK/anc.txt"
  git -C "$WORK" add anc.txt
  git -C "$WORK" commit -qm 'anc commit'
  anc_sha="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" push -q origin HEAD:refs/heads/feature/ancestor-candidate

  _run_promoter_tty promote success promote feature/ancestor-candidate 0
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$anc_sha" ]
}

@test "N2: rollback refuses promoter commits not in stack top; BREAK_GLASS=1 permits (E3)" {
  [ "$(cd "$(git -C "$WORK" remote get-url origin)" && pwd -P)" = "$ORIGIN" ]
  [[ "$ORIGIN" != *"github.com"* ]]
  _prepare_promotion_history
  _promote_sha "$A_SHA"
  _promote_sha "$B_SHA"

  _create_promoter_commit_on_hub "fix(cve): pin service to sha256:2222"
  promoter_sha="$PROMOTER_SHA"
  promoter_short="$(git -C "$WORK" rev-parse --short "$promoter_sha")"
  hub_before="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
  [ "$hub_before" = "$promoter_sha" ]

  # Rollback without BREAK_GLASS must refuse and name the promoter commit
  _run_promoter_tty promote empty rollback
  [ "$status" -ne 0 ]
  [[ "$output" == *"$promoter_short"* ]]
  [[ "$output" == *"fix(cve): pin service"* ]]
  [[ "$output" == *"git cherry-pick -x"* ]]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$hub_before" ]

  # Rollback with BREAK_GLASS=1 succeeds and returns to earlier promotion
  _run_promoter_tty promote empty rollback 1
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$A_SHA" ]
  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}' | sort -r | head -1)"
  git -C "$WORK" fetch -q origin "$tag_ref"
  tag_data="$(git -C "$WORK" cat-file -p FETCH_HEAD)"
  grep -Fxq 'action: rollback' <<< "$tag_data"
  grep -Fxq "new: $A_SHA" <<< "$tag_data"
  [[ "$tag_data" == *"mode: break-glass"* ]]
}

@test "status reports uncontained commits on deploy/hub" {
  [ "$(cd "$(git -C "$WORK" remote get-url origin)" && pwd -P)" = "$ORIGIN" ]
  [[ "$ORIGIN" != *"github.com"* ]]
  _make_candidate
  _create_promoter_commit_on_hub "fix(cve): pin shopping-cart to sha256:abcd"
  promoter_sha="$PROMOTER_SHA"
  promoter_short="$(git -C "$WORK" rev-parse --short "$promoter_sha")"

  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" RELEASE_BRANCH=k3d-manager-v1.43.15 PATH="$PATH" "$WORK/bin/k3dm-hub-promote" status < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncontained commits on deploy/hub"* ]]
  [[ "$output" == *"$promoter_short"* ]]
  [[ "$output" == *"carry them over: git cherry-pick -x"* ]]
}
