#!/usr/bin/env bash
set -euo pipefail

ENTRY_ID="$(lpass ls | grep -i svcADReader | grep PACIFIC | perl -nle 'print $1 if /id: (\d+)/')"
LP_PASS="$(lpass show --id "$ENTRY_ID" --pass)"

kubectl -n vault exec vault-0 -i -- vault kv put secret/jenkins/ad-ldap \
  username="CN=svcADReader,OU=Service Accounts,OU=UsersOU,DC=pacific,DC=costcotravel,DC=com" \
  password="$LP_PASS"

VAULT_PASS="$(kubectl -n vault exec vault-0 -i -- vault kv get -format=json secret/jenkins/ad-ldap | jq -r '.data.data.password')"

if [[ "$LP_PASS" != "$VAULT_PASS" ]]; then
  echo "Vault credential mismatch" >&2
  printf 'LastPass SHA256: %s\n' "$(printf '%s' "$LP_PASS" | sha256sum | awk '{print $1}')" >&2
  printf 'Vault    SHA256: %s\n' "$(printf '%s' "$VAULT_PASS" | sha256sum | awk '{print $1}')" >&2
  exit 1
fi

printf 'Vault credential matches LastPass (SHA256 %s)\n' "$(printf '%s' "$LP_PASS" | sha256sum | awk '{print $1}')"
