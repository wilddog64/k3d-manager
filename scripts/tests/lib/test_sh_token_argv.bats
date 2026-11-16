#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORK="$(mktemp -d)"
  export HOME="$WORK/home"; mkdir -p "$HOME" "$WORK/bin"
  export WORK REPO_ROOT
  [ "$HOME" = "$WORK/home" ]
}
teardown() { rm -rf "$WORK"; }

run_fixture() {
  cat > "$WORK/run" <<'SCRIPT'
source "$REPO_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
source "$REPO_ROOT/scripts/lib/test.sh"
_info() { printf '%s\n' "$*" >> "$WORK/info"; }; _err() { return 1; }
VAULT_RELEASE_DEFAULT=vault
_kubectl() {
  printf '%s\n' "$*" >> "$WORK/argv"
  if [[ "$*" == *'exec -i'* ]]; then
    cat > "$WORK/input"
    if [[ "$*" == *'vault kv put'* && ! -f "$WORK/put" ]]; then cp "$WORK/input" "$WORK/put"; fi
    if [[ "$*" == *'vault kv delete'* ]]; then cp "$WORK/input" "$WORK/delete"; fi
    if [[ "$*" == *'auth/kubernetes/login'* ]]; then
      cp "$WORK/input" "$WORK/jwtinput"
      while [[ $# -gt 0 ]]; do
        if [[ "$1" == -c ]]; then printf '%s' "$2" > "$WORK/login-script"; break; fi
        shift
      done
    fi
    if [[ "$*" == *'vault kv get'* ]]; then cp "$WORK/input" "$WORK/get"; fi
  elif [[ "$*" == *'apply -f -'* ]]; then cat >> "$WORK/apply"; fi
  case "$*" in
    *'get secret vault-root'*jsonpath*) printf %s 'root-secret-987' | base64 ;;
    *'get secret'*jsonpath*) printf %s swordfish | base64 ;;
    *'cat /tmp/secret'*) printf success ;;
    *'create token'*) printf jwt-secret-987 ;;
    *'auth/kubernetes/login'*) printf login-secret-987 ;;
    *'vault kv get'*) printf success ;;
  esac
}
set -x
test_eso
trap -p EXIT TERM > "$WORK/trap"
_cleanup_eso_test secrets vault eso/test '' ns name store 0
trap - EXIT TERM
test_vault
trap -p EXIT TERM >> "$WORK/trap"
trap - EXIT TERM
SCRIPT
  bash "$WORK/run" > "$WORK/out" 2> "$WORK/trace"
  [ "$?" -eq 0 ]
}

@test "ESO root token stays on stdin and out of argv, traps and trace" {
  run_fixture
  for secret in root-secret-987; do
    run grep -Flq "$secret" "$WORK/argv" "$WORK/trap" "$WORK/trace"
    [ "$status" -ne 0 ]
  done
  grep -Fq "ESO synced secret successfully." "$WORK/info"
  grep -Fq "ESO test completed successfully." "$WORK/info"
  grep -Fq "kind: ClusterSecretStore" "$WORK/apply"
  grep -Fq "kind: ExternalSecret" "$WORK/apply"
  [ "$(cat "$WORK/put")" = root-secret-987 ]
  [ "$(cat "$WORK/delete")" = root-secret-987 ]
}

@test "Vault login tokens stay on stdin and JWT has no trailing newline" {
  run_fixture
  for secret in jwt-secret-987 login-secret-987; do
    run grep -Flq "$secret" "$WORK/argv" "$WORK/trap" "$WORK/trace"
    [ "$status" -ne 0 ]
  done
  [ "$(cat "$WORK/jwtinput")" = jwt-secret-987 ]
  [ "$(cat "$WORK/get")" = login-secret-987 ]
  cat > "$WORK/bin/vault" <<'STUB'
#!/bin/sh
cat > "$WORK/vault-input"
STUB
  chmod +x "$WORK/bin/vault"
  export PATH="$WORK/bin:$PATH"
  [ "$(command -v vault)" = "$WORK/bin/vault" ]
  sh -c "$(cat "$WORK/login-script")" sh role < "$WORK/jwtinput"
  printf %s jwt-secret-987 > "$WORK/expected"
  cmp -s "$WORK/expected" "$WORK/vault-input"
}

@test "argv leak detector has a positive control" {
  printf '%s\n' root-secret-987 > "$WORK/planted"
  grep -Fq root-secret-987 "$WORK/planted"
}
