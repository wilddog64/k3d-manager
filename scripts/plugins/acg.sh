#!/usr/bin/env bash
# scripts/plugins/acg.sh — stub: delegates to lib-acg subtree
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
    SCRIPT_DIR="$(cd -P "${BATS_TEST_DIRNAME}/../../.." >/dev/null 2>&1 && pwd)/scripts"
  elif _repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    SCRIPT_DIR="${_repo_root}/scripts"
  else
    SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
  fi
fi
if [[ ! -f "${SCRIPT_DIR}/lib/acg/scripts/plugins/acg.sh" ]]; then
  if _repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    SCRIPT_DIR="${_repo_root}/scripts"
  fi
fi
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/aws.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/acg/scripts/plugins/acg.sh"
