#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  # shellcheck source=../test_helpers.bash
  source "${ROOT}/scripts/tests/test_helpers.bash"
  TMP="$BATS_TEST_TMPDIR"
  mkdir -p "$TMP/bin" "$TMP/home"
  export PATH="$TMP/bin:$PATH" HOME="$TMP/home" K3DM_SECRETS_PASSPHRASE_FILE="$TMP/pass"
  printf 'test passphrase\n' > "$K3DM_SECRETS_PASSPHRASE_FILE"
  SCRIPT="${MACHINE_SECRETS_SOURCE:-$ROOT/bin/k3dm-machine-secrets}"
  source_keychain='' target_keychain=''
  if [[ "$(uname -s)" == Darwin ]]; then
    security list-keychains -d user > "$TMP/search-list.before"
  fi
}

teardown() {
  [[ "$(uname -s)" == Darwin ]] || return 0
  local key saved_line
  local -a saved=()
  for key in "${source_keychain:-}" "${target_keychain:-}"; do
    [[ -n "$key" ]] && security delete-keychain "$key" >/dev/null 2>&1 || true
  done
  security list-keychains -d user > "$TMP/search-list.after"
  if ! cmp -s "$TMP/search-list.before" "$TMP/search-list.after"; then
    while IFS= read -r saved_line; do
      saved+=("$saved_line")
    done < <(sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' "$TMP/search-list.before")
    security list-keychains -d user -s "${saved[@]}"
    security list-keychains -d user > "$TMP/search-list.after"
    if ! cmp -s "$TMP/search-list.before" "$TMP/search-list.after"; then
      printf 'keychain search list differs after cleanup\nBEFORE:\n' >&2
      cat "$TMP/search-list.before" >&2
      printf 'AFTER:\n' >&2
      cat "$TMP/search-list.after" >&2
      return 1
    fi
  fi
}

@test "machine secrets: real throwaway keychain round trip is macOS only" {
  require_macos
  rm -f "$TMP/bin/security"
  [ "$(command -v security)" = /usr/bin/security ]
  project="$TMP/project"
  mkdir -p "$project/bin" "$project/scripts/etc/machine"
  cp "$SCRIPT" "$project/bin/k3dm-machine-secrets"
  printf 'svc-roundtrip|*|fixture|operator: fixture\n' > "$project/scripts/etc/machine/secrets.hub.list"
  source_keychain="$TMP/source.keychain-db"
  target_keychain="$TMP/target.keychain-db"
  security create-keychain -p fixture-pass "$source_keychain"
  security create-keychain -p fixture-pass "$target_keychain"
  security unlock-keychain -p fixture-pass "$source_keychain"
  security unlock-keychain -p fixture-pass "$target_keychain"
  security add-generic-password -s svc-roundtrip -a account-one -X 7370616365202271756f746564220a6e65776c696e65 "$source_keychain"
  security add-generic-password -s svc-roundtrip -a account-two -X 73617920226869220a "$source_keychain"
  security add-generic-password -s svc-roundtrip -a account-three -X 7361792022686922 "$source_keychain"
  security add-generic-password -s svc-other -a account-four -X 6e6f74206c6973746564 "$source_keychain"
  encrypted="$TMP/roundtrip.enc"
  run "$project/bin/k3dm-machine-secrets" export --role hub --out "$encrypted" --keychain "$source_keychain"
  [ "$status" -eq 0 ]
  run "$project/bin/k3dm-machine-secrets" import --in "$encrypted" --keychain "$target_keychain"
  [ "$status" -eq 0 ]
  source_one="$(security find-generic-password -s svc-roundtrip -a account-one -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
  target_one="$(security find-generic-password -s svc-roundtrip -a account-one -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
  source_two="$(security find-generic-password -s svc-roundtrip -a account-two -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
  target_two="$(security find-generic-password -s svc-roundtrip -a account-two -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
  source_three="$(security find-generic-password -s svc-roundtrip -a account-three -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
  target_three="$(security find-generic-password -s svc-roundtrip -a account-three -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
  [ -n "$source_one" ] && [ -n "$source_two" ] && [ "$source_three" = '"say "hi""' ]
  [ "$source_one" = "$target_one" ]
  [ "$source_two" = "$target_two" ]
  [ "$source_three" = "$target_three" ]
  run security find-generic-password -s svc-other -a account-four "$target_keychain"
  [ "$status" -ne 0 ]
  security delete-keychain "$source_keychain"
  security delete-keychain "$target_keychain"
}

@test "M6: stream unlock round trip uses throwaway keychains on macOS" {
  require_macos
  rm -f "$TMP/bin/security"
  source_keychain="$TMP/stream-source.keychain-db"
  target_keychain="$TMP/stream-target.keychain-db"
  security create-keychain -p fixture-pass "$source_keychain"
  security create-keychain -p fixture-pass "$target_keychain"
  security unlock-keychain -p fixture-pass "$source_keychain"
  security unlock-keychain -p fixture-pass "$target_keychain"
  security add-generic-password -s k3dm-cloudflare-api-token -a k3dm -X 746f6b656e "$source_keychain"
  security lock-keychain "$source_keychain"
  run bash -c "printf 'fixture-pass\\n' | '$SCRIPT' export --role hub --stream --unlock --keychain '$source_keychain' | '$SCRIPT' import --in - --keychain '$target_keychain'"
  [ "$status" -eq 0 ]
  source_value="$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
  target_value="$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
  [ -n "$source_value" ]
  [ "$source_value" = "$target_value" ]
  security delete-keychain "$source_keychain"
  security delete-keychain "$target_keychain"
}
