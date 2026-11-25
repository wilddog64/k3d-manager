#!/usr/bin/env bats
# Darwin-only: the production verifier uses macOS stat and ACL interfaces.
# shellcheck disable=SC1090,SC1091,SC2329,SC2030,SC2031

setup() {
  [ "$(uname -s)" = Darwin ] || skip "verified-stage uses Darwin stat and ACL tools"
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRATCH="$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/verified-stage.XXXXXX")"
  BASE="$SCRATCH/base"
  mkdir -p "$BASE"
  SCRATCH="$(cd -P "$SCRATCH" && pwd)"
  BASE="$(cd -P "$BASE" && pwd)"
  SELF="$SCRATCH/self/k3dm-verified-stage"
  TRUST="$SCRATCH"
  mkdir -p "$SCRATCH/self"
  cp "$REPO/bin/k3dm-verified-stage" "$SELF"
  chmod 755 "$SELF"
  export HOME="$SCRATCH"
  [ "$BASE" = "$SCRATCH/base" ] && [ "$SELF" = "$SCRATCH/self/k3dm-verified-stage" ]
  [ "$TRUST" = "$SCRATCH" ] && [ "$HOME" = "$SCRATCH" ]
  source "$REPO/bin/k3dm-verified-stage"
  _VS_BASE="$BASE"; _VS_SELF="$SELF"; _VS_TRUST_TOP="$TRUST"
  _VS_OWNER="$(id -u)"; _VS_GROUP="$(id -g)"; _VS_GIT="$(command -v git)"
  _VS_GIT_CORE="$(dirname "$(command -v git)")"
  _VS_SUDO="$SCRATCH/sudo"
  mkdir -p "$SCRATCH/bin"
  cat > "$_VS_SUDO" <<'EOF'
#!/bin/sh
printf 'sudo %s\n' "$*" >> "$SUDO_LOG"
if [ "$1" = -k ]; then
  if [ "${SUDO_FAIL_K:-0}" = 1 ]; then exit 41; fi
  if [ "${SUDO_FAIL_K:-0}" = post ] && [ "$(grep -c '^sudo -k$' "$SUDO_LOG")" -ge 2 ]; then exit 41; fi
  exit 0
fi
if [ -n "${SUDO_READY_FILE:-}" ]; then : > "$SUDO_READY_FILE"; fi
if [ "${SUDO_HANG:-0}" = 1 ]; then
  : > "$SUDO_READY_FILE"
  while :; do sleep 1; done
fi
if [ "${SUDO_NOEXEC:-0}" = 1 ]; then exit "${SUDO_STATUS:-0}"; fi
shift
"$@"
EOF
  chmod 755 "$_VS_SUDO"
  cat > "$SCRATCH/bin/sudo" <<'EOF'
#!/bin/sh
printf 'sudo %s\n' "$*" >> "$SUDO_LOG"
exit 99
EOF
  LAUNCHCTL_STUB="$SCRATCH/bin/launchctl"
  printf '#!/bin/sh\nexit 99\n' > "$LAUNCHCTL_STUB"
  chmod 755 "$LAUNCHCTL_STUB" "$SCRATCH/bin/sudo"
  export SUDO_LOG="$SCRATCH/sudo.log"
  PATH="$SCRATCH/bin:$PATH"
  export PATH
}

teardown() { [ -z "${SCRATCH:-}" ] || { chmod -R u+rwx "$SCRATCH" 2>/dev/null || true; rm -rf -- "$SCRATCH"; }; }

_entry_setup() {
  local real_git url
  EP="$SCRATCH/entry"
  EP_BASE="$EP/base"
  EP_SELF="$EP/installed/k3dm-verified-stage"
  EP_TRUST="$EP"
  EP_WORK="$EP/work"
  EP_REMOTE="$EP/remote.git"
  EP_GIT="$EP/bin/git"
  EP_GIT_CORE="$EP/git-core"
  EP_SUDO="$EP/bin/sudo"
  EP_SUDO_LOG="$EP/sudo.log"
  EP_GIT_LOG="$EP/git.log"
  EP_FAIL_CLONE="$EP/fail-clone"
  url="${1:-file://$EP_REMOTE}"
  mkdir -p "$EP_BASE" "${EP_SELF%/*}" "${EP_GIT%/*}" "$EP_GIT_CORE" "$EP_WORK/bin"
  real_git="$(command -v git)"
  cat > "$EP_GIT" <<EOF
#!/bin/bash
printf 'PWD=%s %s\\n' "\$PWD" "\$*" >> "$EP_GIT_LOG"
if [ -e "$EP_FAIL_CLONE" ]; then case " \$* " in *' clone '*) exit 1;; esac; fi
exec "$real_git" "\$@"
EOF
  cat > "$EP_SUDO" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$EP_SUDO_LOG"
if [ "${1:-}" = -k ]; then exit 0; fi
FAKE_EUID=0 "$@"
EOF
  chmod 755 "$EP_GIT" "$EP_SUDO"
  export EP_SUDO_LOG
  python3 - "$REPO/bin/k3dm-verified-stage" "$EP_SELF" "$EP_BASE" "$url" "$EP_GIT" "$EP_GIT_CORE" "$EP_SELF" "$EP_TRUST" "$(id -u)" "$(id -g)" "$EP_SUDO" "$(id -u)" <<'PY'
import pathlib, sys
source, target, base, url, git, git_core, self_path, trust, owner, group, sudo, uid = sys.argv[1:]
values = {
    "_VS_BASE": base, "_VS_URL": url, "_VS_GIT": git,
    "_VS_GIT_CORE": git_core, "_VS_SELF": self_path,
    "_VS_TRUST_TOP": trust, "_VS_OWNER": owner,
    "_VS_GROUP": group, "_VS_SUDO": sudo,
}
lines = pathlib.Path(source).read_text().splitlines(keepends=True)
out = []
for line in lines:
    key = line.partition("=")[0]
    if key in values and line.startswith(key + "="):
        line = key + "=" + values[key] + "\n"
    elif line == "_vs_euid() { /usr/bin/id -u; }\n":
        line = f'_vs_euid() {{ printf \'%s\\n\' "${{FAKE_EUID:-{uid}}}"; }}\n'
    out.append(line)
pathlib.Path(target).write_text("".join(out))
pathlib.Path(target).chmod(0o755)
PY
  cat > "$EP_WORK/bin/k3dm-web-console-sshd" <<EOF
#!/bin/bash
/usr/bin/env | /usr/bin/sort > "$EP/child-env"
printf 'E2E-OUTPUT\\n'
exit "\${1:-0}"
EOF
  chmod 755 "$EP_WORK/bin/k3dm-web-console-sshd"
  git -C "$EP_WORK" init -q -b main
  cp "$EP_SELF" "$EP_WORK/bin/k3dm-verified-stage"
  printf '# harmless staged variant\n' >> "$EP_WORK/bin/k3dm-verified-stage"
  git -C "$EP_WORK" add bin
  git -C "$EP_WORK" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm main
  EP_MAIN="$(git -C "$EP_WORK" rev-parse HEAD)"
  git -C "$EP_WORK" branch deploy/hub "$EP_MAIN"
  git -C "$EP_WORK" checkout -qb side
  printf 'side\n' > "$EP_WORK/side.txt"
  git -C "$EP_WORK" add side.txt
  git -C "$EP_WORK" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm side
  EP_SIDE="$(git -C "$EP_WORK" rev-parse HEAD)"
  git clone -q --bare "$EP_WORK" "$EP_REMOTE"
  [ -d "$EP_BASE" ] && [ -x "$EP_SELF" ] && [ -d "$EP_GIT_CORE" ]
}

_entry_assert_copy_is_constants_only() {
  python3 - "$REPO/bin/k3dm-verified-stage" "$EP_SELF" "$EP_BASE" "file://$EP_REMOTE" "$EP_GIT" "$EP_GIT_CORE" "$EP_SELF" "$EP_TRUST" "$(id -u)" "$(id -g)" "$EP_SUDO" <<'PY'
import difflib, pathlib, sys
real, copy = map(pathlib.Path, sys.argv[1:3])
base, url, git, git_core, self_path, trust, owner, group, sudo = sys.argv[3:]
source = real.read_text().splitlines(keepends=True)
original_constants = {line.partition("=")[0]: line for line in source if line.startswith("_VS_") and "=" in line}
expected = {
    "_VS_BASE": base, "_VS_URL": url, "_VS_GIT": git,
    "_VS_GIT_CORE": git_core, "_VS_SELF": self_path,
    "_VS_TRUST_TOP": trust, "_VS_OWNER": owner,
    "_VS_GROUP": group, "_VS_SUDO": sudo,
}
normalized = []
for line in copy.read_text().splitlines(keepends=True):
    key = line.partition("=")[0]
    if key in original_constants and line.startswith(key + "="):
        if key in expected and line != f"{key}={expected[key]}\n":
            raise SystemExit(f"patched constant has unexpected content: {line!r}")
        line = original_constants[key]
    elif line.startswith("_vs_euid() {"):
        wanted = f"_vs_euid() {{ printf '%s\\n' \"${{FAKE_EUID:-{__import__('os').getuid()}}}\"; }}\n"
        if line != wanted:
            raise SystemExit(f"patched EUID seam has unexpected content: {line!r}")
        line = next(item for item in source if item.startswith("_vs_euid() {"))
    normalized.append(line)
if "".join(normalized) != "".join(source):
    sys.stderr.writelines(difflib.unified_diff(source, normalized, fromfile=str(real), tofile="normalized entry copy"))
    raise SystemExit(1)
PY
}

@test "[G7] bootstrap retains its privileged startup settings" {
  [ "$(head -n 1 "$REPO/bin/k3dm-verified-stage")" = '#!/bin/bash -p' ]
  grep -Fxq 'set -euo pipefail' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq 'export LC_ALL=C' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq 'umask 022' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_BASE=/private/var/db/k3dm-verified' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_URL=https://github.com/wilddog64/k3d-manager.git' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_GIT=/Library/Developer/CommandLineTools/usr/bin/git' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_GIT_CORE=/Library/Developer/CommandLineTools/usr/libexec/git-core' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_SELF=/usr/local/libexec/k3dm/k3dm-verified-stage' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_TRUST_TOP=/' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_OWNER=0' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_GROUP=wheel' "$REPO/bin/k3dm-verified-stage"
  grep -Fxq '_VS_SUDO=/usr/bin/sudo' "$REPO/bin/k3dm-verified-stage"
}

@test "[D4] unused argv and validation helpers are absent" {
  run declare -f _vs_git_argv
  [ "$status" -eq 1 ]
  run declare -f _vs_child_argv
  [ "$status" -eq 1 ]
  run declare -f _vs_validate_stage_args
  [ "$status" -eq 1 ]
}

_make_probe_stage() {
  local stage="$BASE/stage/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  mkdir -p "$stage/bin"
  local tool
  for tool in k3dm-web-console-sshd k3dm-web-console-totp k3dm-promote-authority; do
  cat > "$stage/bin/$tool" <<'EOF'
#!/bin/bash
{
  printf 'cwd=%s\n' "$PWD"
  printf 'home=%s\n' "$HOME"
  set -o | grep '^privileged'
  set -o | grep '^xtrace'
} > "$1.meta"
git --version >/dev/null 2>&1 || true
env > "$1.env"
trap -p TSTP > "$1.tstp"
if [ "${2:-}" = hold ]; then : > "$1.ready"; while :; do sleep 1; done; fi
exit "${2:-0}"
EOF
  chmod 755 "$stage/bin/$tool"
  done
  git -C "$stage" init -q -b main
  git -C "$stage" add bin
  git -C "$stage" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm probe
  STAGE_COMMIT="$(git -C "$stage" rev-parse HEAD)"
  mv "$stage" "$BASE/stage/$STAGE_COMMIT"
  STAGE_PATH="$BASE/stage/$STAGE_COMMIT"
  printf '%s\n' "$STAGE_COMMIT" > "$STAGE_PATH/.git/k3dm-verified"
}

_run_probe_refused() {
  local out="$SCRATCH/should-not-exist"
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$out"
  [ "$status" -eq 7 ]
  [ ! -e "$out" ]
  [ ! -e "$out.meta" ]
  [ ! -e "$out.env" ]
  [ ! -e "$out.tstp" ]
}

@test "[M2] validates root, commit and ref before fetching" {
  _vs_euid() { printf '501'; }
  _vs_fetch_verify() { : > "$SCRATCH/fetch-called"; return 0; }
  run main 0123456789012345678901234567890123456789
  [ "$status" -eq 3 ]
  _vs_euid() { printf '0'; }
  run main short
  [ "$status" -eq 2 ]
  run main 0123456789012345678901234567890123456789 --ref '../bad'
  [ "$status" -eq 2 ]
  [ ! -e "$SCRATCH/fetch-called" ]
  [ ! -e "$BASE/repo.git" ]
}

@test "[M2] refuses uppercase hashes and install-self ref before git; ref banner is precise" {
  _vs_euid() { printf '0'; }
  _vs_fetch_verify() { : > "$SCRATCH/fetch-called"; return 0; }
  run main 012345678901234567890123456789012345678A
  [ "$status" -eq 2 ]
  [ ! -e "$SCRATCH/fetch-called" ]
  run main --install-self 0123456789012345678901234567890123456789 --ref main
  [ "$status" -eq 2 ]
  _vs_euid() { printf '501'; }
  run main --install-self 0123456789012345678901234567890123456789
  [ "$status" -eq 3 ]
  run main --install-self 0123456789012345678901234567890123456789
  [ "$status" -eq 3 ]
  [ ! -e "$BASE/repo.git" ]
  run main 0123456789012345678901234567890123456789
  [ "$status" -eq 3 ]
  [[ "$output" != *'UNPROTECTED REF'* ]]
}

@test "[F1] stage parent is checked for trusted owner and write modes" {
  _make_probe_stage
  run _vs_stage_ok "$STAGE_PATH" "$STAGE_COMMIT"
  [ "$status" -eq 0 ]
  chmod 0777 "$BASE/stage"
  run _vs_stage_ok "$STAGE_PATH" "$STAGE_COMMIT"
  [ "$status" -eq 1 ]
  chmod 0755 "$BASE/stage"
  run _vs_stage_ok "$STAGE_PATH" "$STAGE_COMMIT"
  [ "$status" -eq 0 ]
}

@test "[M1] [N1] [N2] fetches an ancestor into an always-recreated marked stage" {
  local work="$SCRATCH/work" remote="$SCRATCH/remote.git" commit target path real_git
  mkdir "$work"
  mkdir -p "$work/bin" "$work/scripts/lib/foundation/scripts/lib" "$work/scripts/libexec" "$work/scripts/etc/launchd-daemons" "$work/scripts/etc/promote"
  git -C "$work" init -q -b main
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
  printf 'verified fixture\n' > "$work/payload"
  for path in bin/k3dm-web-console-sshd bin/k3dm-web-console-totp bin/k3dm-promote-authority scripts/lib/system.sh scripts/lib/foundation/scripts/lib/system.sh scripts/lib/web_console_common.sh scripts/lib/agent_rigor.sh scripts/libexec/k3dm-promote-daemon.py scripts/lib/hub_approval.py scripts/lib/promote_mover.py scripts/etc/launchd-daemons/com.k3d-manager.promote-authority.plist.tmpl scripts/etc/promote/promote.conf.tmpl; do
    mkdir -p "$work/${path%/*}"
    printf 'fixture %s\n' "$path" > "$work/$path"
  done
  git -C "$work" add payload bin scripts
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm payload
  commit="$(git -C "$work" rev-parse HEAD)"
  git -C "$work" branch deploy/hub
  git clone -q --bare "$work" "$remote"
  _VS_URL="file://$remote"
  target="$BASE/stage/$commit"
  mkdir -p "$target"
  printf 'attacker extra\n' > "$target/extra"
  mkdir -p "$BASE/stage/.tmp.interrupted"
  printf 'stale temp\n' > "$BASE/stage/.tmp.interrupted/extra"
  real_git="$(command -v git)"
  cat > "$SCRATCH/git-wrap" <<EOF
#!/bin/bash
"$real_git" "\$@"
rc=\$?
case " \$* " in
  *' clone '*)
    dest=
    for arg in "\$@"; do dest=\$arg; done
    /usr/bin/chgrp -R "$(id -g)" "\$dest"
    /bin/chmod -R g+w "\$dest"
    /bin/chmod +a "everyone allow read" "\$dest/.git"
    ;;
esac
exit "\$rc"
EOF
  chmod 755 "$SCRATCH/git-wrap"
  _VS_GIT="$SCRATCH/git-wrap"
  _VS_GROUP="$(id -G | awk -v primary="$(id -g)" '{ for (i = 1; i <= NF; i++) if ($i != primary) { print $i; exit } }')"
  [ -n "$_VS_GROUP" ]
  git init -q --bare "$BASE/repo.git"
  printf 'operator data\n' > "$BASE/repo.git/operator-data"
  chmod g+w "$BASE/repo.git"
  run _vs_stage "$commit" main
  [ "$status" -eq 0 ]
  [ "$(cat "$target/.git/k3dm-verified")" = "$commit" ]
  [ "$(cat "$target/payload")" = 'verified fixture' ]
  [ ! -e "$target/extra" ]
  [ ! -e "$BASE/stage/.tmp.interrupted" ]
  [ ! -e "$BASE/repo.git/operator-data" ]
  [ -z "$(command git -C "$BASE/repo.git" config --get-regexp '^remote\.origin\.' 2>/dev/null || true)" ]
  git -C "$target" diff --quiet "$commit" --
  [[ "$output" = *"commit: $commit"* ]]
  [[ "$output" = *"origin/main: $commit (commit tip)"* ]]
  [[ "$output" = *"origin/deploy/hub: $commit (commit tip)"* ]]
  for path in bin/k3dm-web-console-sshd bin/k3dm-web-console-totp bin/k3dm-promote-authority scripts/lib/system.sh scripts/lib/foundation/scripts/lib/system.sh scripts/lib/web_console_common.sh scripts/lib/agent_rigor.sh scripts/libexec/k3dm-promote-daemon.py scripts/lib/hub_approval.py scripts/lib/promote_mover.py scripts/etc/launchd-daemons/com.k3d-manager.promote-authority.plist.tmpl scripts/etc/promote/promote.conf.tmpl; do
    [[ "$output" = *"$path"* ]] || { printf 'missing tree path: %s\n%s\n' "$path" "$output"; return 1; }
    grep -Eq "^[0-7]{6}[[:space:]]+blob[[:space:]]+[0-9a-f]{40}[[:space:]]+$path$" <<< "$output"
  done
  [[ "$output" = *"/usr/local/libexec/k3dm/k3dm-verified-stage run $commit k3dm-web-console-sshd <verb> [args...]"* ]]
  [[ "$output" = *"/usr/local/libexec/k3dm/k3dm-verified-stage run $commit k3dm-web-console-totp <verb> [args...]"* ]]
  [[ "$output" = *"/usr/local/libexec/k3dm/k3dm-verified-stage run $commit k3dm-promote-authority <verb> [args...]"* ]]
  [ -z "$(find "$target" -perm +022 -print)" ]
  [ -z "$(find "$target" ! -user "$_VS_OWNER" -print)" ]
  [ -z "$(find "$target" -exec stat -f '%g' {} \; | awk -v group="$_VS_GROUP" '$0 != group { print; exit }')" ]
  run /bin/ls -lReA "$target"
  [ "$(printf '%s\n' "$output" | grep -cE '^ [0-9]+: ')" -eq 0 ]
}

@test "[N1] side-only commit fails on main and works with an explicit side ref" {
  local work="$SCRATCH/work" remote="$SCRATCH/remote.git" main_commit side_commit
  mkdir "$work"
  git -C "$work" init -q -b main
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -qm main
  main_commit="$(git -C "$work" rev-parse HEAD)"
  git -C "$work" checkout -qb side
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -qm side
  side_commit="$(git -C "$work" rev-parse HEAD)"
  git -C "$work" checkout -q main
  git -C "$work" branch deploy/hub "$side_commit"
  git clone -q --bare "$work" "$remote"
  _VS_URL="file://$remote"
  run _vs_stage "$side_commit" main
  [ "$status" -eq 5 ]
  [ ! -e "$BASE/stage/$side_commit" ]
  run _vs_stage "$side_commit" side
  [ "$status" -eq 0 ]
  [ -f "$BASE/stage/$side_commit/.git/k3dm-verified" ]
  [[ "$output" = *"origin/side: $side_commit (commit tip)"* ]]
  [ "$main_commit" != "$side_commit" ]
}

@test "[N2] a corrupted remote object fails fetch and leaves no stage" {
  local work="$SCRATCH/work" remote="$SCRATCH/remote.git" commit blob object
  mkdir "$work"
  git -C "$work" init -q -b main
  printf 'good\n' > "$work/payload"
  git -C "$work" add payload
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm payload
  commit="$(git -C "$work" rev-parse HEAD)"
  git -C "$work" branch deploy/hub
  git clone -q --bare "$work" "$remote"
  blob="$(git -C "$work" hash-object payload)"
  object="$remote/objects/${blob:0:2}/${blob:2}"
  mkdir -p "${object%/*}"
  chmod u+w "$remote/objects" "${object%/*}"
  [ ! -e "$object" ] || chmod u+w "$object"
  python3 - "$object" <<'PY'
import sys, zlib
with open(sys.argv[1], "wb") as stream:
    stream.write(zlib.compress(bytes.fromhex("626c6f622035006576696c0a")))
PY
  _VS_URL="file://$remote"
  mkdir -p "$BASE/stage/$commit"
  printf 'stale\n' > "$BASE/stage/$commit/extra"
  run _vs_stage "$commit" main
  [ "$status" -ne 0 ]
  [ ! -e "$BASE/stage/$commit" ]
}

@test "[M6] install-self atomically replaces self with the staged copy" {
  local work="$SCRATCH/work" remote="$SCRATCH/remote.git" commit old new mode
  mkdir -p "$work/bin"
  git -C "$work" init -q -b main
  cp "$REPO/bin/k3dm-verified-stage" "$work/bin/k3dm-verified-stage"
  git -C "$work" add bin/k3dm-verified-stage
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm bootstrap
  commit="$(git -C "$work" rev-parse HEAD)"
  git -C "$work" branch deploy/hub
  git clone -q --bare "$work" "$remote"
  _VS_URL="file://$remote"
  printf '#!/bin/bash\nexit 99\n' > "$SELF"
  chmod 755 "$SELF"
  old="$(_vs_git hash-object --no-filters "$SELF")"
  _vs_euid() { printf '0'; }
  run main --install-self "$commit"
  [ "$status" -eq 0 ]
  new="$(_vs_git hash-object --no-filters "$SELF")"
  [ "$old" != "$new" ]
  [[ "$output" = *"old blob: $old"* && "$output" = *"new blob: $new"* ]]
  mode="$(stat -f '%Lp' "$SELF")"
  [ "$mode" = 755 ]
  cmp "$SELF" "$BASE/stage/$commit/bin/k3dm-verified-stage"
  [ -z "$(find "$SCRATCH/self" -name 'k3dm-verified-stage.tmp.*' -print)" ]
}

@test "[D3] install-self refuses a staged bootstrap symlink without changing self" {
  local commit=0123456789012345678901234567890123456789 old staged="$BASE/stage/0123456789012345678901234567890123456789/bin/k3dm-verified-stage"
  mkdir -p "${staged%/*}"
  printf '#!/bin/bash\nexit 9\n' > "$BASE/stage/0123456789012345678901234567890123456789/bin/other-bootstrap"
  ln -s other-bootstrap "$staged"
  old="$(_vs_git hash-object --no-filters "$SELF")"
  _vs_euid() { printf '0'; }
  _vs_stage() { :; }
  _vs_stage_ok() { : > "$SCRATCH/stage-check-called"; return 0; }
  run main --install-self "$commit"
  [ "$status" -eq 6 ]
  [ -f "$SCRATCH/stage-check-called" ]
  [ "$(_vs_git hash-object --no-filters "$SELF")" = "$old" ]
  [ -z "$(find "$SCRATCH/self" -name 'k3dm-verified-stage.tmp.*' -print)" ]
}

@test "[M2] executed copy outside self path exits 3" {
  local installed="$SCRATCH/self/installed" executed="$SCRATCH/self/copy" gitstub="$SCRATCH/git" gitcore="$SCRATCH/git-core"
  mkdir -p "$gitcore"
  printf '#!/bin/sh\nexit 0\n' > "$gitstub"
  chmod 755 "$gitstub"
  sed -e "s|^_VS_SELF=.*|_VS_SELF=$installed|" \
      -e "s|^_VS_BASE=.*|_VS_BASE=$BASE|" \
      -e "s|^_VS_TRUST_TOP=.*|_VS_TRUST_TOP=$SCRATCH|" \
      -e "s|^_VS_OWNER=.*|_VS_OWNER=$(id -u)|" \
      -e "s|^_VS_GROUP=.*|_VS_GROUP=$(id -g)|" \
      -e "s|^_VS_GIT=.*|_VS_GIT=$gitstub|" \
      -e "s|^_VS_GIT_CORE=.*|_VS_GIT_CORE=$gitcore|" \
      -e "s|^_VS_SUDO=.*|_VS_SUDO=$_VS_SUDO|" "$REPO/bin/k3dm-verified-stage" > "$installed"
  cp "$installed" "$executed"
  chmod 755 "$installed" "$executed"
  run "$executed"
  [ "$status" -eq 3 ]
  [[ "$output" = *'run the installed bootstrap'* ]]
}

@test "[M2] main prints unprotected ref only for a non-main branch" {
  local work="$SCRATCH/work" remote="$SCRATCH/remote.git" commit
  mkdir "$work"
  git -C "$work" init -q -b main
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -qm first
  git -C "$work" checkout -qb side
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -qm second
  commit="$(git -C "$work" rev-parse HEAD)"
  git -C "$work" checkout -q main
  git -C "$work" branch deploy/hub
  git clone -q --bare "$work" "$remote"
  _VS_URL="file://$remote"
  _vs_euid() { printf '0'; }
  run main "$commit" --ref side
  [ "$status" -eq 0 ]
  [[ "$output" = *'UNPROTECTED REF side'* ]]
  run main "$commit"
  [ "$status" -eq 5 ]
  [[ "$output" != *'UNPROTECTED REF'* ]]
}

@test "[G3] stage and run usage arity refusals return 2" {
  _vs_euid() { printf '501'; }
  local commit=0123456789012345678901234567890123456789
  run main
  [ "$status" -eq 2 ]
  run main stage
  [ "$status" -eq 2 ]
  run main "$commit" extra
  [ "$status" -eq 2 ]
  run main "$commit" --ref
  [ "$status" -eq 2 ]
  run main "$commit" --bad ref
  [ "$status" -eq 2 ]
  run main "$commit" --ref bad..ref
  [ "$status" -eq 2 ]
  run main --install-self
  [ "$status" -eq 2 ]
  run main --install-self "$commit" --ref main
  [ "$status" -eq 2 ]
  run main run
  [ "$status" -eq 2 ]
  run main run "$commit"
  [ "$status" -eq 2 ]
  [ ! -s "$SUDO_LOG" ]
}

@test "[G3] fetch and stage failure exit codes are preserved" {
  run /bin/bash -c 'source "$1"; _vs_prepare_repo() { return 1; }; _vs_fetch_verify 0123456789012345678901234567890123456789 main' _ "$REPO/bin/k3dm-verified-stage"
  [ "$status" -eq 4 ]
  local work="$SCRATCH/failure-work" remote="$SCRATCH/failure-remote.git" commit real_git
  mkdir "$work"
  git -C "$work" init -q -b main
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
  commit="$(git -C "$work" rev-parse HEAD)"
  git -C "$work" branch deploy/hub
  git clone -q --bare "$work" "$remote"
  _VS_URL="file://$remote"
  real_git="$(command -v git)"
  cat > "$SCRATCH/git-fail-clone" <<EOF
#!/bin/bash
case " \$* " in *' clone '*) exit 1;; esac
exec "$real_git" "\$@"
EOF
  chmod 755 "$SCRATCH/git-fail-clone"
  _VS_GIT="$SCRATCH/git-fail-clone"
  run _vs_stage "$commit" main
  [ "$status" -eq 6 ]
  [ ! -e "$BASE/stage/$commit" ]
}

@test "[G3] executed script dispatches main and stage wrapper at the entry point" {
  local gitstub="$SCRATCH/git" gitcore="$SCRATCH/git-core"
  mkdir -p "$gitcore"
  printf '#!/bin/sh\nexit 0\n' > "$gitstub"
  chmod 755 "$gitstub"
  sed -e "s|^_VS_SELF=.*|_VS_SELF=$SELF|" \
      -e "s|^_VS_BASE=.*|_VS_BASE=$BASE|" \
      -e "s|^_VS_TRUST_TOP=.*|_VS_TRUST_TOP=$SCRATCH|" \
      -e "s|^_VS_OWNER=.*|_VS_OWNER=$(id -u)|" \
      -e "s|^_VS_GROUP=.*|_VS_GROUP=$(id -g)|" \
      -e "s|^_VS_GIT=.*|_VS_GIT=$gitstub|" \
      -e "s|^_VS_GIT_CORE=.*|_VS_GIT_CORE=$gitcore|" \
      -e "s|^_VS_SUDO=.*|_VS_SUDO=$_VS_SUDO|" "$REPO/bin/k3dm-verified-stage" > "$SELF"
  chmod 755 "$SELF"
  run "$SELF"
  [ "$status" -eq 2 ]
  run "$SELF" run
  [ "$status" -eq 2 ]
  : > "$SUDO_LOG"
  run "$SELF" stage short
  [ "$status" -eq 2 ]
  [ ! -s "$SUDO_LOG" ]
}

@test "[G3] wrapper refuses root and malformed grammar before sudo" {
  local commit=0123456789012345678901234567890123456789
  _vs_euid() { printf '0'; }
  run _vs_wrapper stage "$commit"
  [ "$status" -eq 3 ]
  _vs_euid() { printf '501'; }
  run _vs_wrapper
  [ "$status" -eq 2 ]
  run _vs_wrapper stage
  [ "$status" -eq 2 ]
  run _vs_wrapper stage short
  [ "$status" -eq 2 ]
  run _vs_wrapper stage "$commit" extra
  [ "$status" -eq 2 ]
  run _vs_wrapper stage "$commit" --bad ref
  [ "$status" -eq 2 ]
  run _vs_wrapper stage --install-self
  [ "$status" -eq 2 ]
  run _vs_wrapper stage --install-self "$commit" extra
  [ "$status" -eq 2 ]
  run _vs_wrapper stage --install-self "$commit" --ref main
  [ "$status" -eq 2 ]
  run _vs_wrapper stage "$commit" --ref bad..ref
  [ "$status" -eq 2 ]
  run _vs_wrapper other "$commit"
  [ "$status" -eq 2 ]
  [ ! -s "$SUDO_LOG" ]
}

@test "[E1] entry-point copy differs only in its patched constants and EUID seam" {
  _entry_setup
  _entry_assert_copy_is_constants_only
}

@test "[E3] entry-point wrapper stages, installs itself, and runs with exact output and environment" {
  _entry_setup
  _entry_assert_copy_is_constants_only
  run "$EP_SELF" stage "$EP_MAIN"
  [ "$status" -eq 0 ] || { printf 'entry stage rc=%s output=%s\n' "$status" "$output"; return 1; }
  [ -f "$EP_BASE/stage/$EP_MAIN/.git/k3dm-verified" ]
  [ "$(cat "$EP_BASE/stage/$EP_MAIN/.git/k3dm-verified")" = "$EP_MAIN" ]
  printf '%s\n' '-k' "$EP_SELF $EP_MAIN" '-k' > "$SCRATCH/expected-sudo"
  cmp "$SCRATCH/expected-sudo" "$EP_SUDO_LOG"

  : > "$EP_SUDO_LOG"
  run "$EP_SELF" stage "$EP_SIDE" --ref side
  [ "$status" -eq 0 ]
  [[ "$output" = *'UNPROTECTED REF side'* ]] || { printf 'side stage output=%s\n' "$output"; return 1; }
  [ -f "$EP_BASE/stage/$EP_SIDE/.git/k3dm-verified" ]
  printf '%s\n' '-k' "$EP_SELF $EP_SIDE --ref side" '-k' > "$SCRATCH/expected-sudo"
  cmp "$SCRATCH/expected-sudo" "$EP_SUDO_LOG"

  : > "$EP_SUDO_LOG"
  local old_blob staged_blob
  old_blob="$(command git hash-object "$EP_SELF")"
  staged_blob="$(command git hash-object "$EP_WORK/bin/k3dm-verified-stage")"
  [ "$old_blob" != "$staged_blob" ]
  run "$EP_SELF" stage --install-self "$EP_MAIN"
  [ "$status" -eq 0 ]
  grep -Fxq "old blob: $old_blob" <<< "$output"
  grep -Fxq "new blob: $staged_blob" <<< "$output"
  printf '%s\n' '-k' "$EP_SELF --install-self $EP_MAIN" '-k' > "$SCRATCH/expected-sudo"
  cmp "$SCRATCH/expected-sudo" "$EP_SUDO_LOG"
  cmp "$EP_SELF" "$EP_BASE/stage/$EP_MAIN/bin/k3dm-verified-stage"

  unset TMUX TMUX_PANE STY SSH_CONNECTION SSH_TTY WEB_CONSOLE_SSH_PORT
  export TMUX=$'odd\001bytes\377'
  export TERM=xterm
  : > "$EP_SUDO_LOG"
  run "$EP_SELF" run "$EP_MAIN" k3dm-web-console-sshd
  [ "$status" -eq 0 ]
  [ "$output" = 'E2E-OUTPUT' ]
  grep -Fxq 'TMUX=1' "$EP/child-env"
  printf '%s\n' '-k' '-k' > "$SCRATCH/expected-sudo"
  cmp "$SCRATCH/expected-sudo" "$EP_SUDO_LOG"
  sed -n 's/=.*//p' "$EP/child-env" | sort -u > "$EP/actual-names"
  cat > "$EP/required-names" <<'EOF'
GIT_CONFIG_COUNT
GIT_CONFIG_GLOBAL
GIT_CONFIG_KEY_0
GIT_CONFIG_NOSYSTEM
GIT_CONFIG_VALUE_0
HOME
LC_ALL
PATH
TERM
TMUX
EOF
  cat "$EP/required-names" > "$EP/allowed-names"
  printf '%s\n' PWD SHLVL _ OLDPWD >> "$EP/allowed-names"
  sort -u "$EP/allowed-names" > "$EP/allowed-names.sorted"
  comm -23 "$EP/actual-names" "$EP/allowed-names.sorted" > "$EP/unexpected-names"
  [ ! -s "$EP/unexpected-names" ]
  sort -u "$EP/required-names" > "$EP/required-names.sorted"
  comm -13 "$EP/actual-names" "$EP/required-names.sorted" > "$EP/missing-names"
  [ ! -s "$EP/missing-names" ]
  grep -Fxq 'PATH=/usr/bin:/bin:/usr/sbin:/sbin' "$EP/child-env"
  grep -Fxq 'LC_ALL=C' "$EP/child-env"
  grep -Fxq 'TERM=xterm' "$EP/child-env"
  grep -Fxq 'GIT_CONFIG_COUNT=1' "$EP/child-env"
  grep -Fxq 'GIT_CONFIG_KEY_0=safe.directory' "$EP/child-env"
  grep -Fxq "GIT_CONFIG_VALUE_0=$EP_BASE/stage/$EP_MAIN" "$EP/child-env"
  grep -Fxq "HOME=$(id -P "$(id -u)" | awk -F: '{print $9}')" "$EP/child-env"
  run grep -qE '^(GIT_DIR|GIT_CONFIG_PARAMETERS|BASH_ENV|POSIXLY_CORRECT|EXTRA_EVIL)=' "$EP/child-env"
  [ "$status" -eq 1 ]
  : > "$EP_SUDO_LOG"
  run "$EP_SELF" run "$EP_MAIN" k3dm-web-console-sshd 3
  [ "$status" -eq 3 ] || { printf 'failing child rc=%s stdout=%s\n' "$status" "$output"; return 1; }
  [ "$output" = 'E2E-OUTPUT' ]
  printf '%s\n' '-k' '-k' > "$SCRATCH/expected-sudo"
  cmp "$SCRATCH/expected-sudo" "$EP_SUDO_LOG"
}

@test "[E4] entry-point exit codes cover validation and operational failures" {
  _entry_setup
  unset FAKE_EUID
  run "$EP_SELF"
  [ "$status" -eq 2 ]
  run "$EP_SELF" stage
  [ "$status" -eq 2 ]
  run "$EP_SELF" stage "$EP_MAIN" extra
  [ "$status" -eq 2 ]
  run "$EP_SELF" stage "$EP_MAIN" --ref
  [ "$status" -eq 2 ]
  run "$EP_SELF" stage "$EP_MAIN" --bogus side
  [ "$status" -eq 2 ]
  run "$EP_SELF" stage short
  [ "$status" -eq 2 ]
  run "$EP_SELF" stage 012345678901234567890123456789012345678A
  [ "$status" -eq 2 ]
  run env FAKE_EUID=0 "$EP_SELF" short
  [ "$status" -eq 2 ]
  run env FAKE_EUID=0 "$EP_SELF" 012345678901234567890123456789012345678A
  [ "$status" -eq 2 ]
  run "$EP_SELF" stage "$EP_MAIN" --ref bad..ref
  [ "$status" -eq 2 ]
  run env FAKE_EUID=0 "$EP_SELF" "$EP_MAIN" --ref bad..ref
  [ "$status" -eq 2 ]
  run "$EP_SELF" stage --install-self "$EP_MAIN" --ref main
  [ "$status" -eq 2 ]
  run "$EP_SELF" --install-self "$EP_MAIN" --ref main
  [ "$status" -eq 2 ]
  run env FAKE_EUID=0 "$EP_SELF" --install-self short
  [ "$status" -eq 2 ]
  run "$EP_SELF" run
  [ "$status" -eq 2 ]
  run "$EP_SELF" run "$EP_MAIN"
  [ "$status" -eq 2 ]
  run "$EP_SELF" run "$EP_MAIN" unknown-tool
  [ "$status" -eq 2 ]
  [ ! -s "$EP_SUDO_LOG" ]
  run env FAKE_EUID=0 "$EP_SELF" "$EP_MAIN" --bogus side
  [ "$status" -eq 2 ]
  run env FAKE_EUID=0 "$EP_SELF" "$EP_MAIN" extra
  [ "$status" -eq 2 ]
  [ ! -s "$EP_SUDO_LOG" ]

  run env FAKE_EUID=0 "$EP_SELF" stage "$EP_MAIN"
  [ "$status" -eq 3 ]
  [ ! -s "$EP_SUDO_LOG" ]
  run "$EP_SELF" "$EP_MAIN"
  [ "$status" -eq 3 ]
  [ ! -s "$EP_SUDO_LOG" ]
  run "$EP_SELF" run "$EP_MAIN" k3dm-web-console-sshd
  [ "$status" -eq 7 ]
  [ ! -s "$EP_SUDO_LOG" ]

  : > "$EP_SUDO_LOG"
  touch "$EP_FAIL_CLONE"
  run env FAKE_EUID=0 "$EP_SELF" "$EP_MAIN"
  [ "$status" -eq 6 ]
  rm -f "$EP_FAIL_CLONE"

  run env FAKE_EUID=0 "$EP_SELF" "$EP_SIDE" --ref main
  [ "$status" -eq 5 ]
  grep -Fq "origin/deploy/hub: $EP_MAIN" <<< "$output"
  [ "$(grep -Fc "origin/main: $EP_MAIN" <<< "$output")" -eq 2 ]
  [ ! -e "$EP_BASE/stage/$EP_SIDE" ]
}

@test "[E4] entry-point fetch failure returns 4" {
  local missing_url
  missing_url="file://$SCRATCH/no-such-remote.git"
  _entry_setup "$missing_url"
  run env FAKE_EUID=0 "$EP_SELF" "$EP_MAIN"
  [ "$status" -eq 4 ]
}

@test "[F2] fetch uses only the constant URL despite planted remote config" {
  _entry_setup
  local evil="$EP/evil.git" evil_work="$EP/evil-work" evil_url="file://$EP/evil.git"
  mkdir -p "$evil_work"
  git -C "$evil_work" init -q -b main
  printf 'evil\n' > "$evil_work/evil.txt"
  git -C "$evil_work" add evil.txt
  git -C "$evil_work" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm evil
  git clone -q --bare "$evil_work" "$evil"
  git init -q --bare "$EP_BASE/repo.git"
  git -C "$EP_BASE/repo.git" config remote.origin.url "$evil_url"
  git -C "$EP_BASE/repo.git" config "url.$evil_url.insteadOf" "file://$EP_REMOTE"
  : > "$EP_GIT_LOG"
  run env FAKE_EUID=0 "$EP_SELF" "$EP_MAIN"
  [ "$status" -eq 0 ]
  grep -Fq "fetch --force file://$EP_REMOTE" "$EP_GIT_LOG"
  [ -f "$EP_BASE/stage/$EP_MAIN/bin/k3dm-web-console-sshd" ]
  [ ! -e "$EP_BASE/stage/$EP_MAIN/evil.txt" ]
  [ ! -e "$EP_BASE/stage/$EP_MAIN/evil.txt" ]
}

@test "[F4] root staging ignores cwd fsmonitor config and confines every git call" {
  _entry_setup
  local cwd_repo="$EP/cwd-repo" marker="$EP/fsmonitor-marker" line
  mkdir -p "$cwd_repo"
  printf '#!/bin/sh\ntouch %s\n' "$marker" > "$EP/fsmonitor"
  chmod 755 "$EP/fsmonitor"
  git -C "$cwd_repo" init -q
  git -C "$cwd_repo" config core.fsmonitor "$EP/fsmonitor"
  : > "$EP_GIT_LOG"
  (cd "$cwd_repo" && env FAKE_EUID=0 "$EP_SELF" "$EP_MAIN")
  [ ! -e "$marker" ]
  [ -s "$EP_GIT_LOG" ]
  while IFS= read -r line; do
    [[ " $line " = *' -C '* ]]
    [[ "$line" = PWD=/\ * ]]
  done < "$EP_GIT_LOG"
}

@test "[F8] entry-point passwd lookup failure exits 2 explicitly" {
  _entry_setup
  run env FAKE_EUID=0 "$EP_SELF" "$EP_MAIN"
  [ "$status" -eq 0 ]
  run env FAKE_EUID=987654321 "$EP_SELF" run "$EP_MAIN" k3dm-web-console-sshd
  [ "$status" -eq 2 ]
  [[ "$output" = *'cannot read passwd entry'* ]]
}

@test "[N3] plain git drops caller config and safe git adds only safe.directory" {
  _VS_GIT="$SCRATCH/git"
  cat > "$_VS_GIT" <<EOF
#!/bin/sh
call=\$(wc -l < "$SCRATCH/git-calls" 2>/dev/null || printf 0)
call=\$((call + 1))
printf '%s\n' "\$call" >> "$SCRATCH/git-calls"
env > "$SCRATCH/git-env.\$call"
printf '%s\n' "\$@" > "$SCRATCH/git-argv.\$call"
EOF
  chmod 755 "$_VS_GIT"
  : > "$SCRATCH/git-calls"
  mkdir "$SCRATCH/safe-repo"
  export GIT_DIR=attacker GIT_CONFIG_PARAMETERS=evil BASH_ENV=evil EXTRA_EVIL=1
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=/nonexistent/evil
  _vs_git --version
  _vs_git_safe "$SCRATCH/safe-repo" status
  run grep -qE '^(GIT_DIR|GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_0|GIT_CONFIG_VALUE_0|BASH_ENV|EXTRA_EVIL)=' "$SCRATCH/git-env.1"
  [ "$status" -eq 1 ]
  grep -Fxq transfer.fsckObjects=true "$SCRATCH/git-argv.1"
  grep -Fxq fetch.fsckObjects=true "$SCRATCH/git-argv.1"
  grep -Fxq -- -c "$SCRATCH/git-argv.1"
  grep -Fxq 'PATH=/usr/bin:/bin' "$SCRATCH/git-env.1"
  grep -Fxq 'HOME=/var/empty' "$SCRATCH/git-env.1"
  grep -Fxq 'GIT_CONFIG_NOSYSTEM=1' "$SCRATCH/git-env.1"
  grep -Fxq 'GIT_CONFIG_GLOBAL=/dev/null' "$SCRATCH/git-env.1"
  grep -Fxq 'GIT_TERMINAL_PROMPT=0' "$SCRATCH/git-env.1"
  grep -Fxq 'GIT_OPTIONAL_LOCKS=0' "$SCRATCH/git-env.1"
  sed -n 's/=.*//p' "$SCRATCH/git-env.1" | sort -u > "$SCRATCH/git-names.1"
  printf '%s\n' PATH HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_TERMINAL_PROMPT GIT_OPTIONAL_LOCKS PWD SHLVL _ OLDPWD | sort -u > "$SCRATCH/git-allowed-names.1"
  comm -23 "$SCRATCH/git-names.1" "$SCRATCH/git-allowed-names.1" > "$SCRATCH/git-unexpected.1"
  [ ! -s "$SCRATCH/git-unexpected.1" ]
  grep -Fxq 'GIT_CONFIG_COUNT=1' "$SCRATCH/git-env.2"
  grep -Fxq 'GIT_CONFIG_KEY_0=safe.directory' "$SCRATCH/git-env.2"
  grep -Fxq "GIT_CONFIG_VALUE_0=$SCRATCH/safe-repo" "$SCRATCH/git-env.2"
  run grep -Fxq GIT_CONFIG_PARAMETERS=evil "$SCRATCH/git-env.2"
  [ "$status" -eq 1 ]
  run grep -Fxq GIT_CONFIG_VALUE_0=/nonexistent/evil "$SCRATCH/git-env.2"
  [ "$status" -eq 1 ]
  grep -Fxq 'GIT_OPTIONAL_LOCKS=0' "$SCRATCH/git-env.2"
}

@test "[M3] run refuses a missing stage before sudo" {
  _vs_euid() { printf '501'; }
  run _vs_run 0123456789012345678901234567890123456789 k3dm-web-console-sshd check
  [ "$status" -eq 7 ]
  [ ! -s "$SUDO_LOG" ]
}

@test "[N4] group-writable stage entry stops before the probe" {
  _make_probe_stage
  chmod g+w "$STAGE_PATH/bin/k3dm-web-console-sshd"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[G2] other-writable stage entry stops before the probe" {
  _make_probe_stage
  chmod o+w "$STAGE_PATH/bin/k3dm-web-console-sshd"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[N4] ACL stage entry stops before the probe" {
  _make_probe_stage
  chmod +a "everyone allow write" "$STAGE_PATH/bin/k3dm-web-console-sshd"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[N4] different owner constant rejects stage entries" {
  _make_probe_stage
  _VS_OWNER=0
  _vs_walk_trusted() { return 0; }
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[N4] operator-owned ancestor above base fails trusted walk" {
  _make_probe_stage
  _vs_root_owned() { [ "$1" != "$SCRATCH" ]; }
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[N4] wrong marker rejects stage" {
  _make_probe_stage
  printf '%040d\n' 0 > "$STAGE_PATH/.git/k3dm-verified"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[N4] symlink to outside the stage is rejected" {
  _make_probe_stage
  ln -s "$SCRATCH/outside" "$STAGE_PATH/escape"
  git -C "$STAGE_PATH" add escape
  git -C "$STAGE_PATH" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm symlink
  local next_commit
  next_commit="$(command git -C "$STAGE_PATH" rev-parse HEAD)"
  mv "$STAGE_PATH" "$BASE/stage/$next_commit"
  STAGE_PATH="$BASE/stage/$next_commit" STAGE_COMMIT="$next_commit"
  printf '%s\n' "$STAGE_COMMIT" > "$STAGE_PATH/.git/k3dm-verified"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[E5] a .git symlink is refused before the probe" {
  _make_probe_stage
  mv "$STAGE_PATH/.git" "$STAGE_PATH/git-real"
  ln -s git-real "$STAGE_PATH/.git"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[D1] any in-stage symlink is rejected and a clean stage is accepted" {
  _make_probe_stage
  ln -s bin/k3dm-web-console-sshd "$STAGE_PATH/bin/internal-link"
  git -C "$STAGE_PATH" add bin/internal-link
  git -C "$STAGE_PATH" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm internal-link
  local next_commit
  next_commit="$(command git -C "$STAGE_PATH" rev-parse HEAD)"
  mv "$STAGE_PATH" "$BASE/stage/$next_commit"
  STAGE_PATH="$BASE/stage/$next_commit" STAGE_COMMIT="$next_commit"
  printf '%s\n' "$STAGE_COMMIT" > "$STAGE_PATH/.git/k3dm-verified"
  _vs_euid() { printf '501'; }
  _run_probe_refused
  _make_probe_stage
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/clean-stage.out"
  [ "$status" -eq 0 ]
  [ -f "$SCRATCH/clean-stage.out.meta" ]
}

@test "[D1] two-link lexical escape pair is rejected" {
  _make_probe_stage
  mkdir -p "$STAGE_PATH/bin/a/b"
  ln -s ../.. "$STAGE_PATH/bin/a/b/s"
  ln -s a/b/s/../../.. "$STAGE_PATH/bin/x"
  git -C "$STAGE_PATH" add bin/a/b/s bin/x
  git -C "$STAGE_PATH" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm escape-pair
  local next_commit
  next_commit="$(command git -C "$STAGE_PATH" rev-parse HEAD)"
  mv "$STAGE_PATH" "$BASE/stage/$next_commit"
  STAGE_PATH="$BASE/stage/$next_commit" STAGE_COMMIT="$next_commit"
  printf '%s\n' "$STAGE_COMMIT" > "$STAGE_PATH/.git/k3dm-verified"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[D2] mode-000 directory makes stage verification fail closed" {
  _make_probe_stage
  mkdir "$STAGE_PATH/locked"
  printf 'secret\n' > "$STAGE_PATH/locked/file"
  git -C "$STAGE_PATH" add locked/file
  git -C "$STAGE_PATH" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm locked-directory
  local next_commit
  next_commit="$(command git -C "$STAGE_PATH" rev-parse HEAD)"
  mv "$STAGE_PATH" "$BASE/stage/$next_commit"
  STAGE_PATH="$BASE/stage/$next_commit" STAGE_COMMIT="$next_commit"
  printf '%s\n' "$STAGE_COMMIT" > "$STAGE_PATH/.git/k3dm-verified"
  chmod 000 "$STAGE_PATH/locked"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[D2] git status failure makes stage verification fail closed" {
  _make_probe_stage
  local real_git="$_VS_GIT"
  cat > "$SCRATCH/git-fail-status" <<EOF
#!/bin/bash
case " \$* " in *' status '*) exit 1;; esac
exec "$real_git" "\$@"
EOF
  chmod 755 "$SCRATCH/git-fail-status"
  _VS_GIT="$SCRATCH/git-fail-status"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[D2] failing find or recursive listing makes stage verification fail closed" {
  _make_probe_stage
  cat > "$SCRATCH/find-fail" <<'EOF'
#!/bin/sh
case " $* " in *' -print0 '*) exit 1;; esac
exec /usr/bin/find "$@"
EOF
  cat > "$SCRATCH/ls-fail" <<'EOF'
#!/bin/sh
case " $* " in *' -lReA '*) exit 1;; esac
exec /bin/ls "$@"
EOF
  chmod 755 "$SCRATCH/find-fail" "$SCRATCH/ls-fail"
  _vs_euid() { printf '501'; }
  _VS_FIND="$SCRATCH/find-fail"
  _run_probe_refused
  _VS_FIND=/usr/bin/find
  _VS_LS="$SCRATCH/ls-fail"
  _run_probe_refused
}

@test "[F3] an empty successful find result cannot certify a stage" {
  _make_probe_stage
  cat > "$SCRATCH/find-empty" <<'EOF'
#!/bin/sh
case " $* " in *' -print0 '*) exit 0;; esac
exec /usr/bin/find "$@"
EOF
  chmod 755 "$SCRATCH/find-empty"
  _VS_FIND="$SCRATCH/find-empty"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[N4] stage path resolving elsewhere is rejected" {
  _make_probe_stage
  mv "$STAGE_PATH" "$BASE/stage/alias"
  ln -s alias "$STAGE_PATH"
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[N4] HEAD different from stage name rejects stage" {
  _make_probe_stage
  git -C "$STAGE_PATH" -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -qm second
  _vs_euid() { printf '501'; }
  _run_probe_refused
}

@test "[N4] untracked and ignored stage files reject stage" {
  _make_probe_stage
  mkdir "$STAGE_PATH/untracked-dir"
  printf 'untracked\n' > "$STAGE_PATH/untracked-dir/file"
  _vs_euid() { printf '501'; }
  _run_probe_refused
  rm -rf "$STAGE_PATH/untracked-dir"
  printf 'ignored\n' > "$STAGE_PATH/.gitignore"
  git -C "$STAGE_PATH" add .gitignore
  git -C "$STAGE_PATH" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm ignore
  local next_commit
  next_commit="$(command git -C "$STAGE_PATH" rev-parse HEAD)"
  mv "$STAGE_PATH" "$BASE/stage/$next_commit"
  STAGE_PATH="$BASE/stage/$next_commit" STAGE_COMMIT="$next_commit"
  printf '%s\n' "$STAGE_COMMIT" > "$STAGE_PATH/.git/k3dm-verified"
  printf 'hidden\n' > "$STAGE_PATH/ignored"
  _run_probe_refused
}

@test "[N4] tool and every relative path argument are refused before sudo" {
  _make_probe_stage
  _vs_euid() { printf '501'; }
  run _vs_run "$STAGE_COMMIT" nope "$SCRATCH/probe"
  [ "$status" -eq 2 ] && [ ! -e "$SCRATCH/probe" ]
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/ca.out" --ca-file relative
  [ "$status" -eq 2 ]
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/cloudflared.out" --cloudflared-config relative
  [ "$status" -eq 2 ]
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/tmux.out" --tmux relative
  [ "$status" -eq 2 ]
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/probe-file.out" PROBE_FILE=relative
  [ "$status" -eq 2 ]
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/trailing-ca.out" --ca-file
  [ "$status" -eq 2 ]
  for output in "$SCRATCH/ca.out" "$SCRATCH/cloudflared.out" "$SCRATCH/tmux.out" "$SCRATCH/probe-file.out"; do
    [ ! -e "$output" ]
  done
  [ ! -s "$SUDO_LOG" ]
}

@test "[N4] invalid port and root run refuse before sudo" {
  _make_probe_stage
  _vs_euid() { printf '501'; }
  WEB_CONSOLE_SSH_PORT=abc run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/probe"
  [ "$status" -eq 2 ]
  WEB_CONSOLE_SSH_PORT=123456 run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/probe"
  [ "$status" -eq 2 ]
  unset WEB_CONSOLE_SSH_PORT
  _vs_euid() { printf '0'; }
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/probe"
  [ "$status" -eq 3 ]
  [ ! -s "$SUDO_LOG" ]
}

@test "[G2] every allowlisted tool runs and passwd-home failure is refused" {
  _make_probe_stage
  _vs_euid() { printf '501'; }
  for tool in k3dm-web-console-sshd k3dm-web-console-totp k3dm-promote-authority; do
    run _vs_run "$STAGE_COMMIT" "$tool" "$SCRATCH/$tool.out"
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/$tool.out.meta" ]
  done
  _vs_euid() { printf '987654321'; }
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd "$SCRATCH/no-passwd.out"
  [ "$status" -eq 2 ]
  [ ! -e "$SCRATCH/no-passwd.out.meta" ]
}

@test "[M3] [N4] [N5] run starts the verified tool in a scrubbed environment from root" {
  local commit
  _make_probe_stage
  commit="$STAGE_COMMIT"
  export HOME="$SCRATCH/caller-home" LANG=caller TMUX='caller bytes' TMUX_PANE='caller pane' STY='caller sty' SSH_CONNECTION='caller connection' SSH_TTY='caller tty' DEVELOPER_DIR=caller WEB_CONSOLE_SSH_PORT=2222 BASH_ENV="$SCRATCH/should-not-run"
  printf 'touch %s\n' "$SCRATCH/bash-env-marker" > "$BASH_ENV"
  export POSIXLY_CORRECT=1
  git() { printf 'function git ran\n' > "$SCRATCH/git-function-marker"; }
  export -f git
  export TERM=xterm
  _vs_euid() { printf '501'; }
  run _vs_run "$commit" k3dm-web-console-sshd "$SCRATCH/probe.out"
  [ "$status" -eq 0 ] || { printf 'run status=%s output=%s\n' "$status" "$output"; return 1; }
  grep -Fxq 'cwd=/' "$SCRATCH/probe.out.meta"
  grep -Fxq "home=$(id -P "$(id -u)" | awk -F: '{print $9}')" "$SCRATCH/probe.out.meta"
  grep -Eq '^privileged[[:space:]]+on$' "$SCRATCH/probe.out.meta"
  grep -Eq '^xtrace[[:space:]]+off$' "$SCRATCH/probe.out.meta"
  [ ! -s "$SCRATCH/probe.out.tstp" ]
  grep -Fxq 'TMUX=1' "$SCRATCH/probe.out.env"
  grep -Fxq 'WEB_CONSOLE_SSH_PORT=2222' "$SCRATCH/probe.out.env"
  grep -Fxq 'LC_ALL=C' "$SCRATCH/probe.out.env"
  for var in TMUX TMUX_PANE STY SSH_CONNECTION SSH_TTY; do
    if [ "${!var+x}" ]; then grep -Fxq "$var=1" "$SCRATCH/probe.out.env"
    else run grep -q "^$var=" "$SCRATCH/probe.out.env"; [ "$status" -eq 1 ]; fi
  done
  cat > "$SCRATCH/expected-env" <<EOF
HOME
GIT_CONFIG_COUNT
GIT_CONFIG_GLOBAL
GIT_CONFIG_KEY_0
GIT_CONFIG_NOSYSTEM
GIT_CONFIG_VALUE_0
LC_ALL
PATH
TERM
TMUX
TMUX_PANE
STY
SSH_CONNECTION
SSH_TTY
WEB_CONSOLE_SSH_PORT
EOF
  printf '%s\n' PWD SHLVL _ OLDPWD > "$SCRATCH/optional-env"
  for var in SSH_CONNECTION SSH_TTY TMUX_PANE STY WEB_CONSOLE_SSH_PORT; do
    [ "${!var+x}" ] && printf '%s\n' "$var" >> "$SCRATCH/optional-env"
  done
  sed -n 's/=.*//p' "$SCRATCH/probe.out.env" | sort -u > "$SCRATCH/actual-env"
  cat "$SCRATCH/expected-env" "$SCRATCH/optional-env" > "$SCRATCH/allowed-env"
  sort -u "$SCRATCH/allowed-env" > "$SCRATCH/allowed-env.sorted"
  sort -u "$SCRATCH/expected-env" > "$SCRATCH/required-env.sorted"
  comm -23 "$SCRATCH/actual-env" "$SCRATCH/allowed-env.sorted" > "$SCRATCH/unexpected-env"
  [ ! -s "$SCRATCH/unexpected-env" ]
  comm -13 "$SCRATCH/actual-env" "$SCRATCH/required-env.sorted" > "$SCRATCH/missing-env"
  [ ! -s "$SCRATCH/missing-env" ] || { printf 'missing env names: '; cat "$SCRATCH/missing-env"; return 1; }
  grep -Fxq 'PATH=/usr/bin:/bin:/usr/sbin:/sbin' "$SCRATCH/probe.out.env"
  grep -Fxq 'HOME='"$(id -P "$(id -u)" | awk -F: '{print $9}')" "$SCRATCH/probe.out.env"
  grep -Fxq 'GIT_CONFIG_NOSYSTEM=1' "$SCRATCH/probe.out.env"
  grep -Fxq 'GIT_CONFIG_GLOBAL=/dev/null' "$SCRATCH/probe.out.env"
  grep -Fxq 'GIT_CONFIG_COUNT=1' "$SCRATCH/probe.out.env"
  grep -Fxq 'GIT_CONFIG_KEY_0=safe.directory' "$SCRATCH/probe.out.env"
  grep -Fxq "GIT_CONFIG_VALUE_0=$BASE/stage/$commit" "$SCRATCH/probe.out.env"
  grep -Fxq 'TERM=xterm' "$SCRATCH/probe.out.env"
  grep -Fxq 'PWD=/' "$SCRATCH/probe.out.env"
  run grep -q '^LANG=' "$SCRATCH/probe.out.env"
  [ "$status" -eq 1 ]
  run grep -q '^TMUX=caller bytes$' "$SCRATCH/probe.out.env"
  [ "$status" -eq 1 ]
  [ ! -e "$SCRATCH/bash-env-marker" ]
  [ ! -e "$SCRATCH/git-function-marker" ]
  [[ "$output" != *'+'* && "$output" != *'syntax error'* ]]
  [ "$(wc -l < "$SUDO_LOG" | tr -d ' ')" -eq 2 ]
  [ "$(sed -n '1p' "$SUDO_LOG")" = 'sudo -k' ]
  [ "$(sed -n '2p' "$SUDO_LOG")" = 'sudo -k' ]
  : > "$SUDO_LOG"
  run _vs_run "$commit" k3dm-web-console-sshd "$SCRATCH/fail.out" 3
  [ "$status" -eq 3 ]
  [ "$(wc -l < "$SUDO_LOG" | tr -d ' ')" -eq 2 ]
  [ "$(sed -n '1p' "$SUDO_LOG")" = 'sudo -k' ]
  [ "$(sed -n '2p' "$SUDO_LOG")" = 'sudo -k' ]
  : > "$SUDO_LOG"
  export SUDO_FAIL_K=1
  run _vs_run "$commit" k3dm-web-console-sshd "$SCRATCH/fail-k.out" 3
  [ "$status" -eq 3 ]
  [ "$(wc -l < "$SUDO_LOG" | tr -d ' ')" -eq 1 ]
  [ ! -e "$SCRATCH/fail-k.out.meta" ]
  unset SUDO_FAIL_K
  : > "$SUDO_LOG"
  export SUDO_FAIL_K=post
  run _vs_run "$commit" k3dm-web-console-sshd "$SCRATCH/post-fail-k.out" 3
  [ "$status" -eq 3 ]
  [[ "$output" = *'warning: could not invalidate sudo ticket'* ]]
  [ "$(wc -l < "$SUDO_LOG" | tr -d ' ')" -eq 2 ]
  unset SUDO_FAIL_K
}

@test "[M3] run passes ignored SIGTSTP to the child" {
  local stage="$BASE/stage/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" commit out="$SCRATCH/tstp.out"
  mkdir -p "$stage/bin"
  cat > "$stage/bin/k3dm-web-console-sshd" <<'EOF'
#!/bin/bash
/bin/kill -TSTP "$$"
printf 'continued\n' > "$1"
EOF
  chmod 755 "$stage/bin/k3dm-web-console-sshd"
  git -C "$stage" init -q -b main
  git -C "$stage" add bin/k3dm-web-console-sshd
  git -C "$stage" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm probe
  commit="$(git -C "$stage" rev-parse HEAD)"
  mv "$stage" "$BASE/stage/$commit"
  stage="$BASE/stage/$commit"
  printf '%s\n' "$commit" > "$stage/.git/k3dm-verified"
  cat > "$SCRATCH/check-tstp.py" <<'PY'
import os, signal, subprocess, sys
source, base, self_path, trust, sudo, commit, out, trap_file = sys.argv[1:]
command = 'source "$1"; _VS_BASE="$2"; _VS_SELF="$3"; _VS_TRUST_TOP="$4"; _VS_OWNER=$(id -u); _VS_GROUP=$(id -g); _VS_GIT=$(command -v git); _VS_GIT_CORE=$(dirname "$(command -v git)"); _VS_SUDO="$5"; _vs_euid() { printf 501; }; _vs_run "$6" k3dm-web-console-sshd "$7"; trap -p TSTP > "$8"'
def reset_tstp():
    signal.signal(signal.SIGTSTP, signal.SIG_DFL)
proc = subprocess.Popen(['/bin/bash', '-c', command, '_', source, base, self_path, trust, sudo, commit, out, trap_file],
                        preexec_fn=reset_tstp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    rc = proc.wait(timeout=2)
except subprocess.TimeoutExpired:
    os.kill(proc.pid, signal.SIGCONT)
    proc.terminate()
    proc.wait(timeout=2)
    raise SystemExit('run or probe stopped on SIGTSTP')
if rc != 0 or not os.path.exists(out) or open(trap_file).read().strip() != "trap -- '' SIGTSTP":
    raise SystemExit('run rc=%s; probe did not continue' % rc)
PY
  run python3 "$SCRATCH/check-tstp.py" "$REPO/bin/k3dm-verified-stage" "$BASE" "$SELF" "$TRUST" "$_VS_SUDO" "$commit" "$out" "$SCRATCH/tstp-trap"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "[G4] run ignores caller BASH_ENV, git function and SHELLOPTS poison" {
  local commit marker="$SCRATCH/run-bash-env-marker" git_marker="$SCRATCH/run-git-function-marker"
  _make_probe_stage
  commit="$STAGE_COMMIT"
  printf 'touch %s\n' "$marker" > "$SCRATCH/run-bashenv"
  cat > "$SCRATCH/run-poison-helper" <<'EOF'
#!/bin/bash
source "$1"
_VS_BASE="$2"; _VS_SELF="$3"; _VS_TRUST_TOP="$4"; _VS_OWNER="$(id -u)"; _VS_GROUP="$(id -g)"
_VS_GIT="$(command -v git)"; _VS_GIT_CORE="$(dirname "$(command -v git)")"; _VS_SUDO="$5"
_vs_euid() { printf '501'; }
git() { : > "$7"; }
export -f git
rm -f "$6" "$7"
_vs_run "$8" k3dm-web-console-sshd "$9"
EOF
  chmod 755 "$SCRATCH/run-poison-helper"
  _vs_euid() { printf '501'; }
  run env BASH_ENV="$SCRATCH/run-bashenv" SHELLOPTS=xtrace POSIXLY_CORRECT=1 /bin/bash "$SCRATCH/run-poison-helper" \
    "$REPO/bin/k3dm-verified-stage" "$BASE" "$SELF" "$TRUST" "$_VS_SUDO" "$marker" "$git_marker" "$commit" "$SCRATCH/poison.out"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
  [ ! -e "$marker" ]
  [ ! -e "$git_marker" ]
  grep -Eq '^xtrace[[:space:]]+off$' "$SCRATCH/poison.out.meta"
  grep -Fq "/bin/bash -p \"\$_VS_BASE/stage/\$commit/bin/\$tool\"" "$REPO/bin/k3dm-verified-stage"
}

@test "[N10] run clears sudo ticket on HUP, INT and TERM" {
  local stage="$BASE/stage/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" commit
  mkdir -p "$stage/bin"
  cat > "$stage/bin/k3dm-web-console-sshd" <<'EOF'
#!/bin/bash
printf 'started\n' > "$1"
while :; do sleep 1; done
EOF
  chmod 755 "$stage/bin/k3dm-web-console-sshd"
  git -C "$stage" init -q -b main
  git -C "$stage" add bin/k3dm-web-console-sshd
  git -C "$stage" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm probe
  commit="$(git -C "$stage" rev-parse HEAD)"
  mv "$stage" "$BASE/stage/$commit"
  stage="$BASE/stage/$commit"
  printf '%s\n' "$commit" > "$stage/.git/k3dm-verified"
  cat > "$SCRATCH/check-run-signals.py" <<'PY'
import os, signal, subprocess, sys, time
source, base, self_path, trust, sudo, commit, log, root = sys.argv[1:]
command = 'source "$1"; _VS_BASE="$2"; _VS_SELF="$3"; _VS_TRUST_TOP="$4"; _VS_OWNER=$(id -u); _VS_GROUP=$(id -g); _VS_GIT=$(command -v git); _VS_GIT_CORE=$(dirname "$(command -v git)"); _VS_SUDO="$5"; _vs_euid() { printf 501; }; _vs_run "$6" k3dm-web-console-sshd "$7" hold'
expected = {'HUP': 129, 'INT': 130, 'TERM': 143}
def reset_signals():
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM, signal.SIGQUIT):
        signal.signal(sig, signal.SIG_DFL)
for name, number in expected.items():
    open(log, 'w').close()
    marker = os.path.join(root, name + '.started')
    proc = subprocess.Popen(['/bin/bash', '-c', command, '_', source, base, self_path, trust, sudo, commit, marker],
                            preexec_fn=reset_signals, start_new_session=True,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 10
    while not os.path.exists(marker) and time.monotonic() < deadline:
        time.sleep(0.02)
    if not os.path.exists(marker):
        os.killpg(proc.pid, signal.SIGKILL)
        raise SystemExit(name + ': run did not start probe')
    os.killpg(proc.pid, getattr(signal, 'SIG' + name))
    rc = proc.wait(timeout=10)
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    if rc != number:
        raise SystemExit('%s: rc=%s expected=%s' % (name, rc, number))
    if open(log).read().splitlines() != ['sudo -k', 'sudo -k']:
        raise SystemExit(name + ': sudo log=' + repr(open(log).read().splitlines()))
open(log, 'w').close()
marker = os.path.join(root, 'QUIT.started')
proc = subprocess.Popen(['/bin/bash', '-c', command, '_', source, base, self_path, trust, sudo, commit, marker],
                        preexec_fn=reset_signals, start_new_session=True,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
deadline = time.monotonic() + 10
while not os.path.exists(marker) and time.monotonic() < deadline:
    time.sleep(0.02)
if not os.path.exists(marker):
    os.killpg(proc.pid, signal.SIGKILL)
    raise SystemExit('QUIT: run did not start probe')
os.killpg(proc.pid, signal.SIGQUIT)
time.sleep(0.1)
if proc.poll() is not None:
    raise SystemExit('run was killed by QUIT')
os.killpg(proc.pid, signal.SIGTERM)
if proc.wait(timeout=10) != 143:
    raise SystemExit('run did not remain signalable after QUIT')
if open(log).read().splitlines() != ['sudo -k', 'sudo -k']:
    raise SystemExit('QUIT: sudo log=' + repr(open(log).read().splitlines()))
PY
  run python3 "$SCRATCH/check-run-signals.py" "$REPO/bin/k3dm-verified-stage" "$BASE" "$SELF" "$TRUST" "$_VS_SUDO" "$commit" "$SUDO_LOG" "$SCRATCH"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "[N5] bootstrap ignores startup poison and runs with POSIXLY_CORRECT set" {
  local marker="$SCRATCH/bootstrap-marker" output_file="$SCRATCH/bootstrap-output" gitstub="$SCRATCH/git" gitcore="$SCRATCH/git-core" captured
  printf 'touch %s\n' "$marker" > "$SCRATCH/bashenv"
  git() { printf 'git function ran\n' > "$SCRATCH/git-function-marker"; }
  export -f git
  mkdir -p "$gitcore"
  cat > "$gitstub" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$SCRATCH/git-called"
exit 1
EOF
  chmod 755 "$gitstub"
  sed -e "s|^_VS_SELF=.*|_VS_SELF=$SELF|" \
      -e "s|^_VS_BASE=.*|_VS_BASE=$BASE|" \
      -e "s|^_VS_TRUST_TOP=.*|_VS_TRUST_TOP=$SCRATCH|" \
      -e "s|^_VS_OWNER=.*|_VS_OWNER=$(id -u)|" \
      -e "s|^_VS_GROUP=.*|_VS_GROUP=$(id -g)|" \
      -e "s|^_VS_GIT=.*|_VS_GIT=$gitstub|" \
      -e "s|^_VS_GIT_CORE=.*|_VS_GIT_CORE=$gitcore|" \
      -e "s|^_VS_SUDO=.*|_VS_SUDO=$_VS_SUDO|" \
      -e 's|^_vs_euid() { /usr/bin/id -u; }|_vs_euid() { printf 0; }|' \
      "$REPO/bin/k3dm-verified-stage" > "$SELF"
  chmod 755 "$SELF"
  run env BASH_ENV="$SCRATCH/bashenv" POSIXLY_CORRECT=1 SHELLOPTS=xtrace "$SELF" 0123456789012345678901234567890123456789
  [ "$status" -eq 4 ]
  captured="$output"
  printf '%s\n' "$captured" > "$output_file"
  [ ! -e "$marker" ]
  [ ! -e "$SCRATCH/git-function-marker" ]
  [ -s "$SCRATCH/git-called" ] || { printf 'bootstrap output: %s\n' "$captured"; return 1; }
  run grep -q '^+' "$output_file"
  [ "$status" -eq 1 ]
  run grep -q 'syntax error' "$output_file"
  [ "$status" -eq 1 ]
}

@test "[N6] CDPATH attacker is live for direct sshd check and dropped by run" {
  local work="$SCRATCH/sshd-work" stage="$BASE/stage/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" attacker="$SCRATCH/attacker" marker="$SCRATCH/cdpath-marker" path
  mkdir -p "$work/bin" "$work/scripts/lib/foundation/scripts/lib" "$work/scripts/etc/ssh" "$work/scripts/etc/launchd" "$work/scripts/libexec"
  for path in bin/k3dm-web-console-sshd scripts/lib/web_console_common.sh scripts/lib/system.sh scripts/lib/agent_rigor.sh scripts/lib/foundation/scripts/lib/system.sh scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl scripts/etc/launchd/com.k3d-manager.web-console-sshd.plist.tmpl scripts/libexec/k3dm-console-forced-command; do
    mkdir -p "$work/${path%/*}"
    cp "$REPO/$path" "$work/$path"
  done
  git -C "$work" init -q -b main
  git -C "$work" add bin scripts
  git -C "$work" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm sshd
  mkdir -p "$BASE/stage"
  git -C "$work" clone -q --no-hardlinks --no-checkout . "$stage"
  git -C "$stage" checkout -q --detach HEAD
  STAGE_COMMIT="$(git -C "$stage" rev-parse HEAD)"
  mv "$stage" "$BASE/stage/$STAGE_COMMIT"
  STAGE_PATH="$BASE/stage/$STAGE_COMMIT"
  printf '%s\n' "$STAGE_COMMIT" > "$STAGE_PATH/.git/k3dm-verified"
  mkdir -p "$attacker/scripts/lib/foundation/scripts/lib"
  printf 'touch %s\n' "$marker" > "$attacker/scripts/lib/foundation/scripts/lib/system.sh"
  run env CDPATH="$attacker" "$STAGE_PATH/bin/k3dm-web-console-sshd" check
  [ -e "$marker" ]
  rm -f "$marker"
  export CDPATH="$attacker"
  _vs_euid() { printf '501'; }
  run _vs_run "$STAGE_COMMIT" k3dm-web-console-sshd check
  [ ! -e "$marker" ]
  grep -q 'sudo -k' "$SUDO_LOG"
}

@test "[M10] wrapper rejects malformed input before sudo" {
  _vs_euid() { printf '501'; }
  run _vs_wrapper stage short
  [ "$status" -eq 2 ]
  [ ! -s "$SUDO_LOG" ]
}

@test "[M10] wrapper clears ticket before and after sudo and returns its status" {
  local commit=0123456789012345678901234567890123456789
  _vs_euid() { printf '501'; }
  export SUDO_NOEXEC=1 SUDO_STATUS=3
  run _vs_wrapper stage "$commit" --ref deploy/hub
  [ "$status" -eq 3 ]
  [ "$(sed -n '1p' "$SUDO_LOG")" = 'sudo -k' ]
  [ "$(sed -n '2p' "$SUDO_LOG")" = "sudo $SELF $commit --ref deploy/hub" ]
  [ "$(sed -n '3p' "$SUDO_LOG")" = 'sudo -k' ]
  : > "$SUDO_LOG"
  export SUDO_FAIL_K=1
  run _vs_wrapper stage "$commit" --ref deploy/hub
  [ "$status" -eq 3 ]
  [ "$(sed -n '1p' "$SUDO_LOG")" = 'sudo -k' ]
  [ "$(wc -l < "$SUDO_LOG" | tr -d ' ')" -eq 1 ]
  unset SUDO_FAIL_K
}

@test "[M10] wrapper clears ticket on HUP, INT and TERM" {
  local signal commit=0123456789012345678901234567890123456789
  _vs_euid() { printf '501'; }
  export SUDO_NOEXEC=1 SUDO_HANG=1 SUDO_STATUS=3
  export SUDO_READY_FILE="$SCRATCH/wrapper-ready"
  cat > "$SCRATCH/send-wrapper-signal.py" <<'PY'
import os, signal, subprocess, sys, time
source, self_path, sudo, sig_name, commit, ready = sys.argv[1:]
command = 'source "$1"; _VS_SELF="$2"; _VS_SUDO="$3"; _vs_euid() { printf 501; }; _vs_wrapper stage "$4"'
def reset_signals():
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM, signal.SIGQUIT):
        signal.signal(sig, signal.SIG_DFL)
proc = subprocess.Popen(['/bin/bash', '-c', command, '_', source, self_path, sudo, commit],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        start_new_session=True, preexec_fn=reset_signals)
deadline = time.monotonic() + 10
while not os.path.exists(ready) and time.monotonic() < deadline:
    time.sleep(0.02)
if not os.path.exists(ready):
    proc.terminate()
    proc.wait(timeout=10)
    raise SystemExit('wrapper did not enter the sudo stand-in')
if sig_name == 'QUIT':
    os.killpg(proc.pid, signal.SIGQUIT)
    time.sleep(0.1)
    if proc.poll() is not None:
        raise SystemExit('wrapper was killed by QUIT')
    os.killpg(proc.pid, signal.SIGTERM)
    expected = 143
else:
    os.killpg(proc.pid, getattr(signal, 'SIG' + sig_name))
    expected = {'HUP': 129, 'INT': 130, 'TERM': 143}[sig_name]
rc = proc.wait(timeout=10)
if rc != expected:
    raise SystemExit('wrapper signal status %s, expected %s' % (rc, expected))
PY
  for signal in HUP INT TERM QUIT; do
    : > "$SUDO_LOG"
    rm -f "$SUDO_READY_FILE"
    run python3 "$SCRATCH/send-wrapper-signal.py" "$REPO/bin/k3dm-verified-stage" "$SELF" "$_VS_SUDO" "$signal" "$commit" "$SUDO_READY_FILE"
    [ "$status" -eq 0 ] || { printf 'signal=%s %s\n' "$signal" "$output"; return 1; }
    [ "$(grep -c '^sudo -k$' "$SUDO_LOG")" -eq 2 ]
  done
}
