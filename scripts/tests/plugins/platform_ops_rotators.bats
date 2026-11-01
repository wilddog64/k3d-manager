#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  platform_ops_dir="${SCRIPT_DIR}/etc/argocd/platform-ops"
}

scan_legacy_base64() {
  grep -rn -- 'base64 --decode' "$1"
}

@test "container templates use BusyBox-compatible base64 -d" {
  run scan_legacy_base64 "${SCRIPT_DIR}/etc"
  [ "$status" -eq 1 ]
}

@test "base64 guard detects a planted invocation in a scratch tree" {
  scratch_etc="${BATS_TEST_TMPDIR}/etc"
  mkdir -p "${scratch_etc}/ldap"
  printf '%s\n' 'base64 --decode' > "${scratch_etc}/ldap/planted.yaml.tmpl"
  run scan_legacy_base64 "$scratch_etc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${scratch_etc}/ldap/planted.yaml.tmpl"* ]]
}

@test "platform-ops rotators decode Kubernetes Secret data" {
  for manifest in \
    "${platform_ops_dir}/keycloak-credential-rotator.yaml" \
    "${platform_ops_dir}/argocd-credential-rotator.yaml" \
    "${platform_ops_dir}/grafana-credential-rotator.yaml"; do
    run grep -F -- 'base64 -d' "${manifest}"
    [ "$status" -eq 0 ]
  done
}

@test "platform-ops rotator notices report failures, skips and success safely" {
  for manifest in "${platform_ops_dir}"/{grafana,argocd,keycloak}-credential-rotator.yaml; do
    # Exercise each notice block, including Keycloak's rollback warning.
    awk '/if \[ -n "\$slack_url" \]; then/ { n++; file=dir "/notice" n; print "set -eu" > file; capture=1 } capture { sub(/^ +/, ""); print > file; if ($0 == "fi") { close(file); capture=0 } }' dir="$BATS_TEST_TMPDIR" "$manifest"
    for block in "$BATS_TEST_TMPDIR"/notice*; do
      mkdir -p "$BATS_TEST_TMPDIR/stubs"
      cat > "$BATS_TEST_TMPDIR/stubs/curl" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; printf '%s' "${REPLY_BODY:-no_service}" > "$1"; fi
  shift
done
printf '%s' "$HTTP_STATUS"
STUB
      chmod +x "$BATS_TEST_TMPDIR/stubs/curl"
      run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" slack_url='https://secret-webhook-marker' HTTP_STATUS=404 /bin/sh "$block"
      [ "$status" -eq 0 ]
      [[ "$output" == *'WARN slack notice not delivered: HTTP 404 no_service'* ]]
      [[ "$output" != *'secret-webhook-marker'* ]]
      run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" slack_url='https://secret-webhook-marker' HTTP_STATUS=200 /bin/sh "$block"
      [ "$status" -eq 0 ]
      [[ "$output" != *WARN* ]]
      run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" slack_url='' HTTP_STATUS=200 /bin/sh "$block"
      [ "$status" -eq 0 ]
      [[ "$output" == *'WARN slack notice skipped'* ]]
      run env PATH="$BATS_TEST_TMPDIR/stubs:$PATH" slack_url='https://secret-webhook-marker' HTTP_STATUS=404 REPLY_BODY='https://secret-webhook-marker' /bin/sh "$block"
      [ "$status" -eq 0 ]
      [[ "$output" != *'secret-webhook-marker'* ]]
    done
    rm -f "$BATS_TEST_TMPDIR"/notice*
  done
}

@test "rotators disarm the restore trap before the Slack notice" {
  for manifest in "${platform_ops_dir}"/{grafana,argocd,keycloak}-credential-rotator.yaml; do
    run awk '/trap - EXIT/ { disarmed=1 } /slack_url="\$\(kubectl get secret platform-ops-notifications/ && !inrollback { if (!disarmed) bad=1 } /rollback\(\) \{/ { inrollback=1 } inrollback && /^ *\}$/ { inrollback=0 } END { exit bad }' "$manifest"
    [ "$status" -eq 0 ] || { echo "notice runs with the restore trap armed: $manifest"; false; }
  done
}
