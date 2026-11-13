#!/usr/bin/env bats

@test "every public plugin function uses a dispatcher-recognized declaration" {
  local plugins="${BATS_TEST_DIRNAME}/../../plugins"
  local plugin function_name declaration
  local pattern='^[[:space:]]*(function[[:space:]]+[A-Za-z][A-Za-z0-9_]*[[:space:]]*\(\)|[A-Za-z][A-Za-z0-9_]*[[:space:]]*\(\))[[:space:]]*\{'
  local failures=0
  for plugin in "$plugins"/*.sh; do
    while IFS= read -r declaration; do
      [[ "$declaration" =~ $pattern ]] && continue
      function_name="$(sed -E 's/^[[:space:]]*function[[:space:]]+([^ (]+).*/\1/; s/^[[:space:]]*([^ (]+)[[:space:]]*\(\).*/\1/' <<<"$declaration")"
      [[ "$function_name" == _* ]] && continue
      printf '%s: %s\n' "${plugin##*/}" "$declaration"
      failures=1
    done < <(grep -E '^[[:space:]]*(function[[:space:]]+[A-Za-z][A-Za-z0-9_]*|[A-Za-z][A-Za-z0-9_]*[[:space:]]*\(\))' "$plugin" || true)
  done
  [ "$failures" -eq 0 ]
}
