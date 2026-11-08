#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

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
  for role in hub worker console control; do
    [ -r "${MACHINE_DIR}/brew.${role}.list" ]
    [ -r "${MACHINE_DIR}/secrets.${role}.list" ]
    [ -r "${MACHINE_DIR}/agents.${role}.list" ]
  done
}

@test "control role manifests stay limited to development tools and smartcd" {
  [ -r "$MACHINE_DIR/brew.control.list" ]
  [ -r "$MACHINE_DIR/secrets.control.list" ]
  [ -r "$MACHINE_DIR/agents.control.list" ]
  while IFS= read -r item; do
    [[ -z "$item" || "$item" == \#* ]] || grep -Fxq "$item" "$MACHINE_DIR/brew.control.list"
  done < "$MACHINE_DIR/brew.console.list"
  run ! grep -Fxq 'cask:orbstack' "$MACHINE_DIR/brew.control.list"
  control_casks="$(grep '^cask:' "$MACHINE_DIR/brew.control.list" | sort)"
  console_casks="$(grep '^cask:' "$MACHINE_DIR/brew.console.list" | sort)"
  [ "$control_casks" = "$console_casks" ]
  [ "$(grep -vc '^#\|^$' "$MACHINE_DIR/agents.control.list")" -eq 1 ]
  grep -Fqx 'smartcd-install' "$MACHINE_DIR/agents.control.list"
  run ! grep -Eq '^(bin/|install-)' "$MACHINE_DIR/agents.control.list"
  run ! grep -Eiq 'hub|acg|cloudflare|vault|webhook' "$MACHINE_DIR/secrets.control.list"
  [ "$(grep -vc '^#\|^$' "$MACHINE_DIR/secrets.control.list")" -eq 1 ]
  grep -Fqx 'gemini-cli-api-key|k3dm|Local find-similar-docs query embedding|operator: see docs/howto/find-prior-art.md' "$MACHINE_DIR/secrets.control.list"
}

@test "control role setup installs its listed tools and only smartcd" {
  setup_machine_fixture
  cat > "$STUBS/brew" <<'SH'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$CALL_LOG"
case "$1" in list) exit 1 ;; esac
exit 0
SH
  chmod +x "$STUBS/brew"
  cp "$MACHINE_DIR/brew.control.list" "$FIXROOT/scripts/etc/machine/brew.control.list"
  cp "$MACHINE_DIR/secrets.control.list" "$FIXROOT/scripts/etc/machine/secrets.control.list"
  cp "$MACHINE_DIR/agents.control.list" "$FIXROOT/scripts/etc/machine/agents.control.list"
  : > "$FIXROOT/scripts/etc/machine/repos.list"
  mkdir -p "$FIXHOME/src/gitrepo/personal/smartcd/.git"
  touch "$CALL_LOG.installsmartcd"
  touch "$CALL_LOG.secret-present"
  run env HOME="$FIXHOME" XDG_CONFIG_HOME="$FIXHOME/.config" XDG_DATA_HOME="$FIXHOME/.local/share" PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" CALL_LOG="$CALL_LOG" GH_STATUS_TEXT=authenticated REMOTE_FIXTURE=https://github.com/cxreg/smartcd.git /usr/bin/make -C "$FIXROOT" machine-setup ROLE=control SECRETS=skip
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
  grep -Eq '^smartcd[[:space:]]+installed$' <<< "$output"
  grep -Fxq "make -C $FIXHOME/src/gitrepo/personal/smartcd install" "$CALL_LOG"
  while IFS= read -r item; do
    [[ -z "$item" || "$item" == \#* ]] || {
      case "$item" in
        cask:*) grep -Fxq "brew install --cask ${item#cask:}" "$CALL_LOG" ;;
        formula:*) grep -Fxq "brew install ${item#formula:}" "$CALL_LOG" ;;
        *) grep -Fxq "brew install $item" "$CALL_LOG" ;;
      esac
    }
  done < "$FIXROOT/scripts/etc/machine/brew.control.list"
  run ! grep -Eq '^make -C .* (install-|bin/)' "$CALL_LOG"
}

@test "control role machine-check reports manifest inventory" {
  setup_machine_fixture
  cp "$MACHINE_DIR/brew.control.list" "$FIXROOT/scripts/etc/machine/brew.control.list"
  cp "$MACHINE_DIR/secrets.control.list" "$FIXROOT/scripts/etc/machine/secrets.control.list"
  cp "$MACHINE_DIR/agents.control.list" "$FIXROOT/scripts/etc/machine/agents.control.list"
  : > "$FIXROOT/scripts/etc/machine/repos.list"
  run_machine --role control --check
  [ "$status" -eq 1 ]
  while IFS= read -r item; do
    [[ -z "$item" || "$item" == \#* ]] || { item="${item#formula:}"; item="${item#cask:}"; grep -Eq "^brew:${item}[[:space:]]+ok$" <<< "$output"; }
  done < "$MACHINE_DIR/brew.control.list"
  grep -Eq '^smartcd[[:space:]]+missing$' <<< "$output"
  run make -n machine-setup ROLE=control
  [ "$status" -eq 0 ]
  [[ "$output" == *'--role "control"'* ]]
  run make -n machine-check ROLE=control
  [ "$status" -eq 0 ]
  [[ "$output" == *'--role "control" --check'* ]]
  run make -n machine-secrets-export ROLE=control
  [ "$status" -eq 0 ]
  [[ "$output" == *'export --role "control"'* ]]
}

@test "N4: existing role manifests remain byte-for-byte unchanged" {
  for role in hub worker console; do
    for phase in brew secrets agents; do
      git show "HEAD:scripts/etc/machine/${phase}.${role}.list" | cmp -s - "$MACHINE_DIR/${phase}.${role}.list"
    done
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
  REAL_PYTHON3="$(command -v python3)"
  FIXROOT="$BATS_TEST_TMPDIR/project"
  FIXHOME="$BATS_TEST_TMPDIR/home"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  CALL_LOG="$BATS_TEST_TMPDIR/calls"
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR/"* && "$FIXHOME" != "$HOME" ]] || return 1
  mkdir -p "$FIXROOT/bin" "$FIXROOT/scripts/lib" "$FIXROOT/scripts/etc/machine" "$FIXHOME" "$STUBS"
  cp "$REPO_ROOT/Makefile" "$FIXROOT/Makefile"
  cp "$SCRIPT_SOURCE" "$FIXROOT/bin/k3dm-machine-setup"
  chmod +x "$FIXROOT/bin/k3dm-machine-setup"
  cat > "$FIXROOT/bin/k3dm-machine-secrets" <<'SH'
#!/bin/sh
printf 'secrets %s\n' "$*" >> "$CALL_LOG"
exit "${SECRETS_STUB_RC:-0}"
SH
  chmod +x "$FIXROOT/bin/k3dm-machine-secrets"
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
[ "$1" = show-keychain-info ] && exit 0
if [ "$1" = find-generic-password ] && [ -e "$CALL_LOG.secret-present" ]; then exit 0; fi
exit 1
SH
  cat > "$STUBS/git" <<'SH'
#!/bin/sh
printf 'git %s\n' "$*" >> "$CALL_LOG"
case "$1" in
  -C)
    case "$2" in
      "$HOME/.claude") printf '%s\n' https://github.com/wilddog64/claude-settings.git ;;
      "$HOME/.codex") printf '%s\n' https://github.com/wilddog64/codex-settings.git ;;
      "$HOME/.gemini") printf '%s\n' https://github.com/wilddog64/gemini-config.git ;;
      "$HOME/.copilot") printf '%s\n' https://github.com/wilddog64/copilot-config.git ;;
      *) printf '%s\n' "${REMOTE_FIXTURE:-https://example.test/existing.git}" ;;
    esac
    exit 0 ;;
  ls-remote) exit 0 ;;
  clone) exit 1 ;;
esac
exit 0
SH
  for tool in ruff pytest; do
    printf '#!/bin/sh\nexit 0\n' > "$STUBS/$tool"
  done
  # Read-only stub baseline: m4-air.local, 2026-11-06; python3 3.15.2,
  # pip 26.2.2 at /opt/homebrew/lib/python3.15/site-packages/pip.
  cat > "$STUBS/python3" <<'SH'
#!/bin/sh
printf 'python3 %s\n' "$*" >> "$CALL_LOG"
if [ "$1" = - ]; then exec "$REAL_PYTHON3" "$@"; fi
[ "$1" = -m ] && [ "$2" = venv ] || exit 1
mkdir -p "$3/bin"
cat > "$3/bin/python" <<'VENV'
#!/bin/sh
printf 'venv-python %s\n' "$*" >> "$CALL_LOG"
case "$1" in
  -c) [ -e "$(dirname "$0")/yaml-installed" ] ;;
  -m)
    [ "$2" = pip ] && [ "$3" = install ] || exit 1
    touch "$(dirname "$0")/yaml-installed"
    ;;
  *) exit 1 ;;
esac
for tool in ruff pytest; do
  printf '#!/bin/sh\nexit 0\n' > "$(dirname "$0")/$tool"
  chmod +x "$(dirname "$0")/$tool"
done
VENV
chmod +x "$3/bin/python"
SH
  # Default fixture models an already-complete managed venv.
  local default_venv="$FIXHOME/.local/share/k3d-manager/venv"
  mkdir -p "$default_venv/bin"
  touch "$default_venv/bin/yaml-installed"
  for tool in ruff pytest; do printf '#!/bin/sh\nexit 0\n' > "$default_venv/bin/$tool"; chmod +x "$default_venv/bin/$tool"; done
  cat > "$default_venv/bin/python" <<'VENV'
#!/bin/sh
printf 'venv-python %s\n' "$*" >> "$CALL_LOG"
[ -e "$(dirname "$0")/yaml-installed" ]
VENV
  chmod +x "$default_venv/bin/python"
  cat > "$STUBS/make" <<'SH'
#!/bin/sh
printf 'make %s\n' "$*" >> "$CALL_LOG"
if [ -e "$CALL_LOG.installsmartcd" ]; then mkdir -p "$HOME/.smartcd/lib/core"; : > "$HOME/.smartcd/lib/core/smartcd"; fi
exit 0
SH
  cat > "$STUBS/ssh-keygen" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = -f ]; then key="$2"; shift 2; else shift; fi
done
printf '%s\n' 'PRIVATE-KEY-TEST-MATERIAL' > "$key"
printf '%s\n' 'public-test-key' > "$key.pub"
printf 'ssh-keygen called\n' >> "$CALL_LOG"
SH
  cat > "$STUBS/id" <<'SH'
#!/bin/sh
[ "$1" = -un ] && printf '%s\n' fixture-user
SH
  cat > "$STUBS/scutil" <<'SH'
#!/bin/sh
[ "$1" = --get ] && [ "$2" = LocalHostName ] && printf '%s\n' fixture-hub
SH
  cat > "$STUBS/ssh" <<'SH'
#!/bin/sh
printf 'ssh %s\n' "$*" >> "$CALL_LOG"
exit 1
SH
  chmod +x "$STUBS"/*
  mkdir -p "$FIXHOME/.ssh" "$FIXHOME/.config/k3d-manager"
  printf 'E2E_M2_PUBLISH_BACK_HOST=fixture-user@fixture-hub.local\n' > "$FIXHOME/.config/k3d-manager/e2e-remote.env"
  printf 'from="192.168.39.0/24",command="%s/scripts/k3d-manager e2e_result_publish",restrict,no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding ssh-ed25519 AAAA e2e-m2-publisher@m2-air-20260824\n' "$FIXROOT" > "$FIXHOME/.ssh/authorized_keys"
}

run_machine() {
  run env HOME="$FIXHOME" XDG_CONFIG_HOME="$FIXHOME/.config" XDG_DATA_HOME="${FIX_XDG_DATA_HOME:-$FIXHOME/.local/share}" REAL_PYTHON3="$REAL_PYTHON3" PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" CALL_LOG="$CALL_LOG" GH_STATUS_TEXT="${GH_STATUS_TEXT:-authenticated}" REMOTE_FIXTURE="${REMOTE_FIXTURE:-https://example.test/existing.git}" "$FIXROOT/bin/k3dm-machine-setup" "$@"
}

@test "N1: agents option rejects unsupported values" {
  setup_machine_fixture
  run_machine --role console --agents never
  [ "$status" -eq 2 ]
  [[ "$output" == *'Invalid --agents value: never'* ]]
}

@test "N2: agents install remains the default" {
  setup_machine_fixture
  printf '%s\n' fake-target > "$FIXROOT/scripts/etc/machine/agents.console.list"
  run_machine --role console
  grep -q '^make -C .* fake-target$' "$CALL_LOG"
}

@test "M1/N3: agents skip avoids new installs but preserves installed agents and smartcd" {
  setup_machine_fixture
  printf '%s\n' install-cleanup install-node-health-watch bin/k3dm-webhook-setup smartcd-install > "$FIXROOT/scripts/etc/machine/agents.hub.list"
  for config in claude-settings codex-settings gemini-config copilot-config; do
    case "$config" in
      claude-settings) dir=.claude ;;
      codex-settings) dir=.codex ;;
      gemini-config) dir=.gemini ;;
      copilot-config) dir=.copilot ;;
    esac
    mkdir -p "$FIXHOME/$dir/.git"
  done
  mkdir -p "$FIXHOME/Library/LaunchAgents"
  mkdir -p "$FIXHOME/.local/bin"
  for name in agy gemini; do printf '#!/bin/sh\nexit 0\n' > "$FIXHOME/.local/bin/$name"; chmod +x "$FIXHOME/.local/bin/$name"; done
  : > "$FIXHOME/Library/LaunchAgents/com.k3d-manager.cleanup.plist"
  mkdir -p "$FIXHOME/src/gitrepo/personal/smartcd/.git"
  touch "$CALL_LOG.installsmartcd"
  REMOTE_FIXTURE='https://github.com/cxreg/smartcd.git' run_machine --role hub --agents skip
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
  printf '%s\n' "$output" | grep -Eq '^agent:install-cleanup +ok$'
  [[ "$output" == *'agent:install-node-health-watch'*'skipped (AGENTS=skip)'* ]]
  [[ "$output" == *'agent:bin/k3dm-webhook-setup'*'skipped (AGENTS=skip)'* ]]
  grep -q '^make -C .* install$' "$CALL_LOG"
  run ! grep -q 'install-node-health-watch' "$CALL_LOG"
  run ! grep -q '^bin/k3dm-' "$CALL_LOG"
}

@test "M2: machine-setup forwards AGENTS to the setup command" {
  output="$(make -n machine-setup ROLE=console AGENTS=skip)"
  [[ "$output" == *'--agents "skip"'* ]]
}

@test "M3/M4: hub secrets include Hermes credentials and rotator is excluded" {
  grep -Fqx 'k3dm-hermes-gh-token|k3dm|Hermes R4 CI re-run PAT|operator: see docs/guides/hermes.md' "$MACHINE_DIR/secrets.hub.list"
  grep -Fqx 'k3dm-slack-webhook|k3dm|Hermes Slack summary relay|operator: see docs/guides/hermes.md' "$MACHINE_DIR/secrets.hub.list"
  run ! grep -Fqx install-token-rotator "$MACHINE_DIR"/agents.*.list
  grep -Fq 'install-token-rotator|not installed by setup:' "$MACHINE_DIR/not-installed.list"
}

@test "machine setup: repository manifest paths are unique" {
  duplicates="$(awk -F'|' '!/^#/ && NF > 1 { print $1 }' "$MACHINE_DIR/repos.list" | sort | uniq -d)"
  [ -z "$duplicates" ]
  grep -Fxq 'gitrepo/personal/k3d-manager|https://github.com/wilddog64/k3d-manager.git|main|hub,worker,console,control' "$MACHINE_DIR/repos.list"
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
  run ! grep -Eq '^git (clone|.* (checkout|reset|pull|clean))' "$CALL_LOG"
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
  run ! grep -Eq '^git clone .*smartcd' "$CALL_LOG"
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
  run ! grep -Eq '^git clone .*smartcd' "$CALL_LOG"
}

@test "machine setup: smartcd rejects a different source checkout" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/personal/smartcd/.git"
  REMOTE_FIXTURE='git@github.com:other/smartcd.git'
  printf '%s\n' 'smartcd-install' > "$FIXROOT/scripts/etc/machine/agents.worker.list"
  run_machine --role worker
  grep -Eq '^smartcd[[:space:]]+skipped \(source clone has another remote\)$' <<< "$output"
  run ! grep -Fq "make -C $FIXHOME/src/gitrepo/personal/smartcd install" "$CALL_LOG"
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

publisher_fixture() {
  setup_machine_fixture
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR/"* && "$FIXHOME" != "$HOME" ]]
  rm -f "$FIXHOME/.config/k3d-manager/e2e-remote.env" "$FIXHOME/.ssh/authorized_keys"
  ssh-keygen -q -t ed25519 -N '' -C e2e-m2-publisher@m2-air-20260824 -f "$BATS_TEST_TMPDIR/publisher"
  local public
  public="$(cat "$BATS_TEST_TMPDIR/publisher.pub")"
  cat > "$STUBS/ssh" <<SH
#!/bin/sh
printf 'ssh %s\\n' "\$*" >> "\$CALL_LOG"
# Captured authorized_keys format from m4-air.local, 2026-11-07; key generated for this test.
printf '%s\\n' 'from="192.168.39.0/24",command="/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/k3d-manager e2e_result_publish",restrict,no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding $public'
SH
  chmod +x "$STUBS/ssh"
}

@test "e2e publish-back: hub setup installs both items and second run is byte-identical" {
  publisher_fixture
  run_machine --role hub --from old-hub.local --secrets skip --agents skip
  grep -Eq '^e2e-publish-back-conf +installed$' <<< "$output"
  grep -Eq '^e2e-publish-back-key +installed$' <<< "$output"
  grep -Fxq 'E2E_M2_PUBLISH_BACK_HOST=fixture-user@fixture-hub.local' "$FIXHOME/.config/k3d-manager/e2e-remote.env"
  [ "$(ls -l "$FIXHOME/.config/k3d-manager/e2e-remote.env" | cut -c1-10)" = '-rw-------' ]
  [ "$(grep -c 'e2e-m2-publisher' "$FIXHOME/.ssh/authorized_keys")" -eq 1 ]
  grep -Fq "command=\"$FIXROOT/scripts/k3d-manager e2e_result_publish\"" "$FIXHOME/.ssh/authorized_keys"
  cp "$FIXHOME/.config/k3d-manager/e2e-remote.env" "$BATS_TEST_TMPDIR/conf.before"
  cp "$FIXHOME/.ssh/authorized_keys" "$BATS_TEST_TMPDIR/keys.before"
  run_machine --role hub --from old-hub.local --secrets skip --agents skip
  grep -Eq '^e2e-publish-back-conf +ok$' <<< "$output"
  grep -Eq '^e2e-publish-back-key +ok$' <<< "$output"
  cmp "$BATS_TEST_TMPDIR/conf.before" "$FIXHOME/.config/k3d-manager/e2e-remote.env"
  cmp "$BATS_TEST_TMPDIR/keys.before" "$FIXHOME/.ssh/authorized_keys"
}

@test "e2e publish-back: updates only its own lines and keeps unrelated authorized keys ordered" {
  publisher_fixture
  mkdir -p "$FIXHOME/.ssh" "$FIXHOME/.config/k3d-manager"
  printf 'before\nE2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local\nafter\n' > "$FIXHOME/.config/k3d-manager/e2e-remote.env"
  printf 'ssh-ed25519 AAAA unrelated-one\nfrom="192.0.2.1",no-pty ssh-ed25519 BBBB unrelated-two\nssh-rsa CCCC unrelated-three\nfrom="192.168.39.0/24",command="/old/k3d-manager e2e_result_publish" ssh-ed25519 DDDD e2e-m2-publisher@m2-air-old\n' > "$FIXHOME/.ssh/authorized_keys"
  run_machine --role hub --from old-hub.local --secrets skip --agents skip
  grep -Fxq before "$FIXHOME/.config/k3d-manager/e2e-remote.env"
  grep -Fxq after "$FIXHOME/.config/k3d-manager/e2e-remote.env"
  printf 'ssh-ed25519 AAAA unrelated-one\nfrom="192.0.2.1",no-pty ssh-ed25519 BBBB unrelated-two\nssh-rsa CCCC unrelated-three\n' > "$BATS_TEST_TMPDIR/unrelated.expected"
  head -n 3 "$FIXHOME/.ssh/authorized_keys" > "$BATS_TEST_TMPDIR/unrelated.actual"
  cmp "$BATS_TEST_TMPDIR/unrelated.expected" "$BATS_TEST_TMPDIR/unrelated.actual"
  [ "$(grep -c 'e2e-m2-publisher' "$FIXHOME/.ssh/authorized_keys")" -eq 1 ]
  grep -Fq "command=\"$FIXROOT/scripts/k3d-manager e2e_result_publish\"" "$FIXHOME/.ssh/authorized_keys"
  [[ "$output" == *'updated (was cliang@m4-air.local)'* ]] || { printf '%s\n' "$output"; return 1; }
}

@test "e2e publish-back: check, dry-run, missing source, and other roles do not write publish files" {
  publisher_fixture
  rm -f "$FIXHOME/.config/k3d-manager/e2e-remote.env" "$FIXHOME/.ssh/authorized_keys"
  run_machine --role hub --check --from old-hub.local --secrets skip --agents skip
  [ ! -e "$FIXHOME/.config/k3d-manager/e2e-remote.env" ]
  [ ! -e "$FIXHOME/.ssh/authorized_keys" ]
  run_machine --role hub --dry-run --from old-hub.local --secrets skip --agents skip
  [[ "$output" == *'would write'* ]]
  [ ! -e "$FIXHOME/.config/k3d-manager/e2e-remote.env" ]
  [ ! -e "$FIXHOME/.ssh/authorized_keys" ]
  : > "$CALL_LOG"
  run_machine --role worker --from old-hub.local --secrets skip --agents skip
  run ! grep -q '^ssh .*old-hub.local' "$CALL_LOG"
  [ ! -e "$FIXHOME/.config/k3d-manager/e2e-remote.env" ]
  [ ! -e "$FIXHOME/.ssh/authorized_keys" ]
  run_machine --role hub --secrets skip --agents skip
  [[ "$output" == *'rerun with FROM=<old hub>'* ]]
  [ ! -e "$FIXHOME/.config/k3d-manager/e2e-remote.env" ]
  [ ! -e "$FIXHOME/.ssh/authorized_keys" ]
}

@test "e2e publish-back: malformed old-host key or subnet writes neither item" {
  publisher_fixture
  rm -f "$FIXHOME/.config/k3d-manager/e2e-remote.env" "$FIXHOME/.ssh/authorized_keys"
  local bad_line
  for bad_line in \
    'from="192.168.39.0/24",command="/old/k3d-manager e2e_result_publish" ssh-rsa AAAA e2e-m2-publisher@m2-air-old' \
    'from="192.168.39.0/24;touch /tmp/nope",command="/old/k3d-manager e2e_result_publish" ssh-ed25519 AAAA e2e-m2-publisher@m2-air-old'; do
    cat > "$STUBS/ssh" <<SH
#!/bin/sh
printf '%s\\n' '$bad_line'
SH
    chmod +x "$STUBS/ssh"
    run_machine --role hub --from old-hub.local --secrets skip --agents skip
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid old hub publisher entry'* ]]
    [ ! -e "$FIXHOME/.config/k3d-manager/e2e-remote.env" ]
    [ ! -e "$FIXHOME/.ssh/authorized_keys" ]
  done
}

@test "machine setup: unprefixed brew packages accept either installation type" {
  setup_machine_fixture
  # Exit codes captured 2026-10-31: m5-air.local `brew list --formula azure-cli` 1, `--cask` 0; m4-air `--formula` 0, `--cask` 1.
  cat > "$STUBS/brew" <<'SH'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$CALL_LOG"
case "$*" in
  'list --cask azure-cli') echo 'azure-cli 2.91.0'; exit 0 ;;
  'list --formula formula-package') echo 'formula-package 2.90.0'; exit 0 ;;
  list*) exit 1 ;;
esac
exit 0
SH
  chmod +x "$STUBS/brew"
  printf '%s\n' azure-cli formula-package > "$FIXROOT/scripts/etc/machine/brew.console.list"
  for mode in --check ''; do
    run_machine --role console $mode
    [ "$status" -eq 0 ]
    grep -Eq '^brew:azure-cli[[:space:]]+ok$' <<< "$output"
    grep -Eq '^brew:formula-package[[:space:]]+ok$' <<< "$output"
  done
  run ! grep -q '^brew install' "$CALL_LOG"
}

@test "machine setup: absent and explicitly typed brew packages remain strict" {
  setup_machine_fixture
  cat > "$STUBS/brew" <<'SH'
#!/bin/sh
case "$*" in
  'list --cask azure-cli'|'list --formula formula-package') exit 0 ;;
  list*) exit 1 ;;
esac
exit 0
SH
  chmod +x "$STUBS/brew"
  printf '%s\n' absent formula:azure-cli cask:formula-package > "$FIXROOT/scripts/etc/machine/brew.console.list"
  run_machine --role console --check
  [ "$status" -eq 1 ]
  for name in absent azure-cli formula-package; do
    grep -Eq "^brew:${name}[[:space:]]+missing$" <<< "$output"
  done
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
  run ! grep -q '^brew ' "$CALL_LOG"
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
  run ! grep -Eq '^security .* (-w|--password)( |$)' "$CALL_LOG"
}

@test "machine setup: missing secrets do not prompt without a TTY" {
  setup_machine_fixture
  printf '%s\n' 'fixture|k3dm|purpose|make secret-setup' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  run_machine --role console
  [ "$status" -eq 1 ]
  [[ "$output" == *'secret:fixture'*'missing'* ]]
  [[ "$output" != *'Run setup command now?'* ]]
  run ! grep -q '^make .*secret-setup' "$CALL_LOG"
}

@test "N3: secrets option rejects unsupported values" {
  setup_machine_fixture
  run_machine --role console --secrets never
  [ "$status" -eq 2 ]
}

@test "M3/M4: secrets skip suppresses prompts and setup commands but still pulls" {
  setup_machine_fixture
  printf '%s\n' 'fixture|k3dm|purpose|make secret-setup' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  tty_machine --role console --secrets skip --from old-mac.local
  [ "$(grep -c '^secrets pull --from old-mac.local --role console$' "$CALL_LOG")" -eq 1 ]
  [[ "$output" == *'missing (skipped: SECRETS=skip)'* ]]
  [[ "$output" != *'[y/N]'* ]]
  run ! grep -q '^make secret-setup' "$CALL_LOG"
}

@test "N4: ask remains the default secret behavior" {
  setup_machine_fixture
  printf '%s\n' 'fixture|k3dm|purpose|make secret-setup' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  tty_machine --role console
  [[ "$output" == *'[y/N]'* ]]
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

@test "machine setup: FROM dry-run describes the pull without invoking it" {
  setup_machine_fixture
  printf 'fixture|acct|fixture secret|operator: see docs/howto/machine-setup.md\n' > "$FIXROOT/scripts/etc/machine/secrets.hub.list"
  run_machine --role hub --dry-run --from old-mac.local
  [ "$status" -ne 0 ]
  [[ "$output" == *'would pull secrets from old-mac.local'* ]]
  run ! grep -q '^secrets pull ' "$CALL_LOG"
}

tty_limited() {
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
  ' "$@"
}

tty_machine() {
  command -v script >/dev/null || skip 'script(1) is required for a pseudo-terminal'
  local wrapper="$BATS_TEST_TMPDIR/tty-machine"
  printf '#!/usr/bin/env bash\nexec' > "$wrapper"
  printf ' %q' env HOME="$FIXHOME" XDG_CONFIG_HOME="$FIXHOME/.config" XDG_DATA_HOME="$FIXHOME/.local/share" PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" CALL_LOG="$CALL_LOG" SECRETS_STUB_RC="${SECRETS_STUB_RC:-0}" GH_STATUS_TEXT=authenticated REMOTE_FIXTURE=https://example.test/existing.git "$FIXROOT/bin/k3dm-machine-setup" "$@" >> "$wrapper"
  printf '\n' >> "$wrapper"
  chmod +x "$wrapper"
  if [[ "$(uname -s)" == Darwin ]]; then
    run tty_limited "${TTY_MACHINE_TIMEOUT:-60}" bash -c "/bin/sleep 3 | script -q /dev/null '$wrapper'"
  else
    run tty_limited "${TTY_MACHINE_TIMEOUT:-60}" bash -c "/bin/sleep 3 | script -qec '$wrapper' /dev/null"
  fi
  if [[ "$status" -eq 124 ]]; then printf 'tty_machine %s\n' "$output"; return 1; fi
  [[ "$output" != *'Operation not permitted'* ]] || skip 'sandbox pseudo-terminal does not permit terminal reads'
}

@test "M7: setup with FROM on a terminal pulls once before the per-item checks" {
  setup_machine_fixture
  printf '%s\n' 'fixture|k3dm|purpose|make secret-setup' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  tty_machine --role console --from old-mac.local
  [ "$(grep -c '^secrets pull --from old-mac.local --role console$' "$CALL_LOG")" -eq 1 ]
  pull_line="$(grep -n '^secrets pull ' "$CALL_LOG" | cut -d: -f1)"
  last_check="$(grep -n '^security find-generic-password -s fixture' "$CALL_LOG" | tail -1 | cut -d: -f1)"
  [ "$pull_line" -lt "$last_check" ]
  [[ "$output" != *'Rerun with FROM='* ]]
}

@test "M9: a failed pull is reported and setup still checks every item" {
  setup_machine_fixture
  printf '%s\n' 'fixture|k3dm|purpose|make secret-setup' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  SECRETS_STUB_RC=1 tty_machine --role console --from old-mac.local
  [ "$status" -ne 0 ]
  [[ "$output" == *'secret-pull'*'missing'* ]]
  [[ "$output" == *'secret:fixture'* ]]
}

@test "N9: no pull without FROM, without a terminal, or in check mode" {
  setup_machine_fixture
  printf '%s\n' 'fixture|k3dm|purpose|make secret-setup' > "$FIXROOT/scripts/etc/machine/secrets.console.list"
  tty_machine --role console
  [[ "$output" == *'Rerun with FROM=<old Mac hostname>'* ]]
  run_machine --role console --from old-mac.local
  run_machine --role console --check --from old-mac.local
  run ! grep -q '^secrets pull' "$CALL_LOG"
  run ! grep -q '^ssh ' "$CALL_LOG"
}

@test "machine setup: safety N3 worker rejects hub installers" {
  setup_machine_fixture
  printf '%s\n' 'install-cleanup' > "$FIXROOT/scripts/etc/machine/agents.worker.list"
  run_machine --role worker
  [ "$status" -eq 1 ]
  [[ "$output" == *'skipped (hub only)'* ]]
  run ! grep -Eq '^make .*install-cleanup' "$CALL_LOG"
}

@test "machine setup: safety N5 leaves existing clone untouched" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/existing/.git"
  printf '%s\n' 'gitrepo/existing|https://example.test/existing.git|-|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  run_machine --role console
  [ "$status" -eq 0 ]
  [[ "$output" == *'repo:gitrepo/existing'*'ok'* ]]
  run ! grep -Eq '^git (clone|.* (checkout|reset|pull|clean))' "$CALL_LOG"
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

@test "machine setup: Python tools on PATH still populate the managed venv" {
  setup_machine_fixture
  rm -rf "$FIXHOME/.local/share/k3d-manager/venv"
  run_machine --role console
  [ "$status" -eq 0 ]
  grep -Fq 'PyYAML==6.0.3' "$CALL_LOG"
  [ -e "$FIXHOME/.local/share/k3d-manager/venv/bin/yaml-installed" ]
}

@test "machine setup: an existing data-dir virtualenv is recognized" {
  setup_machine_fixture
  rm "$STUBS/ruff" "$STUBS/pytest"
  mkdir -p "$FIXHOME/.local/share/k3d-manager/venv/bin"
  for tool in ruff pytest; do touch "$FIXHOME/.local/share/k3d-manager/venv/bin/$tool"; chmod +x "$FIXHOME/.local/share/k3d-manager/venv/bin/$tool"; done
  cat > "$FIXHOME/.local/share/k3d-manager/venv/bin/python" <<'SH'
#!/bin/sh
printf 'venv-python %s\n' "$*" >> "$CALL_LOG"
[ -e "$(dirname "$0")/yaml-installed" ]
SH
  chmod +x "$FIXHOME/.local/share/k3d-manager/venv/bin/python"
  touch "$FIXHOME/.local/share/k3d-manager/venv/bin/yaml-installed"
  run_machine --role console --check
  [ "$status" -eq 0 ]
  grep -Eq '^python-tools[[:space:]]+ok$' <<< "$output"
  run ! grep -q 'pip install' "$CALL_LOG"
}

@test "machine setup: missing Python tools are reported read-only" {
  setup_machine_fixture
  rm "$STUBS/ruff" "$STUBS/pytest"
  rm -rf "$FIXHOME/.local/share/k3d-manager/venv"
  for mode in --check --dry-run; do
    run_machine --role console "$mode"
    if [ "$status" -ne 1 ] || ! grep -Eq '^python-tools[[:space:]]+missing$' <<< "$output"; then printf '%s\n' "$output"; return 1; fi
  done
  run ! grep -Eq '^(python3|venv-python) ' "$CALL_LOG"
  [ ! -e "$FIXHOME/.local/share/k3d-manager/venv" ]
  [ ! -e "$FIXROOT/.venv" ]
}

@test "machine setup: Python tools install outside the repository and second setup is idle" {
  setup_machine_fixture
  rm "$STUBS/ruff" "$STUBS/pytest"
  rm -rf "$FIXHOME/.local/share/k3d-manager/venv"
  run_machine --role console
  [ "$status" -eq 0 ]
  grep -Fq 'installed (add ~/.local/share/k3d-manager/venv/bin to PATH)' <<< "$output"
  [ -x "$FIXHOME/.local/share/k3d-manager/venv/bin/ruff" ]
  [ -x "$FIXHOME/.local/share/k3d-manager/venv/bin/pytest" ]
  [ -e "$FIXHOME/.local/share/k3d-manager/venv/bin/yaml-installed" ]
  [ ! -e "$FIXROOT/.venv" ]
  grep -Fq 'venv-python -m pip install pytest==9.1.1 ruff==0.15.8 PyYAML==6.0.3' "$CALL_LOG"
  : > "$CALL_LOG"
  run_machine --role console
  [ "$status" -eq 0 ]
  grep -Eq '^python-tools[[:space:]]+ok$' <<< "$output"
  run ! grep -q 'pip install' "$CALL_LOG"
}

@test "M1 and N2: existing tool executables get pinned PyYAML; complete venv is idle" {
  setup_machine_fixture
  rm -rf "$FIXHOME/.local/share/k3d-manager/venv"
  rm "$STUBS/ruff" "$STUBS/pytest"
  local venv="$FIXHOME/.local/share/k3d-manager/venv"
  mkdir -p "$venv/bin"
  for tool in ruff pytest; do printf '#!/bin/sh\nexit 0\n' > "$venv/bin/$tool"; chmod +x "$venv/bin/$tool"; done
  cat > "$venv/bin/python" <<'SH'
#!/bin/sh
printf 'venv-python %s\n' "$*" >> "$CALL_LOG"
if [ "$1" = -c ]; then
  if [ -e "$(dirname "$0")/yaml-installed" ]; then exit 0; else exit 1; fi
fi
if [ "$1" = -m ] && [ "$2" = pip ] && [ "$3" = install ]; then
  case " $* " in *' PyYAML==6.0.3 '*) touch "$(dirname "$0")/yaml-installed"; exit 0 ;; esac
fi
exit 1
SH
  chmod +x "$venv/bin/python"
  # Assert the target venv resolves inside the scratch HOME before invoking setup.
  [[ "$venv" == "$FIXHOME"/* && "$FIXROOT" == "$BATS_TEST_TMPDIR"/* ]]
  run_machine --role console
  [ "$status" -eq 0 ]
  [ -e "$venv/bin/yaml-installed" ]
  grep -Fq 'PyYAML==6.0.3' "$CALL_LOG"
  : > "$CALL_LOG"
  run_machine --role console
  [ "$status" -eq 0 ]
  grep -Eq '^python-tools[[:space:]]+ok$' <<< "$output"
  run ! grep -q 'pip install' "$CALL_LOG"
}

@test "M2 and N1: check reports missing yaml without changing scratch venv" {
  setup_machine_fixture
  rm -rf "$FIXHOME/.local/share/k3d-manager/venv"
  rm "$STUBS/ruff" "$STUBS/pytest"
  local venv="$FIXHOME/.local/share/k3d-manager/venv"
  mkdir -p "$venv/bin"
  for tool in ruff pytest; do printf '#!/bin/sh\nexit 0\n' > "$venv/bin/$tool"; chmod +x "$venv/bin/$tool"; done
  cat > "$venv/bin/python" <<'SH'
#!/bin/sh
printf 'venv-python %s\n' "$*" >> "$CALL_LOG"
exit 1
SH
  chmod +x "$venv/bin/python"
  [[ "$venv" == "$FIXHOME"/* && "$FIXROOT" == "$BATS_TEST_TMPDIR"/* ]]
  cp -R "$venv" "$BATS_TEST_TMPDIR/venv-before"
  run_machine --role console --check
  [ "$status" -eq 1 ]
  grep -Eq '^python-tools[[:space:]]+missing$' <<< "$output"
  diff -r "$BATS_TEST_TMPDIR/venv-before" "$venv"
  run ! grep -q 'pip install' "$CALL_LOG"
}

@test "M3: rendered test-metrics plist puts managed venv first on PATH" {
  setup_machine_fixture
  local rendered="$BATS_TEST_TMPDIR/test-metrics.plist"
  local template="$REPO_ROOT/scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl"
  sed -e "s|{{K3DM_REPO_ROOT}}|$FIXROOT|g" -e "s|{{HOME}}|$FIXHOME|g" \
    "$template" > "$rendered"
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR"/* && "$FIXROOT" == "$BATS_TEST_TMPDIR"/* ]]
  grep -A1 '<key>PATH</key>' "$rendered" | grep -Fq "<string>${FIXHOME}/.local/share/k3d-manager/venv/bin:"
  run ! grep -q '{{HOME}}' "$rendered"
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
  rm -rf "$FIXHOME/.local/share/k3d-manager/venv"
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

@test "machine setup: manifest loops keep stdin for children that read it" {
  setup_machine_fixture
  cat > "$STUBS/brew" <<'SH'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$CALL_LOG"
[ "$1" = list ] && exit 1
cat >/dev/null
exit 0
SH
  cat > "$STUBS/make" <<'SH'
#!/bin/sh
printf 'make %s\n' "$*" >> "$CALL_LOG"
cat >/dev/null
exit 0
SH
  chmod +x "$STUBS/brew" "$STUBS/make"
  printf '%s\n' one two cask:three > "$FIXROOT/scripts/etc/machine/brew.console.list"
  printf '%s\n' target-a target-b target-c > "$FIXROOT/scripts/etc/machine/agents.console.list"
  run_machine --role console </dev/null
  [[ "$output" == *'brew:one'*'installed'* ]] || { printf '%s\n' "$output"; return 1; }
  [[ "$output" == *'brew:two'*'installed'* ]] || { printf '%s\n' "$output"; return 1; }
  [[ "$output" == *'brew:three'*'installed'* ]] || { printf '%s\n' "$output"; return 1; }
  [[ "$output" == *'agent:target-c'*'installed'* ]] || { printf '%s\n' "$output"; return 1; }
  [ "$(grep -c '^brew install' "$CALL_LOG")" -eq 3 ]
}

@test "machine setup: no manifest loop reads its list on stdin" {
  run grep -nE 'done < "\$\{manifest_dir\}' "$SCRIPT_SOURCE"
  [ "$status" -eq 1 ]
}

@test "machine setup: failed install output goes to the setup log, not the report" {
  setup_machine_fixture
  cat > "$STUBS/brew" <<'SH'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$CALL_LOG"
[ "$1" = list ] && exit 1
echo "Error: fixture install failure for $2"
exit 1
SH
  chmod +x "$STUBS/brew"
  printf '%s\n' broken > "$FIXROOT/scripts/etc/machine/brew.console.list"
  run_machine --role console
  [ "$status" -eq 1 ]
  [[ "$output" == *'brew:broken'*'missing (see machine-setup.log)'* ]] || { printf '%s\n' "$output"; return 1; }
  [[ "$output" != *'fixture install failure'* ]]
  [[ "$output" != *"$FIXHOME"* ]]
  grep -q 'fixture install failure for broken' "$FIXHOME/.local/state/k3d-manager/machine-setup.log"
  [ -n "$(find "$FIXHOME/.local/state/k3d-manager/machine-setup.log" -perm 600)" ]
}

@test "machine setup: check mode writes no setup log" {
  setup_machine_fixture
  printf '%s\n' absent > "$FIXROOT/scripts/etc/machine/brew.console.list"
  run_machine --role console --check
  [ ! -e "$FIXHOME/.local/state/k3d-manager/machine-setup.log" ]
}

files_fixture() {
  setup_machine_fixture
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR"/* && "$FIXHOME" != "$HOME" ]]
  printf '%s\n' '# fixture' '.cloudflared/tunnel.json' '.cloudflared/cert.pem' > "$FIXROOT/scripts/etc/machine/files.hub.list"
  cat > "$STUBS/scp" <<'SH'
#!/bin/sh
printf 'scp %s\n' "$*" >> "$CALL_LOG"
[ -z "$SCP_FAIL" ] || { : > "$(eval echo \${$#})"; exit 1; }
for last; do :; done
printf 'copied-fixture\n' > "$last"
SH
  chmod +x "$STUBS/scp"
}

@test "files: FROM copies each missing hub file from the old Mac with private modes" {
  files_fixture
  run_machine --role hub --from old-mac.local
  [ "$(grep -c '^scp ' "$CALL_LOG")" -eq 2 ]
  grep -q '^scp -q -o ConnectTimeout=10 -- old-mac.local:.cloudflared/tunnel.json ' "$CALL_LOG"
  grep -q '^scp -q -o ConnectTimeout=10 -- old-mac.local:.cloudflared/cert.pem ' "$CALL_LOG"
  [ "$(cat "$FIXHOME/.cloudflared/tunnel.json")" = copied-fixture ]
  [ "$(ls -l "$FIXHOME/.cloudflared/tunnel.json" | cut -c1-10)" = '-rw-------' ]
  [ "$(ls -ld "$FIXHOME/.cloudflared" | cut -c1-10)" = 'drwx------' ]
  [[ "$output" == *'file:~/.cloudflared/cert.pem'*'copied from old-mac.local'* ]]
  run ls "$FIXHOME/.cloudflared"
  [[ "$output" != *k3dm-partial* ]]
}

@test "files: a file already present is kept and never copied over" {
  files_fixture
  mkdir -p "$FIXHOME/.cloudflared"
  printf 'existing\n' > "$FIXHOME/.cloudflared/tunnel.json"
  run_machine --role hub --from old-mac.local
  [ "$(cat "$FIXHOME/.cloudflared/tunnel.json")" = existing ]
  run grep -c '^scp .*tunnel.json' "$CALL_LOG"
  [ "$output" = 0 ]
  grep -q '^scp .*cert.pem' "$CALL_LOG"
}

@test "files: a failed copy leaves no file or partial and fails the run" {
  files_fixture
  SCP_FAIL=1 run_machine --role hub --from old-mac.local
  [ "$status" -ne 0 ]
  [[ "$output" == *'file:~/.cloudflared/tunnel.json'*'copy from old-mac.local failed'* ]]
  [ ! -e "$FIXHOME/.cloudflared/tunnel.json" ]
  [ ! -e "$FIXHOME/.cloudflared/tunnel.json.k3dm-partial" ]
}

@test "files: no copy without FROM, in check mode, or in dry-run" {
  files_fixture
  run_machine --role hub
  [ "$status" -ne 0 ]
  [[ "$output" == *'file:~/.cloudflared/tunnel.json'*'rerun with FROM='* ]]
  run_machine --role hub --check --from old-mac.local
  [ "$status" -ne 0 ]
  run_machine --role hub --dry-run --from old-mac.local
  [[ "$output" == *'would copy from old-mac.local'* ]]
  run grep -c '^scp ' "$CALL_LOG"
  [ "$output" = 0 ]
  [ ! -e "$FIXHOME/.cloudflared" ]
}

@test "files: a path that leaves HOME is rejected without copying" {
  files_fixture
  printf '%s\n' '../outside.json' '/etc/hosts' > "$FIXROOT/scripts/etc/machine/files.hub.list"
  run_machine --role hub --from old-mac.local
  [ "$status" -ne 0 ]
  [ "$(grep -c 'rejected (bad path)' <<< "$output")" -eq 2 ]
  run grep -c '^scp ' "$CALL_LOG"
  [ "$output" = 0 ]
}

@test "files: the hub manifest names the tunnel credentials cloudflared is configured to read" {
  creds="$(awk '$1 == "credentials-file:" {print $2}' "$REPO_ROOT/scripts/etc/cloudflared/config.yml")"
  [ -n "$creds" ]
  grep -Fqx ".cloudflared/${creds##*/}" "$MACHINE_DIR/files.hub.list"
  grep -Fqx '.cloudflared/cert.pem' "$MACHINE_DIR/files.hub.list"
}

@test "files and secrets: the hub manifests carry what the hub-data export and platform-ops need" {
  grep -Fqx '.ssh/k3dm-hub-data-write' "$MACHINE_DIR/files.hub.list"
  grep -Fqx '.ssh/k3dm-hub-data-write.pub' "$MACHINE_DIR/files.hub.list"
  grep -Fqx '.ssh/config.d/operator' "$MACHINE_DIR/files.hub.list"
  grep -q '^platform-ops-app-rebuild|k3dm|' "$MACHINE_DIR/secrets.hub.list"
  grep -q '^platform-ops-git-writer|k3dm|' "$MACHINE_DIR/secrets.hub.list"
}

@test "files: operator fragment installs Include once and preserves backup" {
  files_fixture
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR"/* && "$FIXHOME" != "$HOME" ]]
  printf '%s\n' '.ssh/config.d/operator' > "$FIXROOT/scripts/etc/machine/files.hub.list"
  mkdir -p "$FIXHOME/.ssh"
  printf 'Host example\n  User example\n' > "$FIXHOME/.ssh/config"
  run_machine --role hub --from old-mac.local
  [[ "$output" == *"file:~/.ssh/config.d/operator"* ]]
  [ "$(head -1 "$FIXHOME/.ssh/config")" = 'Include ~/.ssh/config.d/operator' ]
  [ "$(ls -l "$FIXHOME/.ssh/config" | cut -c1-10)" = '-rw-------' ]
  printf 'Host example\n  User example\n' > "$BATS_TEST_TMPDIR/expected-backup"
  cmp "$BATS_TEST_TMPDIR/expected-backup" "$FIXHOME/.ssh/config.pre-machine-setup"
  cp "$FIXHOME/.ssh/config" "$BATS_TEST_TMPDIR/expected-config"
  run_machine --role hub --from old-mac.local
  [[ "$output" == *"file:~/.ssh/config.d/operator"* ]]
  cmp "$BATS_TEST_TMPDIR/expected-config" "$FIXHOME/.ssh/config"
  cmp "$BATS_TEST_TMPDIR/expected-backup" "$FIXHOME/.ssh/config.pre-machine-setup"
  [ "$(grep -Fxc 'Include ~/.ssh/config.d/operator' "$FIXHOME/.ssh/config")" -eq 1 ]
}

@test "files: existing operator fragment creates missing ssh config" {
  files_fixture
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR"/* && "$FIXHOME" != "$HOME" ]]
  printf '%s\n' '.ssh/config.d/operator' > "$FIXROOT/scripts/etc/machine/files.hub.list"
  mkdir -p "$FIXHOME/.ssh/config.d"
  printf 'fixture\n' > "$FIXHOME/.ssh/config.d/operator"
  run_machine --role hub --from old-mac.local
  [[ "$output" == *"file:~/.ssh/config.d/operator"* ]]
  [ "$(cat "$FIXHOME/.ssh/config")" = 'Include ~/.ssh/config.d/operator' ]
  [ ! -e "$FIXHOME/.ssh/config.pre-machine-setup" ]
}

@test "remote switching: authenticated SSH switches managed origins and restores failed probes" {
  setup_machine_fixture
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR/"* ]]
  mkdir -p "$FIXHOME/src/a/.git" "$FIXHOME/src/b/.git" "$FIXHOME/src/other/.git"
  printf '%s\n' 'a|https://github.com/wilddog64/a.git|-|console' 'b|https://github.com/wilddog64/b.git|-|console' 'other|https://github.com/cxreg/other.git|-|console' > "$FIXROOT/scripts/etc/machine/repos.list"
  cat > "$STUBS/ssh" <<'SH'
#!/bin/sh
# Captured on m4-air.local, 2026-10-31T19:53:21Z:
# ssh -o BatchMode=yes -o ConnectTimeout=10 -T git@github.com (exit 1).
echo "Hi wilddog64! You've successfully authenticated, but GitHub does not provide shell access."
exit 1
SH
  cat > "$STUBS/git" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CALL_LOG"
[ "$1" = -C ] || exit 0
case "$3 $4" in
  'remote get-url') case "$2" in */other) echo https://github.com/cxreg/other.git ;; *) echo "https://github.com/wilddog64/${2##*/}.git" ;; esac ;;
  'ls-remote origin') case "$2" in */b) exit 1 ;; esac ;;
esac
SH
  chmod +x "$STUBS/ssh" "$STUBS/git"
  run_machine --role console
  [ "$status" -eq 1 ]
  [[ "$output" == *'remote:~/src/a'*'switched to ssh'* ]]
  [[ "$(printf '%s\n' "$output" | grep '^remote:')" != *"$FIXHOME"* ]]
  grep -Fq 'remote set-url origin git@github.com:wilddog64/a.git' "$CALL_LOG"
  grep -Fq 'remote set-url origin https://github.com/wilddog64/b.git' "$CALL_LOG"
  run ! grep -Fq 'set-url origin git@github.com:cxreg' "$CALL_LOG"
  run_machine --role console --check
  [ "$status" -eq 1 ]
  [[ "$output" == *'https (SSH available)'* ]]
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/ssh"
  run_machine --role console
  [ "$status" -eq 0 ]
  [[ "$output" == *'https (no GitHub SSH key yet)'* ]]
}

@test "completion permissions: check reports and setup repairs home only" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/.zplug" "$BATS_TEST_TMPDIR/brew/share/zsh"
  touch "$FIXHOME/.zplug/insecure" "$BATS_TEST_TMPDIR/brew/share/zsh/insecure"
  chmod 777 "$FIXHOME/.zplug/insecure" "$BATS_TEST_TMPDIR/brew/share/zsh/insecure"
  printf '#!/bin/sh\n[ "$1" != --prefix ] || echo "%s"\n' "$BATS_TEST_TMPDIR/brew" > "$STUBS/brew"
  run_machine --role console --check
  [ "$status" -eq 1 ]
  [[ "$output" == *'~/.zplug/insecure'* ]]
  [[ "$(printf '%s\n' "$output" | grep '^zsh:completion-dirs')" != *"$FIXHOME"* ]]
  run_machine --role console
  [ "$status" -eq 1 ]
  [ "$(/usr/bin/python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$FIXHOME/.zplug/insecure")" = 0o755 ]
  [ "$(/usr/bin/python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$BATS_TEST_TMPDIR/brew/share/zsh/insecure")" = 0o777 ]
  chmod 755 "$BATS_TEST_TMPDIR/brew/share/zsh/insecure"
  run_machine --role console --check
  [ "$status" -eq 0 ]
  [[ "$output" == *'zsh:completion-dirs'*'ok'* ]]
}

@test "linked SSH config keeps its link and receives one Include" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/.ssh/config.d"
  echo existing > "$FIXHOME/ssh-target"
  ln -s "$FIXHOME/ssh-target" "$FIXHOME/.ssh/config"
  echo fragment > "$FIXHOME/.ssh/config.d/operator"
  echo .ssh/config.d/operator > "$FIXROOT/scripts/etc/machine/files.console.list"
  run_machine --role console
  [ "$status" -eq 0 ]
  [ -L "$FIXHOME/.ssh/config" ]
  [ "$(grep -c '^Include ~/.ssh/config.d/operator$' "$FIXHOME/ssh-target")" -eq 1 ]
}

@test "login shell check invokes an interactive login shell and detects captured errors" {
  setup_machine_fixture
  rm "$STUBS/python3"
  cat > "$STUBS/ssh" <<'SH'
#!/bin/sh
# Login messages reported by the operator on the M5, 2026-10-31.
printf '%s\n' "$*" > "$SSH_CALL"
[ "$5" = '$SHELL -lic exit' ] || exit 42
printf '%s\n' "${SHELL_FIXTURE:-clean}"
SH
  chmod +x "$STUBS/ssh"
  local message
  for message in "Username for 'https://github.com': " 'zsh compinit: insecure directories, run compaudit for list.' 'compdef: command not found' '_main_complete:412: _lastcomp: assignment to invalid subscript range'; do
    run env PATH="$STUBS:/usr/bin:/bin" SSH_CALL="$CALL_LOG" SHELL_FIXTURE="$message" "$FIXROOT/bin/k3dm-machine-setup" --check-shell fixture
    [ "$status" -eq 1 ]
    [[ "$output" == *"$message"* || "$output" == *"${message% }"* ]]
    grep -Fxq -- '-tt -o BatchMode=yes fixture $SHELL -lic exit' "$CALL_LOG"
  done
  run env PATH="$STUBS:/usr/bin:/bin" SSH_CALL="$CALL_LOG" HOME="$FIXHOME" SHELL_FIXTURE="command not found $FIXHOME/secret ghp_abcdefghijklmnopqrstuvwxyz123456" "$FIXROOT/bin/k3dm-machine-setup" --check-shell fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *'~/secret'* && "$output" != *"$FIXHOME"* && "$output" != *'ghp_abc'* ]]
  run env PATH="$STUBS:/usr/bin:/bin" SSH_CALL="$CALL_LOG" "$FIXROOT/bin/k3dm-machine-setup" --check-shell fixture
  [ "$status" -eq 0 ]
  # zplug banner on a clean login, captured on m5-air.local and m2-air.local, 2026-10-31.
  run env PATH="$STUBS:/usr/bin:/bin" SSH_CALL="$CALL_LOG" SHELL_FIXTURE=$'[zplug] \e[33mRun compinit\e[00m' "$FIXROOT/bin/k3dm-machine-setup" --check-shell fixture
  [ "$status" -eq 0 ]
  run env SSH_CALL="$CALL_LOG" "$STUBS/ssh" -tt -o BatchMode=yes fixture exit
  [ "$status" -eq 42 ]
}

@test "login shell check times out and validates its timeout" {
  setup_machine_fixture
  rm "$STUBS/python3"
  printf '#!/bin/sh\nexec sleep 5\n' > "$STUBS/ssh"
  chmod +x "$STUBS/ssh"
  run env PATH="$STUBS:/usr/bin:/bin" K3DM_CHECK_SHELL_TIMEOUT=2 "$FIXROOT/bin/k3dm-machine-setup" --check-shell fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *'timed out'* ]]
  for value in 0 -1 abc 1.5 ''; do
    run env PATH="$STUBS:/usr/bin:/bin" K3DM_CHECK_SHELL_TIMEOUT="$value" "$FIXROOT/bin/k3dm-machine-setup" --check-shell fixture
    [ "$status" -eq 2 ]
  done
}

@test "completion permissions ignore symlinks" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/.zplug"
  (umask 000; ln -s missing "$FIXHOME/.zplug/link")
  if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
    link_mode="$(/usr/bin/stat -f %Lp "$FIXHOME/.zplug/link")"
  else
    link_mode="$(/usr/bin/stat -c %a "$FIXHOME/.zplug/link")"
  fi
  [ "$link_mode" != 755 ] || skip "platform gives symlinks mode 755"
  [ "$link_mode" = 777 ]
  run_machine --role console --check
  [ "$status" -eq 0 ]
  [[ "$output" == *'zsh:completion-dirs'*'ok'* ]]
}

@test "linked SSH config with unwritable target is preserved" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/.ssh/config.d"
  echo existing > "$FIXHOME/ssh-target"
  cp "$FIXHOME/ssh-target" "$BATS_TEST_TMPDIR/snapshot"
  chmod 444 "$FIXHOME/ssh-target"
  ln -s "$FIXHOME/ssh-target" "$FIXHOME/.ssh/config"
  echo fragment > "$FIXHOME/.ssh/config.d/operator"
  echo .ssh/config.d/operator > "$FIXROOT/scripts/etc/machine/files.console.list"
  run_machine --role console
  [ "$status" -eq 0 ]
  [[ "$output" == *"ssh:config"*"skipped (linked; add the Include in ~/ssh-target)"* ]]
  [ -L "$FIXHOME/.ssh/config" ]
  cmp "$FIXHOME/ssh-target" "$BATS_TEST_TMPDIR/snapshot"
}

@test "foreign shell links are reported and preserved" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/src/gitrepo/personal/zshdotfiles" "$FIXHOME/elsewhere"
  for name in .zsh .zshrc .zshenv; do ln -s "$FIXHOME/elsewhere" "$FIXHOME/$name"; done
  run_machine --role worker
  [ "$status" -eq 1 ]
  for name in .zsh .zshrc .zshenv; do
    [[ "$output" == *"shell:$name"*"skipped (linked elsewhere: ~/elsewhere)"* ]]
    [ "$(readlink "$FIXHOME/$name")" = "$FIXHOME/elsewhere" ]
  done
}

@test "tty_machine: timeout kills the fixture and a short command completes" {
  local TTY_MACHINE_TIMEOUT=5
  setup_machine_fixture
  [[ "$FIXROOT" == "$BATS_TEST_TMPDIR"/* && "$FIXROOT/bin/k3dm-machine-setup" != "$SCRIPT_SOURCE" ]]
  cat > "$FIXROOT/bin/k3dm-machine-setup" <<'SH'
#!/bin/sh
printf '%s\n' "$$" > "$CALL_LOG.pid"
exec sleep 300
SH
  chmod +x "$FIXROOT/bin/k3dm-machine-setup"
  run tty_machine --role console
  [ "$status" -ne 0 ]
  [[ "$output" == *"timed out after ${TTY_MACHINE_TIMEOUT:-60}s"* ]]
  run kill -0 "$(cat "$CALL_LOG.pid")"
  [ "$status" -ne 0 ]
  printf '#!/bin/sh\nsleep 1\necho fixture-complete\n' > "$FIXROOT/bin/k3dm-machine-setup"
  tty_machine --role console
  [ "$status" -eq 0 ]
  [[ "$output" == *fixture-complete* ]]
}

@test "machine setup: AI CLI manifests select the correct packages" {
  for role in hub worker; do
    grep -Fxq 'cask:antigravity-cli' "$MACHINE_DIR/brew.$role.list"
    grep -Fxq 'cask:antigravity' "$MACHINE_DIR/brew.$role.list"
  done
  run grep -Exq 'gemini-cli|cask:gemini' "$MACHINE_DIR"/brew.hub.list "$MACHINE_DIR"/brew.worker.list "$MACHINE_DIR"/brew.console.list
  [ "$status" -eq 1 ]
}

@test "machine setup: AI CLI checks use webhook PATH for hub and worker without invoking tools" {
  setup_machine_fixture
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR/"* && "$STUBS/brew" == "$BATS_TEST_TMPDIR/"* ]]
  [ -x "$STUBS/brew" ]
  # Replace only the fixed system directories in the copied script, so host-installed
  # CLIs cannot affect the missing case; the HOME component remains unchanged.
  local fixed="$BATS_TEST_TMPDIR/webhook-system" role name
  mkdir -p "$fixed" "$FIXHOME/.local/bin"
  sed "s|/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin|$fixed|" "$SCRIPT_SOURCE" > "$FIXROOT/bin/k3dm-machine-setup"
  grep -Fq '{{HOME}}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin' "$REPO_ROOT/scripts/etc/launchd/com.k3d-manager.webhook.plist.tmpl"
  for name in agy gemini; do
    printf '#!/bin/sh\nprintf "%s %%s\\n" "$*" >> "$CALL_LOG"\n' "$name" > "$STUBS/$name"
    chmod +x "$STUBS/$name"
  done
  for role in hub worker; do
    run_machine --role "$role" --check --secrets skip --agents skip
    grep -Eq "^ai:agy[[:space:]]+missing$" <<< "$output"
    grep -Eq "^ai:gemini[[:space:]]+skipped \(optional; deprecated\)$" <<< "$output"
    cp "$STUBS/agy" "$STUBS/gemini" "$FIXHOME/.local/bin/"
    run_machine --role "$role" --check --secrets skip --agents skip
    for name in agy gemini; do grep -Eq "^ai:${name}[[:space:]]+ok$" <<< "$output"; done
    run_machine --role "$role" --secrets skip --agents skip
    for name in agy gemini; do grep -Eq "^ai:${name}[[:space:]]+ok$" <<< "$output"; done
    rm "$FIXHOME/.local/bin/agy" "$FIXHOME/.local/bin/gemini"
  done
  grep -q "^brew " "$CALL_LOG"
  run grep -Eq '^(brew uninstall|agy |gemini |security find-generic-password)' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "machine setup: login Keychain status uses exit code without reading values" {
  setup_machine_fixture
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR/"* && "$STUBS" == "$BATS_TEST_TMPDIR/"* ]]
  printf 'fixture|k3dm|test|operator:test\n' > "$FIXROOT/scripts/etc/machine/secrets.hub.list"
  cat > "$STUBS/security" <<'SH'
#!/bin/sh
printf 'security %s\n' "$*" >> "$CALL_LOG"
case "$1" in
  # m5-air.local, 2026-11-01: operator's unlocked local Terminal capture.
  show-keychain-info) if [ -e "$CALL_LOG.locked" ]; then
    # m4-air.local and m5-air.local, 2026-11-01: SSH capture, rc 36.
    echo 'security: SecKeychainCopySettings: User interaction is not allowed.' >&2; exit 36
  fi; printf 'Keychain "%s/Library/Keychains/login.keychain-db" no-timeout\n' "$HOME"; exit 0 ;;
  find-generic-password) exit 0 ;;
esac
exit 1
SH
  chmod +x "$STUBS/security"
  run_machine --role hub --check
  [[ "$output" == *'keychain:login'*'ok'* ]]
  touch "$CALL_LOG.locked"
  for mode in check setup; do
    if [[ "$mode" == check ]]; then run_machine --role hub --check
    else run_machine --role hub; fi
    [ "$status" -ne 0 ]
    [[ "$output" == *'keychain:login'*'locked (reads will fail'* ]]
  done
  run grep -E 'security .* -(w|g)( |$)|security unlock-keychain' "$CALL_LOG"
  [ "$status" -eq 1 ]
  [[ "$output" != *SECRETVALUE_LEAK* ]]
}

@test "machine setup: heartbeat renders candidates without loading and reports render failures" {
  setup_machine_fixture
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR/"* && "$STUBS" == "$BATS_TEST_TMPDIR/"* && "$FIXROOT" == "$BATS_TEST_TMPDIR/"* ]]
  printf '%s\n' bin/k3dm-heartbeat-setup > "$FIXROOT/scripts/etc/machine/agents.hub.list"
  cat > "$FIXROOT/bin/k3dm-heartbeat-setup" <<'SH'
#!/bin/bash
printf 'heartbeat-render %s\n' "$*" >> "$CALL_LOG"
[ ! -e "$CALL_LOG.fail-render" ] || exit 1
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output-dir ]; then mkdir -p "$2"; touch "$2/com.k3d-manager.heartbeat.plist"; break; fi
  shift
done
SH
  chmod +x "$FIXROOT/bin/k3dm-heartbeat-setup"
  printf '#!/bin/sh\nprintf "launchctl %%s\\n" "$*" >> "$CALL_LOG"\n' > "$STUBS/launchctl"
  chmod +x "$STUBS/launchctl"
  tty_machine --role hub
  [[ "$output" == *'agent:bin/k3dm-heartbeat-setup'*'not loaded (optional;'* ]]
  [ -f "$FIXHOME/.local/share/k3d-manager/heartbeat-candidates/com.k3d-manager.heartbeat.plist" ]
  [ ! -e "$FIXHOME/Library/LaunchAgents/com.k3d-manager.heartbeat.plist" ]
  run grep -q '^launchctl ' "$CALL_LOG"
  [ "$status" -eq 1 ]
  rm "$FIXHOME/.local/share/k3d-manager/heartbeat-candidates/com.k3d-manager.heartbeat.plist"
  touch "$CALL_LOG.fail-render"
  tty_machine --role hub
  [ "$status" -ne 0 ]
  [[ "$output" == *'agent:bin/k3dm-heartbeat-setup'*'missing (candidate render failed)'* ]]
  [ ! -e "$FIXHOME/Library/LaunchAgents/com.k3d-manager.heartbeat.plist" ]
  run grep -q '^launchctl ' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "machine setup: hub credentials are checked and missing role map triggers FROM pull" {
  setup_machine_fixture
  cp "$MACHINE_DIR/secrets.hub.list" "$FIXROOT/scripts/etc/machine/secrets.hub.list"
  # macOS security find-generic-password exits 44 for a missing item (m4-air.local, 2026-11-01; spec observation).
  cat > "$STUBS/security" <<'SH'
#!/bin/sh
printf 'security %s\n' "$*" >> "$CALL_LOG"
[ "$1" = show-keychain-info ] && exit 0
[ -e "$CALL_LOG.present" ] && exit 0
exit 44
SH
  chmod +x "$STUBS/security"
  run_machine --role hub --check
  [ "$status" -ne 0 ]
  while IFS='|' read -r service account _; do
    [[ -n "$service" && "$service" != \#* ]] || continue
    [[ "$output" == *"secret:$service"* ]]
  done < "$MACHINE_DIR/secrets.hub.list"
  [[ "$output" == *'secret:k3dm-slack-role-map'*'missing'* ]]
  tty_machine --role hub --from old-mac.local --secrets skip
  grep -q '^secrets pull --from old-mac.local --role hub$' "$CALL_LOG"
  touch "$CALL_LOG.present"
  run_machine --role hub --check
  [[ "$output" == *'secret:k3dm-slack-role-map:k3dm'*'ok'* ]]
}

@test "machine setup: hub manifest includes each hub-read service and account" {
  for entry in \
    'k3dm-slack-role-map|k3dm' 'k3dm-acg-pluralsight|username' 'k3dm-acg-pluralsight|password' \
    'k3d-manager-cloudflared-cert|cloudflared' 'k3d-manager-cloudflared-credentials|cloudflared' \
    'k3d-manager-signing|k3dm-cosign-key' 'k3d-manager-signing|k3dm-cosign-password' \
    'k3dm-webhook-token-cloud-runner|k3dm'; do
    grep -Fq "$entry|" "$MACHINE_DIR/secrets.hub.list"
  done
  for account in redis/cart redis/orders-cache postgres/orders postgres/products postgres/payment payment/encryption payment/stripe payment/paypal rabbitmq/default minio/credentials ldap/admin keycloak/admin keycloak/clients github/pat; do
    grep -Fq "k3d-manager-app-cluster-secrets|$account|" "$MACHINE_DIR/secrets.hub.list"
  done
}

@test "machine setup: hub creates its EC2 key privately and reports it without contents" {
  setup_machine_fixture
  run_machine --role hub --agents skip --secrets skip
  [ -f "$FIXHOME/.ssh/k3d-manager-key.pem" ]
  [ -f "$FIXHOME/.ssh/k3d-manager-key.pub" ]
  [ -n "$(find "$FIXHOME/.ssh/k3d-manager-key.pem" -perm 600)" ]
  [[ "$output" == *'ec2 ssh key:'*present* ]]
  [[ "$output" != *'PRIVATE-KEY-TEST-MATERIAL'* ]]
  run_machine --role hub --check
  [[ "$output" == *'ec2 ssh key:'*present* ]]
  [[ "$output" != *'PRIVATE-KEY-TEST-MATERIAL'* ]]
  run ! grep -R -F 'PRIVATE-KEY-TEST-MATERIAL' "$FIXHOME/.local/state"
}

@test "machine setup: hub check reports missing and does not create a key" {
  setup_machine_fixture
  run_machine --role hub --check
  [[ "$output" == *'ec2 ssh key:'*missing* ]]
  [ ! -e "$FIXHOME/.ssh/k3d-manager-key.pem" ]
  run_machine --role hub --dry-run
  [ ! -e "$FIXHOME/.ssh/k3d-manager-key.pem" ]
}

@test "machine setup: hub preserves an existing EC2 private key" {
  setup_machine_fixture
  mkdir -p "$FIXHOME/.ssh"
  printf '%s\n' 'PRIVATE-KEY-TEST-MATERIAL' > "$FIXHOME/.ssh/k3d-manager-key.pem"
  touch -t 202001010101 "$FIXHOME/.ssh/k3d-manager-key.pem"
  cp -p "$FIXHOME/.ssh/k3d-manager-key.pem" "$BATS_TEST_TMPDIR/original"
  run_machine --role hub --agents skip --secrets skip
  cmp "$BATS_TEST_TMPDIR/original" "$FIXHOME/.ssh/k3d-manager-key.pem"
  [ "$FIXHOME/.ssh/k3d-manager-key.pem" -ot "$FIXROOT/bin/k3dm-machine-setup" ]
  [ ! "$BATS_TEST_TMPDIR/original" -nt "$FIXHOME/.ssh/k3d-manager-key.pem" ]
  [ ! "$BATS_TEST_TMPDIR/original" -ot "$FIXHOME/.ssh/k3d-manager-key.pem" ]
  [[ "$output" != *'PRIVATE-KEY-TEST-MATERIAL'* ]]
  run ! grep -q '^ssh-keygen called' "$CALL_LOG"
}

@test "machine setup: records each setup role in scratch XDG config" {
  setup_machine_fixture
  for role in hub worker console; do
    run_machine --role "$role" --agents skip --secrets skip
    [ "$(cat "$FIXHOME/.config/k3d-manager/machine-role")" = "$role" ]
  done
  run_machine --role worker --check
  [ "$(cat "$FIXHOME/.config/k3d-manager/machine-role")" = console ]
}
