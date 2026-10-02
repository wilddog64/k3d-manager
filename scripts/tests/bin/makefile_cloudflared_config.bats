#!/usr/bin/env bats

REPO_ROOT="${BATS_TEST_DIRNAME}/../../.."

setup() {
  unset CF_PROVIDER APPLY
  export CF_CONFIG="${BATS_TEST_TMPDIR}/home/.cloudflared/config.yml"
  mkdir -p "$(dirname "$CF_CONFIG")"
  source "${REPO_ROOT}/scripts/lib/cloudflared_render.sh"
  _hub_recovery_render_cloudflared_config k3s-hostinger \
    "${REPO_ROOT}/scripts/etc/cloudflared/config.yml" \
    "${REPO_ROOT}/scripts/etc/cloudflared/origins.tsv" > "${BATS_TEST_TMPDIR}/expected.yml"
}

_make_config() {
  if [[ -n "${CF_PROVIDER+x}" ]]; then
    run env CF_CONFIG="$CF_CONFIG" CF_PROVIDER="$CF_PROVIDER" APPLY="${APPLY:-0}" \
      make --no-print-directory -C "$REPO_ROOT" cloudflared-config
  else
    run env CF_CONFIG="$CF_CONFIG" APPLY="${APPLY:-0}" \
      make --no-print-directory -C "$REPO_ROOT" cloudflared-config
  fi
}

@test "cloudflared-config: identical render is not rewritten" {
  cp "${BATS_TEST_TMPDIR}/expected.yml" "$CF_CONFIG"
  before_inode=$(stat -c '%i' "$CF_CONFIG" 2>/dev/null || stat -f '%i' "$CF_CONFIG")
  before_mtime=$(stat -c '%Y' "$CF_CONFIG" 2>/dev/null || stat -f '%m' "$CF_CONFIG")

  _make_config

  [ "$status" -eq 0 ]
  [[ "$output" == *"cloudflared config up to date (k3s-hostinger)"* ]]
  [ "$before_inode" = "$(stat -c '%i' "$CF_CONFIG" 2>/dev/null || stat -f '%i' "$CF_CONFIG")" ]
  [ "$before_mtime" = "$(stat -c '%Y' "$CF_CONFIG" 2>/dev/null || stat -f '%m' "$CF_CONFIG")" ]
}

@test "cloudflared-config: drift is reported and not written without APPLY" {
  sed 's#127.0.0.2:80#127.0.0.1:8000#' "${BATS_TEST_TMPDIR}/expected.yml" > "$CF_CONFIG"
  cp "$CF_CONFIG" "${BATS_TEST_TMPDIR}/before.yml"

  _make_config

  [ "$status" -eq 2 ]
  [[ "$output" == *"127.0.0.2:80"* ]]
  [[ "$output" == *"drift: rerun with APPLY=1 to install"* ]]
  cmp "$CF_CONFIG" "${BATS_TEST_TMPDIR}/before.yml"
}

@test "cloudflared-config: APPLY installs render and keeps a backup" {
  sed 's#127.0.0.2:80#127.0.0.1:8000#' "${BATS_TEST_TMPDIR}/expected.yml" > "$CF_CONFIG"

  APPLY=1 _make_config

  [ "$status" -eq 0 ]
  cmp "$CF_CONFIG" "${BATS_TEST_TMPDIR}/expected.yml"
  backup=$(find "$(dirname "$CF_CONFIG")" -name 'config.yml.bak.*' -type f -print -quit)
  [ -n "$backup" ]
  grep -Fq '127.0.0.1:8000' "$backup"
  [[ "$output" == *'launchctl kickstart -k "gui/'* ]]
}

@test "cloudflared-config: k3d renders the local frontend origin" {
  CF_PROVIDER=k3d _make_config

  [ "$status" -eq 2 ]
  [[ "$output" == *"127.0.0.1:8000"* ]]
}

@test "cloudflared-config: unknown provider writes nothing and exits 2" {
  CF_PROVIDER=bogus _make_config

  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: unknown CF_PROVIDER: bogus"* ]]
  [ ! -e "$CF_CONFIG" ]
}
