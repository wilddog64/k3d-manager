# Resolve a Python interpreter that can parse YAML for BATS tests.
k3dm_python_yaml() {
  local candidate tried="" candidates=()

  if [[ -n "${K3DM_TEST_PYTHON3_CANDIDATES:-}" ]]; then
    IFS=: read -r -a candidates <<< "$K3DM_TEST_PYTHON3_CANDIDATES"
  else
    [[ -n "${K3DM_TEST_PYTHON3:-}" ]] && candidates+=("$K3DM_TEST_PYTHON3")
    candidate="$(command -v python3 2>/dev/null || true)"
    [[ -n "$candidate" ]] && candidates+=("$candidate")
    candidates+=(/opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3)
  fi

  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    tried+="${tried:+, }$candidate"
    if "$candidate" -c 'import yaml' >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf 'no python3 with PyYAML found (tried: %s); set K3DM_TEST_PYTHON3\n' "${tried:-none}" >&2
  return 1
}
