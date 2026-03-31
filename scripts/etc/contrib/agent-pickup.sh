#!/usr/bin/env bash
set -euo pipefail

# scripts/etc/contrib/agent-pickup.sh
# Agent orientation script — run at the start of any Codex or Gemini session.
# Prints branch, recent commits, pending specs, and active context summary.
# Copy to bin/agent-pickup.sh in the target repo.
#
# Usage:
#   bin/agent-pickup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Agent Pickup ==="
echo "  host:   $(hostname)"
echo "  date:   $(date '+%Y-%m-%d %H:%M %Z')"
echo "  repo:   ${REPO_ROOT}"
echo ""

# --- Branch and recent commits ---
echo "-- Git state --"
echo "  branch: $(git -C "${REPO_ROOT}" branch --show-current)"
echo ""
echo "  recent commits:"
git -C "${REPO_ROOT}" log --oneline -5 | sed 's/^/    /'
echo ""

# --- Pending specs ---
echo "-- Pending specs (docs/plans/) --"
PLANS_DIR="${REPO_ROOT}/docs/plans"
if [[ -d "${PLANS_DIR}" ]]; then
  pending=$(grep -rl "^\- \[ \]" "${PLANS_DIR}" 2>/dev/null | sort || true)
  if [[ -n "${pending}" ]]; then
    while IFS= read -r f; do
      echo "  $(basename "${f}")"
      grep "^\- \[ \]" "${f}" | head -3 | sed 's/^/      /'
    done <<< "${pending}"
  else
    echo "  (none)"
  fi
else
  echo "  (docs/plans/ not found)"
fi
echo ""

# --- Active context summary ---
echo "-- Active context (memory-bank/activeContext.md) --"
ACTIVE="${REPO_ROOT}/memory-bank/activeContext.md"
if [[ -f "${ACTIVE}" ]]; then
  head -30 "${ACTIVE}" | sed 's/^/  /'
else
  echo "  (not found)"
fi
echo ""

echo "=== Next step: read the spec in full before doing anything ==="
