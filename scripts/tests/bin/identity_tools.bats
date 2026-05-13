#!/usr/bin/env bats

@test "vault-exec wraps kubectl exec through _run_command" {
  run grep -nF '_identity_exec_pod "$VAULT_NAMESPACE" "$VAULT_POD" "$VAULT_CONTAINER" "${CMD[@]}"' bin/vault-exec
  [ "$status" -eq 0 ]
  [[ "$output" == *'_identity_exec_pod'* ]]

  run grep -nF '_run_command --quiet -- "${cmd[@]}"' scripts/lib/identity_tools.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *'kubectl exec'* || "$output" == *'_run_command --quiet -- "${cmd[@]}"'* ]]
}

@test "ldap-search reads the bind password from the live secret" {
  run grep -nF '_identity_secret_field "$LDAP_NAMESPACE" "$LDAP_ADMIN_SECRET_NAME" "$LDAP_ADMIN_PASSWORD_KEY"' bin/ldap-search
  [ "$status" -eq 0 ]
  [[ "$output" == *'_identity_secret_field'* ]]

  run grep -nF 'tmp_pw="$(mktemp)"' bin/ldap-search
  [ "$status" -eq 0 ]
  [[ "$output" == *'mktemp'* ]]

  run grep -nF 'printf '\''%s\n'\'' "$LDAP_BIND_PASSWORD" | _run_command --quiet -- kubectl exec -i' bin/ldap-search
  [ "$status" -eq 0 ]
  [[ "$output" == *'kubectl exec -i'* ]]
}

@test "identity log helpers use kubectl logs through _run_command" {
  run grep -nF '_identity_logs_pod "$KEYCLOAK_NAMESPACE" "$KEYCLOAK_POD" "${LOG_ARGS[@]}"' bin/keycloak-logs
  [ "$status" -eq 0 ]
  [[ "$output" == *'_identity_logs_pod'* ]]

  run grep -nF '_identity_logs_pod "$LDAP_NAMESPACE" "$LDAP_POD" "${LOG_ARGS[@]}"' bin/ldap-logs
  [ "$status" -eq 0 ]
  [[ "$output" == *'_identity_logs_pod'* ]]

  run grep -nF '_run_command --quiet -- kubectl logs -n "$namespace" "$pod" "$@"' scripts/lib/identity_tools.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *'kubectl logs'* ]]
}
