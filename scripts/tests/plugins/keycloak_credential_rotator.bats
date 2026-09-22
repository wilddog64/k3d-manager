#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/keycloak.sh"
  manifest="${SCRIPT_DIR}/etc/argocd/platform-ops/keycloak-credential-rotator.yaml"
  body="$(yq -r 'select(.kind == "CronJob") | .spec.jobTemplate.spec.template.spec.containers[0].args[0]' "$manifest")"
}

@test "keycloak rotator: CronJob has identity schedule and concurrency policy" {
  [ "$(yq -r 'select(.kind == "CronJob") | .metadata.namespace' "$manifest")" = "identity" ]
  [ "$(yq -r 'select(.kind == "CronJob") | .spec.schedule' "$manifest")" = "0 0 1 * *" ]
  [ "$(yq -r 'select(.kind == "CronJob") | .spec.concurrencyPolicy' "$manifest")" = "Forbid" ]
}

@test "keycloak rotator: Vault payload preserves db_password" {
  local forward rollback
  # Scope each assertion to the single line performing that write. A body-wide grep cannot
  # distinguish the forward write from the rollback write, and the rollback write mentions
  # db_password too — so a body-wide check stays green even when the forward write drops it.
  forward="$(grep -F 'v1/secret/data/keycloak/admin' <<<"$body" | grep -F -- '--arg admin_password "$new"')"
  [ -n "$forward" ]
  [[ "$forward" == *'--arg db_password "$old_db"'* ]]
  [[ "$forward" == *'db_password:$db_password'* ]]

  rollback="$(grep -F 'v1/secret/data/keycloak/admin' <<<"$body" | grep -F -- '--arg admin_password "$old_admin"')"
  [ -n "$rollback" ]
  [[ "$rollback" == *'--arg db_password "$old_db"'* ]]
  [[ "$rollback" == *'db_password:$db_password'* ]]
}

@test "keycloak rotator: never mutates keycloak-secrets ExternalSecret" {
  run grep -E 'keycloak-secrets.*(annotate|patch|force-sync)|(annotate|patch|force-sync).*keycloak-secrets' <<<"$body"
  [ "$status" -ne 0 ]
}

@test "keycloak rotator: uses the master realm" {
  [[ "$body" == *"realms/master"* ]]
  run grep -F 'realms/home' <<<"$body"
  [ "$status" -ne 0 ]
}

@test "keycloak rotator: rollback trap precedes reset-password" {
  trap_line="$(grep -n 'trap rollback EXIT' <<<"$body" | cut -d: -f1)"
  reset_line="$(grep -n 'reset-password' <<<"$body" | head -1 | cut -d: -f1)"
  [ "$trap_line" -lt "$reset_line" ]
}

@test "keycloak rotator: password is not placed in URL or -u argv" {
  run grep -E -- '(-u[[:space:]]+[^|]*\$|https?[^" ]*password=)' <<<"$body"
  [ "$status" -ne 0 ]
}

@test "keycloak rotator: no request body carrying a password is passed in argv" {
  run grep -E -- '-d[[:space:]]+"\$(token|rollback|verify)_body"' <<<"$body"
  [ "$status" -ne 0 ]

  run grep -c -- '--data @-' <<<"$body"
  [ "$status" -eq 0 ]
  [ "$output" -ge 5 ]
}

@test "keycloak rotator: every curl is captured or redirected" {
  while IFS= read -r line; do
    case "$line" in
      *curl*)
        [[ "$line" == *'$(curl '* || "$line" == *'| curl '* || "$line" == *'>/dev/null'* ]]
        ;;
    esac
  done <<<"$body"
}

@test "keycloak rotator: apply path applies the manifest" {
  apply_log="$BATS_TEST_TMPDIR/apply.log"
  export apply_log
  _kubectl() { printf '%s\n' "$*" >>"$apply_log"; }
  export -f _kubectl
  _vault_configure_secret_writer_role() { :; }
  export -f _vault_configure_secret_writer_role
  _keycloak_apply_credential_rotator
  grep -F -- "$manifest" "$apply_log"
}

@test "keycloak rotator: apply path configures the exact Vault role" {
  role_log="$BATS_TEST_TMPDIR/role.log"
  _kubectl() { :; }
  export -f _kubectl
  _vault_configure_secret_writer_role() { printf '%s\n' "$*" >"$role_log"; }
  export -f _vault_configure_secret_writer_role
  run _keycloak_apply_credential_rotator
  [ "$status" -eq 0 ]
  [ "$(cat "$role_log")" = "secrets vault keycloak-credential-rotator identity secret keycloak/admin keycloak-rotation keycloak-rotation" ]
}

@test "keycloak rotator: absent manifest is a no-op" {
  SCRIPT_DIR="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$SCRIPT_DIR"
  _kubectl() { return 1; }
  export -f _kubectl
  run _keycloak_apply_credential_rotator
  [ "$status" -eq 0 ]
}

@test "keycloak rotator: absent Vault role helper is safe" {
  unset -f _vault_configure_secret_writer_role
  _kubectl() { :; }
  export -f _kubectl
  run _keycloak_apply_credential_rotator
  [ "$status" -eq 0 ]
}
