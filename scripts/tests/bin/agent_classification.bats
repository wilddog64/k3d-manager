#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  MACHINE_DIR="${AGENT_CLASSIFICATION_DIR:-$REPO/scripts/etc/machine}"
}

@test "M4: every launchd template label has exactly one hub classification" {
  local file label count
  for file in "$REPO"/scripts/etc/launchd/*.plist.tmpl; do
    label="$(basename "$file" .plist.tmpl | sed 's/^com.k3d-manager\.//')"
    count="$(grep -hE "^${label//./\\.}(\||$)" "$MACHINE_DIR"/hub-local.list "$MACHINE_DIR"/hub-singletons.list "$MACHINE_DIR"/not-installed.list | wc -l | tr -d ' ')"
    [ "$count" -eq 1 ] || { echo "$label has $count classifications" >&2; return 1; }
  done
}

@test "M4: literal code labels have exactly one hub classification" {
  local label count
  while IFS= read -r label; do
    case "$label" in *.plist|*.plist.tmpl|*.sh|sandbox|sandbox.) continue ;; esac
    count="$(grep -hE "^${label//./\\.}(\||$)" "$MACHINE_DIR"/hub-local.list "$MACHINE_DIR"/hub-singletons.list "$MACHINE_DIR"/not-installed.list | wc -l | tr -d ' ')"
    [ "$count" -eq 1 ] || { echo "$label has $count classifications" >&2; return 1; }
  done < <(grep -rhoE 'com\.k3d-manager\.[A-Za-z0-9.-]+' "$REPO/bin" "$REPO/scripts/lib" "$REPO/scripts/plugins" | sed 's/^com\.k3d-manager\.//' | sort -u)
}

@test "M4: cloudflare-tunnel is the last singleton and sandbox forwards are not-installed" {
  [ "$(grep -v '^#' "$MACHINE_DIR/hub-singletons.list" | tail -1 | cut -d'|' -f1)" = cloudflare-tunnel ]
  grep -q '^sandbox\..*|.*ACG sandbox lifecycle' "$MACHINE_DIR/not-installed.list"
}
