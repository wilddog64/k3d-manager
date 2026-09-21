#!/usr/bin/env bats

@test "rotate ghcr pat resolves the target context" {
  local hardcoded_context
  hardcoded_context="$(grep -cF -- '--context ubuntu-k3s' bin/rotate-ghcr-pat || true)"
  [ "$hardcoded_context" -eq 0 ]

  run grep -F 'TARGET_CONTEXT' bin/rotate-ghcr-pat
  [ "$status" -eq 0 ]
}

@test "rotate ghcr pat gates stores and pushes on the pull probe" {
  run grep -nF '_shopping_cart_ghcr_pat_can_pull' bin/rotate-ghcr-pat
  [ "$status" -eq 0 ]

  local probe_line secret_line
  probe_line="$(grep -nF '_shopping_cart_ghcr_pat_can_pull' bin/rotate-ghcr-pat | head -n 1 | cut -d: -f1)"
  secret_line="$(grep -nF 'gh secret set' bin/rotate-ghcr-pat | head -n 1 | cut -d: -f1)"
  [ "$probe_line" -lt "$secret_line" ]
}

@test "rotate ghcr pat never places credentials in argv" {
  local pat_arg vault_arg docker_arg
  pat_arg="$(grep -cF -- '-u "${SHOPPING_CART_ORG}:${TOKEN}"' bin/rotate-ghcr-pat || true)"
  vault_arg="$(grep -cF -- 'X-Vault-Token: ${_vault_root_token}' bin/rotate-ghcr-pat || true)"
  docker_arg="$(grep -cF -- '--docker-password' bin/rotate-ghcr-pat || true)"
  [ "$pat_arg" -eq 0 ]
  [ "$vault_arg" -eq 0 ]
  [ "$docker_arg" -eq 0 ]
}

@test "rotate ghcr pat does not use api github user auth validation" {
  run grep -cF -- 'api.github.com/user' bin/rotate-ghcr-pat
  [ "$status" -eq 1 ]
  [ "$output" -eq 0 ]
}

@test "rotate ghcr pat handles ESO managed secrets" {
  run grep -F 'get externalsecret ghcr-pull-secret' bin/rotate-ghcr-pat
  [ "$status" -eq 0 ]
}
