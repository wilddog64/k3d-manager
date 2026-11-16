#!/usr/bin/env bats
setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORK="$(mktemp -d)"; export WORK
  export HOME="$WORK/home"; mkdir -p "$HOME" "$WORK/bin"
  export PATH="$WORK/bin:$PATH"
  # kubectl secret jsonpath shape: read-only capture, m5-air.local, 2026-11-16.
  cat > "$WORK/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORK/argv"
printf '%s\n' "$@" >> "$WORK/args"
case "$*" in
  *'get secret'*) printf %s root-secret-987 | base64 ;;
  *'exec'*)
    cat > "$WORK/stdin"
    case "$*" in
      *'-format=json'*) printf '{"data":{"data":{"password":"x"}}}\n' ;;
      *'-field='*) printf 'x\n' ;;
      *) printf 'password x\n' ;;
    esac ;;

esac
STUB
  chmod +x "$WORK/bin/kubectl"
  [ "$HOME" = "$WORK/home" ]
  [ "$(command -v kubectl)" = "$WORK/bin/kubectl" ]
}
teardown() { rm -rf "$WORK"; }
@test "all output modes send token on stdin and preserve literal path and field" {
  for mode in field all json; do
    : > "$WORK/argv"
    : > "$WORK/args"
    case "$mode" in
      field) run "$REPO_ROOT/bin/get-ldap-password" --field 'p; touch nope' 'user; touch nope' ;;
      all) run "$REPO_ROOT/bin/get-ldap-password" --field '' 'user; touch nope' ;;
      json) run "$REPO_ROOT/bin/get-ldap-password" --json 'user; touch nope' ;;
    esac
    [ "$status" -eq 0 ]
    result="$output"
    run grep -Fq root-secret-987 "$WORK/argv"
    [ "$status" -ne 0 ]
    [ "$(cat "$WORK/stdin")" = root-secret-987 ]
    grep -Fxq 'secret/ldap/users/user; touch nope' "$WORK/args"
    if [[ "$mode" == field ]]; then
      grep -Fxq 'p; touch nope' "$WORK/args"
    fi
    case "$mode" in
      field) [[ "$result" == *$'\nx' ]] ;;
      all) [[ "$result" == *'password x' ]] ;;
      json) [[ "$result" == *'"password": "x"'* ]] ;;
    esac
  done
}
@test "argv leak detector has a positive control" {
  printf '%s\n' root-secret-987 > "$WORK/planted"
  grep -Fq root-secret-987 "$WORK/planted"
}
