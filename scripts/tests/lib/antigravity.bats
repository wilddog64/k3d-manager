#!/usr/bin/env bats

setup() {
  # Mock global dependencies
  _command_exist() { return 0; }
  _is_mac() { return 0; }
  export -f _command_exist _is_mac
  
  # Source the plugin under test
  source "scripts/plugins/antigravity.sh"
}

@test "_antigravity_ensure_acg_session: returns 0 when gemini succeeds" {
  _ensure_antigravity() { return 0; }
  gemini() { return 0; }
  _info() { :; }
  export -f _ensure_antigravity gemini _info

  run _antigravity_ensure_acg_session
  [ "$status" -eq 0 ]
  unset -f _ensure_antigravity gemini _info
}

@test "_antigravity_ensure_acg_session: returns 1 when gemini fails" {
  _ensure_antigravity() { return 0; }
  gemini() { return 1; }
  _info() { :; }
  export -f _ensure_antigravity gemini _info

  run _antigravity_ensure_acg_session
  [ "$status" -eq 1 ]
  unset -f _ensure_antigravity gemini _info
}

@test "antigravity_acg_extend: calls _antigravity_ensure_acg_session before extend" {
  session_checked=0
  _ensure_antigravity() { return 0; }
  _ensure_antigravity_ide() { return 0; }
  _ensure_antigravity_mcp_playwright() { return 0; }
  _antigravity_launch() { return 0; }
  _antigravity_ensure_acg_session() { echo "SESSION_CHECKED"; return 0; }
  gemini() { return 0; }
  _info() { :; }
  export -f _ensure_antigravity _ensure_antigravity_ide _ensure_antigravity_mcp_playwright _antigravity_launch _antigravity_ensure_acg_session gemini _info

  run antigravity_acg_extend "https://example.com/sandbox"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SESSION_CHECKED" ]]
  unset -f _ensure_antigravity _ensure_antigravity_ide _ensure_antigravity_mcp_playwright _antigravity_launch _antigravity_ensure_acg_session gemini _info
}
