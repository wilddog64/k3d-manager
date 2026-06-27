#!/usr/bin/env bats

setup() {
  TMPL="${BATS_TEST_DIRNAME}/../../etc/vault/unseal-watchdog.yaml.tmpl"
  RENDERED="$(mktemp)"
  VAULT_NS="secrets" \
  VAULT_UNSEAL_IMAGE="hashicorp/vault:1.18.3" \
  VAULT_ENDPOINT="http://vault.secrets.svc:8200" \
  envsubst '$VAULT_NS $VAULT_UNSEAL_IMAGE $VAULT_ENDPOINT' < "$TMPL" > "$RENDERED"
}

teardown() {
  rm -f "$RENDERED"
}

@test "watchdog renders into the provided namespace" {
  grep -q "namespace: secrets" "$RENDERED"
}

@test "watchdog image is pinned (not latest)" {
  grep -q "image: hashicorp/vault:1.18.3" "$RENDERED"
  ! grep -qE "image:.*:latest" "$RENDERED"
}

@test "watchdog mounts the vault-unseal secret optionally" {
  grep -q "secretName: vault-unseal" "$RENDERED"
  grep -q "optional: true" "$RENDERED"
}

@test "watchdog targets the in-cluster endpoint and unseals via shard-1" {
  grep -q "http://vault.secrets.svc:8200" "$RENDERED"
  grep -q "/etc/vault-unseal/shard-1" "$RENDERED"
  grep -q "vault operator unseal" "$RENDERED"
}

@test "inline shell vars survived envsubst (not expanded away)" {
  grep -q 'rc=$?' "$RENDERED"
  grep -q '\$(cat "\$SHARD_FILE")' "$RENDERED"
}
