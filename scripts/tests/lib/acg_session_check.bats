#!/usr/bin/env bats
# scripts/tests/lib/acg_session_check.bats — k3d-manager-owned contract guard for the
# lib-acg ACG session check (agy migration). lib-acg has no BATS harness, so these
# assertions live here to catch a future subtree pull that silently reverts the
# gemini-cli -> deterministic Playwright migration. Pure logic only — no live cluster/CDP.

setup() {
  ACG_ROOT="scripts/lib/acg"
  SESSION_JS="${ACG_ROOT}/scripts/lib/acg_session_check.js"
  CDP_SH="${ACG_ROOT}/scripts/lib/cdp.sh"
}

@test "acg_session_check.js is present in the lib-acg subtree" {
  [ -f "${SESSION_JS}" ]
}

@test "acg_session_check.js passes node --check" {
  command -v node >/dev/null 2>&1 || skip "node not installed"
  run node --check "${SESSION_JS}"
  [ "$status" -eq 0 ]
}

@test "cdp.sh runs the Playwright session check, not the retired gemini-cli path" {
  # grep -c exits 1 when the count is 0, so assert on the count, not exit status
  run grep -ci 'gemini' "${CDP_SH}"
  [ "$output" -eq 0 ]
  run grep -c 'acg_session_check.js' "${CDP_SH}"
  [ "$output" -ge 1 ]
}

@test "cdp.sh preflights node and the playwright module before the session check" {
  run grep -c '_command_exist node' "${CDP_SH}"
  [ "$output" -ge 1 ]
  run grep -c 'node_modules/playwright' "${CDP_SH}"
  [ "$output" -ge 1 ]
}

@test "acg_session_check.js guards against a false-positive ACG_SESSION_OK" {
  # success must require a visible logged-in selector, not just a non-/signin URL
  run grep -c '_pageLooksLoggedIn' "${SESSION_JS}"
  [ "$output" -ge 1 ]
  # a failed signin navigation must throw, not silently fall through
  run grep -c 'Failed to navigate to Pluralsight signin page' "${SESSION_JS}"
  [ "$output" -ge 1 ]
}
