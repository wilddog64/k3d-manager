#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  MACHINE_DIR="${MACHINE_MANIFEST_DIR:-${REPO_ROOT}/scripts/etc/machine}"
  SCRIPT_SOURCE="${MACHINE_SETUP_SOURCE:-${REPO_ROOT}/bin/k3dm-machine-setup}"
}

manifest_disjoint() {
  local dir="$1" item
  while IFS='|' read -r item _; do
    [[ -n "$item" && "$item" != \#* ]] || continue
    if grep -Fqx "$item" "$dir"/agents.*.list; then return 1; fi
  done < "$dir/not-installed.list"
}

@test "machine setup: all roles have readable phase manifests" {
  for role in hub worker console; do
    [ -r "${MACHINE_DIR}/brew.${role}.list" ]
    [ -r "${MACHINE_DIR}/secrets.${role}.list" ]
    [ -r "${MACHINE_DIR}/agents.${role}.list" ]
  done
}

@test "machine setup: installed and not-installed entries are disjoint" {
  manifest_disjoint "$MACHINE_DIR"
}

@test "machine setup: every target and LaunchAgent has an exact manifest mapping" {
  for item in $(sed -nE 's/^(install-[[:alnum:]-]+):[[:space:]]*$/\1/p' "$REPO_ROOT/Makefile"); do
    if ! grep -Fqx "$item" "$MACHINE_DIR"/agents.*.list && ! cut -d'|' -f1 "$MACHINE_DIR/not-installed.list" | grep -Fxq "$item"; then return 1; fi
  done
  for template in "$REPO_ROOT"/scripts/etc/launchd/*.plist.tmpl; do
    item="${template##*/com.k3d-manager.}"; item="${item%.plist.tmpl}"
    case "$item" in
      webhook-token-rotate) action=install-token-rotator ;;
      webhook|hermes|heartbeat) action="bin/k3dm-${item}-setup" ;;
      *) action="install-${item}" ;;
    esac
    if ! grep -Fqx "$action" "$MACHINE_DIR"/agents.*.list && ! cut -d'|' -f1 "$MACHINE_DIR/not-installed.list" | grep -Fxq "$action"; then return 1; fi
  done
}

@test "machine setup: secret setup commands and operator documents exist" {
  for list in "$MACHINE_DIR"/secrets.*.list; do
    while IFS='|' read -r service account purpose command; do
      [[ -n "$service" && "$service" != \#* ]] || continue
      case "$command" in
        'operator: see '*) [ -f "$REPO_ROOT/${command#operator: see }" ] ;;
        'make '*) target="${command#make }"; grep -Eq "^${target}:" "$REPO_ROOT/Makefile" ;;
        bin/*) [ -f "$REPO_ROOT/$command" ] ;;
        *) echo "Invalid command for $service: $command"; return 1 ;;
      esac
    done < "$list"
  done
}

setup_machine_fixture() {
  FIXROOT="$BATS_TEST_TMPDIR/project"
  FIXHOME="$BATS_TEST_TMPDIR/home"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  CALL_LOG="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$FIXROOT/bin" "$FIXROOT/scripts/lib" "$FIXROOT/scripts/etc/machine" "$FIXHOME" "$STUBS"
  cp "$SCRIPT_SOURCE" "$FIXROOT/bin/k3dm-machine-setup"
  chmod +x "$FIXROOT/bin/k3dm-machine-setup"
  printf '%s\n' '_run_command() { return 1; }' > "$FIXROOT/scripts/lib/system.sh"
  : > "$FIXROOT/scripts/lib/core.sh"
  for role in hub worker console; do
    : > "$FIXROOT/scripts/etc/machine/brew.$role.list"
    : > "$FIXROOT/scripts/etc/machine/secrets.$role.list"
    : > "$FIXROOT/scripts/etc/machine/agents.$role.list"
  done
  : > "$FIXROOT/scripts/etc/machine/repos.list"
  : > "$CALL_LOG"
  cat > "$STUBS/uname" <<'SH'
#!/bin/sh
case "$1" in -s) echo Darwin ;; -m) echo arm64 ;; esac
SH
  cat > "$STUBS/xcode-select" <<'SH'
#!/bin/sh
[ ! -e "$CALL_LOG.cltfail" ]
SH
  cat > "$STUBS/brew" <<'SH'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$CALL_LOG"
exit 0
SH
  cat > "$STUBS/gh" <<'SH'
#!/bin/sh
printf 'gh %s\n' "$*" >> "$CALL_LOG"
if [ "$1 $2" = 'auth status' ]; then
  if [ -e "$CALL_LOG.ghstatusfail" ]; then exit 1; fi
  printf '%s\n' "${GH_STATUS_TEXT:-authenticated}"
fi
if [ "$1 $2" = 'auth setup-git' ] && [ -e "$CALL_LOG.ghfail" ]; then exit 1; fi
exit 0
SH
  cat > "$STUBS/security" <<'SH'
#!/bin/sh
printf 'security %s\n' "$*" >> "$CALL_LOG"
exit 1
SH
  cat > "$STUBS/git" <<'SH'
#!/bin/sh
printf 'git %s\n' "$*" >> "$CALL_LOG"
case "$1" in
  -C) printf '%s\n' "${REMOTE_FIXTURE:-https://example.test/existing.git}"; exit 0 ;;
  ls-remote) exit 0 ;;
  clone) exit 1 ;;
esac
exit 0
SH
  for tool in ruff pytest; do
    printf '#!/bin/sh\nexit 0\n' > "$STUBS/$tool"
  done
  cat > "$STUBS/python3" <<'SH'
#!/bin/sh
printf 'python3 %s\n' "$*" >> "$CALL_LOG"
[ "$1" = -m ] && [ "$2" = venv ] || exit 1
mkdir -p "$3/bin"
cat > "$3/bin/python" <<'VENV'
#!/bin/sh
printf 'venv-python %s\n' "$*" >> "$CALL_LOG"
for tool in ruff pytest; do
  printf '#!/bin/sh\nexit 0\n' > "$(dirname "$0")/$tool"
  chmod +x "$(dirname "$0")/$tool"
done
VENV
chmod +x "$3/bin/python"
SH
  cat > "$STUBS/make" <<'SH'
#!/bin/sh
printf 'make %s\n' "$*" >> "$CALL_LOG"
if [ -e "$CALL_LOG.installsmartcd" ]; then mkdir -p "$HOME/.smartcd/lib/core"; : > "$HOME/.smartcd/lib/core/smartcd"; fi
exit 0
SH
  chmod +x "$STUBS"/*
}

run_machine() {
  run env HOME="$FIXHOME" XDG_DATA_HOME="${FIX_XDG_DATA_HOME:-$FIXHOME/.local/share}" PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" CALL_LOG="$CALL_LOG" GH_STATUS_TEXT="${GH_STATUS_TEXT:-authenticated}" REMOTE_FIXTURE="${REMOTE_FIXTURE:-https://example.test/existing.git}" "$FIXROOT/bin/k3dm-machine-setup" "$@"
}

@test "machine setup: repository manifest paths are unique" {
  duplicates="$(awk -F'|' '!/^#/ && NF > 1 { print $1 }' "$MACHINE_DIR/repos.list" | sort | uniq -d)"
  [ -z "$duplicates" ]
  grep -Fxq 'gitrepo/personal/k3d-manager|https://github.com/wilddog64/k3d-manager.git|main|hub,worker,console' "$MACHINE_DIR/repos.list"
}

@test "machine setup: equivalent GitHub remotes identify the same existing checkout" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/existing/.git"
  printf '%s\n' 'gitrepo/existing|https://github.com/Owner/Repo.git|-|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  for remote in 'git@github.com:owner/repo.git' 'ssh://git@github.com/OWNER/REPO/' 'https://github.com/owner/repo'; do
    REMOTE_FIXTURE="$remote"
    run_machine --role console --check
    if [ "$status" -ne 0 ] || ! grep -Eq '^repo:gitrepo/existing[[:space:]]+ok$' <<< "$output"; then printf '%s\n' "$output"; return 1; fi
  done
  ! grep -Eq '^git (clone|.* (checkout|reset|pull|clean))' "$CALL_LOG"
}

@test "machine setup: another GitHub repository is rejected" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/existing/.git"
  printf '%s\n' 'gitrepo/existing|https://github.com/Owner/Repo.git|-|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  REMOTE_FIXTURE='git@github.com:other/repo.git'
  run_machine --role console --check
  [ "$status" -eq 1 ]
  grep -Eq '^repo:gitrepo/existing[[:space:]]+skipped \(existing clone has another remote\)$' <<< "$output"
}

@test "machine setup: SSH config checkout is recognized" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/.claude/.git"
  REMOTE_FIXTURE='git@github.com:WILDDOG64/CLAUDE-SETTINGS.git'
  run_machine --role worker --check
  grep -Eq '^config:claude-settings[[:space:]]+ok$' <<< "$output"
}

@test "machine setup: smartcd library presence is recognized without a clone" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/.smartcd/lib/core"
  touch "$FIXHOME/.smartcd/lib/core/smartcd"
  printf '%s\n' 'smartcd-install' > "$FIXROOT/scripts/etc/machine/agents.worker.list"
  run_machine --role worker --check
  grep -Eq '^smartcd[[:space:]]+ok$' <<< "$output"
  ! grep -Eq '^git clone .*smartcd' "$CALL_LOG"
}

@test "machine setup: smartcd installs from its source checkout" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/personal/smartcd/.git"
  REMOTE_FIXTURE='git@github.com:cxreg/smartcd.git'
  printf '%s\n' 'smartcd-install' > "$FIXROOT/scripts/etc/machine/agents.worker.list"
  touch "$CALL_LOG.installsmartcd"
  run_machine --role worker
  grep -Eq '^smartcd[[:space:]]+installed$' <<< "$output"
  grep -Fq "make -C $FIXHOME/src/gitrepo/personal/smartcd install" "$CALL_LOG"
  ! grep -Eq '^git clone .*smartcd' "$CALL_LOG"
}

@test "machine setup: smartcd rejects a different source checkout" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/personal/smartcd/.git"
  REMOTE_FIXTURE='git@github.com:other/smartcd.git'
  printf '%s\n' 'smartcd-install' > "$FIXROOT/scripts/etc/machine/agents.worker.list"
  run_machine --role worker
  grep -Eq '^smartcd[[:space:]]+skipped \(source clone has another remote\)$' <<< "$output"
  ! grep -Fq "make -C $FIXHOME/src/gitrepo/personal/smartcd install" "$CALL_LOG"
}

@test "machine setup: failed GitHub authentication does not stop the report" {
  setup_machine_fixture
  touch "$CALL_LOG.ghstatusfail"
  mkdir -p "$FIXHOME/src/gitrepo/existing/.git"
  printf '%s\n' 'example' > "$FIXROOT/scripts/etc/machine/brew.console.list"
  printf '%s\n' 'gitrepo/existing|https://example.test/existing.git|-|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  printf '%s\n' 'fixture|k3dm|purpose|operator: see docs/howto/acg.md' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  printf '%s\n' 'fake-target' > "$FIXROOT/scripts/etc/machine/agents.console.list"
  run_machine --role console --check
  [ "$status" -eq 1 ]
  grep -Eq '^github-auth[[:space:]]+missing$' <<< "$output"
  grep -Eq '^brew:example[[:space:]]+ok$' <<< "$output"
  grep -Eq '^repo:gitrepo/existing[[:space:]]+ok$' <<< "$output"
  grep -Eq '^secret:fixture[[:space:]]+missing' <<< "$output"
  grep -Eq '^agent:fake-target[[:space:]]+missing$' <<< "$output"
}

@test "machine setup: missing command line tools do not stop the report" {
  setup_machine_fixture
  touch "$CALL_LOG.cltfail"
  printf '%s\n' 'example' > "$FIXROOT/scripts/etc/machine/brew.console.list"
  printf '%s\n' 'fixture|k3dm|purpose|operator: see docs/howto/acg.md' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  run_machine --role console --check
  [ "$status" -eq 1 ]
  grep -Eq '^command-line-tools[[:space:]]+missing$' <<< "$output"
  grep -Eq '^brew:example[[:space:]]+ok$' <<< "$output"
  grep -Eq '^secret:fixture[[:space:]]+missing' <<< "$output"
}

@test "machine setup: missing Homebrew skips brew and continues reporting" {
  setup_machine_fixture
  rm "$STUBS/brew"
  printf '%s\n' 'fixture|k3dm|purpose|operator: see docs/howto/acg.md' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  run_machine --role console --check
  [ "$status" -eq 1 ]
  grep -Eq '^homebrew[[:space:]]+missing$' <<< "$output"
  grep -Eq '^brew-phase[[:space:]]+skipped \(Homebrew unavailable\)$' <<< "$output"
  grep -Eq '^secret:fixture[[:space:]]+missing' <<< "$output"
  ! grep -q '^brew ' "$CALL_LOG"
}

@test "machine setup: links through intermediate directories resolve as ok" {
  setup_machine_fixture
  base="$FIXHOME/src/gitrepo/personal/zshdotfiles"
  mkdir -p "$base"; touch "$base/smartcd_config" "$base/zshrc"
  ln -s "$base" "$FIXHOME/.zsh"
  ln -s "$base/zshrc" "$FIXHOME/.zshrc"
  ln -s "$FIXHOME/.zsh/smartcd_config" "$FIXHOME/.smartcd_config"
  run_machine --role worker --check
  grep -Eq '^shell:.zshrc[[:space:]]+ok$' <<< "$output"
  grep -Eq '^state-smartcd-config[[:space:]]+ok$' <<< "$output"
}

@test "machine setup: safety N1 checks Keychain without reading values" {
  setup_machine_fixture
  printf '%s\n' 'fixture|k3dm|purpose|operator: see docs/howto/acg.md' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  run_machine --role console --check
  [ "$status" -eq 1 ]
  grep -q '^security find-generic-password ' "$CALL_LOG"
  ! grep -Eq '^security .* (-w|--password)( |$)' "$CALL_LOG"
}

@test "machine setup: missing secrets do not prompt without a TTY" {
  setup_machine_fixture
  printf '%s\n' 'fixture|k3dm|purpose|make secret-setup' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  run_machine --role console
  [ "$status" -eq 1 ]
  [[ "$output" == *'secret:fixture'*'missing'* ]]
  [[ "$output" != *'Run setup command now?'* ]]
  ! grep -q '^make .*secret-setup' "$CALL_LOG"
}

@test "machine setup: safety N2 check and dry-run make no mutating calls" {
  setup_machine_fixture
  printf '%s\n' 'gitrepo/example|https://example.test/example.git|-|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  printf '%s\n' 'example' > "$FIXROOT/scripts/etc/machine/brew.console.list"
  printf '%s\n' 'install-cleanup' > "$FIXROOT/scripts/etc/machine/agents.console.list"
  for mode in --check --dry-run; do
    : > "$CALL_LOG"
    run_machine --role console "$mode"
    [ "$status" -eq 1 ]
    if grep -Eq '^(git clone|brew install|security add|make |launchctl |gh auth setup-git)' "$CALL_LOG"; then cat "$CALL_LOG"; return 1; fi
    if [ -e "$FIXHOME/src/gitrepo/example" ]; then return 1; fi
  done
}

@test "machine setup: safety N3 worker rejects hub installers" {
  setup_machine_fixture
  printf '%s\n' 'install-cleanup' > "$FIXROOT/scripts/etc/machine/agents.worker.list"
  run_machine --role worker
  [ "$status" -eq 1 ]
  [[ "$output" == *'skipped (hub only)'* ]]
  ! grep -Eq '^make .*install-cleanup' "$CALL_LOG"
}

@test "machine setup: safety N5 leaves existing clone untouched" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/existing/.git"
  printf '%s\n' 'gitrepo/existing|https://example.test/existing.git|-|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  run_machine --role console
  [ "$status" -eq 0 ]
  [[ "$output" == *'repo:gitrepo/existing'*'ok'* ]]
  ! grep -Eq '^git (clone|.* (checkout|reset|pull|clean))' "$CALL_LOG"
}

@test "machine setup: failed clone is reported and later phases run" {
  setup_machine_fixture
  printf '%s\n' 'gitrepo/example|https://example.test/example.git|-|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  printf '%s\n' 'fixture|k3dm|purpose|operator: see docs/howto/acg.md' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  printf '%s\n' 'fake-target' > "$FIXROOT/scripts/etc/machine/agents.console.list"
  run_machine --role console
  [ "$status" -eq 1 ]
  [[ "$output" == *'repo:gitrepo/example'*'missing'* ]] || { printf '%s\n' "$output"; return 1; }
  [[ "$output" == *'secret:fixture'* ]]
  [[ "$output" == *'agent:fake-target'*'installed'* ]]
  grep -q '^make .*fake-target' "$CALL_LOG"
}

@test "machine setup: branch clone failure also reaches later phases" {
  setup_machine_fixture
  printf '%s\n' 'gitrepo/example|https://example.test/example.git|feature/test|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  printf '%s\n' 'fake-target' > "$FIXROOT/scripts/etc/machine/agents.console.list"
  run_machine --role console
  [ "$status" -eq 1 ]
  [[ "$output" == *'repo:gitrepo/example'*'missing'*'agent:fake-target'*'installed'* ]]
  grep -q '^git clone --branch feature/test' "$CALL_LOG"
}

@test "machine setup: GitHub git setup failure is reported and later phases run" {
  setup_machine_fixture
  touch "$CALL_LOG.ghfail"
  printf '%s\n' 'fake-target' > "$FIXROOT/scripts/etc/machine/agents.console.list"
  run_machine --role console
  [ "$status" -eq 1 ]
  [[ "$output" == *'github-setup-git'*'missing'*'agent:fake-target'*'installed'* ]]
}

@test "machine setup: Python tools on PATH need no Python invocation" {
  setup_machine_fixture
  run_machine --role console
  [ "$status" -eq 0 ]
  grep -Eq '^python-tools[[:space:]]+ok$' <<< "$output"
  ! grep -Eq '^(python3|venv-python) ' "$CALL_LOG"
}

@test "machine setup: an existing data-dir virtualenv is recognized" {
  setup_machine_fixture
  rm "$STUBS/ruff" "$STUBS/pytest"
  mkdir -p "$FIXHOME/.local/share/k3d-manager/venv/bin"
  for tool in ruff pytest; do touch "$FIXHOME/.local/share/k3d-manager/venv/bin/$tool"; chmod +x "$FIXHOME/.local/share/k3d-manager/venv/bin/$tool"; done
  run_machine --role console --check
  [ "$status" -eq 0 ]
  grep -Eq '^python-tools[[:space:]]+ok$' <<< "$output"
  ! grep -Eq '^(python3|venv-python) ' "$CALL_LOG"
}

@test "machine setup: missing Python tools are reported read-only" {
  setup_machine_fixture
  rm "$STUBS/ruff" "$STUBS/pytest"
  for mode in --check --dry-run; do
    run_machine --role console "$mode"
    if [ "$status" -ne 1 ] || ! grep -Eq '^python-tools[[:space:]]+missing$' <<< "$output"; then printf '%s\n' "$output"; return 1; fi
  done
  ! grep -Eq '^(python3|venv-python) ' "$CALL_LOG"
  [ ! -e "$FIXHOME/.local/share/k3d-manager/venv" ]
  [ ! -e "$FIXROOT/.venv" ]
}

@test "machine setup: Python tools install outside the repository and second setup is idle" {
  setup_machine_fixture
  rm "$STUBS/ruff" "$STUBS/pytest"
  run_machine --role console
  [ "$status" -eq 0 ]
  grep -Fq 'installed (add ~/.local/share/k3d-manager/venv/bin to PATH)' <<< "$output"
  [ -x "$FIXHOME/.local/share/k3d-manager/venv/bin/ruff" ]
  [ -x "$FIXHOME/.local/share/k3d-manager/venv/bin/pytest" ]
  [ ! -e "$FIXROOT/.venv" ]
  grep -Fq 'venv-python -m pip install pytest==9.1.1 ruff==0.15.8' "$CALL_LOG"
  : > "$CALL_LOG"
  run_machine --role console
  [ "$status" -eq 0 ]
  grep -Eq '^python-tools[[:space:]]+ok$' <<< "$output"
  ! grep -Eq '^(python3|venv-python) ' "$CALL_LOG"
}

@test "machine setup: custom XDG data directory holds the Python virtualenv" {
  setup_machine_fixture
  rm "$STUBS/ruff" "$STUBS/pytest"
  FIX_XDG_DATA_HOME="$FIXHOME/custom-data"
  run_machine --role console
  [ "$status" -eq 0 ]
  [ -x "$FIX_XDG_DATA_HOME/k3d-manager/venv/bin/ruff" ]
  [ -x "$FIX_XDG_DATA_HOME/k3d-manager/venv/bin/pytest" ]
  [ ! -e "$FIXROOT/.venv" ]
}

@test "machine setup: virtualenv failure is reported and later phases run" {
  setup_machine_fixture
  rm "$STUBS/ruff" "$STUBS/pytest"
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/python3"; chmod +x "$STUBS/python3"
  printf '%s\n' 'fake-target' > "$FIXROOT/scripts/etc/machine/agents.console.list"
  run_machine --role console
  [ "$status" -eq 1 ]
  [[ "$output" == *'python-tools'*'missing'*'agent:fake-target'*'installed'* ]]
}

@test "machine setup: link failures are reported and later phases run" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/personal/zshdotfiles/workspace"
  touch "$FIXHOME/src/gitrepo/personal/zshdotfiles/workspace/CLAUDE.md"
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/ln"; chmod +x "$STUBS/ln"
  printf '%s\n' 'fixture|k3dm|purpose|operator: see docs/howto/acg.md' > "$FIXROOT/scripts/etc/machine/secrets.worker.list"
  run_machine --role worker
  [ "$status" -eq 1 ]
  [[ "$output" == *'shell:.zsh'*'missing'*'workspace:CLAUDE.md'*'missing'*'secret:fixture'* ]]
  [[ "$output" != *"$FIXHOME"* ]]
}

@test "machine setup: failed backup move is reported and later phases run" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/personal/zshdotfiles"
  touch "$FIXHOME/.zsh"
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/mv"; chmod +x "$STUBS/mv"
  printf '%s\n' 'fixture|k3dm|purpose|operator: see docs/howto/acg.md' > "$FIXROOT/scripts/etc/machine/secrets.worker.list"
  run_machine --role worker
  [ "$status" -eq 1 ]
  [[ "$output" == *'shell:.zsh'*'missing'*'secret:fixture'* ]]
  [ -f "$FIXHOME/.zsh" ]
}

@test "machine setup: direnv allow failure is reported and later phases run" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/personal/zshdotfiles/envrc"
  touch "$FIXHOME/src/gitrepo/personal/zshdotfiles/envrc/personal.envrc"
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/direnv"; chmod +x "$STUBS/direnv"
  printf '%s\n' 'fixture|k3dm|purpose|operator: see docs/howto/acg.md' > "$FIXROOT/scripts/etc/machine/secrets.worker.list"
  run_machine --role worker
  [ "$status" -eq 1 ]
  [[ "$output" == *'state-personal-envrc'*'missing (direnv allow failed)'*'secret:fixture'* ]]
}

@test "machine setup: hub setup scripts are checked by LaunchAgent plist" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/Library/LaunchAgents"
  for name in webhook hermes heartbeat; do
    touch "$FIXHOME/Library/LaunchAgents/com.k3d-manager.$name.plist"
    printf 'bin/k3dm-%s-setup\n' "$name" >> "$FIXROOT/scripts/etc/machine/agents.hub.list"
  done
  run_machine --role hub --check
  for name in webhook hermes heartbeat; do
    if [[ "$output" != *"agent:bin/k3dm-$name-setup"*'ok'* ]]; then return 1; fi
  done
}

@test "machine setup: smartcd and workspace links use the tracked layout" {
  setup_machine_fixture
  base="$FIXHOME/src/gitrepo/personal/zshdotfiles"
  for name in src personal k3d-manager provision-win-tomcat; do mkdir -p "$base/smartcd/$name"; touch "$base/smartcd/$name/bash_enter"; done
  mkdir -p "$base/workspace"; touch "$base/workspace/CLAUDE.md"
  run_machine --role worker
  for name in CLAUDE.md AGENTS.md GEMINI.md; do
    [ "$(readlink "$FIXHOME/src/gitrepo/personal/$name")" = "$base/workspace/CLAUDE.md" ]
  done
  [ "$(readlink "$FIXHOME/.smartcd/scripts$FIXHOME/src/bash_enter")" = "$base/smartcd/src/bash_enter" ]
  [ "$(readlink "$FIXHOME/.smartcd/scripts$FIXHOME/src/gitrepo/personal/bash_enter")" = "$base/smartcd/personal/bash_enter" ]
  [ "$(readlink "$FIXHOME/.smartcd/scripts$FIXHOME/src/gitrepo/personal/k3d-manager/bash_enter")" = "$base/smartcd/k3d-manager/bash_enter" ]
  [ "$(readlink "$FIXHOME/.smartcd/scripts$FIXHOME/src/gitrepo/personal/ansible/provision-win-tomcat/bash_enter")" = "$base/smartcd/provision-win-tomcat/bash_enter" ]
  [[ "$output" != *"$FIXHOME"* ]]
}

@test "machine setup: hosts.yml authentication storage is reported without account or path" {
  setup_machine_fixture
  GH_STATUS_TEXT='Logged in (hosts.yml)'
  run_machine --role console --check
  [[ "$output" == *'hosts.yml storage'*'gh auth logout then gh auth login'* ]]
  [[ "$output" != *"$FIXHOME"* ]]
}

@test "machine setup: Homebrew signature requires the correct installer and notarization" {
  setup_machine_fixture
  cat > "$STUBS/pkgutil" <<'SH'
#!/bin/sh
printf '%s\n' "$SIGNATURE"
SH
  chmod +x "$STUBS/pkgutil"
  for script in "$SCRIPT_SOURCE" "$REPO_ROOT/bin/machine-bootstrap"; do
    sed -n '/^verify_homebrew_package() {/,/^}/p' "$script" > "$BATS_TEST_TMPDIR/verify.sh"
    for signature in \
      'Developer ID Installer: Homebrew (927JGANW46)
Notarization: trusted by the Apple notary service' \
      'Developer ID Installer: Homebrew (WRONGTEAM)
Notarization: trusted by the Apple notary service' \
      'Developer ID Installer: Homebrew (927JGANW46)
Notarization: not trusted' \
      'Developer ID Installer: Other (WRONGTEAM)
Other: (927JGANW46)
Notarization: trusted by the Apple notary service'; do
      run env PATH="$STUBS:/usr/bin:/bin" SIGNATURE="$signature" bash -c 'source "$1"; verify_homebrew_package example.pkg' _ "$BATS_TEST_TMPDIR/verify.sh"
      if [[ "$signature" == *'Developer ID Installer: Homebrew (927JGANW46)'* && "$signature" == *'Notarization: trusted by the Apple notary service'* ]]; then [ "$status" -eq 0 ]; else [ "$status" -ne 0 ]; fi
    done
  done
}
