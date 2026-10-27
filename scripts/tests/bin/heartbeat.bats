#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  TMP="$BATS_TEST_TMPDIR/heartbeat"
  mkdir -p "$TMP"
}

@test "heartbeat: dry run renders intent without provider calls" {
  cat > "$TMP/config.json" <<'EOF'
{"checks":[{"id":"m4-host","secret_source":{"type":"file","path":"/must-not-read"}}]}
EOF
  run python3 "$ROOT/bin/k3dm-heartbeat-setup" --config "$TMP/config.json" --output-dir "$TMP/out" --platform systemd --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/out/heartbeat.json" ]
  [[ "$output" == *"Would render disabled-by-default systemd"* ]]
}

@test "heartbeat: templates contain no enrolled endpoint" {
  run grep -R -E 'https://(hc-ping.com|healthchecks.io)/[[:xdigit:]-]{20,}' "$ROOT/scripts/etc/heartbeat" "$ROOT/scripts/etc/launchd/com.k3d-manager.heartbeat.plist.tmpl" "$ROOT/scripts/etc/systemd"
  [ "$status" -eq 1 ]
}

@test "heartbeat: documented commands execute directly" {
  run "$ROOT/bin/k3dm-heartbeat" --help
  [ "$status" -eq 0 ]
  run "$ROOT/bin/k3dm-heartbeat-setup" --help
  [ "$status" -eq 0 ]
}
