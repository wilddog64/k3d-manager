function ___join_lines() {
    local separator="$1"
    shift || true

    local joined=""
    local token
    for token in "$@"; do
        if [[ -n "$joined" ]]; then
            joined+="$separator"
        fi
        joined+="$token"
    done

    printf '%s' "$joined"
}

function __discover_tests() {
    local tests_var="$1"
    local names_var="$2"
    local suites_var="${3:-}"

    eval "$tests_var=()"
    eval "$names_var=()"
    if [[ -n "$suites_var" ]]; then
        eval "$suites_var=()"
    fi

    local tests_root="${SCRIPT_DIR}/tests"
    if [[ ! -d "$tests_root" ]]; then
        return 0
    fi

    local -a search_dirs=("$tests_root")
    while IFS= read -r dir; do
        search_dirs+=("$dir")
    done < <(find "$tests_root" -mindepth 1 -maxdepth 1 -type d | sort)

    local tests_count=0
    local -a suite_labels=()
    local test_file
    local test_name
    local suite_name
    local seen
    while IFS= read -r test_file; do
        if [[ -z "$test_file" ]]; then
            continue
        fi
        eval "$tests_var+=(\"${test_file}\")"
        tests_count=$((tests_count + 1))
        test_name="$(basename "$test_file" .bats)"
        eval "$names_var+=(\"${test_name}\")"
        suite_name="$(basename "$(dirname "$test_file")")"
        if [[ "$suite_name" == "tests" ]]; then
            continue
        fi
        seen=0
        for dir in "${suite_labels[@]}"; do
            if [[ "$dir" == "$suite_name" ]]; then
                seen=1
                break
            fi
        done
        if [[ $seen -eq 0 ]]; then
            suite_labels+=("$suite_name")
        fi
    done < <(find "${search_dirs[@]}" -maxdepth 1 -type f -name '*.bats' | sort)

    if [[ -n "$suites_var" && $tests_count -gt 0 ]]; then
        eval "$suites_var+=(\"all\")"
        if [[ ${#suite_labels[@]} -gt 0 ]]; then
            while IFS= read -r suite_name; do
                eval "$suites_var+=(\"${suite_name}\")"
            done < <(printf '%s\n' "${suite_labels[@]}" | sort)
        fi
    fi

    return 0
}

function _usage() {
    local verbose="${1:-0}"

    local -a all_fns=()
    while IFS= read -r fn; do
      all_fns+=("$fn")
    done < <(
      {
        declare -F | awk '{print $3}' | grep -v '^_'
        if [[ -d "${PLUGINS_DIR:-}" ]]; then
          grep -h "^function [a-z]" "${PLUGINS_DIR}"/*.sh 2>/dev/null \
            | awk '{print $2}' | sed 's/().*//'
        fi
      } | sort -u
    )

    # Build category lists: label, patterns...
    local -a categories=(
      "Cluster lifecycle"  "create_* deploy_cluster deploy_k3d_cluster deploy_k3s_cluster destroy_*"
      "Infrastructure"     "deploy_vault deploy_eso deploy_ldap deploy_jenkins configure_vault_*"
      "Secrets"            "secret_backend_*"
      "Directory service"  "dirservice_*"
      "Networking"         "*ingress*"
      "vCluster"           "vcluster_*"
      "Shopping cart"      "add_ubuntu_k3s_cluster register_shopping_cart_apps deploy_app_cluster"
      "Testing"            "test test_*"
    )

    __usage_match_category() {
      local pats="$1"
      local -a matches=()
      local fn pat
      for fn in "${all_fns[@]}"; do
        for pat in $pats; do
          # shellcheck disable=SC2053
          if [[ "$fn" == $pat ]]; then
            matches+=("$fn")
            break
          fi
        done
      done
      printf '%s\n' "${matches[@]}"
    }

    printf 'Usage: ./scripts/k3d-manager <function> [args]\n\n'

    if [[ "$verbose" == "1" ]]; then
      printf 'Available functions:\n'
      local i label pats
      for (( i=0; i<${#categories[@]}; i+=2 )); do
        label="${categories[$i]}"
        pats="${categories[$i+1]}"
        local -a matches=()
        while IFS= read -r fn; do
          [[ -n "$fn" ]] && matches+=("$fn")
        done < <(__usage_match_category "$pats")
        if [[ ${#matches[@]} -gt 0 ]]; then
          printf '  %s:\n' "$label"
          printf '    %s\n' "${matches[@]}"
        fi
      done

      local provider="${CLUSTER_PROVIDER:-$(_default_cluster_provider)}"
      local base_suites="all|lib|core|plugins|smoke"
      local -a __suite_names=()
      local -a __tests=() __test_names=()
      __discover_tests __tests __test_names __suite_names

      cat <<EOF

Cluster provider:
  Current: ${provider}
  Override: export CLUSTER_PROVIDER=k3d|orbstack|k3s

Subcommands:
  test [options] ${base_suites}   Run BATS tests (see "test --help")

Environment variables:
  CLUSTER_ROLE=infra|app   Select deployment profile (default: infra)
EOF
    else
      printf 'Categories:\n'
      local i label pats count
      for (( i=0; i<${#categories[@]}; i+=2 )); do
        label="${categories[$i]}"
        pats="${categories[$i+1]}"
        count=$(__usage_match_category "$pats" | grep -c .)  || count=0
        if (( count > 0 )); then
          printf '  %-22s (%d functions)\n' "$label" "$count"
        fi
      done
      printf '\nRun ./scripts/k3d-manager --help for full function list.\n'
    fi
}

function __escape_regex_literal() {
    printf '%s' "$1" | sed -e 's/[].[^$*+?(){}|\\]/\\&/g' -e 's/\//\\\//g'
}

function __slugify() {
    local value="$1"
    local max_len="${2:-24}"
    if [[ -z "$value" ]]; then
        printf 'entry'
        return
    fi
    local sanitized
    sanitized=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    sanitized=$(printf '%s' "$sanitized" | tr -c '[:alnum:]' '-')
    sanitized=$(printf '%s' "$sanitized" | sed -E 's/-+/-/g; s/^-//; s/-$//')
    if [[ -z "$sanitized" ]]; then
        sanitized='entry'
    fi
    if [[ ${#sanitized} -gt $max_len ]]; then
        sanitized="${sanitized:0:$max_len}"
        sanitized="${sanitized%-}"
        if [[ -z "$sanitized" ]]; then
            sanitized='entry'
        fi
    fi
    printf '%s' "$sanitized"
}

function __print_test_usage() {
    local -a __tests=()
    local -a __test_names=()
    local -a __suite_names=()
    __discover_tests __tests __test_names __suite_names

    local base_suites="all|lib|core|plugins|smoke"
    local suites_synopsis="$base_suites"
    if [[ ${#__suite_names[@]} -gt 0 ]]; then
        local -a extra_suites=()
        local suite_name
        for suite_name in "${__suite_names[@]}"; do
            case "$suite_name" in
                all|lib|core|plugins|tests)
                    continue
                    ;;
            esac
            extra_suites+=("$suite_name")
        done
        if [[ ${#extra_suites[@]} -gt 0 ]]; then
            suites_synopsis="${base_suites}|$( ___join_lines '|' "${extra_suites[@]}" )"
        fi
    fi

    local tests_summary="(none)"
    if [[ ${#__test_names[@]} -gt 0 ]]; then
        tests_summary="$( ___join_lines ', ' "${__test_names[@]}" )"
    fi

    cat <<EOF
Usage: test [-v|--verbose] [--case <name>] <suite|test|suite::case>

Run repository BATS tests. Suites may be one of: ${suites_synopsis}
Individual tests use the .bats filename without extension.

Options:
  -v, --verbose          Show output from passing tests
      --case <name>      Run a single test case (literal match)

Examples:
  test all
  test core
  test smoke                  # E2E smoke tests against live k3s cluster
  test smoke jenkins          # Smoke tests scoped to jenkins namespace
  test install_k3d
  test install_k3d --case "_install_k3d exports INSTALL_DIR"
  test install_k3d::"_install_k3d exports INSTALL_DIR"

Available tests: ${tests_summary}
EOF
}

# function test() has been moved to scripts/k3d-manager (dispatcher)
# Reason: CLI entrypoint belongs in the dispatcher, not a utility library.
# Refactor tracking: docs/plans/v0.9.1-test-fn-refactor-task.md
