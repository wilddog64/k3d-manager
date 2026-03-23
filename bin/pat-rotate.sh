#!/usr/bin/env bash
# bin/pat-rotate.sh
#
# Rotate a GitHub Personal Access Token.
# Reads the new token from stdin (interactive prompt or pipe) and updates
# gh CLI auth via `gh auth login --with-token`.
#
# Usage (interactive):  ./bin/pat-rotate.sh
# Usage (pipe):         printf '%s' "$NEW_TOKEN" | ./bin/pat-rotate.sh
#
# The token is NEVER passed as a command-line argument to avoid shell history
# and process-listing exposure.

set -euo pipefail

# --- read token -----------------------------------------------------------

if [[ -t 0 ]]; then
  printf 'New GitHub PAT (input hidden): ' >&2
  read -rs NEW_TOKEN
  printf '\n' >&2
else
  IFS= read -r NEW_TOKEN
fi

if [[ -z "$NEW_TOKEN" ]]; then
  printf 'ERROR: token is empty\n' >&2
  exit 1
fi

# Basic format check — GitHub PATs start with ghp_, gho_, ghu_, ghs_, or ghr_
if ! printf '%s' "$NEW_TOKEN" | grep -qE '^gh[pousr]_[A-Za-z0-9_]{36,}$'; then
  printf 'WARNING: token does not match expected GitHub PAT format (ghp_/gho_/ghu_/ghs_/ghr_)\n' >&2
fi

# --- update gh auth -------------------------------------------------------

printf 'Updating gh auth...\n' >&2
if ! printf '%s' "$NEW_TOKEN" | gh auth login --with-token; then
  printf 'ERROR: gh auth login --with-token failed\n' >&2
  exit 1
fi

# --- verify ---------------------------------------------------------------

if gh auth status 2>&1 | grep -q 'Logged in to github.com'; then
  printf 'SUCCESS: gh auth verified — token updated\n' >&2
else
  printf 'ERROR: gh auth status check failed after update\n' >&2
  exit 1
fi
