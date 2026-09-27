#!/usr/bin/env bats

@test "values file does not fully qualify the repository" {
  values="${BATS_TEST_DIRNAME}/../../etc/helm/observability/blackbox-exporter-values.yaml"
  run grep -F -- 'repository: prometheus/blackbox-exporter' "${values}"
  [ "${status}" -eq 0 ]
  run grep -F -- 'quay.io/prometheus' "${values}"
  [ "${status}" -ne 0 ]
}

@test "vars file exports CF_DOMAIN with an environment override" {
  vars="${BATS_TEST_DIRNAME}/../../etc/vars.sh"
  [ -f "${vars}" ]
  run grep -F -- 'export CF_DOMAIN="${CF_DOMAIN:-' "${vars}"
  [ "${status}" -eq 0 ]
}

@test "rules apply path runs envsubst" {
  plugin="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
  run grep -F -- "envsubst '\$CF_DOMAIN'" "${plugin}"
  [ "${status}" -eq 0 ]
  run grep -F -- '_kubectl apply -f "${_rules_dir}/"' "${plugin}"
  [ "${status}" -ne 0 ]
}

@test "every rules placeholder is in the rules envsubst allowlist" {
  rules="${BATS_TEST_DIRNAME}/../../etc/prometheus/rules"
  plugin="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"

  local _allow_line _allowlist
  _allow_line="$(command grep -F -- '< "${_rule_file}"' "${plugin}" | command grep -F -- 'envsubst')"
  [ -n "${_allow_line}" ]
  _allowlist="${_allow_line#*envsubst \'}"
  _allowlist="${_allowlist%%\'*}"
  [ -n "${_allowlist}" ]

  local _placeholder _name
  while IFS= read -r _placeholder; do
    [ -n "${_placeholder}" ] || continue
    _name="${_placeholder#\$\{}"
    _name="${_name%\}}"
    if [[ " ${_allowlist} " != *" \$${_name} "* ]]; then
      echo "placeholder \${${_name}} under ${rules}/ is absent from the rules envsubst allowlist (${_allowlist})"
      return 1
    fi
  done < <(command grep -rhoE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "${rules}" | sort -u)
}

@test "every Probe target is CF_DOMAIN-suffixed" {
  probes="${BATS_TEST_DIRNAME}/../../etc/prometheus/rules/public-endpoint-probes.yaml"
  run grep -F -- '3ai-talk' "${probes}"
  [ "${status}" -ne 0 ]
  run grep -oF -- '${CF_DOMAIN}' "${probes}"
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | wc -l | tr -d ' ')" -eq 7 ]
}

@test "the ACG PrometheusRules apply cannot report success on failure" {
  plugin="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"

  local _block
  _block=$(awk '/_acg_rules_dir="/ { found=1 } found { print } found && /^  fi$/ { exit }' "${plugin}")
  [ -n "${_block}" ]
  [[ "${_block}" == *"_err "* ]]
  [[ "${_block}" != *"&& _info"* ]]

  run grep -F -- 'return "${_acg_rules_failed}"' "${plugin}"
  [ "${status}" -eq 0 ]
}
