#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  TMP="$BATS_TEST_TMPDIR"
  mkdir -p "$TMP/bin" "$TMP/home"
  export PATH="$TMP/bin:$PATH" HOME="$TMP/home" K3DM_SECRETS_PASSPHRASE_FILE="$TMP/pass"
  printf 'test passphrase\n' > "$K3DM_SECRETS_PASSPHRASE_FILE"
  export SECURITY_LOG="$TMP/security.log" FIXTURE="$TMP/items"
  export OPENSSL_LOG="$TMP/openssl.log" REAL_OPENSSL="$(command -v openssl)"
  : > "$SECURITY_LOG"
  : > "$FIXTURE"
  cat > "$TMP/bin/security" <<'SH'
#!/usr/bin/env bash
printf 'argv:' >> "$SECURITY_LOG"
printf ' <%s>' "$@" >> "$SECURITY_LOG"
printf '\n' >> "$SECURITY_LOG"
case "$1" in
  dump-keychain)
    while IFS=$'\t' read -r svc acct value; do
      printf 'keychain: "/fixture.keychain-db"\nversion: 256\nclass: "genp"\nattributes:\n    0x00000007 <blob>="%s"\n    "acct"<blob>="%s"\n    "svce"<blob>="%s"\n' "$svc" "$acct" "$svc"
    done < "$FIXTURE"
    ;;
  find-generic-password)
    svc='' acct=''
    while (($#)); do case "$1" in -s) svc="$2"; shift 2 ;; -a) acct="$2"; shift 2 ;; *) shift ;; esac; done
    if [[ -n "$acct" ]] && awk -F '\t' -v s="$svc" -v a="$acct" '$1==s && $2==a {found=1} END {exit !found}' "$FIXTURE"; then
      awk -F '\t' -v s="$svc" -v a="$acct" '$1==s && $2==a {print "password: 0x" $3}' "$FIXTURE" >&2
      exit 0
    fi
    exit 44
    ;;
  -i)
    while IFS= read -r line; do
      printf '%s\n' "$line" >> "$SECURITY_LOG.stdin"
      read -r -a words <<< "$line"
      [[ "${words[0]}" == add-generic-password ]] && printf '%s\t%s\t%s\n' "${words[3]}" "${words[5]}" 00 >> "$FIXTURE"
    done
    exit 0
    ;;
esac
SH
  chmod +x "$TMP/bin/security"
  cat > "$TMP/bin/openssl" <<'SH'
#!/usr/bin/env bash
printf 'openssl argv:' >> "$OPENSSL_LOG"
printf ' <%s>' "$@" >> "$OPENSSL_LOG"
printf '\n' >> "$OPENSSL_LOG"
exec "$REAL_OPENSSL" "$@"
SH
  chmod +x "$TMP/bin/openssl"
  SCRIPT="$ROOT/bin/k3dm-machine-secrets"
}

@test "machine secrets: make targets name the transfer script" {
  run make -n -C "$ROOT" machine-secrets-export ROLE=hub
  [ "$status" -eq 0 ]
  [[ "$output" == *'bin/k3dm-machine-secrets export --role "hub"'* ]]
  run make -n -C "$ROOT" machine-secrets-import FILE=/tmp/example.enc FORCE=1
  [ "$status" -eq 0 ]
  [[ "$output" == *'bin/k3dm-machine-secrets import --in "/tmp/example.enc" --force'* ]]
}

@test "machine secrets: export encrypts every matching account without plaintext output" {
  printf 'k3dm-vault-unseal-dr\tsecrets/vault:count\t70617373\nk3dm-vault-unseal-dr\tsecrets/vault:shard1\t6f6e65\nk3dm-cloudflare-api-token\tk3dm\t746f6b656e\n' > "$FIXTURE"
  out="$TMP/export.enc"
  run "$SCRIPT" export --role hub --out "$out"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$out" 2>/dev/null || stat -f %Lp "$out")" = 600 ]
  [[ "$output" == *'exported k3dm-vault-unseal-dr secrets/vault:count'* ]]
  [[ "$output" == *'exported k3dm-vault-unseal-dr secrets/vault:shard1'* ]]
  [[ "$output" != *'74617373'* ]]
  ! grep -F '74617373' "$SECURITY_LOG" || false
  run "$SCRIPT" export --role hub --out "$out"
  [ "$status" -ne 0 ]
  [[ "$output" == *'refusing to overwrite'* ]]
}

@test "machine secrets: import writes secret command only to security stdin" {
  : > "$FIXTURE"
  encrypted="$TMP/import.enc"
  printf 'svc\tacct\t74657374\n' | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$K3DM_SECRETS_PASSPHRASE_FILE" -out "$encrypted"
  run "$SCRIPT" import --in "$encrypted"
  [ "$status" -eq 0 ] || { printf 'import status=%s output=%s\n' "$status" "$output"; return 1; }
  [ ! -e "$encrypted" ]
  grep -F 'add-generic-password -U -s svc -a acct -X 74657374' "$SECURITY_LOG.stdin"
  ! grep -F '74657374' "$SECURITY_LOG" || false
}

@test "M2: present records skip by default and force writes each record once" {
  printf 'svc\tpresent\t1111\n' > "$FIXTURE"
  encrypted="$TMP/m2.enc"
  printf 'svc\tpresent\t2222\nsvc\tnew\t3333\n' | "$REAL_OPENSSL" enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$K3DM_SECRETS_PASSPHRASE_FILE" -out "$encrypted"
  run "$SCRIPT" import --in "$encrypted"
  [ "$status" -eq 0 ]
  [[ "$output" == *'skipped (present) svc present'* ]]
  [[ "$output" == *'copied svc new'* ]]
  [ "$(grep -c '^add-generic-password' "$SECURITY_LOG.stdin")" -eq 1 ]
  : > "$SECURITY_LOG.stdin"
  encrypted="$TMP/m2-force.enc"
  printf 'svc\tpresent\t2222\n' | "$REAL_OPENSSL" enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$K3DM_SECRETS_PASSPHRASE_FILE" -out "$encrypted"
  run "$SCRIPT" import --in "$encrypted" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *'copied svc present'* ]]
  [ "$(grep -c '^add-generic-password' "$SECURITY_LOG.stdin")" -eq 1 ]
}

@test "machine secrets: wrong passphrase does not modify keychain or delete file" {
  encrypted="$TMP/wrong.enc"
  printf 'svc\tacct\t74657374\n' | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$K3DM_SECRETS_PASSPHRASE_FILE" -out "$encrypted"
  printf 'wrong passphrase\n' > "$TMP/wrong-pass"
  export K3DM_SECRETS_PASSPHRASE_FILE="$TMP/wrong-pass"
  run "$SCRIPT" import --in "$encrypted"
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not decrypt'* ]]
  [ -e "$encrypted" ]
  ! grep -q 'add-generic-password' "$SECURITY_LOG.stdin" || false
}

@test "N1: secret and hex are absent from child argv" {
  : > "$FIXTURE"
  encrypted="$TMP/n1.enc"
  printf 'svc\tacct\t74657374\n' | "$REAL_OPENSSL" enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$K3DM_SECRETS_PASSPHRASE_FILE" -out "$encrypted"
  run "$SCRIPT" import --in "$encrypted" --force
  [ "$status" -eq 0 ]
  ! grep -F '74657374' "$SECURITY_LOG" || false
  ! grep -F '74657374' "$OPENSSL_LOG" || false
  ! grep -F 'test' "$SECURITY_LOG" || false
}

@test "N2: secret and hex are absent from command output and side files" {
  : > "$FIXTURE"
  encrypted="$TMP/n2.enc"
  printf 'svc\tacct\t74657374\n' | "$REAL_OPENSSL" enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$K3DM_SECRETS_PASSPHRASE_FILE" -out "$encrypted"
  run "$SCRIPT" import --in "$encrypted" --force
  [ "$status" -eq 0 ]
  [[ "$output" != *'74657374'* && "$output" != *'test'* ]]
  ! grep -F '74657374' "$SECURITY_LOG" || false
}

@test "N3: empty and unsafe records never reach security stdin" {
  : > "$FIXTURE"
  encrypted="$TMP/n3.enc"
  printf 'svc\tacct\t\nunsafe name\tacct\t74657374\nsvc\tacct\t\n' | "$REAL_OPENSSL" enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$K3DM_SECRETS_PASSPHRASE_FILE" -out "$encrypted"
  run "$SCRIPT" import --in "$encrypted" --force
  [ "$status" -ne 0 ]
  [[ "$output" == *'rejected (bad name)'* ]]
  ! grep -F 'add-generic-password' "$SECURITY_LOG.stdin" || false
}

@test "N5: export does not leave plaintext records on disk" {
  printf 'k3dm-cloudflare-api-token\tk3dm\t74657374\n' > "$FIXTURE"
  encrypted="$TMP/n5.enc"
  run "$SCRIPT" export --role hub --out "$encrypted"
  [ "$status" -eq 0 ]
  [[ "$output" == *'exported k3dm-cloudflare-api-token k3dm'* ]]
  [[ "$output" != *'74657374'* ]]
  leaks="$(grep -rlF -e 74657374 "$TMP" "${TMPDIR:-/tmp}"/k3dm-* 2>/dev/null | grep -vxF -e "$FIXTURE" -e "$K3DM_SECRETS_PASSPHRASE_FILE" || true)"
  [ -z "$leaks" ] || { printf "leak: %s\n" "$leaks"; return 1; }
}

@test "machine secrets: manifest, setup hint and migration guide cover the workflow" {
  grep -Fqx 'k3dm-cloudflare-api-token|k3dm|Cloudflare Worker API token|operator: see docs/howto/machine-setup.md' "$ROOT/scripts/etc/machine/secrets.hub.list"
  ! grep -Fq 'k3dm-cloudflare-api-token|k3dm|Cloudflare Worker API token|bin/k3dm-worker-setup' "$ROOT/scripts/etc/machine/secrets.hub.list" || false
  grep -Fq 'Moving from another Mac? Copy the Keychain items' "$ROOT/bin/k3dm-machine-setup"
  grep -Fq 'Copy secrets from the old machine' "$ROOT/docs/howto/machine-setup.md"
  grep -Fq 'iCloud does not sync' "$ROOT/docs/howto/machine-setup.md"
}

@test "machine secrets: real throwaway keychain round trip is macOS only" {
  if [[ "$(uname -s)" != Darwin ]]; then skip 'macOS Keychain required'; fi
  rm -f "$TMP/bin/security"
  [ "$(command -v security)" = /usr/bin/security ]
  project="$TMP/project"
  mkdir -p "$project/bin" "$project/scripts/etc/machine"
  cp "$SCRIPT" "$project/bin/k3dm-machine-secrets"
  printf 'svc-roundtrip|*|fixture|operator: fixture\n' > "$project/scripts/etc/machine/secrets.hub.list"
  source_keychain="$TMP/source.keychain-db"
  target_keychain="$TMP/target.keychain-db"
  security create-keychain -p fixture "$source_keychain"
  security create-keychain -p fixture "$target_keychain"
  security unlock-keychain -p fixture "$source_keychain"
  security unlock-keychain -p fixture "$target_keychain"
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

@test "machine secrets: export with no listed item fails and writes no file" {
  printf 'svc-other\tacct\t6869\n' > "$FIXTURE"
  project="$TMP/project"
  mkdir -p "$project/bin" "$project/scripts/etc/machine"
  cp "$SCRIPT" "$project/bin/k3dm-machine-secrets"
  printf 'svc-wanted|*|fixture|operator: fixture\n' > "$project/scripts/etc/machine/secrets.hub.list"
  run "$project/bin/k3dm-machine-secrets" export --role hub --out "$TMP/none.enc"
  [ "$status" -ne 0 ]
  [[ "$output" == *'nothing exported'* ]]
  [ ! -e "$TMP/none.enc" ]
}

@test "machine secrets: import of a file with no records fails and keeps the file" {
  printf '' | "$REAL_OPENSSL" enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -out "$TMP/empty.enc" -pass "file:$K3DM_SECRETS_PASSPHRASE_FILE"
  run "$SCRIPT" import --in "$TMP/empty.enc"
  [ "$status" -ne 0 ]
  [ -e "$TMP/empty.enc" ]
  [ ! -e "$SECURITY_LOG.stdin" ]
}
