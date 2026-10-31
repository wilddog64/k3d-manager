#!/usr/bin/env bats

setup() {
  SRC="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TREE="${MS_TREE:-$SRC}"
  T="$BATS_TEST_TMPDIR"
  UNAME_USER="zqusr9"
  HOME_FX="$T/home/$UNAME_USER"
  STUBS="$T/stubs"
  CALLS="$T/calls.log"
  MISSING="$T/missing.txt"
  mkdir -p "$HOME_FX" "$STUBS"
  : > "$CALLS"; : > "$MISSING"
  make_stubs
}

make_stubs() {
  local c
  for c in launchctl gh make curl sudo installer softwareupdate xcode-select pkgutil direnv python3 brew security git uname; do
    cat > "$STUBS/$c" <<STUB
#!/bin/bash
echo "$c \$*" >> "$CALLS"
if [ -s "$MISSING" ] && grep -qxF -e "$c \$*" "$MISSING"; then exit 1; fi
case "$c" in
  brew) [ "\${1:-}" = list ] && [ ! -e "$T/complete" ] && exit 1 ;;
  security) case "\$*" in find-*) [ ! -e "$T/complete" ] && exit 44 ;; esac ;;
  gh) [ "\${1:-}" = auth ] && [ ! -e "$T/complete" ] && exit 1 ;;
  xcode-select) [ ! -e "$T/complete" ] && exit 2 ;;
esac
case "$c" in
  python3)
    if [ "\${1:-}" = -m ] && [ "\${2:-}" = venv ]; then
      mkdir -p "\$3/bin"
      for x in python pip python3; do printf '#!/bin/bash\necho "venv-%s \$*" >> "%s"\nexit 0\n' "\$x" "$CALLS" > "\$3/bin/\$x"; chmod +x "\$3/bin/\$x"; done
    fi ;;
  uname) case "\${1:-}" in -m) echo arm64;; *) echo Darwin;; esac ;;
  security)
    case " \$* " in *" -w "*|*" -g "*|*" -gw "*|*" -wg "*) echo "SECRETVALUE_LEAK";; esac ;;
  git)
    if [ "\${1:-}" = -C ]; then d="\$2"; fi
    case "\$*" in
      *get-url*|*remote.origin.url*)
        while IFS='|' read -r p u b r; do
          [ "\$d" = "$HOME_FX/src/\$p" ] && echo "\$u"
        done < "$TREE/scripts/etc/machine/repos.list"
        case "\$d" in
          "$HOME_FX/.claude") echo https://github.com/wilddog64/claude-settings.git;;
          "$HOME_FX/.codex") echo https://github.com/wilddog64/codex-settings.git;;
          "$HOME_FX/.gemini") echo https://github.com/wilddog64/gemini-config.git;;
          "$HOME_FX/.copilot") echo https://github.com/wilddog64/copilot-config.git;;
        esac ;;
      *rev-parse*|*"branch --show-current"*)
        while IFS='|' read -r p u b r; do
          [ "\$d" = "$HOME_FX/src/\$p" ] && echo "\$b"
        done < "$TREE/scripts/etc/machine/repos.list" ;;
      *clone*) for last in "\$@"; do :; done; mkdir -p "\$last/.git" ;;
    esac ;;
esac
exit 0
STUB
    chmod +x "$STUBS/$c"
  done
}

miss() { printf '%s\n' "$1" >> "$MISSING"; }

complete_machine() {
  local role="$1" p u b r f
  touch "$T/complete"
  mkdir -p "$T/sudoers.d"; : > "$T/sudoers.d/k3d-manager"
  for x in ruff pytest; do printf '#!/bin/bash\nexit 0\n' > "$STUBS/$x"; chmod +x "$STUBS/$x"; done
  mkdir -p "$HOME_FX/Library/LaunchAgents" "$HOME_FX/.claude/.git" "$HOME_FX/.codex/.git" "$HOME_FX/.gemini/.git" "$HOME_FX/.copilot/.git" "$HOME_FX/.smartcd/lib/core" "$HOME_FX/src/gitrepo/personal/zshdotfiles"
  touch "$HOME_FX/.smartcd/lib/core/smartcd" "$HOME_FX/src/gitrepo/personal/zshdotfiles/zshrc" "$HOME_FX/src/gitrepo/personal/zshdotfiles/zshenv"
  ln -sfn "$HOME_FX/src/gitrepo/personal/zshdotfiles" "$HOME_FX/.zsh"
  ln -sfn "$HOME_FX/.zsh/zshrc" "$HOME_FX/.zshrc"
  ln -sfn "$HOME_FX/.zsh/zshenv" "$HOME_FX/.zshenv"
  while IFS='|' read -r p u b r; do
    case "$p" in '#'*|'') continue ;; esac
    case "$u" in SKIP*) continue ;; esac
    case ",$r," in *,"$role",*) mkdir -p "$HOME_FX/src/$p/.git" ;; esac
  done < "$TREE/scripts/etc/machine/repos.list"
  for f in "$TREE"/scripts/etc/launchd/*.plist.tmpl; do
    : > "$HOME_FX/Library/LaunchAgents/$(basename "$f" .tmpl)"
  done
  if [ -f "$TREE/scripts/etc/machine/files.$role.list" ]; then
    while IFS= read -r f; do
      case "$f" in '#'*|'') continue ;; esac
      mkdir -p "$(dirname "$HOME_FX/$f")"
      printf "fixture\n" > "$HOME_FX/$f"
      chmod 600 "$HOME_FX/$f"
    done < "$TREE/scripts/etc/machine/files.$role.list"
  fi
}

ensure_copy() {
  if [ "$TREE" = "$SRC" ] || [ ! -d "$T/tree" ]; then
    mkdir -p "$T/tree"
    cp -R "$TREE"/. "$T/tree"/
    rm -rf "$T/tree/.venv"
    TREE="$T/tree"
    make_stubs
  fi
}

ms() {
  case " $* " in *" --check "*|*" --dry-run "*) ;; *) ensure_copy ;; esac
  run env -i HOME="$HOME_FX" K3DM_SUDOERS_FILE="$T/sudoers.d/k3d-manager" PATH="$STUBS:/usr/bin:/bin" TERM=dumb \
    /bin/bash "$TREE/bin/k3dm-machine-setup" "$@" < /dev/null
}

mk() {
  run env -i HOME="$HOME_FX" K3DM_SUDOERS_FILE="$T/sudoers.d/k3d-manager" PATH="$STUBS:/usr/bin:/bin" TERM=dumb \
    /usr/bin/make -C "$TREE" "$@" < /dev/null
}

mutating() {
  grep -E '^(brew (install|reinstall|upgrade|tap|uninstall)|git .*(clone|checkout|reset|pull|clean|switch|merge|rebase|stash)|security (add|delete)|launchctl |make install|make .*install-|curl |sudo |installer |softwareupdate )' "$CALLS" || true
}

# ---------------------------------------------------------------- M1
@test "M1: setup runs for every role and drives only from the lists (brew items appear)" {
  local role
  for role in hub worker console; do
    : > "$CALLS"
    ms --role "$role" --dry-run
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" == *preflight* ]]
  done
  ms --role console --check
  for item in $(grep -vE '^(#|$)' "$TREE/scripts/etc/machine/brew.console.list" | sed 's/^formula://;s/^cask://'); do
    [[ "$output" == *"$item"* ]]
  done
  if [[ "$output" == *aerospace* ]]; then false; fi
}

@test "M1: report order is preflight, tools, repos, secrets, agents" {
  ms --role hub --check
  local pre tools repos sec
  pre=$(echo "$output" | grep -n '^preflight' | head -1 | cut -d: -f1)
  tools=$(echo "$output" | grep -n '^brew:' | head -1 | cut -d: -f1)
  repos=$(echo "$output" | grep -n '^repo:' | head -1 | cut -d: -f1)
  sec=$(echo "$output" | grep -n '^secret:' | head -1 | cut -d: -f1)
  ag=$(echo "$output" | grep -n '^smartcd ' | head -1 | cut -d: -f1)
  [ "$pre" -lt "$tools" ]
  [ "$tools" -lt "$repos" ]
  [ "$repos" -lt "$sec" ]
  [ "$sec" -lt "$ag" ]
}

@test "M1: setup on an empty hub fixture mutates in phase order tools -> repos -> agents" {
  ms --role hub
  local b g m
  b=$(grep -n '^brew install\|^brew .*install' "$CALLS" | head -1 | cut -d: -f1)
  g=$(grep -n '^git .*clone' "$CALLS" | head -1 | cut -d: -f1)
  m=$(grep -n '^make .*install-' "$CALLS" | head -1 | cut -d: -f1)
  [ -n "$b" ] && [ -n "$g" ] && [ -n "$m" ]
  [ "$b" -lt "$g" ]
  [ "$g" -lt "$m" ]
}

@test "M1: hub install-* agents are exactly those in agents.hub.list" {
  ms --role hub
  for t in $(grep -E '^install-' "$TREE/scripts/etc/machine/agents.hub.list"); do
    grep -qE "^make .*$t( |\$)" "$CALLS"
  done
  for t in $(grep -E '^install-' "$TREE/scripts/etc/machine/not-installed.list" | cut -d'|' -f1); do
    if grep -qE "^make .*$t( |\$)" "$CALLS"; then false; fi
  done
}

# ---------------------------------------------------------------- M2
@test "M2: machine-check exits 0 on a complete hub and prints table" {
  complete_machine hub
  ms --role hub --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"preflight-macos"* ]]
  if [[ "$output" == *missing* ]]; then false; fi
}

@test "M2: machine-check exits 0 on a complete console" {
  complete_machine console
  ms --role console --check
  [ "$status" -eq 0 ]
}

@test "M2: machine-check exits 0 on a complete worker" {
  complete_machine worker
  ms --role worker --check
  [ "$status" -eq 0 ]
}

@test "M2: empty machine exits 1 and lists missing items for each role" {
  local r
  for r in hub worker console; do
    ms --role $r --check
    [ "$status" -eq 1 ]
    [[ "$output" == *missing* ]]
  done
}

@test "M2: missing a brew formula -> exit 1 naming it" {
  complete_machine console
  miss "brew list --formula jq"
  ms --role console --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"brew:jq"*missing* ]]
}

@test "M2: missing a cask -> exit 1" {
  complete_machine console
  miss "brew list --cask iterm2"
  ms --role console --check
  [ "$status" -eq 1 ]
}

@test "M2: missing a repo clone -> exit 1 naming it" {
  complete_machine hub
  rm -rf "$HOME_FX/src/gitrepo/personal/lib-foundation"
  ms --role hub --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"repo:gitrepo/personal/lib-foundation"*missing* ]]
}

@test "M2: missing a keychain secret -> exit 1 naming it" {
  complete_machine hub
  miss "security find-generic-password -s k3dm-hermes-audit-token -a k3dm"
  # fall back: break every find-generic-password for that service via a wrapper
  cat > "$STUBS/security" <<STUB
#!/bin/bash
echo "security \$*" >> "$CALLS"
case "\$*" in *k3dm-hermes-audit-token*) exit 44;; esac
exit 0
STUB
  ms --role hub --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"k3dm-hermes-audit-token"*missing* ]]
}

@test "M2: missing a LaunchAgent plist -> exit 1" {
  complete_machine hub
  rm -f "$HOME_FX/Library/LaunchAgents/com.k3d-manager.cleanup.plist"
  ms --role hub --check
  [ "$status" -eq 1 ]
  [[ "$output" == *cleanup*missing* ]]
}

@test "M2: failing preflight item (command-line-tools) -> exit 1" {
  complete_machine console
  miss "xcode-select -p"
  ms --role console --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"command-line-tools"*missing* ]]
}

@test "M2: make machine-check ROLE=console exits 0 when complete, nonzero when a repo is missing" {
  complete_machine console
  mk machine-check ROLE=console
  [ "$status" -eq 0 ]
  rm -rf "$HOME_FX/src/gitrepo/personal/lib-foundation"
  mk machine-check ROLE=console
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo:gitrepo/personal/lib-foundation"*missing* ]]
}

@test "M2: make machine-check without ROLE fails" {
  mk machine-check
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------- M3
@test "M3: second setup run on complete console reports all ok and installs nothing" {
  complete_machine console
  ms --role console
  [ "$status" -eq 0 ]
  if [[ "$output" == *missing* ]]; then false; fi
  [ -z "$(mutating)" ]
}

@test "M3: second setup run on complete hub installs nothing" {
  complete_machine hub
  ms --role hub
  [ "$status" -eq 0 ]
  if [[ "$output" == *missing* ]]; then false; fi
  [ -z "$(mutating)" ]
}

@test "M3: second setup run on complete worker installs nothing" {
  complete_machine worker
  ms --role worker
  [ "$status" -eq 0 ]
  [ -z "$(mutating)" ]
}

@test "M3: first run then second run (missing fixture) converges" {
  complete_machine console
  rm -rf "$HOME_FX/src/gitrepo/personal/lib-foundation"
  ms --role console
  grep -q '^git .*clone' "$CALLS"
  : > "$CALLS"
  ms --role console
  [ -z "$(mutating)" ]
}

# ---------------------------------------------------------------- M4
@test "M4: every launchd template and install-* target is in an agents list or not-installed list" {
  local d="${MS_TREE:-$SRC}" f t n named fail=0 hit
  named="$(cat "$d"/scripts/etc/machine/agents.*.list | cut -d'|' -f1; cut -d'|' -f1 "$d/scripts/etc/machine/not-installed.list")"
  for t in $(grep -oE '^install-[a-z0-9-]+' "$d/Makefile" | sort -u); do
    if ! echo "$named" | grep -qxF "$t"; then echo "UNLISTED target: $t" >&2; fail=1; fi
  done
  for f in "$d"/scripts/etc/launchd/*.plist.tmpl; do
    n="$(basename "$f")"
    hit=0
    while read -r t; do
      [ -n "$t" ] && echo "$named" | grep -qxF "$t" && hit=1
    done < <(awk -v n="$n" '/^[a-zA-Z0-9_-]+:/ {sub(/:.*/,""); tgt=$0} index($0,n) {print tgt}' "$d/Makefile")
    while read -r t; do
      [ -n "$t" ] && echo "$named" | grep -qxF "bin/$(basename "$t")" && hit=1
    done < <(grep -lF "${n%.plist.tmpl}" "$d"/bin/* 2>/dev/null)
    echo "$named" | grep -qF -- "${n#com.k3d-manager.}" && hit=1 || true
    echo "$named" | grep -qF -- "$(echo "${n#com.k3d-manager.}" | sed 's/\.plist\.tmpl$//')" && hit=1 || true
    if [ "$hit" -eq 0 ]; then echo "UNLISTED template: $n" >&2; fail=1; fi
  done
  [ "$fail" -eq 0 ]
}

@test "M4: not-installed entries carry a reason and are not also installed by a role" {
  while IFS='|' read -r t reason; do
    case "$t" in '#'*|'') continue ;; esac
    [ -n "$reason" ]
    if grep -qxF "$t" "$SRC"/scripts/etc/machine/agents.*.list; then false; fi
  done < "$SRC/scripts/etc/machine/not-installed.list"
}

# ---------------------------------------------------------------- M5
@test "M5: howto covers roles, cut-over order, manual SSH and cosign, secret re-entry" {
  f="$SRC/docs/howto/machine-setup.md"
  [ -f "$f" ]
  grep -qi 'hub' "$f"; grep -qi 'worker' "$f"; grep -qi 'console' "$f"
  grep -qi 'cut-over\|cutover' "$f"
  grep -qi 'ssh' "$f"; grep -qi 'cosign' "$f"
  grep -qi 'secret' "$f"; grep -qiE 're-enter|reenter|re-entry' "$f"
}

@test "M5: cut-over steps are an ordered list" {
  f="$SRC/docs/howto/machine-setup.md"
  grep -qE '^1\. ' "$f"; grep -qE '^2\. ' "$f"; grep -qE '^3\. ' "$f"
}

@test "M5: README and Makefile link the howto" {
  grep -q 'docs/howto/machine-setup.md' "$SRC/README.md"
  grep -q 'docs/howto/machine-setup.md' "$SRC/Makefile"
  [ "$(grep -c 'docs/howto/machine-setup.md' "$SRC/README.md")" -ge 2 ]
}

# ---------------------------------------------------------------- N1
@test "N1: no security call passes -w/-g and no secret sentinel appears (all modes, all roles)" {
  local r m
  for r in hub worker console; do
    for m in --check --dry-run ""; do
      : > "$CALLS"
      if [ -n "$m" ]; then ms --role "$r" "$m"; else ms --role "$r"; fi
      if [[ "$output" == *SECRETVALUE_LEAK* ]]; then false; fi
      if grep -E '^security .* -(w|g|gw|wg)( |$)' "$CALLS"; then false; fi
    done
  done
}

@test "N1: no prompt without a TTY, and no keychain write without a TTY" {
  ms --role hub
  if grep -E '^security (add|delete)' "$CALLS"; then false; fi
  # must not block / hang: reaching here with stdin=/dev/null is the proof
}

@test "N1: nothing secret-looking is echoed even when stubs hand back values" {
  ms --role worker --check
  if [[ "$output" == *SECRETVALUE_LEAK* ]]; then false; fi
}

# ---------------------------------------------------------------- N2
@test "N2: --check makes no mutating call (empty machine, every role)" {
  local r
  for r in hub worker console; do
    : > "$CALLS"
    ms --role "$r" --check
    [ -z "$(mutating)" ]
  done
}

@test "N2: --dry-run makes no mutating call (empty machine, every role)" {
  local r
  for r in hub worker console; do
    : > "$CALLS"
    ms --role "$r" --dry-run
    [ -z "$(mutating)" ]
  done
}

@test "N2: make machine-check makes no mutating call" {
  mk machine-check ROLE=hub
  [ -z "$(mutating)" ]
}

@test "N2: --check/--dry-run leave the fixture HOME unchanged" {
  complete_machine console
  find "$HOME_FX" | sort > "$T/before"
  ms --role console --check
  ms --role console --dry-run
  find "$HOME_FX" | sort > "$T/after"
  diff "$T/before" "$T/after"
}

# ---------------------------------------------------------------- N3
@test "N3: worker and console never run hub install-* targets" {
  local r t
  for r in worker console; do
    : > "$CALLS"
    ms --role "$r"
    for t in $(grep -E '^install-' "$TREE/scripts/etc/machine/agents.hub.list"); do
      if ! grep -qxF "$t" "$TREE/scripts/etc/machine/agents.$r.list"; then
        if grep -qE "^make .*$t( |\$)" "$CALLS"; then false; fi
      fi
    done
    if grep -E 'hub-(snapshot|data-export)|webhook\.plist|hermes\.plist|heartbeat\.plist' "$CALLS"; then false; fi
  done
}

@test "N3: console runs no install-* at all and writes no LaunchAgents" {
  ms --role console
  if grep -E '^make .*install-' "$CALLS"; then false; fi
  [ -z "$(ls "$HOME_FX/Library/LaunchAgents" 2>/dev/null)" ]
}

@test "N3: worker only runs install-* named in agents.worker.list" {
  ms --role worker
  while read -r line; do
    t="$(echo "$line" | grep -oE 'install-[a-z0-9-]+' | head -1)"
    grep -qxF "$t" "$TREE/scripts/etc/machine/agents.worker.list"
  done < <(grep -E '^make .*install-' "$CALLS" || true)
}

@test "N3: no role ever uninstalls an agent (no bootout/unload/remove/rm of plists)" {
  local r
  for r in hub worker console; do
    complete_machine "$r"
    : > "$CALLS"
    ms --role "$r"
    if grep -E '^launchctl (bootout|unload|remove|disable)' "$CALLS"; then false; fi
    if grep -E '^make .*(uninstall|remove|unload)' "$CALLS"; then false; fi
  done
  # extra agents already present stay in place
  : > "$HOME_FX/Library/LaunchAgents/com.k3d-manager.hub-snapshot.plist"
  ms --role worker
  [ -e "$HOME_FX/Library/LaunchAgents/com.k3d-manager.hub-snapshot.plist" ]
  ms --role console
  [ -e "$HOME_FX/Library/LaunchAgents/com.k3d-manager.hub-snapshot.plist" ]
}

# ---------------------------------------------------------------- N4
@test "N4: no sudo outside _run_command, no curl|sh, no security -w in the scripts" {
  local f
  for f in "$TREE/bin/k3dm-machine-setup" "$TREE/bin/machine-bootstrap"; do
    if awk '/^_run_command\(\)/ {skip=1} skip {if ($0 ~ /^}/) skip=0; next} {print NR": "$0}' "$f" | grep -E '(^|[^_[:alnum:]-])sudo[[:space:]]' | grep -v '_run_command' | grep -vE '^[0-9]+:[[:space:]]*#'; then false; fi
    if grep -nE 'curl[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh' "$f"; then false; fi
    if grep -nE '(sh|bash)[[:space:]]+-c[[:space:]]+"?\$\(curl' "$f"; then false; fi
    if grep -nE 'security[^|;&#]*[[:space:]]-[a-zA-Z]*[wg][a-zA-Z]*([[:space:]]|$)' "$f" | grep -v 'add-generic' | grep -vE '^[0-9]+:[[:space:]]*#'; then false; fi
  done
}

@test "N4: fixture sudo stub is never called directly by setup or check" {
  local r m
  for r in hub worker console; do
    for m in --check --dry-run ""; do
      : > "$CALLS"
      if [ -n "$m" ]; then ms --role "$r" "$m"; else ms --role "$r"; fi
      if grep -E '^sudo ' "$CALLS"; then false; fi
    done
  done
}

@test "N4: report output has no username and no home path" {
  local r m
  for r in hub worker console; do
    for m in --check --dry-run ""; do
      if [ -n "$m" ]; then ms --role "$r" "$m"; else ms --role "$r"; fi
      if [[ "$output" == *"$UNAME_USER"* ]]; then false; fi
      if [[ "$output" == *"$HOME_FX"* ]]; then false; fi
      if [[ "$output" == *"$(id -un)"* ]]; then false; fi
      if [[ "$output" == *"/Users/"* ]]; then false; fi
    done
  done
  complete_machine hub
  ms --role hub --check
  if [[ "$output" == *"$UNAME_USER"* ]]; then false; fi
}

# ---------------------------------------------------------------- N5
@test "N5: existing clones are never modified (checkout/reset/pull/clean/...)" {
  complete_machine hub
  mkdir -p "$HOME_FX/src/gitrepo/personal/tax-returns/.git"
  ms --role hub
  if grep -E '^git .*(checkout|reset|pull|clean|switch|merge|rebase|stash|fetch|restore|commit|gc|branch -[dDmM])' "$CALLS"; then false; fi
}

@test "N5: clone with a foreign remote is left alone and no mutation is attempted" {
  complete_machine hub
  cat > "$STUBS/git" <<STUB
#!/bin/bash
echo "git \$*" >> "$CALLS"
case "\$*" in *get-url*|*remote.origin.url*) echo https://example.invalid/other.git;; esac
exit 0
STUB
  ms --role hub
  if grep -E '^git .*(checkout|reset|pull|clean|switch|merge|rebase|stash|fetch|restore)' "$CALLS"; then false; fi
  if grep -E "^git .*clone .* $HOME_FX/src/" "$CALLS"; then false; fi
}

@test "N5: existing clone is not re-cloned and its files are untouched" {
  complete_machine console
  d="$HOME_FX/src/gitrepo/personal/k3d-manager"
  echo precious > "$d/dirty.txt"
  ms --role console
  [ "$(cat "$d/dirty.txt")" = precious ]
  if grep -E "^git .*clone .*k3d-manager( |\$)" "$CALLS"; then false; fi
}

@test "PY: --check with neither tool reports python-tools missing, exit 1, no python3 call" {
  ms --role console --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"python-tools"*missing* ]]
  if grep -E '^python3 ' "$CALLS"; then false; fi
}

@test "PY: venv under fixture HOME data dir counts as ok" {
  complete_machine console
  rm -f "$STUBS/ruff" "$STUBS/pytest"
  ms --role console --check
  [[ "$output" == *"python-tools"*missing* ]]
  mkdir -p "$HOME_FX/.local/share/k3d-manager/venv/bin"
  for x in ruff pytest; do printf '#!/bin/bash\nexit 0\n' > "$HOME_FX/.local/share/k3d-manager/venv/bin/$x"; chmod +x "$HOME_FX/.local/share/k3d-manager/venv/bin/$x"; done
  ms --role console --check
  [ "$status" -eq 0 ]
  if [[ "$output" == *"python-tools"*missing* ]]; then false; fi
}

@test "PY: setup creates the venv under HOME data dir and no .venv in the tree" {
  ms --role console
  [ -d "$HOME_FX/.local/share/k3d-manager/venv/bin" ]
  if find "$TREE" -name .venv -maxdepth 3 | grep .; then false; fi
}
